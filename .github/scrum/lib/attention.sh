# shellcheck shell=bash
# "Needs attention" for status, digest and report: reads the open pull requests (one paginated
# call), the blockers of the open tasks of the sprint (at most BACKLOG_BLOCKED_LIMIT calls) and,
# with a working branch, the events of the tasks In review on a branch (same cap).

# shellcheck source=cmd_backlog.sh
. "$SCRUM_ROOT/lib/cmd_backlog.sh"

# attention_json REPO SPRINT ISSUES  Prints the output of attention.jq. Best effort: a read that
# fails only leaves its items out.
attention_json() {
  local repo="$1" sprint="$2" issues="$3" prs nums
  prs="$(gh_get_all "repos/$repo/pulls?state=open&per_page=100" 2>/dev/null)" || prs='[]'
  nums="$(printf '%s' "$issues" | jq -r -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --argjson max "$BACKLOG_BLOCKED_LIMIT" \
    'include "scrum"; [report_tasks($cfg)[] | select(._role != "done") | .number] | sort | .[:$max][]')"
  # shellcheck disable=SC2086  # one number per word
  jqlib attention -n --argjson cfg "$CONFIG_JSON" --argjson sprint "$sprint" --argjson issues "$issues" \
    --argjson blocked "$(blocked_map "$repo" $nums)" --argjson prs "$prs" --arg today "$(today)" \
    --argjson off "$(tz_offset)" --arg repo "$repo" --argjson strings "$(strings_json)" \
    --argjson events "$(location_events "$repo" "$issues")"
}

# location_events REPO ISSUES  {"N": [issue events]} for the open tasks In review with a location
# label (at most BACKLOG_BLOCKED_LIMIT, one call each): when the label was added tells how long
# the task has waited for the release. {} in trunk; a task whose events cannot be read is left out.
location_events() {
  local repo="$1" issues="$2" n events out='{}'
  for n in $(printf '%s' "$issues" | jq -r -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --argjson max "$BACKLOG_BLOCKED_LIMIT" \
      'include "scrum"; [.[] | select(.state == "open" and is_task($cfg) and task_role($cfg) == "in_review")
       | select(task_location($cfg) != null) | .number] | sort | .[:$max][]'); do
    events="$(gh_get_all "repos/$repo/issues/$n/events?per_page=100" 2>/dev/null)" || continue
    out="$(printf '%s' "$out" | jq -c --arg k "$n" --argjson e "$events" '.[$k] = $e' 2>/dev/null)" || out='{}'
  done
  printf '%s' "$out"
}
