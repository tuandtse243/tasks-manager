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

# ---------- run-state.jq ----------

strings_en() { jq -c .en "$PLUGIN_DIR/runtime/share/strings.json"; }
st() { # st OP [--arg k v]...  run-state on stdin; prints its output
  local op="$1"; shift
  jq -L "$PLUGIN_DIR/runtime/lib/jq" --arg op "$op" --argjson strings "$(strings_en)" "$@" -f "$PLUGIN_DIR/runtime/lib/jq/run-state.jq"
}
# A new state of #102, #107 (wave 1) and #103 (wave 2, blocked by #102); #104 blocked by #103.
new_state() {
  local issues
  issues="$(jq -s . <(ri 102 New ai-ready 5 open tuandt '{"work_minutes":20,"review_minutes":10}') <(ri 107 New ai-ready) <(ri 103 New ai-ready) <(ri 104 New ai-ready))"
  select_jq "$issues" '{"102":[],"107":[],"103":[102],"104":[103]}' \
    | st new --arg id 20261123-1000-tuandt --arg branch run/sprint-5-tuandt --arg base main --arg now 2026-11-23T10:00:00Z \
        --arg max_parallel 3 --arg pr_per_wave false --arg test_command "" --arg repo acme/blog | jq .state
}

test_state_new() {
  local s
  s="$(new_state)"
  assert_eq "pending pending pending pending" "$(printf '%s' "$s" | jq -r '[.tasks[].state] | join(" ")')"
  assert_eq "[[102,107],[103],[104]]" "$(printf '%s' "$s" | jq -c .waves)"
  assert_eq "[102]" "$(printf '%s' "$s" | jq -c '.tasks["103"].deps')"
  assert_eq "null" "$(printf '%s' "$s" | jq -c .finished_at)"
}

# spec "Thời gian thật: Task xong"
test_state_done_records_actual_time() {
  local out
  out="$(new_state | st started --arg n 102 --arg now 2026-11-23T10:00:00Z | jq .state \
    | st "done" --arg n 102 --arg now 2026-11-23T10:41:00Z --arg branch worktree-agent-1 --argjson notes '{"manual_test":"open /posts"}')"
  assert_eq "done 41 worktree-agent-1" "$(printf '%s' "$out" | jq -r '.state.tasks["102"] | "\(.state) \(.minutes) \(.branch)"')"
  assert_eq "102" "$(printf '%s' "$out" | jq -r .effects.comment.number)"
  assert_eq '<!-- scrum:actual -->
Actual time: 41m · done
Estimate: AI ~20m · Review ~10m
<!-- {"minutes":41,"result":"done","run":"20261123-1000-tuandt","started_at":"2026-11-23T10:00:00Z","ended_at":"2026-11-23T10:41:00Z"} -->
<!-- /scrum:actual -->' "$(printf '%s' "$out" | jq -r .effects.comment.body)"
}

# spec "Task lỗi: Task phụ thuộc task lỗi"
test_state_failed_drops_what_it_blocks() {
  local out
  out="$(new_state | st started --arg n 102 --arg now 2026-11-23T10:00:00Z | jq .state \
    | st failed --arg n 102 --arg now 2026-11-23T10:30:00Z --arg reason "tests fail" --arg status_new New)"
  assert_eq "failed excluded excluded pending" "$(printf '%s' "$out" | jq -r '.state.tasks | "\(.["102"].state) \(.["103"].state) \(.["104"].state) \(.["107"].state)"')"
  assert_eq "blocked by #102, which was not finished" "$(printf '%s' "$out" | jq -r '.state.tasks["103"].reason')"
  assert_eq "[102]" "$(printf '%s' "$out" | jq -c .effects.to_new)"
  assert_eq "103 104" "$(printf '%s' "$out" | jq -r '[.effects.dropped[].number] | join(" ")')"
  assert_contains "$(printf '%s' "$out" | jq -r .effects.comment.body)" "could not finish this task: tests fail"
  assert_contains "$(printf '%s' "$out" | jq -r .effects.comment.body)" "Actual time: 30m · failed"
}

test_state_transitions_checked() {
  local s
  s="$(new_state)"
  assert_eq "#102 is pending; it cannot be merged" "$(printf '%s' "$s" | st merged --arg n 102 --arg now x --arg sha abc | jq -r .error)"
  assert_eq "#999 is not a task of run 20261123-1000-tuandt" "$(printf '%s' "$s" | st started --arg n 999 --arg now x | jq -r .error)"
  s="$(printf '%s' "$s" | st "done" --arg n 102 --arg now 2026-11-23T10:41:00Z --arg branch b | jq .state)"
  assert_eq "null" "$(printf '%s' "$s" | jq -c '.tasks["102"].minutes')" "never started: no minutes"
  s="$(printf '%s' "$s" | st conflict --arg n 102 --arg now x --arg files $'a.txt\nb.txt' | jq .state)"
  assert_eq 'conflict ["a.txt","b.txt"]' "$(printf '%s' "$s" | jq -r '.tasks["102"] | "\(.state) \(.conflict_files | tojson)"')"
  s="$(printf '%s' "$s" | st merged --arg n 102 --arg now x --arg sha abc | jq .state)"
  assert_eq "merged abc" "$(printf '%s' "$s" | jq -r '.tasks["102"] | "\(.state) \(.merge_commit)"')"
}

test_state_view() {
  local s v
  s="$(new_state | st "done" --arg n 102 --arg now 2026-11-23T10:41:00Z --arg branch b | jq .state \
    | st merged --arg n 102 --arg now x --arg sha abc | jq .state \
    | st started --arg n 107 --arg now 2026-11-23T10:00:00Z | jq .state)"
  v="$(printf '%s' "$s" | st view)"
  assert_eq "1" "$(printf '%s' "$v" | jq -r .next_wave)"
  assert_eq '{"wave":1,"to_run":[107],"to_merge":[]}' "$(printf '%s' "$v" | jq -c '.waves[0] | {wave, to_run, to_merge}')"
  assert_json_eq '{"merged":1,"running":1,"pending":2}' "$(printf '%s' "$v" | jq -c .counts)"
}

test_state_pr_finishes_the_run() {
  local s
  s="$(new_state | st pr --arg wave 1 --arg pr '{"number":200,"url":"u"}' --arg now N | jq .state)"
  assert_eq "null" "$(printf '%s' "$s" | jq -c .finished_at)" "wave 1 of 3"
  s="$(printf '%s' "$s" | st pr --arg wave "" --arg pr '{"number":201,"url":"u"}' --arg now N | jq .state)"
  assert_eq '"N" [1,null]' "$(printf '%s' "$s" | jq -c '.finished_at, [.prs[].wave]' | tr '\n' ' ' | sed 's/ $//')"
}

# ---------- start, record, merge, status: a temporary git repo and a bare remote ----------

git_env() {
  plan_env
  export SCRUM_NOW=2026-11-23T10:00:00Z
  git init -q --bare -b main "$T/remote.git"
  git init -q -b main "$SCRUM_REPO_DIR"
  git -C "$SCRUM_REPO_DIR" config user.email t@example.com
  git -C "$SCRUM_REPO_DIR" config user.name t
  git -C "$SCRUM_REPO_DIR" config commit.gpgsign false
  printf 'one\ntwo\nthree\n' > "$SCRUM_REPO_DIR/app.txt"
  git -C "$SCRUM_REPO_DIR" add -A
  git -C "$SCRUM_REPO_DIR" commit -q -m init
  git -C "$SCRUM_REPO_DIR" remote add origin "$T/remote.git"
  git -C "$SCRUM_REPO_DIR" push -q origin main 2>/dev/null
  route_json 'repo view acme/blog*' 'main'
}

INT=run/sprint-5-tuandt
RUN_ID=20261123-1000-tuandt
state_file() { printf '%s/.scrum/run/%s.json' "$SCRUM_REPO_DIR" "$RUN_ID"; }
task_state() { jq -r --arg n "$1" '.tasks[$n].state' "$(state_file)"; }

# agent_work N FILE TEXT  What an agent does: a worktree from the integration branch, one commit.
agent_work() {
  git -C "$SCRUM_REPO_DIR" worktree add -q -b "agent-$1" "$T/wt$1" "$INT" 2>/dev/null
  printf '%s\n' "$3" > "$T/wt$1/$2"
  git -C "$T/wt$1" add -A
  git -C "$T/wt$1" commit -q -m "#$1 work"
}

# spec "Bắt đầu lần chạy: Bắt đầu"
test_cmd_run_start() {
  git_env
  run_scrum run start
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "$INT" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)"
  assert_eq "$(git -C "$SCRUM_REPO_DIR" rev-parse origin/main)" "$(git -C "$SCRUM_REPO_DIR" rev-parse HEAD)"
  [ -f "$(state_file)" ] || _fail "no state file"
  assert_eq "102 103 107" "$(jq -r '[.tasks | keys[]] | join(" ")' "$(state_file)")"
  assert_eq "$INT main" "$(jq -r '"\(.branch) \(.base)"' "$(state_file)")"
  assert_contains "$(cat "$SCRUM_REPO_DIR/.git/info/exclude")" ".scrum/"
  assert_eq "" "$(git -C "$SCRUM_REPO_DIR" status --porcelain)" "the state file is not seen by git"
  assert_eq "3" "$(gh_writes | grep -c 'PUT repos/acme/blog/issues/10[237]/labels')"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["points: 3","ai-ready","status: In progress"]}'
  assert_not_contains "$(gh_calls)" "assignees --input"
  assert_contains "$OUT" "Run $RUN_ID: 3 tasks in 2 waves, now In progress: #102, #107, #103."
  # a second start while this run is not finished
  run_scrum run start
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "run $RUN_ID is not finished"
}

test_cmd_run_start_assigns_a_task_nobody_has() {
  git_env
  ri 111 New '' 5 open '' > "$FAKE_GH_DIR/i111.json"
  route 'api repos/acme/blog/issues/111' i111.json
  run_scrum run start 111 --max-parallel 2 --pr-per-wave
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'api -X POST repos/acme/blog/issues/111/assignees --input -'
  assert_contains "$(gh_calls)" 'STDIN {"assignees":["tuandt"]}'
  assert_eq "2 true" "$(jq -r '"\(.max_parallel) \(.pr_per_wave)"' "$(state_file)")"
}

# spec "Bắt đầu lần chạy: Có thay đổi chưa commit"
test_cmd_run_start_with_uncommitted_changes_changes_nothing() {
  git_env
  printf 'edited\n' >> "$SCRUM_REPO_DIR/app.txt"
  run_scrum run start
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "Commit or stash them first"
  assert_eq "main" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)"
  assert_eq "" "$(git -C "$SCRUM_REPO_DIR" branch --list "$INT")"
  assert_eq "auth status" "$(gh_calls)" "GitHub is not even read"
  [ ! -d "$SCRUM_REPO_DIR/.scrum" ] || _fail "state written"
}

test_cmd_run_start_existing_branch_refused() {
  git_env
  git -C "$SCRUM_REPO_DIR" branch "$INT"
  run_scrum run start
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "the branch $INT already exists"
  assert_eq "" "$(gh_writes)"
}

test_cmd_run_start_nothing_to_run() {
  git_env
  run_scrum run start 110 --max-parallel 0
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--max-parallel must be a whole number greater than 0"
  route_first 'api repos/acme/blog/issues/110' '!404'
  run_scrum run start 110
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "no task to run"
  assert_contains "$ERR" "#110  ?: could not be read from GitHub"
  assert_eq "" "$(gh_writes)"
}

# spec "Merge theo đợt: Merge sạch" and "Thời gian thật: Task xong"
test_cmd_run_record_and_merge_clean() {
  git_env
  run_scrum run start
  agent_work 102 a.txt "from 102"
  agent_work 107 b.txt "from 107"
  run_scrum run record 102 --started
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "running" "$(task_state 102)"
  printf '{"result":"done","manual_test":"open /posts","look_closely":"the migration"}' > "$T/notes.json"
  export SCRUM_NOW=2026-11-23T10:41:00Z
  : > "$FAKE_GH_LOG"
  run_scrum run record 102 --done --branch agent-102 --notes "$T/notes.json"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#102 is done on agent-102 in 41 min"
  assert_contains "$(gh_calls)" 'api -X POST repos/acme/blog/issues/102/comments --input -'
  assert_contains "$(gh_calls)" 'Actual time: 41m · done'
  assert_eq "the migration" "$(jq -r '.tasks["102"].notes.look_closely' "$(state_file)")"
  run_scrum run record 107 --done --branch agent-107
  assert_status 0 "$STATUS" "$ERR"
  run_scrum run merge 102
  assert_status 0 "$STATUS" "$ERR"
  run_scrum run merge 107
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "Merge #107 Task 107
Merge #102 Task 102" "$(git -C "$SCRUM_REPO_DIR" log --merges --format=%s "$INT")"
  assert_eq "merged merged" "$(task_state 102) $(task_state 107)"
  assert_eq "$(git -C "$SCRUM_REPO_DIR" rev-parse "$INT")" "$(jq -r '.tasks["107"].merge_commit' "$(state_file)")"
  run_scrum run merge 103
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "#103 is pending; only a task recorded as done can be merged"
}

# spec "Merge theo đợt: Conflict"
test_cmd_run_merge_conflict_leaves_the_branch_as_it_was() {
  git_env
  run_scrum run start
  agent_work 102 app.txt "102 rewrote this"
  agent_work 107 app.txt "107 rewrote this"
  run_scrum run record 102 --done --branch agent-102
  run_scrum run record 107 --done --branch agent-107
  run_scrum run merge 102
  assert_status 0 "$STATUS" "$ERR"
  local before; before="$(git -C "$SCRUM_REPO_DIR" rev-parse HEAD)"
  run_scrum run merge 107
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "merging #107 (agent-107) into $INT conflicts in:
  app.txt"
  assert_contains "$ERR" "scrum run record 107 --failed --reason \"merge conflict\""
  assert_eq "$before" "$(git -C "$SCRUM_REPO_DIR" rev-parse HEAD)"
  assert_eq "" "$(git -C "$SCRUM_REPO_DIR" status --porcelain)" "no merge left half done"
  [ ! -f "$SCRUM_REPO_DIR/.git/MERGE_HEAD" ] || _fail "merge not aborted"
  assert_eq "conflict" "$(task_state 107)"
  assert_eq '["app.txt"]' "$(jq -c '.tasks["107"].conflict_files' "$(state_file)")"
  # fixed by hand on the task branch, then merged again
  git -C "$T/wt107" merge -q "$INT" >/dev/null 2>&1 || true
  printf 'both\n' > "$T/wt107/app.txt"
  git -C "$T/wt107" add -A
  git -C "$T/wt107" commit -q -m "fix conflict"
  run_scrum run merge 107
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "merged" "$(task_state 107)"
}

# spec "Task lỗi: Một task lỗi" and "Task phụ thuộc task lỗi"
test_cmd_run_record_failed() {
  git_env
  run_scrum run start
  ri 102 'In progress' ai-ready > "$FAKE_GH_DIR/p102.json"
  ri 103 'In progress' ai-ready > "$FAKE_GH_DIR/p103.json"
  route_first 'api repos/acme/blog/issues/102' p102.json
  route_first 'api repos/acme/blog/issues/103' p103.json
  run_scrum run record 102 --started
  export SCRUM_NOW=2026-11-23T10:20:00Z
  : > "$FAKE_GH_LOG"
  run_scrum run record 102 --failed --reason "tests fail: 2 of 40"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'api -X POST repos/acme/blog/issues/102/comments --input -'
  assert_contains "$(gh_calls)" 'could not finish this task: tests fail: 2 of 40'
  assert_contains "$(gh_calls)" 'api -X PUT repos/acme/blog/issues/102/labels --input -'
  assert_contains "$(gh_calls)" 'api -X PUT repos/acme/blog/issues/103/labels --input -'
  assert_contains "$(gh_calls)" 'STDIN {"labels":["points: 3","ai-ready","status: New"]}'
  assert_contains "$(gh_calls)" 'it is blocked by #102'
  assert_eq "failed excluded pending" "$(task_state 102) $(task_state 103) $(task_state 107)"
  assert_contains "$OUT" "#103 is left out: it is blocked by #102"
  # a failed task is never merged
  run_scrum run merge 102
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "#102 is failed"
}

test_cmd_run_record_checks() {
  git_env
  run_scrum run record 102 --started
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "there is no unfinished run"
  run_scrum run start
  run_scrum run record 102 --done
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--done needs --branch"
  run_scrum run record 102 --done --branch nope
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "there is no local branch nope"
  run_scrum run record 102 --failed
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--failed needs --reason"
  run_scrum run record 999 --started
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "#999 is not a task of run $RUN_ID"
}

# spec "Chạy tiếp sau khi dừng": status of each task, and what is next
test_cmd_run_status() {
  git_env
  run_scrum run status
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "No run yet"
  run_scrum run start
  agent_work 102 a.txt "from 102"
  run_scrum run record 102 --done --branch agent-102
  run_scrum run merge 102
  run_scrum run record 107 --started
  run_scrum run status
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Run $RUN_ID on $INT (not finished), Sprint 5"
  assert_contains "$OUT" "Wave 1:
  #102  merged  Task 102"
  assert_contains "$OUT" "  #107  running  Task 107"
  assert_contains "$OUT" "Wave 2:
  #103  pending  Task 103"
  assert_contains "$OUT" "  #110  Task 110: has no ai-ready label"
  assert_contains "$OUT" "Next: wave 1; run #107"
  run_scrum run status --json
  assert_eq "1 [107] false" "$(printf '%s' "$OUT" | jq -r '"\(.next_wave) \(.waves[0].to_run | tojson) \(.finished)"')"
  run_scrum run status nope
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "there is no run nope"
}
