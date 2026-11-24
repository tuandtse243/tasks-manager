# shellcheck shell=bash
# scrum mine: every open task of one person in every sprint and the backlog, the pull requests
# waiting for their review, and what to do next (spec my-work, design 5). Read-only.
. "$SCRUM_ROOT/lib/cmd_backlog.sh"   # blocked_map, BACKLOG_BLOCKED_LIMIT
. "$SCRUM_ROOT/lib/cmd_team.sh"      # open_sprint

MINE_REVIEW_LIMIT=50

# review_requests REPO LOGIN  Open pull requests that ask LOGIN for a review (one search call);
# "null" when GitHub did not answer.
review_requests() {
  local items
  items="$(ghx api -X GET search/issues -f q="repo:$1 is:pr is:open review-requested:$2" -f per_page="$MINE_REVIEW_LIMIT" 2>/dev/null \
    | jq -c 'if type == "object" and (.items | type) == "array" then .items else error("no items") end' 2>/dev/null)" || items=""
  [ -n "$items" ] || items=null
  printf '%s' "$items"
}

cmd_mine() {
  local json=0 login="" repo issues ms sprint nums blocked prs out
  while [ $# -gt 0 ]; do
    case "$1" in
      --user) login="${2:-}"; login="${login#@}"; [ -n "$login" ] || die "--user needs a GitHub login"; shift ;;
      --json) json=1 ;;
      *) die "unknown option for mine: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  repo="$(repo_slug)"
  if [ -z "$login" ]; then
    login="$(gh_get user | jq -r '.login // empty')" || login=""
    [ -n "$login" ] || die "cannot tell who you are on GitHub; pass --user LOGIN"
  fi
  issues="$(gh_get_all "repos/$repo/issues?assignee=$login&state=open&per_page=100")" || die "cannot read the issues of $repo"
  ms="$(fetch_milestones "$repo")" || die "cannot read the sprints (milestones) of $repo"
  sprint="$(open_sprint "$ms")"
  # Blockers are read for at most BACKLOG_BLOCKED_LIMIT tasks: the New tasks of the open sprint
  # first (they decide what to do next), then the others by number.
  nums="$(printf '%s' "$issues" | jq -r -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --argjson max "$BACKLOG_BLOCKED_LIMIT" \
    --argjson cur "$(printf '%s' "$sprint" | jq '.number? // null')" \
    'include "scrum"; [.[] | select(.state == "open" and is_task($cfg))
      | {number, first: ($cur != null and (.milestone.number // null) == $cur and task_role($cfg) == "new")}]
     | (map(select(.first)) | sort_by(.number)) + (map(select(.first | not)) | sort_by(.number))
     | .[:$max][].number')"
  # shellcheck disable=SC2086  # one number per word
  blocked="$(blocked_map "$repo" $nums)"
  prs="$(review_requests "$repo" "$login")"
  out="$(jqlib mine -n --argjson cfg "$CONFIG_JSON" --arg login "$login" --argjson issues "$issues" --argjson ms "$ms" \
    --argjson sprint "$sprint" --argjson blocked "$blocked" --argjson prs "$prs")"
  if [ "$json" = 1 ]; then printf '%s\n' "$out"; return 0; fi
  printf '%s' "$out" | jq -r -L "$JQ_LIB" --arg ai "$(config_get .labels.ai_ready)" --argjson s "$(strings_json)" 'include "scrum";
    def plural($n; $w): "\($n) \($w)\(if $n == 1 then "" else "s" end)";
    def pts: if .points == null then "-" else "\(.points) pt" end;
    def where: if .location == null then "" else "  (\(location_text($s; .location)))" end;
    def notes: if .blocked_by == null then "  (blocked-by not checked)"
               elif (.blocked_by | length) > 0 then "  (blocked by \(.blocked_by | map("#\(.)") | join(", ")))"
               else "" end;
    if .total.tasks == 0 then "@\(.login) has no open tasks."
    else
      "Open tasks of @\(.login): \(plural(.total.tasks; "task")), \(.total.points) points"
        + (if .sprint == null then " (no sprint is open)" else "" end),
      (.groups[] | "", "\(.title)",
        (.tasks[] | "  #\(.number)  \(pts)  \(.sprint // "backlog")  \(.title)\(estimate_brief)\(where)\(notes)"))
    end,
    (.sprint.title as $st | .time | if . == null then empty
     elif .estimated == 0 then "", "Time left in \($st): \(plural(.tasks; "task")) without a time estimate. Add one: scrum task estimate N --work 25m --review 20m"
     else "",
       "Time left in \($st): about \(.work_minutes | fmt_duration) of work (\(plural(.waves; "wave")), each as long as its longest task plus the merge) and \(.review_minutes | fmt_duration) of review.",
       (if .missing > 0 then "\(plural(.missing; "task")) without a time estimate, not counted: \(.missing_numbers | map("#\(.)") | join(", "))." else empty end)
     end),
    "",
    (if .next == null then
       (if .total.tasks == 0 then empty
        elif .sprint == null then "Next: no sprint is open; pick from the list above, or plan one with /scrum-github:sprint-new."
        else "Next: no task of \(.sprint.title) is ready to start (every one is blocked, not checked, or not yours)." end)
     elif .next.action == "continue" then "Next: continue #\(.next.number) \(.next.title)."
     else "Next: #\(.next.number) \(.next.title); nothing open blocks it. Start it: scrum task start \(.next.number)" end),
    (if (.ai_ready | length) > 0 then
       "AI agents can work \(if (.ai_ready | length) == 1 then "one of them" else "\(.ai_ready | length) of them" end) (labelled \($ai)): \(.ai_ready | map("#\(.)") | join(", ")). Run them: /scrum-github:run"
     else empty end),
    (if .reviews == null then "Pull requests waiting for review by @\(.login): could not be read from GitHub."
     elif (.reviews | length) == 0 then "Pull requests waiting for review by @\(.login): none."
     else "Pull requests waiting for review by @\(.login):", (.reviews[] | "  #\(.number)  \(.title)  by @\(.author // "?")") end)'
}
