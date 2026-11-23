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

# change ai-run: my New tasks labelled ai-ready point to /scrum-github:run
test_next_run_ai_ready_tasks() {
  local list
  list="$( { issue 4 New 3 alice | jq -c '.labels += [{name: "ai-ready"}]'
             issue 5 New 1 alice
             issue 6 New 1 bob | jq -c '.labels += [{name: "ai-ready"}]'; } | issues)"
  next_of true true "$SPRINT" "$list"
  assert_eq "run" "$(step_id)"
  assert_eq "/scrum-github:run" "$(printf '%s' "$STEP" | jq -r .command)"
  assert_eq "[4]" "$(printf '%s' "$STEP" | jq -c .issues)"
  # without the label: start as before
  list="$( { issue 5 New 1 alice; issue 6 New 1 bob | jq -c '.labels += [{name: "ai-ready"}]'; } | issues)"
  next_of true true "$SPRINT" "$list"
  assert_eq "start" "$(step_id)"
}

# change ai-run: an unfinished run comes first; ai-ready tasks all blocked are not suggested to /run
test_next_unfinished_run_and_blocked_ai_ready() {
  local list
  list="$( { issue 4 'In progress' 3 alice | jq -c '.labels += [{name: "ai-ready"}]'
             issue 5 New 1 alice | jq -c '.labels += [{name: "AI-Ready"}]'; } | issues)"
  STEP="$(jqt next-step -n --argjson init true --argjson pushed true --argjson sprint "$SPRINT" --argjson issues "$list" \
    --arg me alice --arg today 2026-11-19 --argjson cfg "$(defaults)" --argjson backlog_count 0 --argjson run_open '{"id":"20261119-0900-alice"}')"
  assert_eq "run-resume" "$(step_id)"
  assert_contains "$(printf '%s' "$STEP" | jq -r .message)" "run 20261119-0900-alice of AI agents is not finished"
  list="$( { issue 5 New 1 alice | jq -c '.labels += [{name: "AI-Ready"}]'; } | issues)"
  STEP="$(jqt next-step -n --argjson init true --argjson pushed true --argjson sprint "$SPRINT" --argjson issues "$list" \
    --arg me alice --arg today 2026-11-19 --argjson cfg "$(defaults)" --argjson backlog_count 0 --argjson ai_blocked '{"5":[3]}')"
  assert_eq "start" "$(step_id)" "the only ai-ready task is blocked"
  STEP="$(jqt next-step -n --argjson init true --argjson pushed true --argjson sprint "$SPRINT" --argjson issues "$list" \
    --arg me alice --arg today 2026-11-19 --argjson cfg "$(defaults)" --argjson backlog_count 0 --argjson ai_blocked '{"5":[]}')"
  assert_eq "run" "$(step_id)" "label names are not case-sensitive"
}

# ---------- release step (delta next-step-guidance, change release) ----------

# done_at NUMBER CLOSED_AT  A Done task closed at that time.
done_at() { issue "$1" Done 3 alice | jq -c --arg c "$2" '. + {closed_at: $c}'; }
# release_of SPRINT ISSUES [TAG] [SINCE]  The --argjson release value.
release_of() {
  jq -nc --arg s "$1" --argjson i "$2" --arg t "${3:-}" --arg d "${4:-}" \
    '{sprint: $s, tag: (if $t == "" then null else $t end), since: (if $d == "" then null else $d end), issues: $i}'
}
next_with_release() { # next_with_release SPRINT_OR_null ISSUES RELEASE
  STEP="$(jqt next-step -n --argjson init true --argjson pushed true --argjson sprint "$1" --argjson issues "$2" \
    --arg me alice --arg today 2026-11-19 --argjson cfg "$(defaults)" --argjson backlog_count 0 --argjson release "$3")"
}

test_next_release_after_closed_sprint_not_released() {
  local s5
  s5="$( { done_at 1 2026-11-12T10:00:00Z; done_at 2 2026-11-12T11:00:00Z; done_at 3 2026-11-13T10:00:00Z
           done_at 4 2026-11-13T11:00:00Z; issue 5 New 1 -; } | issues)"
  next_with_release null '[]' "$(release_of "Sprint 5" "$s5" v1.4.2 2026-11-10T08:00:00Z)"
  assert_eq "release" "$(step_id)"
  assert_eq "/scrum-github:release" "$(printf '%s' "$STEP" | jq -r .command)"
  assert_eq "[1,2,3,4]" "$(printf '%s' "$STEP" | jq -c .issues)"
  assert_contains "$(printf '%s' "$STEP" | jq -r .message)" "Sprint 5 is closed and 4 of its Done tasks are in no version yet (latest: v1.4.2)"
  # with an open sprint: after your own task in progress, before picking up a new one
  next_with_release "$SPRINT" "$( { issue 20 New 3 alice; } | issues)" "$(release_of "Sprint 5" "$s5" v1.4.2 2026-11-10T08:00:00Z)"
  assert_eq "release" "$(step_id)"
  next_with_release "$SPRINT" "$( { issue 12 'In progress' 3 alice; } | issues)" "$(release_of "Sprint 5" "$s5" v1.4.2 2026-11-10T08:00:00Z)"
  assert_eq "continue" "$(step_id)"
}

test_next_no_release_when_already_released() {
  local s5
  s5="$( { done_at 1 2026-11-12T10:00:00Z; done_at 2 2026-11-13T10:00:00Z; } | issues)"
  next_with_release null '[]' "$(release_of "Sprint 5" "$s5" v1.5.0 2026-11-14T08:00:00Z)"
  assert_eq "sprint-new" "$(step_id)"
  next_with_release null '[]' null
  assert_eq "sprint-new" "$(step_id)" "tags not read: no release step"
}

test_next_release_without_any_tag() {
  next_with_release null '[]' "$(release_of "Sprint 1" "$(done_at 1 2026-11-12T10:00:00Z | issues)")"
  assert_eq "release" "$(step_id)"
  assert_not_contains "$(printf '%s' "$STEP" | jq -r .message)" "latest:"
}

test_cmd_next_suggests_release_after_a_closed_sprint() {
  next_env
  { issue 20 New 3 alice; } | issues > "$FAKE_GH_DIR/issues.json"
  printf '[%s,{"number":2,"title":"Sprint 2","state":"closed","closed_at":"2026-11-14T10:00:00Z","description":""}]' "$SPRINT" > "$FAKE_GH_DIR/milestones.json"
  route_json 'api --paginate repos/acme/blog/issues?milestone=2*' "$( { done_at 7 2026-11-12T10:00:00Z; done_at 8 2026-11-13T10:00:00Z; } | issues)"
  route_json 'api repos/acme/blog' '{"default_branch":"main"}'
  route_json 'api --paginate repos/acme/blog/tags*' '[{"name":"v1.4.2"}]'
  route_json 'api repos/acme/blog/compare/v1.4.2...main' '{"status":"ahead","base_commit":{"commit":{"committer":{"date":"2026-11-12T12:00:00Z"}}}}'
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "release [8]" "$(printf '%s' "$OUT" | jq -r '"\(.step) \(.issues | tojson)"')"
  assert_eq "" "$(gh_writes)"
}

test_cmd_next_skips_release_when_tags_cannot_be_read() {
  next_env
  { issue 20 New 3 alice; } | issues > "$FAKE_GH_DIR/issues.json"
  printf '[%s,{"number":2,"title":"Sprint 2","state":"closed","closed_at":"2026-11-14T10:00:00Z","description":""}]' "$SPRINT" > "$FAKE_GH_DIR/milestones.json"
  route_json 'api --paginate repos/acme/blog/issues?milestone=2*' "$(done_at 7 2026-11-12T10:00:00Z | issues)"
  route_json 'api repos/acme/blog' '{"default_branch":"main"}'
  route 'api --paginate repos/acme/blog/tags*' '!fail'
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "start" "$(printf '%s' "$OUT" | jq -r .step)"
}

test_cmd_next_reads_no_tags_while_you_have_work_in_progress() {
  next_env
  printf '[%s,{"number":2,"title":"Sprint 2","state":"closed","closed_at":"2026-11-14T10:00:00Z","description":""}]' "$SPRINT" > "$FAKE_GH_DIR/milestones.json"
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "continue" "$(printf '%s' "$OUT" | jq -r .step)"
  assert_not_contains "$(gh_calls)" "/tags"
}

# spec "Already released" through scrum next: the latest tag is after every Done task.
test_cmd_next_no_release_when_the_sprint_is_released() {
  next_env
  { issue 20 New 3 alice; } | issues > "$FAKE_GH_DIR/issues.json"
  printf '[%s,{"number":2,"title":"Sprint 2","state":"closed","closed_at":"2026-11-14T10:00:00Z","description":""}]' "$SPRINT" > "$FAKE_GH_DIR/milestones.json"
  route_json 'api --paginate repos/acme/blog/issues?milestone=2*' "$( { done_at 7 2026-11-12T10:00:00Z; done_at 8 2026-11-13T10:00:00Z; } | issues)"
  route_json 'api repos/acme/blog' '{"default_branch":"main"}'
  route_json 'api --paginate repos/acme/blog/tags*' '[{"name":"v1.5.0"},{"name":"v1.4.2"}]'
  route_json 'api repos/acme/blog/compare/v1.5.0...main' '{"status":"identical","base_commit":{"commit":{"committer":{"date":"2026-11-14T12:00:00Z"}}}}'
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "start" "$(printf '%s' "$OUT" | jq -r .step)"
}

# A closed sprint with no Done task (only not planned): no release step.
test_cmd_next_no_release_without_done_tasks() {
  next_env
  { issue 20 New 3 alice; } | issues > "$FAKE_GH_DIR/issues.json"
  printf '[%s,{"number":2,"title":"Sprint 2","state":"closed","closed_at":"2026-11-14T10:00:00Z","description":""}]' "$SPRINT" > "$FAKE_GH_DIR/milestones.json"
  route_json 'api --paginate repos/acme/blog/issues?milestone=2*' "$(done_at 7 2026-11-12T10:00:00Z | jq -c '.state_reason = "not_planned"' | issues)"
  route_json 'api repos/acme/blog' '{"default_branch":"main"}'
  route_json 'api --paginate repos/acme/blog/tags*' '[]'
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "start" "$(printf '%s' "$OUT" | jq -r .step)"
}

# The default branch cannot be read: the release step is skipped.
test_cmd_next_skips_release_when_repo_cannot_be_read() {
  next_env
  { issue 20 New 3 alice; } | issues > "$FAKE_GH_DIR/issues.json"
  printf '[%s,{"number":2,"title":"Sprint 2","state":"closed","closed_at":"2026-11-14T10:00:00Z","description":""}]' "$SPRINT" > "$FAKE_GH_DIR/milestones.json"
  route_json 'api --paginate repos/acme/blog/issues?milestone=2*' "$(done_at 7 2026-11-12T10:00:00Z | issues)"
  route 'api repos/acme/blog' '!fail'
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "start" "$(printf '%s' "$OUT" | jq -r .step)"
}

# The tags are listed but none can be compared with the default branch: whether they are released
# cannot be read, so the step is skipped (not treated as "no tag yet").
test_cmd_next_skips_release_when_tags_cannot_be_compared() {
  next_env
  { issue 20 New 3 alice; } | issues > "$FAKE_GH_DIR/issues.json"
  printf '[%s,{"number":2,"title":"Sprint 2","state":"closed","closed_at":"2026-11-14T10:00:00Z","description":""}]' "$SPRINT" > "$FAKE_GH_DIR/milestones.json"
  route_json 'api --paginate repos/acme/blog/issues?milestone=2*' "$(done_at 7 2026-11-12T10:00:00Z | issues)"
  route_json 'api repos/acme/blog' '{"default_branch":"main"}'
  route_json 'api --paginate repos/acme/blog/tags*' '[{"name":"v1.5.0"}]'
  route 'api repos/acme/blog/compare/*' '!fail'
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "start" "$(printf '%s' "$OUT" | jq -r .step)"
}

# Review fix 4: the boundary is the tagger date; tasks closed before it are released.
test_cmd_next_release_boundary_is_the_tagger_date() {
  next_env
  { issue 20 New 3 alice; } | issues > "$FAKE_GH_DIR/issues.json"
  printf '[%s,{"number":2,"title":"Sprint 2","state":"closed","closed_at":"2026-11-14T10:00:00Z","description":""}]' "$SPRINT" > "$FAKE_GH_DIR/milestones.json"
  route_json 'api --paginate repos/acme/blog/issues?milestone=2*' "$( { done_at 7 2026-11-12T10:00:00Z; done_at 8 2026-11-13T10:00:00Z; } | issues)"
  route_json 'api repos/acme/blog' '{"default_branch":"main"}'
  route_json 'api --paginate repos/acme/blog/tags*' '[{"name":"v1.4.2"}]'
  route_json 'api repos/acme/blog/compare/v1.4.2...main' '{"status":"ahead","base_commit":{"commit":{"committer":{"date":"2026-11-12T12:00:00Z"}}}}'
  route_json 'api repos/acme/blog/git/ref/tags/v1.4.2' '{"object":{"type":"tag","sha":"t142"}}'
  route_json 'api repos/acme/blog/git/tags/t142' '{"tagger":{"date":"2026-11-13T12:00:00Z"}}'
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "start" "$(printf '%s' "$OUT" | jq -r .step)"
}
