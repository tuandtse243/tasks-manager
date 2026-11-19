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
  assert_eq "false" "$(status_of '["status: Done"]' done | jq -r .changed)"
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

test_cmd_task_new_without_open_sprint() {
  task_env
  jq '.[0].state = "closed"' "$FIXTURES/milestones.json" > "$FAKE_GH_DIR/milestones.json"
  run_scrum task new --title "x"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "/scrum-github:sprint-new"
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
