# shellcheck shell=bash
# scrum team: who is on the team, their areas, capacity and load in the open sprint. Read-only.
# team_members is shared by every command that needs the team (spec team, design 1-2).

# team_assignees REPO  The repo's assignable users (GitHub) when cfg.team is empty; "null" when
# team is set (nothing is read) or GitHub did not answer.
team_assignees() {
  local list
  if [ "$(config_get '(.team // []) | length')" != 0 ]; then printf 'null'; return 0; fi
  list="$(gh_get_all "repos/$1/assignees?per_page=100" 2>/dev/null | jq -c '[.[] | .login? // empty]' 2>/dev/null)" || list=""
  [ -n "$list" ] || list=null
  printf '%s' "$list"
}

# team_members REPO  {source, members: [{login, areas, capacity}]}; calls GitHub only when
# cfg.team is empty.
team_members() {
  jq -n -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --argjson a "$(team_assignees "$1")" 'include "scrum"; team_list($cfg; $a)'
}

# open_sprint MILESTONES  The open sprint (milestone JSON), or "null" when there is none.
open_sprint() {
  jqlib sprint-resolve -n --argjson ms "$1" --argjson cfg "$CONFIG_JSON" --arg title "" --arg today "$(today)"
}

cmd_team() {
  local json=0 repo assignees ms sprint issues='[]' out
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      *) die "unknown option for team: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  repo="$(repo_slug)"
  assignees="$(team_assignees "$repo")"
  ms="$(fetch_milestones "$repo")" || die "cannot read the sprints (milestones) of $repo"
  sprint="$(open_sprint "$ms")"
  if [ "$sprint" != null ]; then
    issues="$(fetch_milestone_issues "$repo" "$(printf '%s' "$sprint" | jq -r .number)")"
  fi
  out="$(jqlib team -n --argjson cfg "$CONFIG_JSON" --argjson assignees "$assignees" --argjson sprint "$sprint" --argjson issues "$issues")"
  if [ "$json" = 1 ]; then printf '%s\n' "$out"; return 0; fi
  printf '%s' "$out" | jq -r '
    def plural($n; $w): "\($n) \($w)\(if $n == 1 then "" else "s" end)";
    (.members | length) as $n
    | (if .source == "config" then "Team (from team in .github/scrum.yml): \(plural($n; "member"))"
       else "Team (from GitHub: the people who can be assigned issues in this repository): \(plural($n; "member")). Declare team in .github/scrum.yml to give them areas and a capacity."
       end),
      (if .sprint == null then "There is no open sprint, so no load is shown." else "Load in \(.sprint.title):" end),
      (if $n == 0 then "  (nobody)" else empty end),
      (.members[]
       | "  @\(.login)"
         + (if (.areas | length) > 0 then "  [\(.areas | join(", "))]" else "" end)
         + (if .load != null then
              "  \(plural(.load.tasks; "open task")), "
              + (if .capacity != null then "\(.load.points) / \(.capacity) pt" + (if .load.points > .capacity then " (over capacity)" else "" end)
                 else "\(.load.points) pt, no capacity set" end)
            elif .capacity != null then "  capacity \(.capacity) pt"
            else "" end))'
}
