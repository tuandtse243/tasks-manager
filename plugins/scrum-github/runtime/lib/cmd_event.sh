# shellcheck shell=bash
# scrum event | scrum pr-check  (run by GitHub Actions; read $GITHUB_EVENT_PATH)

event_file() {
  local ev="${GITHUB_EVENT_PATH:-}"
  [ -n "$ev" ] && [ -f "$ev" ] || die "GITHUB_EVENT_PATH is not set. This command runs inside GitHub Actions."
  printf '%s' "$ev"
}

# apply_decision REPO KIND ISSUE_JSON  (PR_DRAFT, PR_BASE and PR_HEAD describe the pull request)
apply_decision() {
  local repo="$1" kind="$2" issue="$3" d n skip
  n="$(printf '%s' "$issue" | jq -r .number)"
  d="$(jqlib event-decide -n --argjson cfg "$CONFIG_JSON" --arg kind "$kind" --argjson issue "$issue" \
    --argjson draft "${PR_DRAFT:-false}" --arg base "${PR_BASE:-}" --arg head "${PR_HEAD:-}")"
  skip="$(printf '%s' "$d" | jq -r '.skip // empty')"
  if [ -n "$skip" ]; then
    info "#$n: no change ($skip)"
    return 0
  fi
  if [ "$(printf '%s' "$d" | jq -r '.labels != null')" = "true" ]; then
    printf '%s' "$d" | jq -c '{labels}' | gh_send PUT "repos/$repo/issues/$n/labels" >/dev/null
    info "#$n: labels set to $(printf '%s' "$d" | jq -r '.labels | join(", ")')"
  fi
  if [ "$(printf '%s' "$d" | jq -r .close)" = "true" ]; then
    printf '{"state":"closed","state_reason":"completed"}' | gh_send PATCH "repos/$repo/issues/$n" >/dev/null
    info "#$n: closed as completed"
  fi
  project_touch "$repo" "$n"
}

# event_pr_kind  The kind of the event's pull request (pr_kind in scrum.jq, from PR_HEAD and
# PR_BASE): task, release, hotfix, promotion or back_merge; always task in trunk.
event_pr_kind() {
  jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --arg h "$PR_HEAD" --arg b "$PR_BASE" \
    'include "scrum"; pr_kind($cfg; $h; $b)'
}

# promotion_merged REPO EVENT_FILE  A promotion (working branch into staging) was merged: the open
# tasks with the working branch's location label that the merge commit contains get the label of
# the base branch in place of it; the others keep theirs (spec pr-task-linking "Task location
# after merge", design 5 and 6). What is contained comes from the commits, not from the body.
promotion_merged() {
  local repo="$1" ev="$2" sha working label issues contents n issue
  sha="$(jq -r '.pull_request.merge_commit_sha // empty' "$ev")"
  if [ -z "$sha" ]; then warn "the promotion has no merge commit; task locations unchanged"; return 0; fi
  working="$(branch_role working)"
  label="$(jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --arg w "$working" 'include "scrum"; location_label($cfg; $w)')"
  if ! issues="$(gh_get_all "repos/$repo/issues?labels=$(branch_uri "$label")&state=open&per_page=100")"; then
    warn "cannot read the tasks labelled \"$label\"; task locations unchanged"
    return 0
  fi
  contents="$(branch_contents "$repo" "$sha" "$issues" "$(jq -nc --arg w "$working" '[$w]')")"
  if [ "$(printf '%s' "$contents" | jq -r '.contained | length')" = 0 ]; then
    info "The promotion contains no task labelled \"$label\"."
  fi
  for n in $(printf '%s' "$contents" | jq -r '.contained[]'); do
    issue="$(printf '%s' "$issues" | jq -c --argjson n "$n" '[.[] | select(.number == $n)][0]')"
    apply_decision "$repo" pr_promoted "$issue"
  done
  for n in $(printf '%s' "$contents" | jq -r '.missing[]'); do info "#$n: no change (not in the promotion)"; done
  for n in $(printf '%s' "$contents" | jq -r '.unknown[]'); do
    warn "#$n: cannot tell whether the promotion contains it; label unchanged"
  done
  if [ "$(printf '%s' "$contents" | jq -r .truncated)" = true ]; then
    warn "only the first $(printf '%s' "$contents" | jq -r .limit) of $(printf '%s' "$contents" | jq -r .total) tasks labelled \"$label\" were checked"
  fi
}

cmd_event() {
  require_tools
  load_config
  local ev name action repo kind body links numbers n issue PR_DRAFT=false PR_BASE="" PR_HEAD=""
  ev="$(event_file)"
  name="${GITHUB_EVENT_NAME:-}"
  action="$(jq -r '.action // ""' "$ev")"
  repo="$(repo_slug)"

  case "$name" in
    pull_request|pull_request_target)
      PR_DRAFT="$(jq -c '.pull_request.draft // false' "$ev")"
      PR_BASE="$(jq -r '.pull_request.base.ref // ""' "$ev")"
      PR_HEAD="$(jq -r '.pull_request.head.ref // ""' "$ev")"
      case "$action" in
        opened|reopened|ready_for_review|edited) kind=pr_open ;;
        converted_to_draft) kind=pr_draft ;;
        closed)
          if [ "$(jq -r '.pull_request.merged // false' "$ev")" = "true" ]; then kind=pr_merged
          elif [ "$(jq -r '(.statuses.in_review // "") != ""' <<<"$CONFIG_JSON")" = true ]; then kind=pr_closed
          else info "Pull request closed without merging: task statuses unchanged."; return 0; fi ;;
        *) info "Ignoring pull request action '$action'."; return 0 ;;
      esac
      # Merge table of design 4 for presets with a working branch: these merges are not about
      # the tasks the body links.
      if [ "$kind" = pr_merged ] && has_working_branch; then
        case "$(event_pr_kind)" in
          promotion) promotion_merged "$repo" "$ev"; return 0 ;;
          release) info "Release pull request merged: scrum release finish sets its tasks Done."; return 0 ;;
          back_merge) info "Back-merge merged: task statuses unchanged."; return 0 ;;
        esac
      fi
      body="$(jq -r '.pull_request.body // ""' "$ev")"
      links="$(jqlib links -n --arg body "$body" --arg repo "$repo")"
      numbers="$(printf '%s' "$links" | jq -r '.issues[]')"
      if [ -z "$numbers" ]; then info "The pull request closes no task."; return 0; fi
      for n in $numbers; do
        if ! issue="$(gh_get "repos/$repo/issues/$n" 2>/dev/null)" || [ -z "$issue" ]; then
          warn "cannot read #$n; skipped"; continue
        fi
        apply_decision "$repo" "$kind" "$issue"
      done
      ;;
    issues)
      case "$action" in
        closed) kind=issue_closed ;;
        reopened) kind=issue_reopened ;;
        opened) kind=issue_opened ;;
        *) info "Ignoring issue action '$action'."; return 0 ;;
      esac
      apply_decision "$repo" "$kind" "$(jq -c .issue "$ev")"
      ;;
    *)
      info "Ignoring event '$name'."
      ;;
  esac
}

cmd_pr_check() {
  require_tools nogh
  load_config
  local ev repo body links no_task msg solve
  ev="$(event_file)"
  repo="$(repo_slug)"
  no_task="$(config_get .labels.no_task)"
  if jq -e --arg l "$no_task" 'any(.pull_request.labels[]?; .name == $l)' "$ev" >/dev/null; then
    info "OK: the pull request has the \"$no_task\" label."
    return 0
  fi
  body="$(jq -r '.pull_request.body // ""' "$ev")"
  links="$(jqlib links -n --arg body "$body" --arg repo "$repo")"
  if [ "$(printf '%s' "$links" | jq '.issues | length')" -gt 0 ]; then
    info "OK: closes $(printf '%s' "$links" | jq -r '.issues | map("#\(.)") | join(", ")')."
    return 0
  fi
  msg="This pull request does not close a task. Add \"Closes #<task number>\" to the description, or add the \"$no_task\" label."
  solve="$(printf '%s' "$links" | jq -r '.solve | map("\"Solve #\(.)\" with \"Closes #\(.)\"") | join(", ")')"
  if [ -n "$solve" ]; then
    msg="$msg GitHub does not understand \"Solve\": replace $solve."
  fi
  printf '::error title=No linked task::%s\n' "$msg"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '### No linked task\n\n%s\n' "$msg" >> "$GITHUB_STEP_SUMMARY"; fi
  printf '%s\n' "$msg" >&2
  exit 1
}
