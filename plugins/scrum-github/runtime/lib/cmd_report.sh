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

  local data title
  data="$(jqlib report-data -n --argjson cfg "$CONFIG_JSON" --argjson sprint "$SPRINT" --argjson issues "$ISSUES" \
    --argjson ms "$MILESTONES" --arg today "$(today)" --argjson off "$(tz_offset)" --arg now "$(now_iso)" --arg repo "$REPO")"
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
