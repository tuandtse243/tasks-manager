# shellcheck shell=bash
# scrum run: work my tasks with AI agents (spec ai-run, design 1-7). The runtime does the parts
# that touch git and GitHub; the skill /scrum-github:run starts the agents. The state of a run is
# kept in .scrum/run/<id>.json in the repository (excluded from git), so a run can be resumed.
. "$SCRUM_ROOT/lib/cmd_backlog.sh"   # blocked_map, BACKLOG_BLOCKED_LIMIT
. "$SCRUM_ROOT/lib/cmd_team.sh"      # open_sprint

# ---------- choosing the tasks ----------

# run_numbers_json "102,107 103"  -> [102,107,103], or dies on a word that is not a number.
run_numbers_json() {
  local list='[]' n
  for n in $(printf '%s' "$1" | tr ',' ' '); do
    n="${n#\#}"
    case "$n" in ""|*[!0-9]*) die "not an issue number: $n" ;; esac
    list="$(jq -nc --argjson l "$list" --argjson n "$n" '$l + [$n]')"
  done
  printf '%s' "$list"
}

# run_select REPO LOGIN NUMBERS_JSON|null  Prints the output of run-select.jq (read-only).
run_select() {
  local repo="$1" login="$2" numbers="$3" ms sprint issues n one cands blocked
  ms="$(fetch_milestones "$repo")" || die "cannot read the sprints (milestones) of $repo"
  sprint="$(open_sprint "$ms")"
  if [ "$numbers" = null ]; then
    issues="$(gh_get_all "repos/$repo/issues?assignee=$login&state=open&per_page=100")" || die "cannot read the issues of $repo"
  else
    issues='[]'
    for n in $(printf '%s' "$numbers" | jq -r '.[]'); do
      one="$(gh_get "repos/$repo/issues/$n" 2>/dev/null)" || one=""
      if [ -z "$one" ] || ! printf '%s' "$one" | jq -e 'type == "object" and .number != null' >/dev/null 2>&1; then
        one="$(jq -nc --argjson n "$n" '{number: $n, _unreadable: true}')"
      fi
      issues="$(printf '%s' "$issues" | jq -c --argjson i "$one" '. + [$i]')"
    done
  fi
  # First pass: the candidates, whose blockers are then read (one call each, at most
  # BACKLOG_BLOCKED_LIMIT; the others count as not read and are left out).
  cands="$(jqlib run-select -n --argjson cfg "$CONFIG_JSON" --arg login "$login" --argjson issues "$issues" \
    --argjson sprint "$sprint" --argjson blocked '{}' --argjson numbers "$numbers" \
    | jq -r --argjson max "$BACKLOG_BLOCKED_LIMIT" '.candidates[:$max][]')"
  # shellcheck disable=SC2086  # one number per word
  blocked="$(blocked_map "$repo" $cands)"
  jqlib run-select -n --argjson cfg "$CONFIG_JSON" --arg login "$login" --argjson issues "$issues" \
    --argjson sprint "$sprint" --argjson blocked "$blocked" --argjson numbers "$numbers"
}

# print_run_plan  The selection in RUN_SEL, for a person.
print_run_plan() {
  printf '%s' "$RUN_SEL" | jq -r -L "$JQ_LIB" 'include "scrum";
    def plural($n; $w): "\($n) \($w)\(if $n == 1 then "" else "s" end)";
    (.tasks | length) as $n
    | (if .mode == "default" and .sprint == null then
         "There is no open sprint, so no task is chosen. Name the tasks (scrum run plan N,N) or create a sprint with /scrum-github:sprint-new."
       elif $n == 0 then "No task to run."
       else "Run for @\(.login)\(if .sprint then " in \(.sprint.title)" else "" end): \(plural($n; "task")) in \(plural(.waves | length; "wave"))" end),
      (.tasks as $t | .waves | to_entries[] | .key as $i
       | "", "Wave \($i + 1)\(if $i > 0 then " (after wave \($i) is merged)" else "" end):",
         (.value[] as $num | $t[] | select(.number == $num) | "  #\(.number)  \(if .points == null then "-" else "\(.points) pt" end)  \(.title)\(estimate_brief)")),
      (if (.excluded | length) > 0 then "", "Not in this run:", (.excluded[] | "  #\(.number)  \(.title // "?"): \(.reason)") else empty end),
      (if $n == 0 then empty
       else .eta as $e
         | "",
           (if $e.estimated == 0 then "Time: no task has a time estimate. Add one: scrum task estimate N --work 25m --review 20m"
            else "Time: about \($e.work_minutes | fmt_duration) of work (\(plural($e.waves; "wave")), each as long as its longest task plus the merge) and \($e.review_minutes | fmt_duration) of review."
                 + (if $e.missing > 0 then " Not counted, without a time estimate: \($e.missing_numbers | map("#\(.)") | join(", "))." else "" end) end)
       end)'
}

# whoami_login  The GitHub login of the user, or dies.
whoami_login() {
  local login
  login="$(gh_get user | jq -r '.login // empty')" || login=""
  [ -n "$login" ] || die "cannot tell who you are on GitHub"
  printf '%s' "$login"
}

# scrum run plan [N,N...] [--json] [--dry-run]  Read-only.
cmd_run_plan() {
  local json=0 nums="" numbers=null repo login
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --dry-run) ;;   # plan never writes; accepted for the skill's --dry-run
      -*) die "unknown option for run plan: $1" ;;
      *) nums="$nums $1" ;;
    esac
    shift
  done
  [ -z "$nums" ] || numbers="$(run_numbers_json "$nums")"
  require_tools
  load_config
  repo="$(repo_slug)"
  login="$(whoami_login)"
  RUN_SEL="$(run_select "$repo" "$login" "$numbers")"
  if [ "$json" = 1 ]; then printf '%s\n' "$RUN_SEL"; else print_run_plan; fi
}
