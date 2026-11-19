# scrum backlog (spec: backlog)

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }

# bl_issue NUMBER [LABELS_CSV] [ASSIGNEE] [BODY] [STATE] [MILESTONE]
bl_issue() {
  jq -nc --argjson n "$1" --arg l "${2:-}" --arg a "${3:-}" --arg b "${4:-}" --arg s "${5:-open}" --arg m "${6:-}" '{
    number: $n, title: "Task \($n)", state: $s, body: $b,
    milestone: (if $m == "" then null else {number: ($m | tonumber), title: "Sprint \($m)"} end),
    labels: ($l | split(",") | map(select(. != "")) | map({name: .})),
    assignees: (if $a == "" then [] else [{login: $a}] end) }'
}
backlog_of() { # backlog_of ISSUES_JSON [BLOCKED_JSON]
  local blocked="${2:-}"
  [ -n "$blocked" ] || blocked='{}'
  printf '%s' "$1" | jqt backlog --argjson cfg "$(defaults)" --argjson blocked "$blocked"
}

test_backlog_keeps_only_open_tasks_without_milestone() {
  local issues out
  issues="$( { bl_issue 30 'points: 3' alice; bl_issue 31 'type: feature'; bl_issue 32 '' '' '' closed;
               bl_issue 34 'type: epic'; bl_issue 35 'scrum: meta'; bl_issue 36 '' '' '' open 4; } | jq -sc .)"
  out="$(backlog_of "$issues")"
  assert_eq "[30]" "$(printf '%s' "$out" | jq -c '[.tasks[].number]')"
}

test_backlog_totals_and_parent() {
  local issues out
  issues="$( { bl_issue 33 '' '' $'Some text\n\nPart of #7'; bl_issue 30 'points: 3' alice; } | jq -sc .)"
  out="$(backlog_of "$issues")"
  assert_eq "[30,33]" "$(printf '%s' "$out" | jq -c '[.tasks[].number]')"
  assert_eq "2 3 1" "$(printf '%s' "$out" | jq -r '"\(.total) \(.points) \(.unestimated)"')"
  assert_eq "7" "$(printf '%s' "$out" | jq -r '.tasks[] | select(.number == 33) | .parent')"
  assert_eq '["alice"]' "$(printf '%s' "$out" | jq -c '.tasks[] | select(.number == 30) | .assignees')"
}

test_backlog_blocked_and_not_checked() {
  local issues out
  issues="$( { bl_issue 30; bl_issue 33; } | jq -sc .)"
  out="$(backlog_of "$issues" '{"33":[30]}')"
  assert_eq "[30]" "$(printf '%s' "$out" | jq -c '.tasks[] | select(.number == 33) | .blocked_by')"
  assert_eq "null" "$(printf '%s' "$out" | jq -c '.tasks[] | select(.number == 30) | .blocked_by')"
}

# ---------- scrum backlog with a fake gh ----------

backlog_env() { # BACKLOG_ISSUES_JSON
  setup_fake_gh
  setup_repo 'version: 1'
  route 'api --paginate repos/acme/blog/issues?milestone=none*' "backlog.json"
  printf '%s' "$1" > "$FAKE_GH_DIR/backlog.json"
}

test_cmd_backlog_lists_tasks() {
  backlog_env "$( { bl_issue 30 'points: 3' alice; bl_issue 33 '' '' 'Part of #7'; } | jq -sc .)"
  route 'api --paginate repos/acme/blog/issues/33/dependencies/blocked_by*' "blocked.json"
  printf '[{"number":30,"state":"open"},{"number":29,"state":"closed"}]' > "$FAKE_GH_DIR/blocked.json"
  run_scrum backlog
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Backlog: 2 tasks, 3 points (1 not estimated)"
  assert_contains "$OUT" "#30  3 pt  @alice  Task 30"
  assert_contains "$OUT" "#33  -  -  Task 33  (part of #7; blocked by #30)"
  assert_eq "" "$(gh_writes)" "no GitHub writes"
}

test_cmd_backlog_empty() {
  backlog_env '[]'
  run_scrum backlog
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "The backlog is empty"
  assert_contains "$OUT" "/scrum-github:task-new"
}

test_cmd_backlog_reads_blockers_of_50_tasks_at_most() {
  backlog_env "$(jq -nc '[range(1; 61) | {number: ., title: "T\(.)", state: "open", milestone: null, labels: [], assignees: []}]')"
  run_scrum backlog --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "50" "$(gh_calls | grep -c 'dependencies/blocked_by')"
  assert_eq "10" "$(printf '%s' "$OUT" | jq '[.tasks[] | select(.blocked_by == null)] | length')"
  assert_eq "60" "$(printf '%s' "$OUT" | jq .total)"
}
