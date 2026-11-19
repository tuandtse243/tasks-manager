# scrum next (spec: next-step-guidance)

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }
SPRINT='{"number":3,"title":"Sprint 3","state":"open","description":"scrum:start=2026-11-16 end=2026-11-27","due_on":"2026-11-27T00:00:00Z"}'

# issue NUMBER STATUS POINTS ASSIGNEE  (POINTS or ASSIGNEE "-" for none)
issue() {
  jq -nc --argjson n "$1" --arg s "$2" --arg p "$3" --arg a "$4" '{
    number: $n, title: "Task \($n)", state: (if $s == "Done" then "closed" else "open" end),
    state_reason: (if $s == "Done" then "completed" else null end),
    labels: ([{name: "status: \($s)"}] + (if $p == "-" then [] else [{name: "points: \($p)"}] end)),
    assignees: (if $a == "-" then [] else [{login: $a}] end) }'
}
issues() { jq -sc . ; }

# next_of [init pushed sprint issues today]  -> sets STEP to the jq result
next_of() {
  STEP="$(jqt next-step -n --argjson init "${1:-true}" --argjson pushed "${2:-true}" \
    --argjson sprint "${3:-$SPRINT}" --argjson issues "${4:-[]}" --arg me alice \
    --arg today "${5:-2026-11-19}" --argjson cfg "$(defaults)" --argjson backlog_count "${6:-0}")"
}
step_id() { printf '%s' "$STEP" | jq -r .step; }

test_next_not_initialized() {
  next_of false false null
  assert_eq "init" "$(step_id)"
  assert_eq "/scrum-github:init" "$(printf '%s' "$STEP" | jq -r .command)"
}

test_next_not_pushed() {
  next_of true false
  assert_eq "push" "$(step_id)"
  assert_contains "$(printf '%s' "$STEP" | jq -r .command)" "git push"
}

test_next_no_open_sprint() {
  next_of true true null
  assert_eq "sprint-new" "$(step_id)"
  assert_eq "/scrum-github:sprint-new" "$(printf '%s' "$STEP" | jq -r .command)"
}

test_next_sprint_past_end_even_with_work_in_progress() {
  next_of true true "$SPRINT" "$( { issue 12 'In progress' 3 alice; } | issues)" 2026-11-28
  assert_eq "sprint-close" "$(step_id)"
  assert_eq "/scrum-github:sprint-close" "$(printf '%s' "$STEP" | jq -r .command)"
}

test_next_continue_own_task() {
  next_of true true "$SPRINT" "$( { issue 15 New - -; issue 12 'In progress' 3 alice; } | issues)"
  assert_eq "continue" "$(step_id)"
  assert_eq "[12]" "$(printf '%s' "$STEP" | jq -c .issues)"
  assert_eq "/scrum-github:task-pr" "$(printf '%s' "$STEP" | jq -r .command)"
}

test_next_estimate_before_picking() {
  next_of true true "$SPRINT" "$( { issue 15 New - -; issue 20 New 3 alice; issue 9 Done - bob; } | issues)"
  assert_eq "estimate" "$(step_id)"
  assert_eq "[15]" "$(printf '%s' "$STEP" | jq -c .issues)"
  assert_eq 'gh issue edit 15 --add-label "points: N"' "$(printf '%s' "$STEP" | jq -r .command)"
}

test_next_in_progress_without_assignee() {
  next_of true true "$SPRINT" "$( { issue 16 'In progress' 3 -; issue 20 New 3 alice; } | issues)"
  assert_eq "assign" "$(step_id)"
  assert_eq "[16]" "$(printf '%s' "$STEP" | jq -c .issues)"
  assert_contains "$(printf '%s' "$STEP" | jq -r .command)" "gh issue edit 16 --add-assignee"
}

test_next_start_own_new_task() {
  next_of true true "$SPRINT" "$( { issue 18 New 1 -; issue 20 New 3 alice; issue 12 'In progress' 3 bob; } | issues)"
  assert_eq "start" "$(step_id)"
  assert_eq "/scrum-github:task-start 20" "$(printf '%s' "$STEP" | jq -r .command)"
}

test_next_start_lowest_unassigned_never_someone_elses() {
  next_of true true "$SPRINT" "$( { issue 24 New 1 -; issue 22 New 3 bob; issue 21 New 3 -; } | issues)"
  assert_eq "start" "$(step_id)"
  assert_eq "[21]" "$(printf '%s' "$STEP" | jq -c .issues)"
}

test_next_nothing_left() {
  next_of true true "$SPRINT" "$( { issue 22 New 3 bob; issue 12 'In progress' 3 bob; issue 9 Done 1 alice; } | issues)"
  assert_eq "done" "$(step_id)"
  assert_contains "$(printf '%s' "$STEP" | jq -r .message)" "7 days left"
  assert_eq "/scrum-github:sprint-status" "$(printf '%s' "$STEP" | jq -r .command)"
}

# ---------- scrum next with a fake gh ----------

next_env() { # an installed, pushed repo with Sprint 3 open; alice is logged in
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2026-11-19
  route 'auth status*' "auth.txt"
  route 'api repos/acme/blog/contents/.github/workflows' "workflows.json"
  route 'api --paginate repos/acme/blog/milestones*' "milestones.json"
  route 'api --paginate repos/acme/blog/issues?milestone=3*' "issues.json"
  route 'api user' "user.json"
  cp "$FIXTURES/gh-auth-status.txt" "$FAKE_GH_DIR/auth.txt"
  cp "$FIXTURES/remote-workflows.json" "$FAKE_GH_DIR/workflows.json"
  printf '[%s]' "$SPRINT" > "$FAKE_GH_DIR/milestones.json"
  printf '{"login":"alice"}' > "$FAKE_GH_DIR/user.json"
  { issue 12 'In progress' 3 alice; issue 20 New 3 -; } | issues > "$FAKE_GH_DIR/issues.json"
}

test_cmd_next_not_initialized_calls_no_github() {
  setup_fake_gh
  setup_repo
  run_scrum next
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "not set up"
  assert_contains "$OUT" "/scrum-github:init"
  assert_eq "" "$(gh_calls)" "no gh call"
}

test_cmd_next_not_pushed() {
  next_env
  route_first 'api repos/acme/blog/contents/.github/workflows' '!404'
  run_scrum next
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "git push"
  assert_not_contains "$(gh_calls)" "milestones"
}

test_cmd_next_json_in_progress_writes_nothing() {
  next_env
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "continue" "$(printf '%s' "$OUT" | jq -r .step)"
  assert_eq "[12]" "$(printf '%s' "$OUT" | jq -c .issues)"
  assert_eq "" "$(gh_writes)" "no GitHub writes"
}

test_cmd_next_text_output() {
  next_env
  { issue 20 New 3 -; } | issues > "$FAKE_GH_DIR/issues.json"
  run_scrum next
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" 'Next: Pick up #20 "Task 20".'
  assert_contains "$OUT" "  /scrum-github:task-start 20"
}

test_cmd_next_workflows_not_readable_fails() {
  next_env
  route_first 'api repos/acme/blog/contents/.github/workflows' '!fail'
  run_scrum next
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "/scrum-github:doctor"
}

# delta next-step-guidance "Sprint rỗng, backlog có task"
test_next_empty_sprint_with_backlog() {
  next_of true true "$SPRINT" '[]' 2026-11-19 4
  assert_eq "fill" "$(step_id)"
  assert_eq "/scrum-github:sprint-fill" "$(printf '%s' "$STEP" | jq -r .command)"
  assert_contains "$(printf '%s' "$STEP" | jq -r .message)" "4 tasks wait in the backlog"
}

test_next_empty_sprint_and_empty_backlog() {
  next_of true true "$SPRINT" '[]' 2026-11-19 0
  assert_eq "done" "$(step_id)"
}

test_cmd_next_empty_sprint_counts_backlog() {
  next_env
  printf '[]' > "$FAKE_GH_DIR/issues.json"
  route_json 'api --paginate repos/acme/blog/issues?milestone=none*' '[{"number":30,"state":"open","milestone":null,"labels":[],"assignees":[]}]'
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "fill" "$(printf '%s' "$OUT" | jq -r .step)"
}

test_cmd_next_skips_backlog_when_sprint_has_tasks() {
  next_env
  run_scrum next
  assert_not_contains "$(gh_calls)" "milestone=none"
}
