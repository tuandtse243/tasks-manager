# shellcheck shell=bash
# scrum backlog: open tasks without a sprint (milestone). Read-only. Also used by sprint fill,
# task list --backlog and next.

BACKLOG_BLOCKED_LIMIT=50   # "blocked by" is one call per task; later tasks show "not checked"

# backlog_issues REPO  Open issues without a milestone (raw).
backlog_issues() { gh_get_all "repos/$1/issues?milestone=none&state=open&per_page=100"; }

# backlog_count REPO  Number of tasks in the backlog; fails when GitHub cannot be read.
backlog_count() {
  local issues
  issues="$(backlog_issues "$1")" || return 1
  printf '%s' "$issues" | jq -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" \
    'include "scrum"; [.[] | select(.state == "open" and .milestone == null and is_task($cfg))] | length'
}

# blocked_map REPO NUMBERS...  {"N": [open blocking numbers]} for each number; null when GitHub
# did not answer. One call per number: callers pass at most BACKLOG_BLOCKED_LIMIT numbers.
blocked_map() {
  local repo="$1" n list blocked='{}'
  shift
  for n in "$@"; do
    if list="$(gh_get_all "repos/$repo/issues/$n/dependencies/blocked_by?per_page=100" 2>/dev/null)"; then
      list="$(printf '%s' "$list" | jq -c '[.[] | select(.state == "open") | .number] | sort' 2>/dev/null)" || list=null
    else
      list=null
    fi
    blocked="$(printf '%s' "$blocked" | jq -c --arg k "$n" --argjson v "$list" '.[$k] = $v')"
  done
  printf '%s' "$blocked"
}

# fetch_backlog REPO [ISSUES]  Sets BACKLOG to the output of backlog.jq.
fetch_backlog() {
  local issues="${2:-}" nums
  [ -n "$issues" ] || issues="$(backlog_issues "$1")"
  nums="$(printf '%s' "$issues" | jq -r -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --argjson max "$BACKLOG_BLOCKED_LIMIT" \
    'include "scrum"; [.[] | select(.state == "open" and .milestone == null and is_task($cfg)) | .number] | sort | .[:$max][]')"
  # shellcheck disable=SC2086  # one number per word
  BACKLOG="$(printf '%s' "$issues" | jqlib backlog --argjson cfg "$CONFIG_JSON" --argjson blocked "$(blocked_map "$1" $nums)")"
}

# print_backlog  The backlog in BACKLOG, for a person.
print_backlog() {
  printf '%s' "$BACKLOG" | jq -r '
    def pts: if .points == null then "-" else "\(.points) pt" end;
    def who: if (.assignees | length) == 0 then "-" else (.assignees | map("@" + .) | join(", ")) end;
    def notes: [ (if .parent then "part of #\(.parent)" else empty end),
                 (if .blocked_by == null then "blocked-by not checked"
                  elif (.blocked_by | length) > 0 then "blocked by \(.blocked_by | map("#\(.)") | join(", "))"
                  else empty end) ] | join("; ");
    if .total == 0 then "The backlog is empty. Add tasks with /scrum-github:task-new or /scrum-github:plan."
    else
      "Backlog: \(.total) task\(if .total == 1 then "" else "s" end), \(.points) points\(if .unestimated > 0 then " (\(.unestimated) not estimated)" else "" end)",
      (.tasks[] | "  #\(.number)  \(pts)  \(who)  \(.title)\(notes | if . == "" then "" else "  (\(.))" end)")
    end'
}

cmd_backlog() {
  local json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      *) die "unknown option for backlog: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  fetch_backlog "$(repo_slug)"
  if [ "$json" = 1 ]; then printf '%s\n' "$BACKLOG"; else print_backlog; fi
}
