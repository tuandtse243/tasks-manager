# spec: project-board-sync

pcfg() { jq '.project += {enabled: true, owner: "acme", number: 2}' "$PLUGIN_DIR/runtime/share/defaults.json"; }
pmeta() { jqt project-meta --argjson cfg "$(pcfg)" < "$FIXTURES/${1:-project-meta.json}"; }

# item NUMBER LABELS_CSV BOARD SYNCED [STATE] [POINTS_ON_BOARD]  -> one normalized item
item() {
  jq -n -c --arg n "$1" --arg l "$2" --arg b "$3" --arg s "$4" --arg st "${5:-open}" --arg p "${6:-}" '{
    item_id: "PVTI_\($n)", node_id: "I_\($n)", number: ($n | tonumber), repo: "acme/blog",
    state: $st, state_reason: (if $st == "closed" then "completed" else null end),
    labels: ($l | split(",") | map(select(. != "") | {name: .})),
    milestone: {number: 1, state: "OPEN"},
    board: (if $b == "" then null else $b end), synced: (if $s == "" then null else $s end),
    points: (if $p == "" then null else ($p | tonumber) end)}'
}
plan() { # plan ITEM... -> sync plan for these items
  jq -s . <<<"$*" | jqt project-sync-plan --argjson cfg "$(pcfg)" --argjson meta "$(pmeta)"
}
ops() { plan "$@" | jq -c '[.ops[] | del(.msg, .item_id)]'; }

# ---------- metadata ----------

test_meta_ready_project() {
  local m; m="$(pmeta)"
  assert_json_eq '{"new":"O_todo","in_progress":"O_prog","done":"O_done"}' "$(printf '%s' "$m" | jq -c .options)"
  assert_eq "F_synced F_points" "$(printf '%s' "$m" | jq -r '"\(.synced_field) \(.points_field)"')"
  assert_eq '[]' "$(printf '%s' "$m" | jq -c '.missing_fields + .missing_options + .conflicts')"
}

test_meta_new_project_needs_fields_and_has_conflict() {
  local m; m="$(pmeta project-meta-new.json)"
  assert_json_eq '[{"name":"Synced status","type":"TEXT"},{"name":"Points","type":"NUMBER"}]' "$(printf '%s' "$m" | jq -c .missing_fields)"
  assert_eq '["Item closed"]' "$(printf '%s' "$m" | jq -c .conflicts)"
}

test_meta_missing_option() {
  local m
  m="$(jq '.data.repositoryOwner.projectV2.fields.nodes |= map(if .name == "Status" then .options |= map(select(.name != "In Progress")) else . end)' \
        "$FIXTURES/project-meta.json" | jqt project-meta --argjson cfg "$(pcfg)")"
  assert_eq '["In Progress"]' "$(printf '%s' "$m" | jq -c .missing_options)"
}

test_meta_points_off() {
  local m
  m="$(jqt project-meta --argjson cfg "$(pcfg | jq '.project.points_field = null')" < "$FIXTURES/project-meta.json")"
  assert_eq "null" "$(printf '%s' "$m" | jq -c .points_field)"
  assert_eq '[]' "$(printf '%s' "$m" | jq -c .missing_fields)"
}

test_items_keep_only_this_repos_issues() {
  local items
  items="$(jq '.data.node.items.nodes' "$FIXTURES/project-items.json" | jqt project-items --arg repo acme/blog)"
  assert_eq '[1,2,3,9]' "$(printf '%s' "$items" | jq -c 'map(.number)')"
  assert_json_eq '{"number":3,"state":"open","state_reason":null,"board":"Done","synced":"in_progress","points":1}' \
    "$(printf '%s' "$items" | jq -c '.[] | select(.number == 3) | {number,state,state_reason,board,synced,points}')"
}

# ---------- decisions (L = label, B = board, S = synced) ----------

test_plan_card_moved_on_board() {
  assert_json_eq '[{"op":"set_labels","number":5,"labels":["points: 3","status: In progress"]},{"op":"set_synced","number":5,"text":"in_progress"}]' \
    "$(ops "$(item 5 'status: New,points: 3' 'In Progress' new open 3)")"
}

test_plan_status_changed_by_pr() {
  assert_json_eq '[{"op":"set_status","number":5,"option_id":"O_done"},{"op":"set_synced","number":5,"text":"done"}]' \
    "$(ops "$(item 5 'status: Done' Todo new closed)")"
}

test_plan_both_changed_label_wins() {
  local p
  p="$(plan "$(item 5 'status: In progress' Done new)")"
  assert_json_eq '["comment","set_status","set_synced"]' "$(printf '%s' "$p" | jq -c '[.ops[].op]')"
  assert_eq "O_prog" "$(printf '%s' "$p" | jq -r '.ops[] | select(.op == "set_status") | .option_id')"
  assert_contains "$(printf '%s' "$p" | jq -r '.ops[0].body')" 'back in "In Progress"'
}

test_plan_both_changed_to_the_same() {
  assert_json_eq '[{"op":"set_synced","number":5,"text":"done"}]' "$(ops "$(item 5 'status: Done' Done new closed)")"
}

test_plan_no_change() {
  local p; p="$(plan "$(item 5 'status: New' Todo new)")"
  assert_eq '[]' "$(printf '%s' "$p" | jq -c .ops)"
  assert_eq "1" "$(printf '%s' "$p" | jq -r .unchanged)"
}

test_plan_new_item_follows_label() {
  assert_json_eq '[{"op":"set_status","number":5,"option_id":"O_prog"},{"op":"set_synced","number":5,"text":"in_progress"}]' \
    "$(ops "$(item 5 'status: In progress' Done '')")"
}

test_plan_garbage_synced_counts_as_empty() {
  assert_json_eq '["set_status","set_synced"]' "$(ops "$(item 5 'status: New' Done 'hello')" | jq -c 'map(.op)')"
}

test_plan_empty_column_gets_label() {
  assert_json_eq '[{"op":"set_status","number":5,"option_id":"O_todo"}]' "$(ops "$(item 5 'status: New' '' new)")"
}

test_plan_drag_to_done_closes() {
  assert_json_eq '[{"op":"set_labels","number":7,"labels":["status: Done"]},{"op":"close","number":7},{"op":"set_synced","number":7,"text":"done"}]' \
    "$(ops "$(item 7 'status: In progress' Done in_progress)")"
}

test_plan_drag_out_of_done_reopens_as_new() {
  assert_json_eq '[{"op":"set_labels","number":7,"labels":["status: New"]},{"op":"reopen","number":7},{"op":"set_synced","number":7,"text":"new"}]' \
    "$(ops "$(item 7 'status: Done' Todo 'done' closed)")"
}

test_plan_unknown_column_warns() {
  local p; p="$(plan "$(item 8 'status: New' Review new)")"
  assert_eq '[]' "$(printf '%s' "$p" | jq -c .ops)"
  assert_contains "$(printf '%s' "$p" | jq -r '.warnings[0]')" '#8 is in the board column "Review"'
}

test_plan_skips_feature_and_not_planned() {
  local closed_np
  closed_np="$(item 4 'status: New' Done new closed | jq -c '.state_reason = "not_planned"')"
  assert_eq '[]' "$(ops "$(item 9 'type: feature' Done '')" "$closed_np")"
}

# ---------- points ----------

test_plan_points_set_and_overwrite() {
  assert_json_eq '[{"op":"set_points","number":5,"value":3}]' "$(ops "$(item 5 'status: New,points: 3' Todo new open)")"
  assert_json_eq '[{"op":"set_points","number":5,"value":3}]' "$(ops "$(item 5 'status: New,points: 3' Todo new open 8)")"
}

test_plan_points_cleared_without_label() {
  assert_json_eq '[{"op":"clear_points","number":5}]' "$(ops "$(item 5 'status: New' Todo new open 3)")"
}

test_plan_points_off() {
  local m
  m="$(jqt project-meta --argjson cfg "$(pcfg | jq '.project.points_field = null')" < "$FIXTURES/project-meta.json")"
  assert_eq '[]' "$(item 5 'status: New,points: 3' Todo new | jq -s . | jqt project-sync-plan --argjson cfg "$(pcfg)" --argjson meta "$m" | jq -c .ops)"
}

# ---------- mutations ----------

test_mutations_batch_by_size() {
  local docs
  docs="$(jq -n '[range(0; 25) | {op: "set_synced", number: ., item_id: "PVTI_\(.)", text: "new"}]' \
          | jqt project-mutations --argjson meta "$(pmeta)")"
  assert_eq "2" "$(printf '%s' "$docs" | jq length)"
  assert_eq "20" "$(printf '%s' "$docs" | jq -r '.[0]' | grep -c 'updateProjectV2ItemFieldValue')"
  assert_contains "$(printf '%s' "$docs" | jq -r '.[1]')" 'm4: updateProjectV2ItemFieldValue(input: {projectId: "PVT_p1", itemId: "PVTI_24", fieldId: "F_synced", value: {text: "new"}})'
}

test_mutations_skip_issue_ops() {
  local docs
  docs="$(jq -n '[{op: "set_labels", number: 1, labels: []}, {op: "clear_points", number: 1, item_id: "PVTI_1"}, {op: "set_status", number: 1, item_id: "PVTI_1", option_id: "O_done"}]' \
          | jqt project-mutations --argjson meta "$(pmeta)" | jq -r '.[0]')"
  assert_contains "$docs" 'm0: clearProjectV2ItemFieldValue(input: {projectId: "PVT_p1", itemId: "PVTI_1", fieldId: "F_points"})'
  assert_contains "$docs" 'm1: updateProjectV2ItemFieldValue(input: {projectId: "PVT_p1", itemId: "PVTI_1", fieldId: "F_status", value: {singleSelectOptionId: "O_done"}})'
}

# ---------- commands with a fake gh ----------

PROJECT_YML='project:
  enabled: true
  owner: acme
  number: 2'

# project_env [META_FIXTURE]  Fake GitHub with the board of fixtures/project-items.json.
project_env() {
  setup_fake_gh
  setup_repo "$PROJECT_YML"
  export SCRUM_TODAY=2014-09-22
  cp "$FIXTURES/${1:-project-meta.json}" "$FAKE_GH_DIR/meta.json"
  cp "$FIXTURES/project-items.json" "$FAKE_GH_DIR/items.json"
  cp "$FIXTURES/milestones.json" "$FAKE_GH_DIR/milestones.json"
  jq 'map(. + {node_id: "I_\(.number)"})' "$FIXTURES/issues-sprint1.json" > "$FAKE_GH_DIR/issues.json"
  route 'api graphql -F query=@*/project.graphql*' meta.json
  route 'api graphql -F query=@*/items.graphql*' items.json
  route_json 'api graphql -F query=@*/add-item.graphql*' '{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_new"}}}}'
  route_json 'api graphql -F query=@*/create-field.graphql*' '{"data":{"createProjectV2Field":{"projectV2Field":{"id":"F_x"}}}}'
  route_json 'api graphql -f query=mutation*' '{"data":{}}'
  route 'api --paginate repos/acme/blog/milestones*' milestones.json
  route 'api --paginate repos/acme/blog/issues?milestone=1*' issues.json
}
gh_mutations() { grep -E 'api graphql (-f query=mutation|-F query=@.*/(add-item|create-field)\.graphql)' "$FAKE_GH_LOG" || true; }

test_cmd_sync_applies_both_directions() {
  project_env
  run_scrum project sync
  assert_status 0 "$STATUS" "$ERR"
  local w; w="$(gh_writes)"
  assert_contains "$w" "PUT repos/acme/blog/issues/2/labels"
  assert_contains "$w" "PUT repos/acme/blog/issues/3/labels"
  assert_contains "$w" "PATCH repos/acme/blog/issues/3"
  assert_not_contains "$w" "issues/1/"
  assert_not_contains "$w" "issues/9/"
  # labels before closing, both before the board fields
  assert_eq "PUT repos/acme/blog/issues/3/labels" "$(grep -oE -- '(PUT|PATCH) repos/acme/blog/issues/3[a-z/]*' "$FAKE_GH_LOG" | head -1)"
  assert_contains "$(gh_calls)" 'STDIN {"state":"closed","state_reason":"completed"}'
  assert_contains "$(gh_mutations)" "content=I_4" "#4 of the open sprint added to the board"
  assert_contains "$OUT" "#3: closed as completed"
  assert_contains "$OUT" "Board sync: 1 added, 3 changed, 1 unchanged."
}

test_cmd_sync_second_run_changes_nothing() {
  project_env
  # The board after the first run: every item agrees, #4 is on it.
  jq '.data.node.items.nodes |= (map(
        if .content.number == 2 then .content.labels.nodes = [{"name":"status: In progress"},{"name":"points: 3"}] | .synced.text = "in_progress"
        elif .content.number == 3 then .content.state = "CLOSED" | .content.stateReason = "COMPLETED" | .content.labels.nodes = [{"name":"status: Done"},{"name":"points: 1"}] | .synced.text = "done"
        else . end)
      + [{"id":"PVTI_4","type":"ISSUE","content":{"id":"I_4","number":4,"state":"OPEN","stateReason":null,"repository":{"nameWithOwner":"acme/blog"},"labels":{"nodes":[{"name":"status: New"},{"name":"points: 3"}]},"milestone":{"number":1,"state":"OPEN"}},"status":{"name":"Todo"},"synced":{"text":"new"},"points":{"number":3}}])' \
    "$FIXTURES/project-items.json" > "$FAKE_GH_DIR/items.json"
  run_scrum project sync
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
  assert_eq "" "$(gh_mutations)"
}

test_cmd_sync_reads_every_page() {
  project_env
  jq '.data.node.items.pageInfo = {"hasNextPage": true, "endCursor": "CUR1"} | .data.node.items.nodes = [.data.node.items.nodes[0]]' \
    "$FIXTURES/project-items.json" > "$FAKE_GH_DIR/page1.json"
  : > "$FAKE_GH_DIR/routes.new"
  printf '%s\t%s\n' 'api graphql -F query=@*/items.graphql* -f after=CUR1' items.json > "$FAKE_GH_DIR/routes.new"
  sed 's#items.json$#page1.json#' "$FAKE_GH_DIR/routes" >> "$FAKE_GH_DIR/routes.new"
  mv "$FAKE_GH_DIR/routes.new" "$FAKE_GH_DIR/routes"
  run_scrum project sync
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "2" "$(grep -c 'items.graphql' "$FAKE_GH_LOG")"
  assert_contains "$(gh_writes)" "PUT repos/acme/blog/issues/3/labels" "item from page 2 synced"
}

test_cmd_sync_label_failure_keeps_board() {
  project_env
  route 'api -X PUT repos/acme/blog/issues/3/labels*' '!fail'
  # the failure route must win over nothing else; put it first
  { grep 'issues/3/labels' "$FAKE_GH_DIR/routes"; grep -v 'issues/3/labels' "$FAKE_GH_DIR/routes"; } > "$FAKE_GH_DIR/r2"; mv "$FAKE_GH_DIR/r2" "$FAKE_GH_DIR/routes"
  run_scrum project sync
  assert_status 1 "$STATUS"
  assert_not_contains "$(gh_writes)" "PATCH repos/acme/blog/issues/3" "no close after the label failed"
  assert_not_contains "$(gh_calls)" '"PVTI_3"' "no board update for #3"
  assert_contains "$(gh_calls)" '"PVTI_2"' "other issues still synced"
}

test_cmd_sync_uses_project_token() {
  project_env
  SCRUM_PROJECT_TOKEN=pat123 run_scrum project sync
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" "TOKEN pat123"
  # every write and every GraphQL call goes out with the project token
  assert_eq "$(grep -cE -- '-X (PUT|PATCH|POST)|^api graphql' "$FAKE_GH_LOG")" \
    "$(grep -B1 -E -- '-X (PUT|PATCH|POST)|^api graphql' "$FAKE_GH_LOG" | grep -c '^TOKEN pat123')"
}

test_cmd_sync_missing_secret_in_actions() {
  project_env
  GITHUB_ACTIONS=true SCRUM_PROJECT_TOKEN='' run_scrum project sync
  assert_status 1 "$STATUS"
  assert_contains "$OUT" "::error title=Project token missing::"
  assert_contains "$ERR" "SCRUM_PROJECT_TOKEN"
  assert_eq "" "$(gh_writes)"
}

test_cmd_sync_off_does_nothing() {
  setup_fake_gh
  setup_repo 'version: 1'
  run_scrum project sync
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "off"
  assert_not_contains "$(gh_calls)" "graphql"
}

test_cmd_sync_not_ready_points_to_init() {
  project_env project-meta-new.json
  run_scrum project sync
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "scrum project init"
  assert_eq "" "$(gh_writes)"
}

# --issue N (workflow on issue events)

issue_item_json() { # issue_item_json NUMBER LABELS_JSON MILESTONE_STATE ON_BOARD(yes/no) [BOARD] [SYNCED]
  jq -n -c --argjson n "$1" --argjson l "$2" --arg ms "$3" --arg on "$4" --arg b "${5:-Todo}" --arg s "${6:-new}" '
    {data: {repository: {issue: {id: "I_\($n)", number: $n, state: "OPEN", stateReason: null,
      repository: {nameWithOwner: "acme/blog"}, labels: {nodes: ($l | map({name: .}))},
      milestone: (if $ms == "" then null else {number: 1, state: $ms} end),
      projectItems: {nodes: (if $on == "yes" then [{id: "PVTI_\($n)", type: "ISSUE", project: {id: "PVT_p1"},
        status: {name: $b}, synced: {text: $s}, points: null}] else [{id: "PVTI_o", type: "ISSUE", project: {id: "PVT_other"}, status: null, synced: null, points: null}] end)}}}}}'
}

test_cmd_sync_issue_adds_task_of_open_sprint() {
  project_env
  route_json 'api graphql -F query=@*/issue-item.graphql*' "$(issue_item_json 12 '["status: New","points: 3"]' OPEN no)"
  run_scrum project sync --issue 12
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_mutations)" "content=I_12"
  assert_contains "$(gh_calls)" 'itemId: "PVTI_new"'
  assert_contains "$OUT" "#12: added to the board"
  assert_not_contains "$(gh_calls)" "items.graphql" "one issue only"
}

test_cmd_sync_issue_without_sprint_is_left_out() {
  project_env
  route_json 'api graphql -F query=@*/issue-item.graphql*' "$(issue_item_json 12 '["status: New"]' '' no)"
  run_scrum project sync --issue 12
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_mutations)"
}

test_cmd_sync_issue_on_board() {
  project_env
  route_json 'api graphql -F query=@*/issue-item.graphql*' "$(issue_item_json 12 '["status: New"]' OPEN yes 'In Progress' new)"
  run_scrum project sync --issue 12
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_writes)" "PUT repos/acme/blog/issues/12/labels"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In progress"]}'
}

# ---------- project init ----------

test_cmd_init_default_project() {
  project_env project-meta-new.json
  # The project is read again after the fields are created: then it has them.
  cp "$FIXTURES/project-meta.json" "$FAKE_GH_DIR/meta2.json"
  sed 's#\tmeta.json$#\tmeta.json,meta2.json#' "$FAKE_GH_DIR/routes" > "$FAKE_GH_DIR/r2"; mv "$FAKE_GH_DIR/r2" "$FAKE_GH_DIR/routes"
  run_scrum project init --allow-builtin-workflows
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_mutations)" "name=Synced status -f type=TEXT"
  assert_contains "$(gh_mutations)" "name=Points -f type=NUMBER"
  assert_contains "$OUT" "created       Synced status (text)"
  assert_contains "$(gh_mutations)" "content=I_4" "tasks of the open sprint added"
  assert_contains "$ERR" "Item closed"
  assert_contains "$OUT" "hide the field"
}

test_cmd_init_stops_on_builtin_workflow() {
  project_env project-meta-new.json
  run_scrum project init
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "Item closed"
  assert_contains "$ERR" "--allow-builtin-workflows"
  assert_eq "" "$(gh_mutations)"
  assert_eq "" "$(gh_writes)"
}

test_cmd_init_missing_option() {
  project_env
  jq '.data.repositoryOwner.projectV2.fields.nodes |= map(if .name == "Status" then .options |= map(select(.name != "In Progress")) else . end)' \
    "$FIXTURES/project-meta.json" > "$FAKE_GH_DIR/meta.json"
  run_scrum project init
  assert_status 1 "$STATUS"
  assert_contains "$ERR" 'no option "In Progress"'
  assert_contains "$ERR" "project.status_options"
  assert_eq "" "$(gh_mutations)"
  assert_eq "" "$(gh_writes)"
}

test_cmd_init_second_run_unchanged() {
  project_env
  jq '.data.node.items.nodes |= (map(
        if .content.number == 2 then .content.labels.nodes = [{"name":"status: In progress"},{"name":"points: 3"}] | .synced.text = "in_progress"
        elif .content.number == 3 then .content.state = "CLOSED" | .content.stateReason = "COMPLETED" | .content.labels.nodes = [{"name":"status: Done"},{"name":"points: 1"}] | .synced.text = "done"
        else . end)
      + [{"id":"PVTI_4","type":"ISSUE","content":{"id":"I_4","number":4,"state":"OPEN","stateReason":null,"repository":{"nameWithOwner":"acme/blog"},"labels":{"nodes":[{"name":"status: New"},{"name":"points: 3"}]},"milestone":{"number":1,"state":"OPEN"}},"status":{"name":"Todo"},"synced":{"text":"new"},"points":{"number":3}}])' \
    "$FIXTURES/project-items.json" > "$FAKE_GH_DIR/items.json"
  run_scrum project init
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "unchanged     Status, Synced status, Points"
  assert_contains "$OUT" "0 added, 0 changed, 4 unchanged"
  assert_eq "" "$(gh_mutations)"
  assert_eq "" "$(gh_writes)"
}

test_cmd_init_dry_run_writes_nothing() {
  project_env project-meta-new.json
  run_scrum project init --dry-run --allow-builtin-workflows
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "would create  Synced status (text)"
  assert_contains "$OUT" "would: #4: add to the board"
  assert_eq "" "$(gh_mutations)"
  assert_eq "" "$(gh_writes)"
}

test_cmd_init_no_access() {
  project_env
  { printf '%s\t%s\n' 'api graphql -F query=@*/project.graphql*' '!fail'; cat "$FAKE_GH_DIR/routes"; } > "$FAKE_GH_DIR/r2"; mv "$FAKE_GH_DIR/r2" "$FAKE_GH_DIR/routes"
  run_scrum project init
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "SCRUM_PROJECT_TOKEN"
  assert_contains "$ERR" "gh auth refresh -s project"
}

# ---------- best-effort hooks ----------

test_hook_task_new_adds_to_board() {
  project_env
  route_json 'api -X POST repos/acme/blog/issues*' '{"number":12,"title":"Login","html_url":"u"}'
  route_json 'api graphql -F query=@*/issue-item.graphql*' "$(issue_item_json 12 '["status: New","points: 3"]' OPEN no)"
  run_scrum task new --title Login --points 3
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_mutations)" "content=I_12"
  assert_contains "$(gh_calls)" 'value: {number: 3}'
}

test_hook_failure_is_only_a_warning() {
  project_env
  route_json 'api -X POST repos/acme/blog/issues*' '{"number":12,"title":"Login","html_url":"u"}'
  { printf '%s\t%s\n' 'api graphql*' '!fail'; cat "$FAKE_GH_DIR/routes"; } > "$FAKE_GH_DIR/r2"; mv "$FAKE_GH_DIR/r2" "$FAKE_GH_DIR/routes"
  run_scrum task new --title Login
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Created #12"
  assert_contains "$ERR" "the project board was not updated"
}

test_hook_off_makes_no_graphql_call() {
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2014-09-22
  cp "$FIXTURES/milestones.json" "$FAKE_GH_DIR/milestones.json"
  route 'api --paginate repos/acme/blog/milestones*' milestones.json
  route_json 'api -X POST repos/acme/blog/issues*' '{"number":12,"title":"Login","html_url":"u"}'
  run_scrum task new --title Login
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$(gh_calls)" "graphql"
}

test_hook_event_merge_moves_card() {
  project_env
  local ev="$T/event.json"
  jq -n '{action: "closed", pull_request: {merged: true, body: "Closes #12"}}' > "$ev"
  route_json 'api repos/acme/blog/issues/12' '{"number":12,"state":"open","labels":[{"name":"status: In progress"}]}'
  route_json 'api graphql -F query=@*/issue-item.graphql*' "$(issue_item_json 12 '["status: Done"]' OPEN yes 'In Progress' in_progress)"
  GITHUB_EVENT_PATH="$ev" GITHUB_EVENT_NAME=pull_request_target GITHUB_ACTIONS=true SCRUM_PROJECT_TOKEN=pat run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'singleSelectOptionId: "O_done"'
  assert_contains "$(gh_calls)" 'value: {text: "done"}'
}

test_hook_event_without_secret_warns() {
  project_env
  local ev="$T/event.json"
  jq -n '{action: "closed", pull_request: {merged: true, body: "Closes #12"}}' > "$ev"
  route_json 'api repos/acme/blog/issues/12' '{"number":12,"state":"open","labels":[{"name":"status: In progress"}]}'
  GITHUB_EVENT_PATH="$ev" GITHUB_EVENT_NAME=pull_request_target GITHUB_ACTIONS=true SCRUM_PROJECT_TOKEN='' run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_writes)" "PUT repos/acme/blog/issues/12/labels"
  assert_contains "$ERR" "SCRUM_PROJECT_TOKEN is not set"
  assert_not_contains "$(gh_calls)" "graphql"
}

# Recorded from a project created with "gh project create" (ids replaced). spec: Chặn built-in workflow
test_meta_real_new_project() {
  local m; m="$(pmeta project-meta-real.json)"
  assert_json_eq '{"new":"O_Todo","in_progress":"O_InProgress","done":"O_Done"}' "$(printf '%s' "$m" | jq -c .options)"
  assert_json_eq '["Item added to project","Item closed","Pull request linked to issue","Pull request merged"]' "$(printf '%s' "$m" | jq -c .conflicts)"
  assert_json_eq '["Synced status","Points"]' "$(printf '%s' "$m" | jq -c '[.missing_fields[].name]')"
}

# Recorded after "scrum project init" on the sandbox board (ids replaced). Points come back as 3.0.
test_items_real_board_is_in_sync() {
  local items p
  items="$(jq '.data.node.items.nodes' "$FIXTURES/project-items-real.json" | jqt project-items --arg repo tuandtse243/scrum-sandbox)"
  assert_eq '[3,4,10,11]' "$(printf '%s' "$items" | jq -c 'map(.number) | sort')"
  p="$(printf '%s' "$items" | jqt project-sync-plan --argjson cfg "$(pcfg)" --argjson meta "$(pmeta)")"
  assert_eq '[]' "$(printf '%s' "$p" | jq -c .ops)" "3.0 on the board equals the label points: 3"
  assert_eq "4" "$(printf '%s' "$p" | jq -r .unchanged)"
}

# delta work-plan, design 7: a backlog task (no milestone) created by plan apply stays off the board.
test_hook_plan_apply_backlog_task_not_added() {
  project_env
  printf '[]' > "$FAKE_GH_DIR/milestones.json"
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":12,"id":1200,"title":"Login"}'
  route_json 'api graphql -F query=@*/issue-item.graphql*' "$(issue_item_json 12 '["status: New","points: 3"]' '' no)"
  jq -n '{version: 2, title: "Login", features: [{id: "F1", title: "Accounts", tasks: [{id: "T1", title: "Login", points: 3}]}]}' > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" "issue-item.graphql" "the board was consulted"
  assert_eq "" "$(gh_mutations)" "nothing added to the board"
  assert_not_contains "$ERR" "warning"
}

# delta project-board-sync: the new task commands update the board in the same run.
test_hook_task_estimate_updates_points() {
  project_env
  route_json 'api repos/acme/blog/issues/12' '{"number":12,"state":"open","labels":[{"name":"status: In progress"},{"name":"points: 3"}],"assignees":[]}'
  route_json 'api graphql -F query=@*/issue-item.graphql*' "$(issue_item_json 12 '["status: In progress","points: 7"]' OPEN yes 'In Progress' in_progress)"
  run_scrum task estimate 12 7
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'value: {number: 7}'
}

test_hook_task_move_into_sprint_adds_to_board() {
  project_env
  route_json 'api repos/acme/blog/issues/30' '{"number":30,"state":"open","milestone":null,"labels":[{"name":"status: New"}],"assignees":[]}'
  route_json 'api graphql -F query=@*/issue-item.graphql*' "$(issue_item_json 30 '["status: New"]' OPEN no)"
  run_scrum task move 30 --sprint "Sprint 1"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_mutations)" "content=I_30"
}

test_hook_task_drop_consults_the_board() {
  project_env
  route_json 'api repos/acme/blog/issues/12' '{"number":12,"state":"open","labels":[{"name":"status: New"}],"assignees":[]}'
  route_json 'api graphql -F query=@*/issue-item.graphql*' "$(issue_item_json 12 '["status: New"]' OPEN yes)"
  run_scrum task drop 12
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" "issue-item.graphql"
}

# ---------- In review column (delta project-board-sync "Cột In review trên board") ----------

rcfg() { pcfg | jq -c '.statuses.in_review = "In review" | .project.status_options.in_review = "Review"'; }
rplan() { jq -s . <<<"$*" | jqt project-sync-plan --argjson cfg "$(rcfg)" --argjson meta "$(jqt project-meta --argjson cfg "$(rcfg)" < "$FIXTURES/project-meta.json")"; }

test_meta_in_review_option() {
  local m; m="$(jqt project-meta --argjson cfg "$(rcfg)" < "$FIXTURES/project-meta.json")"
  assert_eq "O_review" "$(jq -r .options.in_review <<<"$m")"
  assert_eq "[]" "$(jq -c .missing_options <<<"$m")"
}

test_meta_in_review_missing_option() {
  local m; m="$(jqt project-meta --argjson cfg "$(pcfg | jq -c '.statuses.in_review = "In review"')" < "$FIXTURES/project-meta.json")"
  assert_eq '["In Review"]' "$(jq -c .missing_options <<<"$m")"
}

test_plan_drag_to_review_column() {
  local p; p="$(rplan "$(item 5 'status: In progress,points: 3' Review in_progress open 3)")"
  assert_eq '[{"op":"set_labels","number":5,"labels":["points: 3","status: In review"]},{"op":"set_synced","number":5,"text":"in_review"}]' \
    "$(jq -c '[.ops[] | del(.msg, .item_id)]' <<<"$p")"
}

test_plan_in_review_label_moves_card() {
  local p; p="$(rplan "$(item 5 'status: In review' 'In Progress' in_progress)")"
  assert_eq '[{"op":"set_status","number":5,"option_id":"O_review"},{"op":"set_synced","number":5,"text":"in_review"}]' \
    "$(jq -c '[.ops[] | del(.msg, .item_id)]' <<<"$p")"
}

test_plan_off_review_column_still_warns() {
  local cfg p
  cfg="$(pcfg | jq -c '.project.status_options.in_review = "Review"')"
  p="$(jq -s . <<<"$(item 8 'status: New' Review new)" | jqt project-sync-plan --argjson cfg "$cfg" --argjson meta "$(pmeta)")"
  assert_eq '[]' "$(jq -c .ops <<<"$p")"
  assert_contains "$(jq -r '.warnings[0]' <<<"$p")" '#8 is in the board column "Review"'
}

test_cmd_init_in_review_needs_its_column() {
  project_env
  printf '%s\nstatuses:\n  in_review: In review\n' "$PROJECT_YML" > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum project init
  assert_status 1 "$STATUS"
  assert_contains "$ERR" 'no option "In Review"'
  assert_eq "" "$(gh_mutations)"
  assert_eq "" "$(gh_writes)"
}
