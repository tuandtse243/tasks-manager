# spec: pr-task-linking

links() { jqt links -n --arg body "$1" --arg repo "acme/blog" | jq -c .; }

test_link_closes() { assert_eq '{"issues":[1],"solve":[]}' "$(links 'Closes #1')"; }
test_link_several() { assert_eq '{"issues":[2,3],"solve":[]}' "$(links 'fixes #2, resolves #3')"; }
test_link_case_and_variants() { assert_eq '[1,2,3,4]' "$(links 'CLOSED #1. Fixed #2
Resolve: #3 close acme/Blog#4' | jq -c .issues)"; }
test_link_solve_is_not_a_link() { assert_eq '{"issues":[],"solve":[1]}' "$(links 'Solve #1')"; }
test_link_other_repo_ignored() { assert_eq '[]' "$(links 'Closes other-org/other-repo#5' | jq -c .issues)"; }
test_link_not_inside_words_or_comments() {
  assert_eq '[]' "$(links 'unfixes #3 and enclosed #4 <!-- Closes #9 --> Closes #' | jq -c .issues)"
}
test_link_template_placeholder() {
  assert_eq '[]' "$(links "$(sed 's/{{NO_TASK_LABEL}}/no-task/' "$PLUGIN_DIR/templates/github/pull_request_template.md")" | jq -c .issues)"
}

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }
decide() { jqt event-decide -n --argjson cfg "$(defaults)" --arg kind "$1" --argjson issue "$2" | jq -c '{skip, labels: (.labels | if . then sort else . end), close}'; }

test_decide_open_moves_new_to_in_progress() {
  assert_eq '{"skip":null,"labels":["points: 3","status: In progress"],"close":false}' \
    "$(decide pr_open '{"number":1,"state":"open","labels":[{"name":"status: New"},{"name":"points: 3"}]}')"
}
test_decide_open_without_status() {
  assert_eq '["status: In progress"]' "$(decide pr_open '{"number":1,"state":"open","labels":[]}' | jq -c .labels)"
}
test_decide_open_does_not_move_back() {
  assert_eq '"already done"' "$(decide pr_open '{"number":1,"state":"open","labels":[{"name":"status: Done"}]}' | jq -c .skip)"
  assert_eq '"issue is closed"' "$(decide pr_open '{"number":1,"state":"closed","state_reason":"completed","labels":[{"name":"status: Done"}]}' | jq -c .skip)"
}
test_decide_merge_sets_done_and_closes() {
  assert_eq '{"skip":null,"labels":["status: Done"],"close":true}' \
    "$(decide pr_merged '{"number":1,"state":"open","labels":[{"name":"status: In progress"}]}')"
}
test_decide_merge_already_done_and_closed() {
  assert_eq '"already done"' "$(decide pr_merged '{"number":1,"state":"closed","state_reason":"completed","labels":[{"name":"status: Done"}]}' | jq -c .skip)"
}
test_decide_issue_closed_completed() {
  assert_eq '["status: Done"]' "$(decide issue_closed '{"number":3,"state":"closed","state_reason":"completed","labels":[{"name":"status: In progress"}]}' | jq -c .labels)"
  assert_eq '"closed as not planned"' "$(decide issue_closed '{"number":3,"state":"closed","state_reason":"not_planned","labels":[]}' | jq -c .skip)"
}
test_decide_issue_reopened() {
  assert_eq '["status: In progress"]' "$(decide issue_reopened '{"number":3,"state":"open","labels":[{"name":"status: Done"}]}' | jq -c .labels)"
}
test_decide_issue_reopened_keeps_new() {
  assert_eq '"already new"' "$(decide issue_reopened '{"number":3,"state":"open","labels":[{"name":"status: New"},{"name":"points: 3"}]}' | jq -c .skip)"
}
test_decide_issue_reopened_without_status() {
  assert_eq '["status: In progress"]' "$(decide issue_reopened '{"number":3,"state":"open","labels":[]}' | jq -c .labels)"
}
test_decide_skips_feature_meta_pr() {
  assert_eq '"feature or meta issue"' "$(decide issue_reopened '{"number":5,"state":"open","labels":[{"name":"type: feature"}]}' | jq -c .skip)"
  assert_eq '"feature or meta issue"' "$(decide issue_closed '{"number":8,"state":"closed","labels":[{"name":"scrum: meta"}]}' | jq -c .skip)"
  assert_eq '"is a pull request"' "$(decide pr_open '{"number":6,"state":"open","pull_request":{},"labels":[]}' | jq -c .skip)"
}
test_decide_issue_form_points() {
  assert_eq '["points: 7","status: New"]' \
    "$(decide issue_opened '{"number":9,"state":"open","body":"### Description\n\nSign up\n\n### Points\n\n7","labels":[{"name":"status: New"}]}' | jq -c .labels)"
  assert_eq '"no points in the issue form"' \
    "$(decide issue_opened '{"number":9,"state":"open","body":"### Points\n\n_No response_","labels":[]}' | jq -c .skip)"
}

# ---------- commands ----------

event_env() { # event_env EVENT_NAME EVENT_JSON
  setup_fake_gh
  setup_repo 'version: 1'
  export GITHUB_EVENT_NAME="$1" GITHUB_EVENT_PATH="$T/event.json"
  printf '%s' "$2" > "$GITHUB_EVENT_PATH"
}

test_cmd_event_pr_opened() {
  event_env pull_request_target '{"action":"opened","pull_request":{"number":20,"body":"Closes #1","merged":false,"labels":[]}}'
  route_json 'api repos/acme/blog/issues/1' '{"number":1,"state":"open","labels":[{"name":"status: New"}]}'
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'api -X PUT repos/acme/blog/issues/1/labels --input -'
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In progress"]}'
}

test_cmd_event_pr_merged_into_any_branch() {
  event_env pull_request_target '{"action":"closed","pull_request":{"number":20,"body":"Closes #1","merged":true,"base":{"ref":"release"}}}'
  route_json 'api repos/acme/blog/issues/1' '{"number":1,"state":"open","labels":[{"name":"status: In progress"}]}'
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: Done"]}'
  assert_contains "$(gh_calls)" 'STDIN {"state":"closed","state_reason":"completed"}'
}

test_cmd_event_pr_closed_unmerged() {
  event_env pull_request_target '{"action":"closed","pull_request":{"number":20,"body":"Closes #1","merged":false}}'
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
  assert_not_contains "$(gh_calls)" "issues/1"
}

test_cmd_event_issue_closed_by_hand() {
  event_env issues '{"action":"closed","issue":{"number":3,"state":"closed","state_reason":"completed","labels":[{"name":"status: In progress"}]}}'
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'api -X PUT repos/acme/blog/issues/3/labels --input -'
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: Done"]}'
}

test_cmd_event_reopened_pr_keeps_done() {
  event_env pull_request_target '{"action":"reopened","pull_request":{"number":20,"body":"Closes #1"}}'
  route_json 'api repos/acme/blog/issues/1' '{"number":1,"state":"closed","state_reason":"completed","labels":[{"name":"status: Done"}]}'
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
}

check_env() { event_env pull_request_target "$1"; }

test_pr_check_missing_link() {
  check_env '{"action":"opened","pull_request":{"number":20,"body":"Adds login","labels":[]}}'
  run_scrum pr-check
  assert_status 1 "$STATUS"
  assert_contains "$OUT" '::error title=No linked task::'
  assert_contains "$ERR" 'Add "Closes #<task number>"'
  assert_contains "$ERR" '"no-task" label'
}

test_pr_check_solve_suggestion() {
  check_env '{"action":"opened","pull_request":{"number":20,"body":"Solve #1","labels":[]}}'
  run_scrum pr-check
  assert_status 1 "$STATUS"
  assert_contains "$ERR" 'replace "Solve #1" with "Closes #1"'
}

test_pr_check_passes_with_link() {
  check_env '{"action":"edited","pull_request":{"number":20,"body":"Closes #1","labels":[]}}'
  run_scrum pr-check
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "OK: closes #1."
}

test_pr_check_passes_with_filled_template() {
  local body
  body="$(sed -e 's/{{NO_TASK_LABEL}}/no-task/' -e 's/^Closes #$/Closes #12/' "$PLUGIN_DIR/templates/github/pull_request_template.md")"
  check_env "$(jq -n --arg b "$body" '{action:"opened",pull_request:{number:20,body:$b,labels:[]}}')"
  run_scrum pr-check
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "OK: closes #12."
}

test_pr_check_no_task_label() {
  check_env '{"action":"labeled","pull_request":{"number":20,"body":"Bump deps","labels":[{"name":"no-task"}]}}'
  run_scrum pr-check
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_calls)" "pr-check needs no GitHub calls"
}

# ---------- with statuses.in_review set (delta pr-task-linking "Vòng đời PR khi bật In review") ----------

review_cfg() { defaults | jq -c '.statuses.in_review = "In review"'; }
rdecide() { # rdecide KIND ISSUE DRAFT
  jqt event-decide -n --argjson cfg "$(review_cfg)" --arg kind "$1" --argjson issue "$2" --argjson draft "${3:-false}" \
    | jq -c '{skip, labels: (.labels | if . then sort else . end), close}'
}
iss() { jq -nc --arg s "$1" '{number: 1, state: "open", labels: [{name: "status: \($s)"}]}'; }

test_review_draft_pr_opened_moves_new_to_in_progress() {
  assert_eq '["status: In progress"]' "$(rdecide pr_open "$(iss New)" true | jq -c .labels)"
}
test_review_ready_pr_moves_to_in_review() {
  assert_eq '["status: In review"]' "$(rdecide pr_open "$(iss 'In progress')" false | jq -c .labels)"
  assert_eq '["status: In review"]' "$(rdecide pr_open "$(iss New)" false | jq -c .labels)" "non-draft PR opened on a New task"
}
test_review_converted_to_draft_moves_back() {
  assert_eq '["status: In progress"]' "$(rdecide pr_draft "$(iss 'In review')" | jq -c .labels)"
}
test_review_closed_unmerged_moves_back_from_review_only() {
  assert_eq '["status: In progress"]' "$(rdecide pr_closed "$(iss 'In review')" | jq -c .labels)"
  assert_eq '"not in review"' "$(rdecide pr_closed "$(iss New)" | jq -c .skip)"
}
test_review_merge_sets_done() {
  assert_eq '{"skip":null,"labels":["status: Done"],"close":true}' "$(rdecide pr_merged "$(iss 'In review')")"
}
test_review_never_moves_done_back() {
  assert_eq '"already done"' "$(rdecide pr_open "$(iss Done)" false | jq -c .skip)"
  assert_eq '"already done"' "$(rdecide pr_draft "$(iss Done)" | jq -c .skip)"
}

test_off_mode_ignores_draft_and_unmerged_close() {
  assert_eq '["status: In progress"]' "$(decide pr_open "$(iss New)" | jq -c .labels)" "draft or not, as before"
  assert_eq '"no In review status"' "$(decide pr_draft "$(iss 'In progress')" | jq -c .skip)"
  assert_eq '"no In review status"' "$(decide pr_closed "$(iss 'In progress')" | jq -c .skip)"
}

test_cmd_event_review_ready_for_review() {
  event_env pull_request_target '{"action":"ready_for_review","pull_request":{"number":20,"draft":false,"body":"Closes #1","merged":false}}'
  printf 'version: 1\nstatuses:\n  in_review: In review\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_json 'api repos/acme/blog/issues/1' '{"number":1,"state":"open","labels":[{"name":"status: In progress"}]}'
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In review"]}'
}

test_cmd_event_review_converted_to_draft() {
  event_env pull_request_target '{"action":"converted_to_draft","pull_request":{"number":20,"draft":true,"body":"Closes #1","merged":false}}'
  printf 'version: 1\nstatuses:\n  in_review: In review\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_json 'api repos/acme/blog/issues/1' '{"number":1,"state":"open","labels":[{"name":"status: In review"}]}'
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In progress"]}'
}

test_cmd_event_review_closed_unmerged() {
  event_env pull_request_target '{"action":"closed","pull_request":{"number":20,"draft":false,"body":"Closes #1","merged":false}}'
  printf 'version: 1\nstatuses:\n  in_review: In review\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_json 'api repos/acme/blog/issues/1' '{"number":1,"state":"open","labels":[{"name":"status: In review"}]}'
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In progress"]}'
}

test_cmd_event_off_converted_to_draft_writes_nothing() {
  event_env pull_request_target '{"action":"converted_to_draft","pull_request":{"number":20,"draft":true,"body":"Closes #1","merged":false}}'
  route_json 'api repos/acme/blog/issues/1' '{"number":1,"state":"open","labels":[{"name":"status: In progress"}]}'
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
}
