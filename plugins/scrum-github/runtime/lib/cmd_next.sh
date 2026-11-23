# shellcheck shell=bash
# scrum next: the one next step for the person running it (next-step.jq decides). Read-only.
# Stops as early as the priority order allows, so a repo that is not set up needs no gh call.

# next_release_info REPO MILESTONES  For the release step: {sprint, tag, since, issues} of the most
# recently closed sprint and the latest version tag on the default branch, with the time the tag
# was made (release_tag_time); null when no sprint is closed or GitHub cannot be read (the step is
# then skipped).
next_release_info() {
  local repo="$1" last branch vtags prev issues
  last="$(printf '%s' "$2" | jq -c '[.[] | select(.state == "closed")] | sort_by(.closed_at // "") | .[-1] // null')"
  [ "$last" != null ] || { printf 'null'; return 0; }
  . "$SCRUM_ROOT/lib/cmd_release.sh"
  branch="$(release_default_branch "$repo" 2>/dev/null)" || { printf 'null'; return 0; }
  vtags="$(release_version_tags "$repo" 2>/dev/null)" || { printf 'null'; return 0; }
  # Version tags that cannot be confirmed on the branch: whether the sprint is released is unknown.
  prev="$(release_latest_tag "$repo" "$branch" "$vtags")" || { printf 'null'; return 0; }
  issues="$(fetch_milestone_issues "$repo" "$(printf '%s' "$last" | jq -r .number)" 2>/dev/null)" || { printf 'null'; return 0; }
  jq -nc --argjson m "$last" --argjson p "$prev" --argjson i "$issues" \
    '{sprint: $m.title, tag: ($p.name // null), since: ($p.date // null), issues: $i}'
}

cmd_next() {
  local json=0 init=true pushed=true sprint=null issues='[]' me="" remote result ms='[]' waiting=0 run_open=null ai_blocked='{}' ai f release=null
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
      --argjson release "$release"
  }
  result="$(next_step)"
  # The release step reads tags and a sprint's issues, so only when no step above it applies:
  # these are the steps it comes before (next-step.jq has the order).
  case "$(printf '%s' "$result" | jq -r .step)" in
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
