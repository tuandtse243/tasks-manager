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

# ---------- scrum pr-check [--title | --source | --link] (spec repo-governance, branching-presets) ----------
# Without an option every check runs; the installed workflow runs each one as a named step.
# Release, promotion and back-merge pull requests are exempt from all three (design 8, 10).

# pr_check_fail TITLE MESSAGE  Reports one failed check (annotation, step summary, stderr).
pr_check_fail() {
  printf '::error title=%s::%s\n' "$1" "$2"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '### %s\n\n%s\n' "$1" "$2" >> "$GITHUB_STEP_SUMMARY"; fi
  printf '%s\n' "$2" >&2
}

# pr_check_title EVENT_FILE  Conventional Commits title: type, optional (scope) and !, then ": ".
pr_check_title() {
  local title
  if ! title="$(jq -er '.pull_request.title | strings' "$1")"; then
    info "Title: not in the event; not checked."; return 0
  fi
  if printf '%s' "$title" | grep -Eq '^(feat|fix|docs|chore|refactor|test|ci|perf|build|revert)(\([^()]+\))?!?: [^ ]'; then
    info "OK: the title \"$title\" is a Conventional Commit."
    return 0
  fi
  pr_check_fail "Pull request title" "The title \"$title\" does not follow Conventional Commits. Start it with a type (feat, fix, docs, chore, refactor, test, ci, perf, build or revert), an optional scope in parentheses and \"!\" for a breaking change, then \": \" and the summary. Example: feat(auth): log in with email"
  return 1
}

# pr_check_source EVENT_FILE  The head branch may target the base branch (allowed_source).
pr_check_source() {
  local head base res
  head="$(jq -r '.pull_request.head.ref // ""' "$1")"
  base="$(jq -r '.pull_request.base.ref // ""' "$1")"
  if [ -z "$head" ] || [ -z "$base" ]; then
    info "Source branch: not in the event; not checked."; return 0
  fi
  res="$(jq -cn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --arg h "$head" --arg b "$base" \
    'include "scrum"; allowed_source($cfg; $h; $b)')"
  if [ "$(printf '%s' "$res" | jq -r .allowed)" = true ]; then
    info "OK: $head may target $base."
    return 0
  fi
  pr_check_fail "Source branch" "$(printf '%s' "$res" | jq -r --arg h "$head" --arg b "$base" \
    '"A pull request from \($h) may not target \($b), which accepts \(.accepts | join(", ")). This branch must target \(.target): change the base branch of the pull request to \(.target)."')"
  return 1
}

# pr_check_link EVENT_FILE REPO  The description closes a task, or the pull request has the no-task label.
pr_check_link() {
  local ev="$1" repo="$2" body links no_task msg solve
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
  pr_check_fail "No linked task" "$msg"
  return 1
}

cmd_pr_check() {
  local only="" ev repo head base kind failed=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) only="title" ;;
      --source) only="source" ;;
      --link) only="link" ;;
      *) die "unknown option for pr-check: $1. Use: scrum pr-check [--title | --source | --link]" ;;
    esac
    shift
  done
  require_tools nogh
  load_config
  ev="$(event_file)"
  repo="$(repo_slug)"
  head="$(jq -r '.pull_request.head.ref // ""' "$ev")"
  base="$(jq -r '.pull_request.base.ref // ""' "$ev")"
  kind="$(jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --arg h "$head" --arg b "$base" \
    'include "scrum"; if pr_exempt($cfg; $h; $b) then pr_kind($cfg; $h; $b) else "" end')"
  if [ -n "$head" ] && [ -n "$base" ] && [ -n "$kind" ]; then
    info "OK: a $(printf '%s' "$kind" | tr '_' '-') pull request ($head into $base); the title, source-branch and task-link checks do not apply."
    return 0
  fi
  if [ -z "$only" ] || [ "$only" = title ]; then pr_check_title "$ev" || failed=1; fi
  if [ -z "$only" ] || [ "$only" = source ]; then pr_check_source "$ev" || failed=1; fi
  if [ -z "$only" ] || [ "$only" = link ]; then pr_check_link "$ev" "$repo" || failed=1; fi
  [ "$failed" = 0 ] || exit 1
}
