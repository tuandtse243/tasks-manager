# spec: work-plan (delta of change requirement-planning)

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }
validate() { printf '%s' "$1" | jqt plan-validate --argjson cfg "$(defaults)" | jq -r '.[]'; }
normalize() { printf '%s' "$1" | jqt plan-normalize -c; }

MIN='{"version":2,"title":"Blog post comments","features":[{"id":"F1","title":"Comments","tasks":[{"id":"T1","title":"Store"}]}]}'
V1='{"feature":{"title":"Blog post comments","body":"Readers can comment."},
     "tasks":[{"title":"Comment model","points":3,"acceptance":["stored with author and time"]},{"title":"Comment form","points":1}]}'

# A version 2 plan: one feature, three tasks, T2 depends on T1.
plan3() {
  cat <<'EOF'
{"version": 2, "title": "Blog post comments", "sprint": "current", "epic": null,
 "features": [{"id": "F1", "title": "Comments", "body": "Readers can comment.", "issue": null,
   "tasks": [
     {"id": "T1", "title": "Store comments", "points": 3, "acceptance": ["Saved with author"], "subtasks": ["Migration", "API"], "issue": null},
     {"id": "T2", "title": "Show comments", "points": 3, "depends_on": ["T1"], "issue": null},
     {"id": "T3", "title": "Comment form", "points": 1, "issue": null}]}],
 "assumptions": ["Only signed-in users comment"], "out_of_scope": ["Moderation"]}
EOF
}

# ---------- normalize (Đọc được plan phiên bản 1) ----------

test_normalize_v1_to_v2() {
  local n; n="$(normalize "$V1")"
  assert_eq "2" "$(jq -r .version <<<"$n")"
  assert_eq "current" "$(jq -r .sprint <<<"$n")"
  assert_eq "Blog post comments" "$(jq -r .title <<<"$n")"
  assert_json_eq '[{"id":"F1","title":"Blog post comments","issue":null,"tasks":["T1","T2"]}]' \
    "$(jq -c '[.features[] | {id, title, issue, tasks: [.tasks[].id]}]' <<<"$n")"
  assert_eq "null" "$(jq -c '.features[0].tasks[1].issue' <<<"$n")"
  assert_eq '["stored with author and time"]' "$(jq -c '.features[0].tasks[0].acceptance' <<<"$n")"
}

test_normalize_v1_keeps_named_sprint() {
  assert_eq "Sprint 2" "$(normalize '{"sprint":"Sprint 2","feature":{"title":"x"},"tasks":[{"title":"a"}]}' | jq -r .sprint)"
}

test_normalize_v2_unchanged() {
  assert_json_eq "$(plan3)" "$(normalize "$(plan3)")"
}

# ---------- validate (Kiểm tra plan, Định dạng plan phiên bản 2) ----------

test_validate_minimal_plan() {
  assert_eq "" "$(validate "$MIN")"
}

test_validate_plan_with_epic() {
  assert_eq "" "$(validate '{"version":2,"title":"Blog","epic":{"title":"Blog"},"features":[
    {"id":"F1","title":"Comments","tasks":[{"id":"T1","title":"a"}]},
    {"id":"F2","title":"Likes","tasks":[{"id":"T2","title":"b"}]}]}')"
}

test_validate_point_outside_scale() {
  local e; e="$(validate "$(plan3 | jq '.features[0].tasks[1].points = 5')")"
  assert_eq "task T2: 5 is not an allowed point value (allowed: 0, 1, 3, 7)" "$e"
}

test_validate_cycle() {
  local e; e="$(validate "$(plan3 | jq '.features[0].tasks[0].depends_on = ["T2"]')")"
  assert_eq "dependency cycle between T1, T2" "$e"
}

test_validate_unknown_dependency() {
  local e; e="$(validate "$(plan3 | jq '.features[0].tasks[0].depends_on = ["T9"]')")"
  assert_eq "task T1 depends on T9, which is not a task of this plan" "$e"
}

test_validate_self_dependency() {
  assert_eq "task T3 depends on itself" "$(validate "$(plan3 | jq '.features[0].tasks[2].depends_on = ["T3"]')")"
}

test_validate_many_errors_at_once() {
  local e; e="$(validate "$(plan3 | jq '.features[0].tasks[2].id = "T1" | .features[0].tasks[1].points = 5')")"
  assert_contains "$e" 'id "T1" is used more than once'
  assert_contains "$e" "task T2: 5 is not an allowed point value"
}

test_validate_required_fields() {
  local e; e="$(validate '{"version":2,"features":[{"id":"F1","tasks":[{"title":"a"}]},{"id":"F2","title":"x","tasks":[]}]}')"
  assert_contains "$e" "title is required"
  assert_contains "$e" "feature F1: title is required"
  assert_contains "$e" 'task "a": id is required'
  assert_contains "$e" "feature F2: tasks must be a non-empty list"
}

# A gh that always fails: offline commands must not need it.
broken_gh() {
  printf '#!/bin/sh\necho "gh: broken" >&2\nexit 1\n' > "$T/broken-gh"; chmod +x "$T/broken-gh"
  export SCRUM_GH="$T/broken-gh"
}

test_cmd_validate_offline_summary() {
  setup_repo 'version: 1'
  broken_gh
  plan3 > "$T/x.json"
  run_scrum plan validate "$T/x.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "The plan is valid: 1 feature, 3 tasks, 7 points." "$OUT"
}

test_cmd_validate_errors_exit_nonzero() {
  setup_repo 'version: 1'
  broken_gh
  plan3 | jq '.features[0].tasks[1].points = 5' > "$T/x.json"
  run_scrum plan validate "$T/x.json"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "T2: 5 is not an allowed point value"
}

test_cmd_validate_accepts_v1() {
  setup_repo 'version: 1'
  broken_gh
  printf '%s' "$V1" > "$T/old.json"
  run_scrum plan validate "$T/old.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "1 feature, 2 tasks, 4 points"
}

# ---------- plan init (Khởi tạo thư mục plan, Vị trí plan file) ----------

test_init_new_folder() {
  setup_repo 'version: 1'
  broken_gh
  run_scrum plan init "Blog post comments"
  assert_status 0 "$STATUS" "$ERR"
  [ -d "$SCRUM_REPO_DIR/docs/plans/blog-post-comments" ] || _fail "folder not created"
  assert_eq "docs/plans/blog-post-comments/plan.json" "$(jq -r .plan <<<"$OUT")"
  assert_json_eq '{"slug":"blog-post-comments","dir":"docs/plans/blog-post-comments","plan":"docs/plans/blog-post-comments/plan.json","view":"docs/plans/blog-post-comments/plan.md","brief":"docs/plans/blog-post-comments/brief.md","exists":{"plan":false,"view":false,"brief":false}}' "$OUT"
}

test_init_given_slug() {
  setup_repo 'version: 1'
  broken_gh
  run_scrum plan init "Bình luận dưới bài viết" --slug binh-luan-bai-viet
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "docs/plans/binh-luan-bai-viet" "$(jq -r .dir <<<"$OUT")"
  [ -d "$SCRUM_REPO_DIR/docs/plans/binh-luan-bai-viet" ] || _fail "folder not created"
}

test_init_existing_plan_untouched() {
  setup_repo 'version: 1'
  broken_gh
  mkdir -p "$SCRUM_REPO_DIR/docs/plans/blog-post-comments"
  plan3 > "$SCRUM_REPO_DIR/docs/plans/blog-post-comments/plan.json"
  local before; before="$(cksum < "$SCRUM_REPO_DIR/docs/plans/blog-post-comments/plan.json")"
  run_scrum plan init "Blog post comments"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "true" "$(jq -r .exists.plan <<<"$OUT")"
  assert_contains "$ERR" "already exists"
  assert_eq "$before" "$(cksum < "$SCRUM_REPO_DIR/docs/plans/blog-post-comments/plan.json")"
  assert_eq "plan.json" "$(ls "$SCRUM_REPO_DIR/docs/plans/blog-post-comments")"
}

test_init_invalid_slug() {
  setup_repo 'version: 1'
  broken_gh
  run_scrum plan init "Blog" --slug "Blog Post"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "invalid slug"
  [ ! -e "$SCRUM_REPO_DIR/docs" ] || _fail "a folder was created"
}

test_init_uses_planning_dir() {
  setup_repo 'planning:
  dir: planning'
  broken_gh
  run_scrum plan init "Blog post comments"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "planning/blog-post-comments/plan.json" "$(jq -r .plan <<<"$OUT")"
  [ -d "$SCRUM_REPO_DIR/planning/blog-post-comments" ] || _fail "folder not created"
}

# ---------- render (Bản xem ở local, Ước lượng) ----------

render() { # render PLAN [CFG] [MILESTONES]
  printf '%s' "$1" | jqt plan-render -r --argjson cfg "${2:-$(defaults)}" --argjson milestones "${3:-[]}"
}

test_render_unapplied_matches_fixture() {
  assert_eq "$(cat "$FIXTURES/plan-view-new.md")" "$(render "$(plan3)")"
}

test_render_applied_matches_fixture() {
  local p
  p="$(plan3 | jq '.epic = {title: "Blog", issue: 9} | .features[0].issue = 10
                   | .features[0].tasks[0].issue = 11 | .features[0].tasks[1].issue = 12 | .features[0].tasks[2].issue = 13')"
  assert_eq "$(cat "$FIXTURES/plan-view-applied.md")" "$(render "$p")"
  assert_contains "$(render "$p")" "| T1 | Store comments | 3 | – | #11 |"
}

estimate_plan() { # three tasks: 3, 7, not estimated
  plan3 | jq '.features[0].tasks[0].points = 3 | .features[0].tasks[1].points = 7 | .features[0].tasks[2].points = null'
}

test_estimate_points_only() {
  local v; v="$(render "$(estimate_plan)")"
  assert_contains "$v" "Total: 10 points, 1 task not estimated. Not estimated: T3."
  assert_not_contains "$v" " h)"
  assert_not_contains "$v" "Hours"
}

test_estimate_hours() {
  local v; v="$(render "$(estimate_plan)" "$(defaults | jq '.planning.hours_per_point = 4')")"
  assert_contains "$v" "Total: 10 points (40 h)"
  assert_contains "$v" "| T2 | Show comments | 7 | 28 | T1 | – |"
}

closed_sprints() { # velocities 10, 12, 14 in the three most recent closed sprints, plus an older one
  jq -n '[{number: 1, title: "Sprint 1", state: "closed", closed_at: "2014-09-26T10:00:00Z", description: "<!-- scrum:velocity=40 -->"},
          {number: 2, title: "Sprint 2", state: "closed", closed_at: "2014-10-03T10:00:00Z", description: "<!-- scrum:velocity=10 -->"},
          {number: 4, title: "Sprint 4", state: "closed", closed_at: "2014-10-17T10:00:00Z", description: "<!-- scrum:velocity=14 -->"},
          {number: 3, title: "Sprint 3", state: "closed", closed_at: "2014-10-10T10:00:00Z", description: "<!-- scrum:velocity=12 -->"},
          {number: 5, title: "Sprint 5", state: "open", description: ""}]'
}

test_estimate_sprints_from_velocity() {
  local p v
  p="$(plan3 | jq '.features[0].tasks = [range(0; 10) | {id: "T\(. + 1)", title: "t\(.)", points: 3}]')"
  v="$(render "$p" "$(defaults)" "$(closed_sprints)")"
  assert_contains "$v" "Velocity: 12 points per sprint on average over the last 3 closed sprints (Sprint 2: 10, Sprint 3: 12, Sprint 4: 14). Estimated 3 sprints."
}

test_estimate_without_closed_sprints() {
  assert_not_contains "$(render "$(plan3)" "$(defaults)" '[{"number":1,"title":"Sprint 1","state":"open"}]')" "Velocity"
}

test_cmd_render_twice_offline_identical() {
  setup_repo 'version: 1'
  broken_gh
  plan3 > "$T/plan.json"
  run_scrum plan render "$T/plan.json" --offline
  assert_status 0 "$STATUS" "$ERR"
  cp "$T/plan.md" "$T/first.md"
  run_scrum plan render "$T/plan.json" --offline
  assert_eq "$(cat "$T/first.md")" "$(cat "$T/plan.md")"
  assert_contains "$(head -1 "$T/plan.md")" "Do not edit by hand"
}

test_cmd_render_gh_failing_still_ok() {
  setup_repo 'version: 1'
  broken_gh
  export SCRUM_REPO=acme/blog
  plan3 > "$T/plan.json"
  run_scrum plan render "$T/plan.json" --out "$T/view/out.md"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$ERR"
  assert_contains "$(cat "$T/view/out.md")" "Total: 7 points"
  assert_not_contains "$(cat "$T/view/out.md")" "Velocity"
  [ ! -e "$T/plan.md" ] || _fail "--out was not used"
}

test_cmd_render_reads_velocity() {
  setup_fake_gh
  setup_repo 'version: 1'
  closed_sprints > "$FAKE_GH_DIR/ms.json"
  route 'api --paginate repos/acme/blog/milestones*' ms.json
  plan3 > "$T/plan.json"
  run_scrum plan render "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(cat "$T/plan.md")" "Velocity: 12 points per sprint"
}

test_cmd_render_rejects_invalid_plan() {
  setup_repo 'version: 1'
  broken_gh
  plan3 | jq '.features[0].tasks[1].points = 5' > "$T/plan.json"
  run_scrum plan render "$T/plan.json" --offline
  assert_status 1 "$STATUS"
  [ ! -e "$T/plan.md" ] || _fail "view written for an invalid plan"
}

# ---------- apply (Áp plan, Ghi lại số issue, Chạy lại, Sprint và backlog, Phụ thuộc, Xem trước) ----------

# Fake GitHub: Sprint 1 (current, #1) and Sprint 2 (#2) open, Sprint 0 (#3) closed.
# Each POST to /issues answers the next of #10, #11, #12, ... (ids are number * 100).
apply_env() {
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2014-09-22
  jq '. + [{"number": 2, "title": "Sprint 2", "state": "open", "description": "<!-- scrum:start=2014-09-29 end=2014-10-03 -->"},
           {"number": 3, "title": "Sprint 0", "state": "closed", "description": "<!-- scrum:start=2014-09-15 end=2014-09-19 -->"}]' \
    "$FIXTURES/milestones.json" > "$FAKE_GH_DIR/ms.json"
  route 'api --paginate repos/acme/blog/milestones*' ms.json
  local n
  for n in 9 10 11 12 13 14; do
    printf '{"number":%s,"id":%s00,"title":"Issue %s"}' "$n" "$n" "$n" > "$FAKE_GH_DIR/c$n.json"
  done
  create_numbers 10 11 12 13 14
}
create_numbers() { # create_numbers N... (or !fail)  Answers of successive POST /issues
  local files="" n
  for n in "$@"; do
    if [ "$n" = "!fail" ]; then files="$files,!fail"; else files="$files,c$n.json"; fi
  done
  grep -v 'POST repos/acme/blog/issues --input -' "$FAKE_GH_DIR/routes" > "$FAKE_GH_DIR/routes.new" || true
  mv "$FAKE_GH_DIR/routes.new" "$FAKE_GH_DIR/routes"
  route 'api -X POST repos/acme/blog/issues --input -' "${files#,}"
}
issue_get() { # issue_get NUMBER JSON  GET /issues/NUMBER answers JSON
  printf '%s' "$2" > "$FAKE_GH_DIR/get$1.json"
  route_first "api repos/acme/blog/issues/$1" "get$1.json"
}
creates() { grep -c 'api -X POST repos/acme/blog/issues --input -' "$FAKE_GH_LOG" || true; }
stdin_of() { # stdin_of N  JSON body of the N-th write call
  grep '^STDIN ' "$FAKE_GH_LOG" | sed -n "${1}p" | sed 's/^STDIN //'
}

test_apply_v1_plan_in_current_sprint() {
  apply_env
  printf '%s' "$V1" > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "3" "$(creates)"
  assert_json_eq '{"title":"Blog post comments","body":"Readers can comment.","labels":["type: feature"],"milestone":1}' "$(stdin_of 1)"
  assert_contains "$(stdin_of 2)" '"labels":["status: New","points: 3"]'
  assert_contains "$(stdin_of 2)" 'Part of #10'
  assert_contains "$(stdin_of 2)" '"milestone":1'
  assert_eq "2" "$(jq -r .version "$T/plan.json")" "rewritten as version 2"
  assert_json_eq '[10,11,12]' "$(jq -c '[.features[0].issue, .features[0].tasks[].issue]' "$T/plan.json")"
  assert_contains "$(gh_calls)" 'STDIN {"sub_issue_id":1100}'
  assert_contains "$(gh_calls)" 'STDIN {"sub_issue_id":1200}'
  assert_contains "$OUT" "linked #11 T1 as sub-issue of #10 F1"
}

test_apply_records_numbers_and_renders_view() {
  apply_env
  plan3 > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '[10,11,12,13]' "$(jq -c '[.features[0].issue, .features[0].tasks[].issue]' "$T/plan.json")"
  assert_contains "$(cat "$T/plan.md")" "| T3 | Comment form | 1 | – | #13 |"
  assert_json_eq "$(plan3 | jq -S 'del(.. | .issue?)')" "$(jq -S 'del(.. | .issue?)' "$T/plan.json")" "rest of the plan unchanged"
}

test_apply_subtasks_become_checklist() {
  apply_env
  plan3 > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "Store comments" "$(stdin_of 2 | jq -r .title)"
  assert_eq '### Acceptance criteria

- [ ] Saved with author

### Subtasks

- [ ] Migration
- [ ] API

Part of #10' "$(stdin_of 2 | jq -r .body)"
  assert_eq "4" "$(creates)" "subtasks are not issues"
}

test_apply_epic_with_two_features() {
  apply_env
  create_numbers 9 10 11 12 13
  plan3 | jq '.epic = {title: "Blog"} | .features += [{id: "F2", title: "Likes", tasks: [{id: "T4", title: "Like a post"}]}]
              | .features[0].tasks = [.features[0].tasks[0]]' > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '{"title":"Blog","body":"","labels":["type: epic"],"milestone":1}' "$(stdin_of 1)"
  assert_eq "9" "$(jq -r .epic.issue "$T/plan.json")"
  assert_contains "$(gh_calls)" 'api -X POST repos/acme/blog/issues/9/sub_issues --input -'
  assert_eq "2" "$(grep -c 'issues/9/sub_issues --input' "$FAKE_GH_LOG")" "two features under the epic"
}

test_apply_failure_midway_keeps_first_number() {
  apply_env
  create_numbers 10 11 '!fail'
  plan3 > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 1 "$STATUS"
  assert_json_eq '[10,11,null,null]' "$(jq -c '[.features[0].issue, .features[0].tasks[].issue]' "$T/plan.json")"
  jq . "$T/plan.json" >/dev/null || _fail "plan file is not valid JSON"
  assert_contains "$(cat "$T/plan.md")" "| T1 | Store comments | 3 | – | #11 |" "view rendered after the failure"
  assert_contains "$(cat "$T/plan.md")" "| T2 | Show comments | 3 | T1 | – |"
}

test_apply_rerun_after_failure_creates_only_missing() {
  apply_env
  plan3 | jq '.features[0].issue = 10 | .features[0].tasks[0].issue = 11' > "$T/plan.json"
  create_numbers 12 13
  issue_get 11 '{"number":11,"id":1100,"body":""}'
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "2" "$(creates)"
  assert_json_eq '[10,11,12,13]' "$(jq -c '[.features[0].issue, .features[0].tasks[].issue]' "$T/plan.json")"
  assert_contains "$(gh_calls)" 'STDIN {"issue_id":1100}' "T2 (#12) blocked by T1 (#11), looked up by id"
}

applied_env() { # plan3 fully applied: F1 #10, T1 #11, T2 #12 (blocked by #11), T3 #13; links exist
  apply_env
  plan3 | jq '.features[0].issue = 10 | .features[0].tasks[0].issue = 11 | .features[0].tasks[1].issue = 12 | .features[0].tasks[2].issue = 13' > "$T/plan.json"
  printf '[{"number":11,"id":1100},{"number":12,"id":1200},{"number":13,"id":1300}]' > "$FAKE_GH_DIR/subs10.json"
  route_first 'api --paginate repos/acme/blog/issues/10/sub_issues*' subs10.json
  printf '[{"number":11,"id":1100}]' > "$FAKE_GH_DIR/blk12.json"
  route_first 'api --paginate repos/acme/blog/issues/12/dependencies/blocked_by*' blk12.json
}

test_apply_second_run_writes_nothing() {
  applied_env
  local before; before="$(cksum < "$T/plan.json")"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
  assert_contains "$OUT" "Nothing to do"
  assert_eq "$before" "$(cksum < "$T/plan.json")"
}

test_apply_added_task_only() {
  applied_env
  jq '.features[0].tasks += [{"id": "T4", "title": "Delete a comment", "points": 1}]' "$T/plan.json" > "$T/p2.json"
  mv "$T/p2.json" "$T/plan.json"
  create_numbers 14
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "1" "$(creates)"
  assert_eq "14" "$(jq -r '.features[0].tasks[3].issue' "$T/plan.json")"
  assert_eq "1" "$(grep -c 'issues/10/sub_issues --input' "$FAKE_GH_LOG")"
  assert_contains "$(gh_calls)" 'STDIN {"sub_issue_id":1400}'
}

test_apply_backlog_without_open_sprint() {
  apply_env
  printf '[]' > "$FAKE_GH_DIR/ms.json"
  plan3 | jq 'del(.sprint)' > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "4" "$(creates)"
  assert_not_contains "$(grep '^STDIN' "$FAKE_GH_LOG")" '"milestone"'
  assert_not_contains "$(gh_calls)" 'milestones' "no sprint named: milestones are not read"
}

test_apply_current_sprint() {
  apply_env
  plan3 > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "1 1 1" "$(for i in 2 3 4; do stdin_of $i | jq -r .milestone; done | tr '\n' ' ' | sed 's/ $//')"
}

test_apply_task_sprint_overrides_plan() {
  apply_env
  plan3 | jq '.sprint = "Sprint 1" | .features[0].tasks[2].sprint = "Sprint 2"' > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "Comment form 2" "$(grep '^STDIN' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r 'select(.title == "Comment form") | "\(.title) \(.milestone)"')"
  assert_eq "Show comments 1" "$(grep '^STDIN' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r 'select(.title == "Show comments") | "\(.title) \(.milestone)"')"
}

test_apply_unknown_sprint_writes_nothing() {
  apply_env
  plan3 | jq '.features[0].tasks[2].sprint = "Sprint 9"' > "$T/plan.json"
  local before; before="$(cksum < "$T/plan.json")"
  run_scrum plan apply "$T/plan.json"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" 'no sprint named "Sprint 9"'
  assert_eq "" "$(gh_writes)"
  assert_eq "$before" "$(cksum < "$T/plan.json")"
}

test_apply_closed_sprint_writes_nothing() {
  apply_env
  plan3 | jq '.sprint = "Sprint 0"' > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "Sprint 0 is closed"
  assert_eq "" "$(gh_writes)"
}

test_apply_dependency_blocked_by() {
  apply_env
  plan3 > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'api -X POST repos/acme/blog/issues/12/dependencies/blocked_by --input -'
  assert_contains "$(gh_calls)" 'STDIN {"issue_id":1100}'
  assert_contains "$OUT" "linked #12 T2 as blocked by #11 T1"
}

test_apply_dependency_rejected_falls_back() {
  apply_env
  route_first 'api -X POST repos/acme/blog/issues/*/dependencies/blocked_by*' '!fail'
  issue_get 12 '{"number":12,"id":1200,"body":"Part of #10"}'
  plan3 > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'api -X PATCH repos/acme/blog/issues/12 --input -'
  assert_eq 'Part of #10

<!-- scrum:blocked-by -->
### Blocked by

- #11
<!-- /scrum:blocked-by -->' "$(grep '^STDIN' "$FAKE_GH_LOG" | tail -1 | sed 's/^STDIN //' | jq -r .body)"
  assert_contains "$OUT" "fallback"
}

test_apply_sub_issue_rejected_falls_back_once() {
  apply_env
  route_first 'api -X POST repos/acme/blog/issues/10/sub_issues*' '!fail'
  issue_get 10 '{"number":10,"id":1000,"body":"Readers can comment."}'
  plan3 > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  local body
  body="$(grep -A1 'PATCH repos/acme/blog/issues/10 ' "$FAKE_GH_LOG" | grep '^STDIN' | tail -1 | sed 's/^STDIN //' | jq -r .body)"
  assert_eq 'Readers can comment.

<!-- scrum:children -->
### Tasks

- [ ] #11
- [ ] #12
- [ ] #13
<!-- /scrum:children -->' "$body"
  assert_contains "$OUT" "fallback"
  # Second run: GitHub's body already has the block; it is replaced, not repeated.
  issue_get 10 "$(jq -n --arg b "$body" '{number: 10, id: 1000, body: $b}')"
  printf '[{"number":11,"id":1100}]' > "$FAKE_GH_DIR/blk12.json"
  route_first 'api --paginate repos/acme/blog/issues/12/dependencies/blocked_by*' blk12.json
  : > "$FAKE_GH_LOG"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "0" "$(creates)"
  body="$(grep -A1 'PATCH repos/acme/blog/issues/10 ' "$FAKE_GH_LOG" | grep '^STDIN' | tail -1 | sed 's/^STDIN //' | jq -r .body)"
  assert_eq "1" "$(printf '%s' "$body" | grep -c '<!-- scrum:children -->')"
}

test_apply_dry_run_new_plan() {
  apply_env
  plan3 | jq '.features[0].tasks = .features[0].tasks[0:2] | .features[0].tasks[1].depends_on = []' > "$T/plan.json"
  local before; before="$(cksum < "$T/plan.json")"
  run_scrum plan apply "$T/plan.json" --dry-run
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
  assert_eq "$before" "$(cksum < "$T/plan.json")"
  assert_eq "3" "$(printf '%s\n' "$OUT" | grep -c '^create ')"
  assert_eq "2" "$(printf '%s\n' "$OUT" | grep -c 'as sub-issue of')"
  [ ! -e "$T/plan.md" ] || _fail "dry run wrote the view"
}

test_apply_dry_run_partly_applied() {
  apply_env
  plan3 | jq '.features[0].issue = 10 | .features[0].tasks = .features[0].tasks[0:2] | .features[0].tasks[0].issue = 11' > "$T/plan.json"
  run_scrum plan apply "$T/plan.json" --dry-run
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "1" "$(printf '%s\n' "$OUT" | grep -c '^create ')"
  assert_contains "$OUT" "skip    T1 #11 already exists"
  assert_eq "" "$(gh_writes)"
}

# ---------- check (Kiểm tra gộp trước khi duyệt) ----------

test_check_valid_plan() {
  apply_env
  plan3 > "$T/plan.json"
  run_scrum plan check "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  [ -f "$T/plan.md" ] || _fail "view not written"
  assert_contains "$OUT" 'create  task T1 "Store comments" (3 points, Sprint 1)'
  assert_eq "" "$(gh_writes)"
}

test_check_invalid_plan() {
  apply_env
  plan3 | jq '.features[0].tasks[1].points = 5' > "$T/plan.json"
  run_scrum plan check "$T/plan.json"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "5 is not an allowed point value"
  [ ! -e "$T/plan.md" ] || _fail "view written for an invalid plan"
  assert_eq "" "$(gh_calls)"
}

test_check_offline() {
  setup_repo 'version: 1'
  broken_gh
  plan3 > "$T/plan.json"
  run_scrum plan check "$T/plan.json" --offline
  assert_status 0 "$STATUS" "$ERR"
  [ -f "$T/plan.md" ] || _fail "view not written"
  assert_not_contains "$OUT" "would do"
}

# ---------- --update (Cập nhật issue đã có) ----------

update_env() { # applied plan; GET answers for each issue
  applied_env
  issue_get 10 '{"number":10,"id":1000,"state":"open","title":"Comments","body":"Readers can comment.","labels":[{"name":"type: feature"}],"milestone":{"number":1,"title":"Sprint 1"}}'
  issue_get 11 "$(jq -nc '{number:11,id:1100,state:"open",title:"Store comments",
    body:"### Acceptance criteria\n\n- [ ] Saved with author\n\n### Subtasks\n\n- [ ] Migration\n- [ ] API\n\nPart of #10",
    labels:[{name:"status: In progress"},{name:"points: 3"}],milestone:{number:1,title:"Sprint 1"}}')"
  issue_get 12 '{"number":12,"id":1200,"state":"open","title":"Show comments","body":"Part of #10","labels":[{"name":"status: New"},{"name":"points: 3"}],"milestone":null}'
  issue_get 13 '{"number":13,"id":1300,"state":"open","title":"Comment form","body":"Part of #10","labels":[{"name":"status: New"},{"name":"points: 1"}],"milestone":{"number":1,"title":"Sprint 1"}}'
}

test_update_backlog_to_sprint() {
  update_env
  # T2 (#12) is in the backlog on GitHub; the plan now puts it in Sprint 2.
  jq '.features[0].tasks[1].sprint = "Sprint 2"' "$T/plan.json" > "$T/p2.json"; mv "$T/p2.json" "$T/plan.json"
  run_scrum plan apply "$T/plan.json" --update
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'api -X PATCH repos/acme/blog/issues/12 --input -'
  assert_contains "$(gh_calls)" 'STDIN {"milestone":2}'
  assert_not_contains "$(gh_calls)" 'issues/12/labels' "status label left alone"
  assert_eq "1" "$(gh_writes | wc -l | tr -d ' ')" "only #12 changes"
}

test_update_points() {
  update_env
  jq '.features[0].tasks[0].points = 7' "$T/plan.json" > "$T/p2.json"; mv "$T/p2.json" "$T/plan.json"
  run_scrum plan apply "$T/plan.json" --update
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'api -X PUT repos/acme/blog/issues/11/labels --input -'
  assert_contains "$(gh_calls)" 'STDIN {"labels":["status: In progress","points: 7"]}'
  assert_contains "$OUT" "points 3 -> 7"
}

test_update_closed_issue_skipped() {
  update_env
  issue_get 12 '{"number":12,"id":1200,"state":"closed","title":"Show comments","body":"Part of #10","labels":[{"name":"status: Done"}],"milestone":{"number":1,"title":"Sprint 1"}}'
  jq '.features[0].tasks[1].title = "Show comments under posts"' "$T/plan.json" > "$T/p2.json"; mv "$T/p2.json" "$T/plan.json"
  run_scrum plan apply "$T/plan.json" --update
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$(gh_calls)" 'PATCH repos/acme/blog/issues/12'
  assert_contains "$OUT" "skip    T2 #12 is closed, not updated"
}

test_update_keeps_fallback_block() {
  update_env
  issue_get 10 '{"number":10,"id":1000,"state":"open","title":"Comments","body":"Readers can comment.\n\n<!-- scrum:children -->\n### Tasks\n\n- [ ] #11\n<!-- /scrum:children -->","labels":[{"name":"type: feature"}],"milestone":{"number":1,"title":"Sprint 1"}}'
  jq '.features[0].body = "Readers can comment on posts."' "$T/plan.json" > "$T/p2.json"; mv "$T/p2.json" "$T/plan.json"
  run_scrum plan apply "$T/plan.json" --update
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"body":"Readers can comment on posts.\n\n<!-- scrum:children -->\n### Tasks\n\n- [ ] #11\n<!-- /scrum:children -->"}'
}

test_no_update_flag_makes_no_edits() {
  update_env
  jq '.features[0].tasks[0].points = 7 | .features[0].tasks[1].title = "Changed"' "$T/plan.json" > "$T/p2.json"; mv "$T/p2.json" "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
}

# ---------- schema (design 2) ----------

test_schema_is_json_and_design_example_is_valid() {
  jq -e '.properties.version.const == 2 and (.required | index("features"))' "$PLUGIN_DIR/runtime/share/plan.schema.json" >/dev/null \
    || _fail "plan.schema.json is not the version 2 schema"
  jq -e '.description | contains("Version 1")' "$PLUGIN_DIR/runtime/share/plan.schema.json" >/dev/null || _fail "version 1 not described"
  local design='{"version": 2, "title": "Blog post comments", "sprint": null, "epic": null,
    "features": [{"id": "F1", "title": "Bình luận dưới bài viết", "body": "…", "issue": null,
      "tasks": [
        {"id": "T1", "title": "Lưu bình luận", "body": "…", "acceptance": ["…"], "subtasks": ["Migration", "API"],
         "points": 3, "depends_on": [], "assignees": [], "bug": false, "issue": null},
        {"id": "T2", "title": "Hiển thị bình luận", "points": 3, "depends_on": ["T1"], "issue": null}]}],
    "assumptions": ["…"], "out_of_scope": ["…"]}'
  assert_eq "" "$(validate "$design")"
  assert_eq "" "$(validate "$(normalize "$V1")")"
}

test_fallback_blocks_replaced_not_repeated() {
  local b
  b="$(jq -nr -L "$PLUGIN_DIR/runtime/lib/jq" 'include "scrum";
    "Body" | set_scrum_block("blocked-by"; "### Blocked by\n\n- #10") | set_scrum_block("children"; "### Tasks\n\n- [ ] #11")
    | set_scrum_block("blocked-by"; "### Blocked by\n\n- #10\n- #12") | set_scrum_block("children"; "### Tasks\n\n- [ ] #11")')"
  assert_eq "1" "$(printf '%s' "$b" | grep -c '<!-- scrum:blocked-by -->')"
  assert_eq "1" "$(printf '%s' "$b" | grep -c '<!-- scrum:children -->')"
  assert_contains "$b" "- #12"
  assert_eq "Body" "$(printf '%s' "$b" | head -1)"
}

test_apply_task_null_sprint_is_backlog() {
  apply_env
  plan3 | jq '.features[0].tasks[2].sprint = null' > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "false" "$(grep '^STDIN' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r 'select(.title == "Comment form") | has("milestone")')"
  assert_eq "1" "$(grep '^STDIN' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r 'select(.title == "Show comments") | .milestone')"
  assert_contains "$(cat "$T/plan.md")" "Sprint: backlog (no sprint)"
}

# Real GitHub answers recorded on the sandbox repo (tests/fixtures/github-*.json, task 1.2):
# with the relations already present, apply makes no write at all.
test_apply_with_recorded_github_answers() {
  apply_env
  cp "$FIXTURES/github-sub-issues-list.json" "$FAKE_GH_DIR/subs.json"
  cp "$FIXTURES/github-blocked-by-list.json" "$FAKE_GH_DIR/blk.json"
  route_first 'api --paginate repos/acme/blog/issues/9/sub_issues*' subs.json
  route_first 'api --paginate repos/acme/blog/issues/11/dependencies/blocked_by*' blk.json
  jq -n '{version: 2, title: "Blog post comments", sprint: "current",
          features: [{id: "F1", title: "Blog post comments", issue: 9, tasks: [
            {id: "T1", title: "Store comments", points: 3, issue: 10},
            {id: "T2", title: "Show the comment form", points: 1, depends_on: ["T1"], issue: 11}]}]}' > "$T/plan.json"
  run_scrum plan apply "$T/plan.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
  assert_contains "$OUT" "Nothing to do"
}

test_recorded_duplicate_answers_are_422() {
  local f
  for f in github-blocked-by-duplicate github-blocked-by-self github-sub-issues-duplicate; do
    assert_eq "422" "$(jq -r .status "$FIXTURES/$f.json")" "$f"
  done
  assert_eq "11" "$(jq -r .number "$FIXTURES/github-blocked-by-created.json")"
}
