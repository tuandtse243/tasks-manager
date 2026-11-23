# spec: task-management

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }

status_of() { # status_of LABELS_JSON ROLE -> new label list (sorted)
  jq -n --argjson l "$1" '{number: 1, labels: ($l | map({name: .}))}' \
    | jqt status-labels --argjson cfg "$(defaults)" --arg role "$2" | jq -c '{labels: (.labels | sort), changed}'
}

test_move_new_to_in_progress() {
  assert_json_eq '{"labels":["points: 3","status: In progress"],"changed":true}' \
    "$(status_of '["status: New","points: 3"]' in_progress)"
}

test_two_statuses_become_one() {
  assert_json_eq '{"labels":["bug","status: In progress"],"changed":true}' \
    "$(status_of '["status: New","status: Done","bug"]' in_progress)"
}

test_same_status_is_unchanged() {
  assert_eq "false" "$(status_of '["status: Done"]' 'done' | jq -r .changed)"
}

payload() { jqt task-payload -n --argjson cfg "$(defaults)" --argjson task "$1" --argjson milestone 1 "${@:2}"; }

test_payload_from_the_guide() {
  assert_json_eq '{"title":"Sign up via email, Facebook, LinkedIn","body":"","labels":["status: New","points: 7"],"assignees":["ruby"],"milestone":1}' \
    "$(payload '{"title":"Sign up via email, Facebook, LinkedIn","points":7,"assignees":["ruby"]}')"
}

test_payload_rejects_point_outside_scale() {
  assert_eq "5 is not an allowed point value. Allowed: 0, 1, 3, 7" "$(payload '{"title":"x","points":5}' | jq -r .error)"
}

test_payload_bug_and_unestimated() {
  assert_json_eq '["status: New","bug"]' "$(payload '{"title":"Crash","bug":true}' | jq -c .labels)"
}

test_payload_with_acceptance_and_parent() {
  local body
  body="$(payload '{"title":"x","body":"Do it","acceptance":["one","two"]}' --arg parent 5 | jq -r .body)"
  assert_eq 'Do it

### Acceptance criteria

- [ ] one
- [ ] two

Part of #5' "$body"
}

test_branch_name() {
  assert_eq "feat/2-login" "$(printf '{"number":2,"title":"Login"}' | jqt branch-name -r --argjson cfg "$(defaults)")"
  assert_eq "feat/1-sign-up-via-email-facebook-linkedin" \
    "$(printf '{"number":1,"title":"Sign up via email, Facebook, LinkedIn!"}' | jqt branch-name -r --argjson cfg "$(defaults)")"
  assert_eq "feat/9-task" "$(printf '{"number":9,"title":"???"}' | jqt branch-name -r --argjson cfg "$(defaults)")"
}

# ---------- commands ----------

task_env() {
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2014-09-22
  route 'api --paginate repos/acme/blog/milestones*' milestones.json
  cp "$FIXTURES/milestones.json" "$FAKE_GH_DIR/milestones.json"
}

test_cmd_task_new_full() {
  task_env
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":1,"title":"Sign up via email, Facebook, LinkedIn","html_url":"https://github.com/acme/blog/issues/1"}'
  run_scrum task new --title "Sign up via email, Facebook, LinkedIn" --points 7 --assignee @ruby
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Created #1 Sign up via email, Facebook, LinkedIn in Sprint 1"
  assert_contains "$(gh_calls)" 'STDIN {"title":"Sign up via email, Facebook, LinkedIn","body":"","labels":["status: New","points: 7"],"assignees":["ruby"],"milestone":1}'
}

test_cmd_task_new_invalid_points_no_call() {
  task_env
  run_scrum task new --title "x" --points 5
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "Allowed: 0, 1, 3, 7"
  assert_eq "" "$(gh_writes)"
  assert_not_contains "$(gh_calls)" "milestones" "fails before reading GitHub"
}

# delta task-management "Tạo task": no open sprint -> the backlog (it was an error before 0.9.0).
test_cmd_task_new_without_open_sprint_goes_to_the_backlog() {
  task_env
  jq '.[0].state = "closed"' "$FIXTURES/milestones.json" > "$FAKE_GH_DIR/milestones.json"
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":3,"title":"Fix login","html_url":"u3"}'
  run_scrum task new --title "Fix login"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Created #3 Fix login in the backlog"
  assert_contains "$OUT" "/scrum-github:sprint-new"
  assert_contains "$(gh_calls)" 'STDIN {"title":"Fix login","body":"","labels":["status: New"],"assignees":[]}'
}

test_cmd_task_new_with_open_sprint_goes_into_it() {
  task_env
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":3,"title":"Fix login","html_url":"u3"}'
  run_scrum task new --title "Fix login"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Created #3 Fix login in Sprint 1"
  assert_contains "$(gh_calls)" '"milestone":1}'
}

test_cmd_task_new_backlog_flag() {
  task_env
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":3,"title":"Fix login","html_url":"u3"}'
  run_scrum task new --title "Fix login" --backlog
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Created #3 Fix login in the backlog"
  assert_not_contains "$OUT" "no open sprint"
  assert_not_contains "$(gh_calls)" '"milestone"'
}

test_cmd_task_new_backlog_and_sprint_refused() {
  task_env
  run_scrum task new --title "Fix login" --backlog --sprint "Sprint 1"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "use --sprint or --backlog, not both"
  assert_eq "" "$(gh_calls)" "nothing read or written"
}

test_cmd_task_new_unknown_sprint_refused() {
  task_env
  run_scrum task new --title "Fix login" --sprint "Sprint 9"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" 'no sprint named "Sprint 9"'
  assert_eq "" "$(gh_writes)"
}

start_env() {
  task_env
  git init -q -b main "$SCRUM_REPO_DIR"
  git -C "$SCRUM_REPO_DIR" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
  route_json 'api user' '{"login":"david"}'
  route_json 'repo view acme/blog*' 'main'
}

test_cmd_task_start_new_task() {
  start_env
  route_json 'api repos/acme/blog/issues/2' '{"number":2,"title":"Login","state":"open","assignees":[],"labels":[{"name":"status: New"},{"name":"points: 3"}]}'
  run_scrum task start 2
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "feat/2-login" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)"
  assert_contains "$(gh_calls)" 'api -X POST repos/acme/blog/issues/2/assignees --input -'
  assert_contains "$(gh_calls)" 'STDIN {"assignees":["david"]}'
  assert_contains "$(gh_calls)" 'STDIN {"labels":["points: 3","status: In progress"]}'
  assert_contains "$OUT" 'Closes #2'
}

test_cmd_task_start_existing_branch() {
  start_env
  git -C "$SCRUM_REPO_DIR" branch feat/2-login
  route_json 'api repos/acme/blog/issues/2' '{"number":2,"title":"Login","state":"open","assignees":[{"login":"david"}],"labels":[{"name":"status: New"}]}'
  run_scrum task start 2
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Checked out existing branch feat/2-login"
  assert_eq "feat/2-login" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)"
  assert_not_contains "$(gh_calls)" "assignees --input"
}

test_cmd_task_start_closed_issue_changes_nothing() {
  start_env
  route_json 'api repos/acme/blog/issues/2' '{"number":2,"title":"Login","state":"closed","assignees":[],"labels":[]}'
  run_scrum task start 2
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "#2 is closed"
  assert_eq "" "$(gh_writes)"
  assert_eq "main" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)"
}

test_cmd_task_start_assigned_to_someone_else() {
  start_env
  route_json 'api repos/acme/blog/issues/2' '{"number":2,"title":"Login","state":"open","assignees":[{"login":"ruby"}],"labels":[{"name":"status: New"}]}'
  run_scrum task start 2
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "assigned to ruby"
  assert_not_contains "$(gh_calls)" "assignees --input"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In progress"]}'
}

# plan apply: see test_plan.sh

# delta work-plan: subtasks are a checklist; a backlog task has no milestone key.
test_payload_with_subtasks() {
  assert_eq 'Do it

### Acceptance criteria

- [ ] one

### Subtasks

- [ ] Migration
- [ ] Test

Part of #5' "$(payload '{"title":"x","body":"Do it","acceptance":["one"],"subtasks":["Migration","Test"]}' --arg parent 5 | jq -r .body)"
}

test_payload_backlog_has_no_milestone() {
  assert_eq "false" "$(jqt task-payload -n --argjson cfg "$(defaults)" --argjson task '{"title":"x"}' --argjson milestone null | jq 'has("milestone")')"
}

# ---------- task list, move, estimate, assign, drop ----------

# ops_issue NUMBER STATUS POINTS ASSIGNEE MILESTONE [EXTRA_LABEL] [STATE]
ops_issue() {
  jq -nc --argjson n "$1" --arg s "$2" --arg p "$3" --arg a "$4" --arg m "$5" --arg x "${6:-}" --arg st "${7:-open}" '{
    number: $n, title: "Task \($n)", state: $st, body: "",
    milestone: (if $m == "" then null else {number: ($m | tonumber), title: "Sprint \($m)"} end),
    labels: ([{name: "status: \($s)"}] + (if $p == "" then [] else [{name: "points: \($p)"}] end)
             + (if $x == "" then [] else [{name: $x}] end)),
    assignees: (if $a == "" then [] else [{login: $a}] end) }'
}

ops_env() {
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2026-11-19
  printf '[{"number":4,"title":"Sprint 4","state":"open","description":"<!-- scrum:start=2026-11-16 end=2026-11-27 -->"},{"number":2,"title":"Sprint 2","state":"closed","description":"<!-- scrum:start=2026-10-19 end=2026-10-30 -->"}]' > "$FAKE_GH_DIR/ms.json"
  route 'api --paginate repos/acme/blog/milestones*' ms.json
  ops_issue 12 'In progress' 3 alice 4 > "$FAKE_GH_DIR/i12.json"
  ops_issue 14 New '' '' 4 > "$FAKE_GH_DIR/i14.json"
  ops_issue 30 New 1 '' '' > "$FAKE_GH_DIR/i30.json"
  ops_issue 31 New '' '' '' 'type: feature' > "$FAKE_GH_DIR/i31.json"
  ops_issue 13 Done 1 bob 4 '' closed > "$FAKE_GH_DIR/i13.json"
  local n; for n in 12 14 30 31 13; do route "api repos/acme/blog/issues/$n" "i$n.json"; done
  jq -s . "$FAKE_GH_DIR/i12.json" "$FAKE_GH_DIR/i14.json" "$FAKE_GH_DIR/i13.json" > "$FAKE_GH_DIR/sprint.json"
  jq -s . "$FAKE_GH_DIR/i30.json" "$FAKE_GH_DIR/i31.json" > "$FAKE_GH_DIR/backlog.json"
  route 'api --paginate repos/acme/blog/issues?milestone=4*' sprint.json
  route 'api --paginate repos/acme/blog/issues?milestone=none*' backlog.json
  route_json 'api user' '{"login":"alice"}'
}

test_cmd_task_list_mine_in_progress() {
  ops_env
  run_scrum task list --mine --status in_progress
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#12  In progress  3 pt  @alice  Task 12"
  assert_not_contains "$OUT" "#14"
}

test_cmd_task_list_backlog_json() {
  ops_env
  run_scrum task list --backlog --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[30]" "$(printf '%s' "$OUT" | jq -c '[.[].number]')"
  assert_eq "" "$(gh_writes)"
}

test_cmd_task_move_to_backlog() {
  ops_env
  run_scrum task move 12 --backlog
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"milestone":null}'
  assert_contains "$(gh_calls)" 'Moved from Sprint 4 to the backlog.'
  assert_contains "$OUT" "Moved #12 from Sprint 4 to the backlog."
}

test_cmd_task_move_into_open_sprint() {
  ops_env
  run_scrum task move '#30' --sprint "Sprint 4"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"milestone":4}'
  assert_contains "$(gh_calls)" 'Moved from the backlog to Sprint 4.'
}

test_cmd_task_move_to_closed_sprint_writes_nothing() {
  ops_env
  run_scrum task move 30 --sprint "Sprint 2"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "Sprint 2 is closed"
  assert_eq "" "$(gh_writes)"
}

test_cmd_task_move_checks_every_task_first() {
  ops_env
  run_scrum task move 30,31 --sprint "Sprint 4"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "#31 is not a task"
  assert_eq "" "$(gh_writes)" "#30 not moved either"
}

test_cmd_task_estimate_replaces_points() {
  ops_env
  run_scrum task estimate 12 7
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'PUT repos/acme/blog/issues/12/labels'
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In progress","points: 7"]}'
}

test_cmd_task_estimate_outside_scale_calls_nothing() {
  ops_env
  run_scrum task estimate 12 5
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "5 is not in the point scale (0, 1, 3, 7)"
  assert_eq "" "$(gh_writes)" "no GitHub writes"
  assert_not_contains "$(gh_calls)" "issues/12" "checked before reading the issue"
}

test_cmd_task_assign_and_unassign() {
  ops_env
  run_scrum task assign 14 @alice bob
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" '-X POST repos/acme/blog/issues/14/assignees'
  assert_contains "$(gh_calls)" 'STDIN {"assignees":["alice","bob"]}'
  : > "$FAKE_GH_LOG"
  run_scrum task assign 14 alice --unassign
  assert_contains "$(gh_calls)" '-X DELETE repos/acme/blog/issues/14/assignees'
  assert_contains "$(gh_calls)" 'STDIN {"assignees":["alice"]}'
}

test_cmd_task_drop_with_reason() {
  ops_env
  run_scrum task drop 14 --reason "A library does this"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'Dropped (not planned): A library does this'
  assert_contains "$(gh_calls)" 'STDIN {"state":"closed","state_reason":"not_planned"}'
}

test_cmd_task_drop_closed_task_refused() {
  ops_env
  run_scrum task drop 13
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "#13 is closed"
  assert_eq "" "$(gh_writes)"
}

# delta task-management "Lệnh task với In review"
test_cmd_task_list_in_review() {
  ops_env
  printf 'version: 1\nstatuses:\n  in_review: In review\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  ops_issue 14 'In review' 3 alice 4 > "$FAKE_GH_DIR/i14.json"
  jq -s . "$FAKE_GH_DIR/i12.json" "$FAKE_GH_DIR/i14.json" > "$FAKE_GH_DIR/sprint.json"
  run_scrum task list --status in_review
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#14  In review  3 pt  @alice  Task 14"
  assert_not_contains "$OUT" "#12"
}

test_cmd_task_list_in_review_refused_when_off() {
  ops_env
  run_scrum task list --status in_review
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "statuses.in_review"
}

# ---------- logins outside the team (spec team "Cảnh báo login ngoài team") ----------

test_cmd_task_assign_warns_about_a_login_outside_the_team() {
  ops_env
  printf 'team:\n  - login: tuandt\n  - login: an-nguyen\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum task assign 14 tuandtt
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$ERR" "tuandtt is not in the team"
  assert_contains "$ERR" "tuandt, an-nguyen"
  assert_contains "$(gh_calls)" 'STDIN {"assignees":["tuandtt"]}' "still assigned"
}

test_cmd_task_assign_no_warning_without_team() {
  ops_env
  run_scrum task assign 14 bob
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$ERR" "not in the team"
}

test_cmd_task_assign_known_login_any_case_no_warning() {
  ops_env
  printf 'team:\n  - login: tuandt\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum task assign 14 TuanDT
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$ERR" "not in the team"
}

test_cmd_task_new_warns_about_a_login_outside_the_team() {
  task_env
  printf 'team:\n  - login: ruby\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":1,"title":"x","html_url":"u"}'
  run_scrum task new --title "x" --assignee bob --assignee ruby
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$ERR" "bob is not in the team (team in .github/scrum.yml: ruby)"
  assert_not_contains "$ERR" "ruby is not"
  assert_contains "$(gh_calls)" '"assignees":["bob","ruby"]'
}

# ---------- spec scenarios checked end to end (tests added for the team-and-backlog-tasks change) ----------

# "Vừa backlog vừa sprint" with the options the other way round.
test_cmd_task_new_sprint_then_backlog_refused() {
  task_env
  run_scrum task new --title "Fix login" --sprint "Sprint 1" --backlog
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "use --sprint or --backlog, not both"
  assert_eq "" "$(gh_writes)"
}

# "Sprint chỉ định không tồn tại" when no sprint is open at all: still an error, not the backlog.
test_cmd_task_new_unknown_sprint_without_open_sprint() {
  task_env
  jq '.[0].state = "closed"' "$FIXTURES/milestones.json" > "$FAKE_GH_DIR/milestones.json"
  run_scrum task new --title "Fix login" --sprint "Sprint 9"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "Sprint 9"
  assert_eq "" "$(gh_writes)"
}

# "Chủ động đưa vào backlog" with points, an assignee and bug: no milestone, the rest kept.
test_cmd_task_new_backlog_keeps_points_and_assignee() {
  task_env
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":3,"title":"Fix login","html_url":"u3"}'
  run_scrum task new --title "Fix login" --backlog --points 3 --assignee ruby --bug
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"title":"Fix login","body":"","labels":["status: New","points: 3","bug"],"assignees":["ruby"]}'
}

# "Team trống" with an explicit empty list: no warning.
test_cmd_task_assign_no_warning_with_empty_team_list() {
  ops_env
  printf 'team: []\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum task assign 14 bob
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$ERR" "not in the team"
}

# A login written with @ in the team and in --assignee is the same person: no warning.
test_cmd_task_new_at_login_in_team_no_warning() {
  task_env
  printf 'team:\n  - login: "@ruby"\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":1,"title":"x","html_url":"u"}'
  run_scrum task new --title "x" --assignee @ruby
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$ERR" "not in the team"
}

# A login is passed as it is, never expanded by the shell.
test_cmd_task_logins_are_not_globbed() {
  ops_env
  printf 'team:\n  - login: tuandt\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  touch "$T/aaa" "$T/bbb"
  run_scrum task assign 14 '*'
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"assignees":["*"]}'
  assert_contains "$ERR" "* is not in the team"
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":1,"title":"x","html_url":"u"}'
  run_scrum task new --title x --assignee '*' --backlog
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" '"assignees":["*"]'
}

# ---------- time estimates (spec time-estimate) ----------

# "Tạo task có thời gian"
test_cmd_task_new_with_time_estimate() {
  task_env
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":3,"title":"Fix login","html_url":"u3"}'
  run_scrum task new --title "Fix login" --work 15m --review 10m
  assert_status 0 "$STATUS" "$ERR"
  local body
  body="$(gh_calls | sed -n 's/^STDIN //p' | jq -r .body)"
  assert_contains "$body" "<!-- scrum:estimate -->"
  assert_contains "$body" "AI ~15m · Review ~10m"
  assert_contains "$body" '<!-- {"work_minutes":15,"review_minutes":10,"by":"ai"} -->'
}

test_cmd_task_new_time_estimate_in_vietnamese_and_by_human() {
  task_env
  printf 'version: 1\nlanguage: vi\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":3,"title":"x","html_url":"u3"}'
  run_scrum task new --title "x" --body "Do it" --work 1h30m --by human
  assert_status 0 "$STATUS" "$ERR"
  local body
  body="$(gh_calls | sed -n 's/^STDIN //p' | jq -r .body)"
  case "$body" in "Do it"*) ;; *) _fail "body starts with its text: $body" ;; esac
  assert_contains "$body" "Người ~1h30m"
  assert_contains "$body" '{"work_minutes":90,"by":"human"}'
}

# "Không hợp lệ"
test_cmd_task_new_invalid_duration_writes_nothing() {
  task_env
  run_scrum task new --title "x" --review abc
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--review"
  assert_contains "$ERR" "1h30m"
  assert_eq "" "$(gh_calls)" "nothing read or written"
}

test_cmd_task_new_without_time_has_no_block() {
  task_env
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":3,"title":"x","html_url":"u3"}'
  run_scrum task new --title "x"
  assert_not_contains "$(gh_calls)" "scrum:estimate"
}

est_issue() { # est_issue BODY  -> issue 12 with that body, 3 points, In progress
  jq -c --arg b "$1" '.body = $b' "$FAKE_GH_DIR/i12.json" > "$FAKE_GH_DIR/i12b.json"
  route_first 'api repos/acme/blog/issues/12' i12b.json
}
EST_BODY='Lưu bình luận

<!-- scrum:estimate -->
AI ~25m · Review ~20m
<!-- {"work_minutes":25,"review_minutes":20,"by":"ai"} -->
<!-- /scrum:estimate -->'

# "Chỉ đổi thời gian" and "Ghi đè"
test_cmd_task_estimate_only_time_keeps_points() {
  ops_env
  est_issue "$EST_BODY"
  run_scrum task estimate 12 --review 30m
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$(gh_calls)" "labels" "points untouched"
  assert_contains "$(gh_calls)" "-X PATCH repos/acme/blog/issues/12 --input -"
  local body
  body="$(gh_calls | sed -n 's/^STDIN //p' | jq -r .body)"
  case "$body" in "Lưu bình luận"*) ;; *) _fail "body starts with its text: $body" ;; esac
  assert_eq "1" "$(printf '%s' "$body" | grep -c '<!-- scrum:estimate -->')"
  assert_contains "$body" '{"work_minutes":25,"review_minutes":30,"by":"ai"}'
  assert_contains "$OUT" "#12 time estimate: work 25m (AI), review 30m."
}

test_cmd_task_estimate_first_time_on_a_plain_body() {
  ops_env
  est_issue "Lưu bình luận"
  run_scrum task estimate 12 --work 25 --review 20m
  assert_status 0 "$STATUS" "$ERR"
  local body
  body="$(gh_calls | sed -n 's/^STDIN //p' | jq -r .body)"
  assert_eq "$EST_BODY" "$body"
}

test_cmd_task_estimate_points_and_time() {
  ops_env
  est_issue "$EST_BODY"
  run_scrum task estimate 12 7 --by human
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In progress","points: 7"]}'
  assert_contains "$(gh_calls)" 'Human ~25m · Review ~20m'
  assert_contains "$OUT" "#12 now has 7 points."
}

test_cmd_task_estimate_same_time_writes_nothing() {
  ops_env
  est_issue "$EST_BODY"
  run_scrum task estimate 12 --work 25m
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
  assert_contains "$OUT" "already has this time estimate"
}

# "Không có gì để đổi"
test_cmd_task_estimate_nothing_to_change() {
  ops_env
  run_scrum task estimate 12
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "give points, or at least one of --work, --review, --by"
  assert_eq "" "$(gh_calls)" "nothing read or written"
}

test_cmd_task_estimate_invalid_duration_calls_nothing() {
  ops_env
  run_scrum task estimate 12 --work 0
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--work"
  assert_eq "" "$(gh_calls)"
}

test_cmd_task_estimate_by_alone_without_estimate_refused() {
  ops_env
  run_scrum task estimate 12 --by human
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--by needs --work or --review"
  assert_eq "" "$(gh_writes)"
}

test_cmd_task_estimate_broken_block_is_rewritten() {
  ops_env
  est_issue 'Text

<!-- scrum:estimate -->
AI ~25m
<!-- {"work_minutes": -->
<!-- /scrum:estimate -->'
  run_scrum task estimate 12 --review 10m
  assert_status 0 "$STATUS" "$ERR"
  local body
  body="$(gh_calls | sed -n 's/^STDIN //p' | jq -r .body)"
  assert_eq 'Text

<!-- scrum:estimate -->
Review ~10m
<!-- {"review_minutes":10,"by":"ai"} -->
<!-- /scrum:estimate -->' "$body"
}

# ---------- time estimates: edge cases (tests for the spec scenarios) ----------

# Points only, as before the change: the label changes, the body (and its estimate block) is not written.
test_cmd_task_estimate_points_only_leaves_the_estimate_block() {
  ops_env
  est_issue "$EST_BODY"
  run_scrum task estimate 12 7
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In progress","points: 7"]}'
  assert_not_contains "$(gh_calls)" "-X PATCH" "the body is not written"
  assert_not_contains "$OUT" "time estimate"
  assert_contains "$OUT" "#12 now has 7 points."
}

# Durations with spaces around them, hours with 0 minutes, plain minutes.
test_cmd_task_estimate_duration_forms() {
  ops_env
  est_issue "Lưu bình luận"
  run_scrum task estimate 12 --work ' 25m' --review 1h0m
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls | sed -n 's/^STDIN //p' | jq -r .body)" '{"work_minutes":25,"review_minutes":60,"by":"ai"}'
}

test_cmd_task_estimate_bare_unit_refused() {
  local d
  for d in h m 0m; do
    ops_env
    run_scrum task estimate 12 --review "$d"
    assert_status 1 "$STATUS" "--review $d"
    assert_contains "$ERR" "--review"
    assert_contains "$ERR" "1h30m"
    assert_eq "" "$(gh_calls)" "nothing read or written for $d"
  done
}

# "Ghi đè" in the language of the repository: the line people read is in Vietnamese.
test_cmd_task_estimate_overwrite_in_vietnamese() {
  ops_env
  printf 'version: 1\nlanguage: vi\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  est_issue "$EST_BODY"
  run_scrum task estimate 12 --by human
  assert_status 0 "$STATUS" "$ERR"
  local body
  body="$(gh_calls | sed -n 's/^STDIN //p' | jq -r .body)"
  assert_contains "$body" "Người ~25m · Review ~20m"
  assert_contains "$body" '{"work_minutes":25,"review_minutes":20,"by":"human"}'
  assert_eq "1" "$(printf '%s' "$body" | grep -c '<!-- scrum:estimate -->')"
}

# "Ghi đè" on a body with two estimate blocks (one pasted by hand): one block is left.
test_cmd_task_estimate_two_blocks_become_one() {
  ops_env
  est_issue "$EST_BODY

<!-- scrum:estimate -->
AI ~99m
<!-- {\"work_minutes\":99} -->
<!-- /scrum:estimate -->"
  run_scrum task estimate 12 --review 30m
  assert_status 0 "$STATUS" "$ERR"
  local body
  body="$(gh_calls | sed -n 's/^STDIN //p' | jq -r .body)"
  assert_eq "1" "$(printf '%s' "$body" | grep -c '<!-- scrum:estimate -->')"
  assert_contains "$body" '{"work_minutes":25,"review_minutes":30,"by":"ai"}'
}
