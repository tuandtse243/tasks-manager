# Scenario tests (black box, from the specs) for stream B: pr-task-linking (status follows the
# code), sprint-reporting (location, waiting to be promoted) and sprint-lifecycle (unreleased
# tasks at sprint close). Change: branching-and-release-flow.

# shellcheck source=fixtures/scenarios/helpers.sh
. "$FIXTURES/scenarios/helpers.sh"

all_out() { printf '%s\n%s' "$OUT" "$ERR"; }

# ---------- scrum event ----------

# pr_event CONFIG ACTION MERGED HEAD BASE [BODY] [DRAFT] [MERGE_SHA]  The event of pull request #20.
pr_event() {
  sc_gh
  setup_repo "$1"
  export GITHUB_EVENT_NAME=pull_request_target GITHUB_EVENT_PATH="$T/event.json"
  jq -n --arg a "$2" --argjson m "$3" --arg h "$4" --arg b "$5" --arg body "${6:-Closes #1}" \
    --argjson d "${7:-false}" --arg sha "${8:-mrg020}" \
    '{action: $a, number: 20, pull_request: {number: 20, title: "feat: task 1", body: $body, draft: $d, merged: $m,
      merge_commit_sha: (if $m then $sha else null end), state: (if $a == "closed" then "closed" else "open" end),
      head: {ref: $h}, base: {ref: $b}, labels: [], html_url: "https://github.com/acme/blog/pull/20"},
      repository: {full_name: "acme/blog"}}' > "$GITHUB_EVENT_PATH"
  route_json 'api repos/acme/blog/pulls/20' "$(jq -c .pull_request "$GITHUB_EVENT_PATH")"
}

# labels_sent N  The label sets written to issue N (PUT replaces, POST adds), one JSON per line.
labels_sent() {
  stdin_of "-X PUT repos/acme/blog/issues/$1/labels"
  stdin_of "-X POST repos/acme/blog/issues/$1/labels"
}
closed_sent() { stdin_of "-X PATCH repos/acme/blog/issues/$1 " | grep '"state":"closed"' || true; }

# spec pr-task-linking: Merge (trunk)
test_event_trunk_merge_sets_done_and_closes() {
  pr_event "$CFG_TRUNK" closed true feat/1-task main
  route_issues "[$(issue_json 1 'In review')]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(labels_sent 1)" '"status: Done"'
  assert_contains "$(closed_sent 1)" '"state_reason":"completed"'
}

# spec pr-task-linking: Merge ở preset standard / Merged into the working branch
test_event_standard_merge_into_develop_keeps_in_review_with_location() {
  pr_event "$CFG_STANDARD" closed true feat/1-task develop
  route_issues "[$(issue_json 1 'In review')]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  local sent
  sent="$(labels_sent 1)"
  assert_contains "$sent" '"on: develop"'
  assert_not_contains "$sent" '"status: Done"'
  assert_eq "" "$(closed_sent 1)" "the task stays open"
  # the final set keeps In review
  if printf '%s' "$(stdin_of '-X PUT repos/acme/blog/issues/1/labels')" | grep -q .; then
    assert_contains "$(stdin_of '-X PUT repos/acme/blog/issues/1/labels' | tail -1)" '"status: In review"'
  fi
}

# spec pr-task-linking: Merged into the working branch (a task still In progress moves to In review)
test_event_standard_merge_from_in_progress_moves_to_in_review() {
  pr_event "$CFG_STANDARD" closed true feat/1-task develop
  route_issues "[$(issue_json 1 'In progress')]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  local last
  last="$(stdin_of '-X PUT repos/acme/blog/issues/1/labels' | tail -1)"
  assert_contains "$last" '"status: In review"'
  assert_contains "$last" '"on: develop"'
  assert_eq "" "$(closed_sent 1)"
}

# promotion_env  environments: #1 and #2 are on develop; the promotion pull request #30
# (develop -> staging, merge commit prm888) contains #1 (merged as aaa111), not #2 (bbb222,
# merged into develop after the promoted commit).
promotion_env() {
  pr_event "$CFG_ENVIRONMENTS" closed true develop staging $'Promote develop to staging\n\n- #1' false prm888
  route_issues "[$(issue_json 1 'In review' develop),$(issue_json 2 'In review' develop)]"
  route_task_pr 1 21 aaa111
  route_task_pr 2 22 bbb222
  route_contains aaa111 '*' ahead
  route_contains bbb222 '*' behind
}

# spec pr-task-linking: Promoted to staging
test_event_promotion_moves_contained_task_to_staging() {
  promotion_env
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  local last
  last="$(stdin_of '-X PUT repos/acme/blog/issues/1/labels' | tail -1)"
  assert_contains "$last" '"on: staging"'
  assert_not_contains "$last" '"on: develop"' "at most one location label"
  assert_contains "$last" '"status: In review"'
  assert_eq "" "$(closed_sent 1)"
}

# spec pr-task-linking: Not in the promotion
test_event_promotion_keeps_later_task_on_develop() {
  promotion_env
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(labels_sent 2)" "#2 keeps on: develop"
  assert_not_contains "$(gh_writes)" "issues/2/labels/" "no label of #2 is removed"
}

# spec pr-task-linking: Hotfix merged into main
test_event_hotfix_into_main_sets_done() {
  pr_event "$CFG_STANDARD" closed true hotfix/31-payment-fails main 'Closes #31'
  route_issues "[$(issue_json 31 'In review' '' bug)]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(labels_sent 31)" '"status: Done"'
  assert_contains "$(closed_sent 31)" '"state_reason":"completed"'
}

# spec pr-task-linking: Merged into a task branch
test_event_merge_into_task_branch_changes_nothing() {
  pr_event "$CFG_STANDARD" closed true feat/1-part feat/2-other
  route_issues "[$(issue_json 1 'In review')]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)" "#1 keeps its status and stays open"
}

# spec pr-task-linking: Done only on the release branch (a merge into staging by hand)
test_event_merge_into_develop_never_closes() {
  pr_event "$CFG_ENVIRONMENTS" closed true feat/1-task develop
  route_issues "[$(issue_json 1 'In review')]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(closed_sent 1)"
  assert_not_contains "$(labels_sent 1)" '"status: Done"'
}

# spec pr-task-linking: Mở PR không nháp (preset standard)
test_event_standard_ready_pr_opened_moves_to_in_review() {
  pr_event "$CFG_STANDARD" opened false feat/1-task develop
  route_issues "[$(issue_json 1 New)]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(labels_sent 1 | tail -1)" '"status: In review"'
}

# spec pr-task-linking: Mở PR nháp (preset standard)
test_event_standard_draft_pr_opened_moves_to_in_progress() {
  pr_event "$CFG_STANDARD" opened false feat/1-task develop 'Closes #1' true
  route_issues "[$(issue_json 1 New)]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(labels_sent 1 | tail -1)" '"status: In progress"'
}

# spec pr-task-linking: Chuyển về nháp (preset standard)
test_event_standard_converted_to_draft_moves_back() {
  pr_event "$CFG_STANDARD" converted_to_draft false feat/1-task develop 'Closes #1' true
  route_issues "[$(issue_json 1 'In review')]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(labels_sent 1 | tail -1)" '"status: In progress"'
}

# spec pr-task-linking: Đóng không merge (preset standard)
test_event_standard_closed_unmerged_moves_back() {
  pr_event "$CFG_STANDARD" closed false feat/1-task develop
  route_issues "[$(issue_json 1 'In review')]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(labels_sent 1 | tail -1)" '"status: In progress"'
  assert_eq "" "$(closed_sent 1)"
}

# spec pr-task-linking: Task đã Done MUST NOT bị lùi trạng thái (preset standard)
test_event_standard_done_task_not_moved_back() {
  pr_event "$CFG_STANDARD" reopened false feat/1-task develop
  route_issues "[$(issue_json 1 Done '' '' closed)]"
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)"
}

# ---------- sprint-reporting ----------

SPRINT3='{"number":3,"title":"Sprint 3","state":"open","description":"<!-- scrum:start=2026-11-16 end=2026-11-27 -->","due_on":"2026-11-27T00:00:00Z","created_at":"2026-11-14T00:00:00Z"}'

# report_env CONFIG ISSUES_JSON  Sprint 3 (2026-11-16 to 2026-11-27), today 2026-11-24.
report_env() {
  sc_gh
  setup_repo "$1"
  export SCRUM_TODAY=2026-11-24 SCRUM_NOW=2026-11-24T08:00:00Z
  route_json 'api --paginate repos/acme/blog/milestones*' "[$SPRINT3]"
  printf '%s' "$2" > "$FAKE_GH_DIR/sprint-issues.json"
  route 'api --paginate repos/acme/blog/issues?milestone=3*' sprint-issues.json
  route_issues "$2"
  # #12's pull request is open (in code review)
  route_open_prs '[{"number":20,"title":"feat: task 12","head":"feat/12-task","base":"develop","body":"Closes #12"}]'
  route_json 'api --paginate repos/acme/blog/issues/*/dependencies/blocked_by*' '[]'
}

mixed_issues() {
  printf '[%s,%s]' "$(issue_json 12 'In review')" "$(issue_json 13 'In review' develop)"
}

# lines_with TEXT  The output lines containing TEXT.
lines_with() { printf '%s\n' "$OUT" | grep -F -- "$1" || true; }

# spec sprint-reporting: Mixed locations
test_status_shows_code_review_and_develop() {
  report_env "$CFG_STANDARD" "$(mixed_issues)"
  route_task_pr 13 21 aaa111 develop 2026-11-23T10:00:00Z 2026-11-23T10:00:00Z
  run_scrum status
  assert_status 0 "$STATUS" "$ERR"
  local l12 l13
  l12="$(lines_with '#12')"
  l13="$(lines_with '#13')"
  [ -n "$l12" ] || _fail "#12 is not shown: $OUT"
  [ -n "$l13" ] || _fail "#13 is not shown: $OUT"
  assert_contains "$(printf '%s' "$l12" | tr '[:upper:]' '[:lower:]')" "review" "#12 is in code review"
  assert_contains "$l13" "develop" "#13 is on develop"
  assert_not_contains "$l12" "develop"
  assert_eq "" "$(gh_writes)"
}

# spec sprint-reporting: Trunk
test_status_trunk_unchanged() {
  report_env "$CFG_TRUNK" "$(mixed_issues)"
  run_scrum status
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$OUT" "develop" "trunk shows no location"
  assert_not_contains "$(printf '%s' "$OUT" | tr '[:upper:]' '[:lower:]')" "code review"
}

# waiting_env  #13 got "on: develop" seven working days ago, #14 two working days ago.
waiting_env() {
  report_env "$CFG_STANDARD" "[$(issue_json 13 'In review' develop),$(issue_json 14 'In review' develop)]"
  route_task_pr 13 21 aaa111 develop 2026-11-13T10:00:00Z 2026-11-13T10:00:00Z
  route_task_pr 14 22 bbb222 develop 2026-11-20T10:00:00Z 2026-11-20T10:00:00Z
}

# spec sprint-reporting: Waiting on develop
test_attention_lists_task_waiting_on_develop() {
  waiting_env
  run_scrum status --json
  assert_status 0 "$STATUS" "$ERR"
  local items
  items="$(printf '%s' "$OUT" | jq -c '[.attention[] | select(.number == 13) | select(.text | test("develop")) | select(.text | test("7|seven"))]')"
  [ "$items" != "[]" ] || _fail "#13 is not listed as waiting on develop for 7 days: $(printf '%s' "$OUT" | jq -c .attention)"
}

# spec sprint-reporting: Recently merged
test_attention_skips_task_two_days_on_develop() {
  waiting_env
  run_scrum status --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[]" "$(printf '%s' "$OUT" | jq -c '[.attention[] | select(.number == 14) | select(.text | test("develop"))]')" \
    "#14 is not listed"
}

# spec sprint-reporting: Waiting on develop (text output names the branch and the days)
test_attention_text_names_branch_and_days() {
  waiting_env
  run_scrum status
  assert_status 0 "$STATUS" "$ERR"
  local l
  l="$(printf '%s\n' "$OUT" | sed -n '/:$/,$p' | grep -F '#13' | grep -F 'develop' || true)"
  [ -n "$l" ] || _fail "no attention line for #13 on develop: $OUT"
  assert_contains "$l" "7"
}

# ---------- sprint-lifecycle ----------

# close_env  Sprint 3 with #12 Done and #13 In review on develop; Sprint 4 exists.
close_env() {
  report_env "$CFG_STANDARD" "[$(issue_json 12 Done '' '' closed),$(issue_json 13 'In review' develop)]"
  export SCRUM_TODAY=2026-11-27
  route_first 'api --paginate repos/acme/blog/milestones*' "$(printf '[%s,{"number":4,"title":"Sprint 4","state":"open","description":"<!-- scrum:start=2026-11-30 end=2026-12-11 -->"}]' "$SPRINT3" > "$FAKE_GH_DIR/ms34.json"; echo ms34.json)"
  route_task_pr 13 21 aaa111 develop 2026-11-23T10:00:00Z 2026-11-23T10:00:00Z
  route_json 'api -X PATCH repos/acme/blog/issues/13 --input -' '{"number":13}'
  route_json 'api -X PATCH repos/acme/blog/milestones/3 --input -' '{"number":3}'
}

# spec sprint-lifecycle: Merged but not released
test_close_preview_lists_merged_not_released() {
  close_env
  run_scrum sprint close
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Velocity: 3 points" "only #12 counts"
  local l13
  l13="$(lines_with '#13')"
  [ -n "$l13" ] || _fail "#13 is not listed: $OUT"
  assert_contains "$OUT" "/scrum-github:release" "suggests releasing before closing"
  assert_contains "$(printf '%s' "$OUT" | tr '[:upper:]' '[:lower:]')" "releas"
  assert_eq "" "$(gh_writes)" "a preview writes nothing"
}

# spec sprint-lifecycle: Merged but not released (velocity in --json-free text: #13 not counted)
test_close_preview_velocity_counts_only_done() {
  close_env
  run_scrum sprint close
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$OUT" "Velocity: 6 points" "#13 is not counted"
}

# spec sprint-lifecycle: Close without releasing
test_close_confirmed_moves_unreleased_task_keeping_label() {
  close_env
  run_scrum sprint close "Sprint 3" --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(stdin_of '-X PATCH repos/acme/blog/issues/13 ' | head -1)" '"milestone":4' "#13 moves to the next sprint"
  assert_not_contains "$(stdin_of '-X PATCH repos/acme/blog/issues/13 ')" '"labels"' "its labels are not rewritten"
  assert_not_contains "$(gh_writes)" "issues/13/labels" "keeps its status and location label"
  assert_not_contains "$(stdin_of '-X PATCH repos/acme/blog/issues/13 ')" '"state":"closed"'
  assert_contains "$(stdin_of '-X PATCH repos/acme/blog/milestones/3')" '"state":"closed"'
  assert_contains "$(stdin_of '-X PATCH repos/acme/blog/milestones/3')" 'scrum:velocity=3'
}
