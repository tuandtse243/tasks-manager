# spec: ai-run (change ai-run)

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }

# ri NUMBER STATUS [EXTRA_LABEL] [MILESTONE] [STATE] [ASSIGNEE] [EST_JSON]  An issue.
ri() {
  jq -nc --argjson n "$1" --arg s "$2" --arg x "${3:-}" --arg m "${4-5}" --arg st "${5:-open}" --arg a "${6-tuandt}" --arg e "${7:-}" '{
    number: $n, title: "Task \($n)", state: $st,
    body: ("### Acceptance criteria\n\n- [ ] Works for \($n)\n- [x] Has tests"
           + (if $e == "" then "" else "\n\n<!-- scrum:estimate -->\nAI\n<!-- \($e) -->\n<!-- /scrum:estimate -->" end)),
    milestone: (if $m == "" then null else {number: ($m | tonumber), title: "Sprint \($m)"} end),
    labels: ([{name: "status: \($s)"}, {name: "points: 3"}] + (if $x == "" then [] else [{name: $x}] end)),
    assignees: (if $a == "" then [] else [{login: $a}] end) }'
}
S5='{"number":5,"title":"Sprint 5","state":"open"}'

select_jq() { # select_jq ISSUES BLOCKED [NUMBERS] [SPRINT]
  jq -n -L "$PLUGIN_DIR/runtime/lib/jq" --argjson cfg "$(defaults)" --arg login tuandt --argjson issues "$1" \
    --argjson sprint "${4:-$S5}" --argjson blocked "$2" --argjson numbers "${3:-null}" \
    -f "$PLUGIN_DIR/runtime/lib/jq/run-select.jq"
}

# ---------- run-select.jq ----------

# spec "Chọn task để chạy: Mặc định"
test_select_default_needs_ai_ready() {
  local issues out
  issues="$(jq -s . <(ri 102 New ai-ready) <(ri 107 New ai-ready) <(ri 110 New) <(ri 111 'In progress' ai-ready) <(ri 112 New ai-ready 6))"
  out="$(select_jq "$issues" '{"102":[],"107":[]}')"
  assert_eq "[[102,107]]" "$(printf '%s' "$out" | jq -c .waves)"
  assert_eq '[{"number":110,"title":"Task 110","reason":"has no ai-ready label"}]' "$(printf '%s' "$out" | jq -c .excluded)"
  assert_eq "[102,107]" "$(printf '%s' "$out" | jq -c .candidates)"
}

test_select_default_only_mine() {
  local issues
  issues="$(jq -s . <(ri 102 New ai-ready) <(ri 103 New ai-ready 5 open an-nguyen))"
  assert_eq "[[102]]" "$(select_jq "$issues" '{"102":[]}' | jq -c .waves)"
}

# spec "Chọn task để chạy: Bị chặn bởi task ngoài lần chạy"
test_select_blocked_by_task_outside_the_run() {
  local out
  out="$(select_jq "$(jq -s . <(ri 103 New))" '{"103":[102]}' '[103]')"
  assert_eq "[]" "$(printf '%s' "$out" | jq -c .waves)"
  assert_eq "103 blocked by #102, which is open and not in this run" "$(printf '%s' "$out" | jq -r '.excluded[] | "\(.number) \(.reason)"')"
}

test_select_numbers_choose_exactly_those() {
  local issues out
  # 110 has no ai-ready label and 111 is someone else's: chosen anyway when named
  issues="$(jq -s . <(ri 110 New) <(ri 111 New '' '' open an-nguyen))"
  out="$(select_jq "$issues" '{"110":[],"111":[]}' '[110,111,110]')"
  assert_eq "[[110,111]]" "$(printf '%s' "$out" | jq -c .waves)"
  assert_eq "numbers" "$(printf '%s' "$out" | jq -r .mode)"
}

test_select_closed_feature_pr_and_unreadable_excluded() {
  local issues out
  issues="$(jq -s . <(ri 1 New '' 5 closed) <(ri 2 New 'type: feature') <(ri 4 Done) \
    <(ri 3 New | jq -c '. + {pull_request: {url: "x"}}'))"
  out="$(select_jq "$issues" '{}' '[1,2,3,4,9]')"
  assert_eq "1 is closed|2 is a feature, epic or meta issue, not a task|3 is a pull request, not a task|4 is already Done|9 could not be read from GitHub" \
    "$(printf '%s' "$out" | jq -r '[.excluded[] | "\(.number) \(.reason)"] | join("|")')"
  assert_eq "[]" "$(printf '%s' "$out" | jq -c .tasks)"
}

# spec "Chia đợt và xem trước: Hai đợt"
test_select_two_waves() {
  local issues out
  issues="$(jq -s . <(ri 102 New ai-ready) <(ri 107 New ai-ready) <(ri 103 New ai-ready))"
  out="$(select_jq "$issues" '{"102":[],"107":[],"103":[102]}')"
  assert_eq "[[102,107],[103]]" "$(printf '%s' "$out" | jq -c .waves)"
  assert_eq "[]" "$(printf '%s' "$out" | jq -c .excluded)"
  assert_eq "1 1 2" "$(printf '%s' "$out" | jq -r '[.tasks[].wave] | join(" ")')"
}

test_select_exclusion_spreads_to_what_it_blocks() {
  local issues out
  issues="$(jq -s . <(ri 102 New ai-ready) <(ri 103 New ai-ready) <(ri 104 New ai-ready))"
  out="$(select_jq "$issues" '{"102":[99],"103":[102],"104":null}')"
  assert_eq "102:[99] 103:[102] 104:null" "$(printf '%s' "$out" | jq -r '[.excluded[] | "\(.number):\(.blocked_by | tojson)"] | join(" ")')"
  assert_contains "$(printf '%s' "$out" | jq -r '.excluded[2].reason')" "could not be read"
  assert_eq "[]" "$(printf '%s' "$out" | jq -c .tasks)"
}

test_select_eta_by_waves() {
  local issues out
  issues="$(jq -s . <(ri 102 New ai-ready 5 open tuandt '{"work_minutes":20,"review_minutes":10}') \
    <(ri 107 New ai-ready 5 open tuandt '{"work_minutes":35,"review_minutes":15}') \
    <(ri 103 New ai-ready 5 open tuandt '{"work_minutes":15,"review_minutes":5}') <(ri 108 New ai-ready))"
  out="$(select_jq "$issues" '{"102":[],"107":[],"103":[102],"108":[103]}')"
  # waves (20, 35) (15) (none): 35 + 5 + 15 + 5 = 60
  assert_json_eq '{"work_minutes":60,"review_minutes":30,"estimated":3,"missing":1,"missing_numbers":[108],"waves":3}' "$(printf '%s' "$out" | jq -c .eta)"
}

test_select_no_open_sprint() {
  local out
  out="$(select_jq "$(jq -s . <(ri 102 New ai-ready))" '{"102":[]}' null null)"
  assert_eq "[] null" "$(printf '%s' "$out" | jq -c '.tasks, .sprint' | tr '\n' ' ' | sed 's/ $//')"
}

# ---------- scrum run plan ----------

MS5='[{"number":5,"title":"Sprint 5","state":"open","description":"<!-- scrum:start=2026-11-23 end=2026-12-04 -->"}]'

run_env() {
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2026-11-23
  printf '%s' "$MS5" > "$FAKE_GH_DIR/ms.json"
  route 'api --paginate repos/acme/blog/milestones*' ms.json
  route_json 'api user' '{"login":"tuandt"}'
}

plan_env() {
  run_env
  ri 102 New ai-ready 5 open tuandt '{"work_minutes":20,"review_minutes":10}' > "$FAKE_GH_DIR/i102.json"
  ri 107 New ai-ready > "$FAKE_GH_DIR/i107.json"
  ri 103 New ai-ready > "$FAKE_GH_DIR/i103.json"
  ri 110 New > "$FAKE_GH_DIR/i110.json"
  jq -s . "$FAKE_GH_DIR/i102.json" "$FAKE_GH_DIR/i107.json" "$FAKE_GH_DIR/i103.json" "$FAKE_GH_DIR/i110.json" > "$FAKE_GH_DIR/mine.json"
  route 'api --paginate repos/acme/blog/issues?assignee=tuandt&state=open*' mine.json
  local n
  for n in 102 107 103 110; do route "api repos/acme/blog/issues/$n" "i$n.json"; done
  route_json 'api --paginate repos/acme/blog/issues/103/dependencies/blocked_by*' '[{"number":102,"state":"open"}]'
  route_json 'api --paginate repos/acme/blog/issues/*/dependencies/blocked_by*' '[]'
}

test_cmd_run_plan_waves_and_left_out() {
  plan_env
  run_scrum run plan
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Run for @tuandt in Sprint 5: 3 tasks in 2 waves"
  assert_contains "$OUT" "Wave 1:
  #102  3 pt  Task 102  [AI 20m, review 10m]
  #107  3 pt  Task 107"
  assert_contains "$OUT" "Wave 2 (after wave 1 is merged):
  #103  3 pt  Task 103"
  assert_contains "$OUT" "  #110  Task 110: has no ai-ready label"
  assert_contains "$OUT" "Time: about 25m of work (2 waves, each as long as its longest task plus the merge) and 10m of review."
  assert_contains "$OUT" "Not counted, without a time estimate: #107, #103."
  # spec "Xem trước không ghi": nothing written, no branch
  assert_eq "" "$(gh_writes)"
  [ ! -d "$SCRUM_REPO_DIR/.scrum" ] || _fail "plan wrote a state file"
}

test_cmd_run_plan_numbers_and_json() {
  plan_env
  run_scrum run plan 103 --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[]" "$(printf '%s' "$OUT" | jq -c .waves)"
  assert_eq "blocked by #102, which is open and not in this run" "$(printf '%s' "$OUT" | jq -r '.excluded[0].reason')"
  assert_not_contains "$(gh_calls)" "issues?assignee"
  run_scrum run plan 102,#103 --dry-run
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "2 tasks in 2 waves"
  assert_eq "" "$(gh_writes)"
}

test_cmd_run_plan_bad_number() {
  run_env
  run_scrum run plan 12x
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "not an issue number: 12x"
  assert_eq "" "$(gh_calls)"
}

test_cmd_run_unknown_subcommand() {
  run_env
  run_scrum run frob
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "scrum run plan | start | record | merge | finish | status"
}
