# shellcheck shell=bash
# scrum next: the one next step for the person running it (next-step.jq decides). Read-only.
# Stops as early as the priority order allows, so a repo that is not set up needs no gh call.

# next_release_info REPO MILESTONES  For the release step: {sprint, tag, since, issues} of the most
# recently closed sprint and the latest version tag on the release branch, with the time the tag
# was made (release_tag_time); null when no sprint is closed or GitHub cannot be read (the step is
# then skipped).
next_release_info() {
  local repo="$1" last branch vtags prev issues
  last="$(printf '%s' "$2" | jq -c '[.[] | select(.state == "closed")] | sort_by(.closed_at // "") | .[-1] // null')"
  [ "$last" != null ] || { printf 'null'; return 0; }
  . "$SCRUM_ROOT/lib/cmd_release.sh"
  trunk_follow_default_branch "$repo"
  branch="$(branch_role release)"
  vtags="$(release_version_tags "$repo" 2>/dev/null)" || { printf 'null'; return 0; }
  # Version tags that cannot be confirmed on the branch: whether the sprint is released is unknown.
  prev="$(release_latest_tag "$repo" "$branch" "$vtags")" || { printf 'null'; return 0; }
  issues="$(fetch_milestone_issues "$repo" "$(printf '%s' "$last" | jq -r .number)" 2>/dev/null)" || { printf 'null'; return 0; }
  jq -nc --argjson m "$last" --argjson p "$prev" --argjson i "$issues" \
    '{sprint: $m.title, tag: ($p.name // null), since: ($p.date // null), issues: $i}'
}

# next_flow_info REPO  Presets with a working branch (spec next-step-guidance "Branch flow steps"):
# {unprotected: [long-lived branches with no rule], back_merge: [open back-merge pull requests],
#  promotion_open, release_open, issues: [open issues with a location label]}. What GitHub does
# not answer is left out (no step from it) rather than guessed.
next_flow_info() {
  local repo="$1" b rules open unprotected='[]' back='[]' promo=false rel=false issues='[]' release working staging
  release="$(branch_role release)"; working="$(branch_role working)"; staging="$(branch_role staging)"
  # Protect is suggested only when it can be done: the user is an admin of the repository and
  # its plan offers rulesets (a private repository on a free plan answers 403). A branch with
  # classic branch protection counts as protected.
  if [ "$(gh_get "repos/$repo" 2>/dev/null | jq -r '.permissions.admin // false' 2>/dev/null)" = true ] \
      && gh_get "repos/$repo/rulesets?per_page=1" >/dev/null 2>&1; then
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      rules="$(branch_rules "$repo" "$b" 2>/dev/null)" || continue
      [ "$(printf '%s' "$rules" | jq 'length')" = 0 ] || continue
      [ "$(gh_get "repos/$repo/branches/$(branch_uri "$b")" 2>/dev/null | jq -r '.protected // false' 2>/dev/null)" != true ] || continue
      unprotected="$(printf '%s' "$unprotected" | jq -c --arg b "$b" '. + [$b]')"
    done <<BRANCHES
$(branch_role chain)
BRANCHES
  fi
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    open="$(open_prs "$repo" "$release" "$b" 2>/dev/null)" || continue
    back="$(jq -nc --argjson a "$back" --argjson b "$open" '$a + $b')"
  done <<BRANCHES
$(branch_role lower)
BRANCHES
  if [ -n "$staging" ]; then
    if open="$(open_prs "$repo" "$working" "$staging" 2>/dev/null)"; then
      [ "$(printf '%s' "$open" | jq length)" = 0 ] || promo=true
    else promo=true; fi
  fi
  if open="$(open_prs_matching "$repo" release/ "$release" 2>/dev/null)"; then
    [ "$(printf '%s' "$open" | jq length)" = 0 ] || rel=true
  else rel=true; fi
  . "$SCRUM_ROOT/lib/cmd_release.sh"
  issues="$(location_issues "$repo" 2>/dev/null)" || issues='[]'
  jq -nc --argjson u "$unprotected" --argjson b "$back" --argjson p "$promo" --argjson r "$rel" --argjson i "$issues" \
    '{unprotected: $u, back_merge: $b, promotion_open: $p, release_open: $r, issues: $i}'
}

cmd_next() {
  local json=0 init=true pushed=true sprint=null issues='[]' me="" remote result ms='[]' waiting=0 run_open=null ai_blocked='{}' ai f release=null flow=null
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      *) die "unknown option for next: $1" ;;
    esac
    shift
  done

  require_tools nogh
  if [ ! -f "$(config_path)" ]; then
    init=false; pushed=false; CONFIG_JSON="$(cat "$SHARE_DIR/defaults.json")"
  else
    require_tools
    load_config
    REPO="$(repo_slug)"
    remote="$(remote_workflows "$REPO")" || die "cannot read .github/workflows on the default branch of $REPO. Check: /scrum-github:doctor"
    printf '%s\n' "$remote" | grep -qx scrum-status-sync.yml || pushed=false
  fi

  if [ "$pushed" = true ] && has_working_branch; then
    flow="$(next_flow_info "$REPO")"
  fi
  if [ "$pushed" = true ]; then
    ms="$(fetch_milestones "$REPO")"
    sprint="$(jqlib sprint-resolve -n --argjson ms "$ms" --argjson cfg "$CONFIG_JSON" --arg title "" --arg today "$(today)")"
    if [ "$sprint" != null ]; then
      issues="$(fetch_milestone_issues "$REPO" "$(printf '%s' "$sprint" | jq -r .number)")"
      me="$(ghx api user | jq -r '.login // ""')"
      # /scrum-github:run: an unfinished run in this working tree, and what blocks my ai-ready tasks.
      for f in "$(repo_dir)"/.scrum/run/*.json; do
        [ -e "$f" ] || continue
        if [ "$(jq -r '.finished_at == null' "$f" 2>/dev/null)" = true ]; then run_open="$(jq -c '{id}' "$f")"; fi
      done
      ai="$(printf '%s' "$issues" | jq -r -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --arg me "$me" \
        'include "scrum"; [report_tasks($cfg)[] | select(._role == "new" and (._who | index($me)) and has_label_ci($cfg.labels.ai_ready)) | .number] | .[:50][]')"
      if [ -n "$ai" ]; then
        . "$SCRUM_ROOT/lib/cmd_backlog.sh"
        # shellcheck disable=SC2086  # one number per word
        ai_blocked="$(blocked_map "$REPO" $ai)"
      fi
      if [ "$(printf '%s' "$issues" | jq -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum"; report_tasks($cfg) | length')" = 0 ]; then
        . "$SCRUM_ROOT/lib/cmd_backlog.sh"
        waiting="$(backlog_count "$REPO" 2>/dev/null)" || waiting=0
      fi
    fi
  fi

  next_step() {
    jqlib next-step -n --argjson init "$init" --argjson pushed "$pushed" --argjson sprint "$sprint" \
      --argjson issues "$issues" --arg me "$me" --arg today "$(today)" --argjson cfg "$CONFIG_JSON" \
      --argjson backlog_count "${waiting:-0}" --argjson run_open "$run_open" --argjson ai_blocked "$ai_blocked" \
      --argjson release "$release" --argjson flow "$flow"
  }
  result="$(next_step)"
  # The release step reads tags and a sprint's issues, so only when no step above it applies:
  # these are the steps it comes before (next-step.jq has the order). With a working branch,
  # tasks become Done only when released, so the release step comes from the branch flow.
  has_working_branch || case "$(printf '%s' "$result" | jq -r .step)" in
    sprint-new|estimate|assign|run|start|done)
      release="$(next_release_info "$REPO" "$ms")"
      [ "$release" = null ] || result="$(next_step)" ;;
  esac
  if [ "$json" = 1 ]; then
    printf '%s\n' "$result"
  else
    printf '%s' "$result" | jq -r '"Next: \(.message)", "  \(.command)"'
  fi
}
