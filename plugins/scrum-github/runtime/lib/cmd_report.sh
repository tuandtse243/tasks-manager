# shellcheck shell=bash
# scrum status | scrum report

# load_sprint_data NAME  Sets REPO, MILESTONES, SPRINT, ISSUES.
load_sprint_data() {
  REPO="$(repo_slug)"
  MILESTONES="$(fetch_milestones "$REPO")"
  SPRINT="$(resolve_sprint "$MILESTONES" "$1")"
  ISSUES="$(fetch_milestone_issues "$REPO" "$(printf '%s' "$SPRINT" | jq -r .number)")"
}

cmd_status() {
  local name="" json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      -*) die "unknown option for status: $1" ;;
      *) name="$1" ;;
    esac
    shift
  done
  require_tools
  load_config
  load_sprint_data "$name"
  local p attention strings
  p="$(jqlib progress -n --argjson cfg "$CONFIG_JSON" --argjson sprint "$SPRINT" --argjson issues "$ISSUES" --arg today "$(today)")"
  . "$SCRUM_ROOT/lib/attention.sh"
  attention="$(attention_json "$REPO" "$SPRINT" "$ISSUES")"
  if [ "$json" = 1 ]; then printf '%s' "$p" | jq --argjson a "$attention" '. + {attention: $a.items}'; return 0; fi
  strings="$(strings_json)"
  printf '%s' "$p" | jqlib progress-table -r --argjson cfg "$CONFIG_JSON" --argjson strings "$strings"
  printf '%s' "$attention" | jq -r --argjson s "$strings" \
    'if (.lines | length) > 0 then "", ($s.attention_title + ":"), (.lines[] | "  - " + .) else empty end'
}

HISTORY_TASK_LIMIT=100      # events are read for at most this many tasks of the sprint
HISTORY_REMOVED_LIMIT=30    # and for at most this many issues that may have left it

# history_issues REPO SPRINT ISSUES  Sets HISSUES to the sprint's tasks with `_events`, plus the
# issues that left the sprint (`_in_now: false`), and HISTORY_LIMITED=1 when a limit was reached.
# Not run in $(...): it sets variables.
history_issues() {
  local repo="$1" sprint="$2" issues="$3" title start nums n events out='[]' cands q
  title="$(printf '%s' "$sprint" | jq -r .title)"
  start="$(printf '%s' "$sprint" | jq -r -L "$JQ_LIB" 'include "scrum"; sprint_info.start')"
  HISTORY_LIMITED=0
  nums="$(printf '%s' "$issues" | jq -r -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum"; [.[] | select(is_task($cfg)) | .number] | sort | .[]')"
  [ "$(printf '%s\n' "$nums" | grep -c .)" -le "$HISTORY_TASK_LIMIT" ] || HISTORY_LIMITED=1
  for n in $(printf '%s\n' "$nums" | head -n "$HISTORY_TASK_LIMIT"); do
    events="$(gh_get_all "repos/$repo/issues/$n/events?per_page=100" 2>/dev/null)" || events='[]'
    out="$(printf '%s' "$out" | jq -c --argjson e "$events" --argjson n "$n" '. + [{number: $n, _events: $e}]')"
  done
  out="$(printf '%s' "$issues" | jq -c --argjson h "$out" '($h | map({key: (.number | tostring), value: ._events}) | from_entries) as $m
    | map(. + {_in_now: true} + (if $m[.number | tostring] then {_events: $m[.number | tostring]} else {} end))')"
  # Issues that left the sprint: updated since its start and not in it now.
  q="repo:$repo is:issue updated:>=$start -milestone:\"$title\""
  cands="$(ghx api -X GET search/issues -f q="$q" -f per_page="$HISTORY_REMOVED_LIMIT" 2>/dev/null | jq -c '.items // []' 2>/dev/null)" || cands='[]'
  [ -n "$cands" ] || cands='[]'
  [ "$(printf '%s' "$cands" | jq length)" -lt "$HISTORY_REMOVED_LIMIT" ] || HISTORY_LIMITED=1
  for n in $(printf '%s' "$cands" | jq -r -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum"; .[] | select(is_task($cfg)) | .number'); do
    events="$(gh_get_all "repos/$repo/issues/$n/events?per_page=100" 2>/dev/null)" || continue
    if printf '%s' "$events" | jq -e --arg t "$title" 'any(.[]; .event == "demilestoned" and .milestone.title == $t)' >/dev/null; then
      out="$(printf '%s' "$out" | jq -c --argjson c "$cands" --argjson e "$events" --argjson n "$n" \
        '. + [($c[] | select(.number == $n)) + {_in_now: false, _events: $e}]')"
    fi
  done
  HISSUES="$out"
}

cmd_report() {
  local name="" out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out) out="${2:-}"; shift ;;
      -*) die "unknown option for report: $1" ;;
      *) name="$1" ;;
    esac
    shift
  done
  require_tools
  load_config
  load_sprint_data "$name"
  [ "$(printf '%s' "$SPRINT" | jq -r '(.description // "") | test("scrum:start=") or (.due_on != null)')" = "true" ] \
    || die "$(printf '%s' "$SPRINT" | jq -r .title) has no end date. Give the milestone a due date."

  local data title attention
  history_issues "$REPO" "$SPRINT" "$ISSUES"
  . "$SCRUM_ROOT/lib/attention.sh"
  attention="$(attention_json "$REPO" "$SPRINT" "$ISSUES")"
  data="$(jqlib report-data -n --argjson cfg "$CONFIG_JSON" --argjson sprint "$SPRINT" --argjson issues "$ISSUES" \
    --argjson ms "$MILESTONES" --arg today "$(today)" --argjson off "$(tz_offset)" --arg now "$(now_iso)" --arg repo "$REPO" \
    --argjson hissues "$HISSUES" --argjson attention "$attention" --argjson strings "$(strings_json)" \
    --argjson limited "$( [ "$HISTORY_LIMITED" = 1 ] && echo true || echo false )")"
  title="$(printf '%s' "$SPRINT" | jq -r .title)"
  if [ -z "$out" ]; then
    out="scrum-reports/$(printf '%s' "$title" | jq -Rr 'ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "") | if . == "" then "sprint" else . end').html"
  fi
  mkdir -p "$(dirname "$out")"
  # Every "<" becomes <, so text from issues cannot close the <script> element the data lives in.
  jq -n -r --rawfile t "$SHARE_DIR/report.html" --argjson d "$data" \
    '$t | sub("__SCRUM_DATA__"; ($d | tojson | gsub("<"; "\\u003c")))' > "$out"
  info "Wrote $out"
}
