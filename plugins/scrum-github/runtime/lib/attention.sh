# shellcheck shell=bash
# "Needs attention" for status, digest and report: reads the open pull requests (one paginated
# call) and the blockers of the open tasks of the sprint (at most BACKLOG_BLOCKED_LIMIT calls).

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
    --argjson off "$(tz_offset)" --arg repo "$repo" --argjson strings "$(strings_json)"
}
