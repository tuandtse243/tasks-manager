# shellcheck shell=bash
# scrum next: the one next step for the person running it (next-step.jq decides). Read-only.
# Stops as early as the priority order allows, so a repo that is not set up needs no gh call.

cmd_next() {
  local json=0 init=true pushed=true sprint=null issues='[]' me="" remote result ms
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
    fi
  fi

  result="$(jqlib next-step -n --argjson init "$init" --argjson pushed "$pushed" --argjson sprint "$sprint" \
    --argjson issues "$issues" --arg me "$me" --arg today "$(today)" --argjson cfg "$CONFIG_JSON")"
  if [ "$json" = 1 ]; then
    printf '%s\n' "$result"
  else
    printf '%s' "$result" | jq -r '"Next: \(.message)", "  \(.command)"'
  fi
}
