# spec: my-work

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }

# mi NUMBER STATUS POINTS MILESTONE [EXTRA_LABEL] [pr]  An open issue assigned to tuandt.
mi() {
  jq -nc --argjson n "$1" --arg s "$2" --arg p "$3" --arg m "$4" --arg x "${5:-}" --arg pr "${6:-}" '{
    number: $n, title: "Task \($n)", state: "open", body: "",
    milestone: (if $m == "" then null else {number: ($m | tonumber), title: "Sprint \($m)"} end),
    labels: ([{name: "status: \($s)"}] + (if $p == "" then [] else [{name: "points: \($p)"}] end)
             + (if $x == "" then [] else [{name: $x}] end)),
    assignees: [{login: "tuandt"}] }
    + (if $pr == "" then {} else {pull_request: {url: "x"}} end)'
}

MS='[{"number":5,"title":"Sprint 5","state":"open","description":"<!-- scrum:start=2026-11-23 end=2026-12-04 -->"},
     {"number":7,"title":"Sprint 7","state":"open","description":"<!-- scrum:start=2026-12-21 end=2027-01-01 -->"},
     {"number":6,"title":"Sprint 6","state":"open","description":"<!-- scrum:start=2026-12-07 end=2026-12-18 -->"}]'
S5='{"number":5,"title":"Sprint 5","state":"open"}'

mine_jq() { # mine_jq ISSUES BLOCKED [SPRINT] [PRS] [CFG]
  jq -n -L "$PLUGIN_DIR/runtime/lib/jq" --argjson cfg "${5:-$(defaults)}" --arg login tuandt --argjson issues "$1" \
    --argjson ms "$MS" --argjson sprint "${3:-$S5}" --argjson blocked "$2" --argjson prs "${4:-[]}" \
    -f "$PLUGIN_DIR/runtime/lib/jq/mine.jq"
}

# ---------- jq ----------

test_mine_groups_in_order() {
  local issues out
  issues="$(jq -s . <(mi 51 New 1 '') <(mi 60 New 3 6) <(mi 45 New 3 5) <(mi 42 'In progress' 3 5) <(mi 70 New '' 7))"
  out="$(mine_jq "$issues" '{"42":[],"45":[42],"51":[],"60":[],"70":[]}')"
  assert_eq "in_progress:42 current:45 sprint:60 sprint:70 backlog:51" \
    "$(printf '%s' "$out" | jq -r '[.groups[] | "\(.key):\(.tasks | map(.number) | join(","))"] | join(" ")')"
  assert_eq "Sprint 6" "$(printf '%s' "$out" | jq -r '.groups[2].title')" "other sprints by end date"
  assert_eq "[42]" "$(printf '%s' "$out" | jq -c '.groups[1].tasks[0].blocked_by')"
  assert_json_eq '{"tasks":5,"points":10}' "$(printf '%s' "$out" | jq -c .total)"
}

test_mine_drops_prs_features_and_epics() {
  local issues
  issues="$(jq -s . <(mi 1 New 1 5) <(mi 2 New 1 5 'type: feature') <(mi 3 New 1 5 'type: epic') <(mi 4 New 1 5 '' pr) <(mi 5 New 1 5 'scrum: meta'))"
  assert_eq "[1]" "$(mine_jq "$issues" '{}' | jq -c '[.groups[].tasks[].number]')"
}

test_mine_in_review_group_when_on() {
  local issues cfg
  cfg="$(defaults | jq -c '.statuses.in_review = "In review"')"
  issues="$(jq -s . <(mi 45 New 3 5) <(mi 43 'In review' 3 5) <(mi 42 'In progress' 3 5))"
  assert_eq "in_progress in_review current" "$(mine_jq "$issues" '{}' "$S5" '[]' "$cfg" | jq -r '[.groups[].key] | join(" ")')"
}

test_mine_next_skips_a_blocked_task() {
  local issues out
  issues="$(jq -s . <(mi 45 New 3 5) <(mi 47 New 1 5))"
  out="$(mine_jq "$issues" '{"45":[42],"47":[]}')"
  assert_json_eq '{"number":47,"title":"Task 47","action":"start"}' "$(printf '%s' "$out" | jq -c .next)"
}

test_mine_next_continues_in_progress() {
  local issues
  issues="$(jq -s . <(mi 47 New 1 5) <(mi 42 'In progress' 3 5))"
  assert_json_eq '{"number":42,"title":"Task 42","action":"continue"}' "$(mine_jq "$issues" '{"42":[],"47":[]}' | jq -c .next)"
}

test_mine_order_follows_dependencies() {
  local issues
  # 44 is blocked by 46 (mine), so 46 comes first though its number is higher
  issues="$(jq -s . <(mi 44 New 1 5) <(mi 46 New 1 5) <(mi 48 New 1 5))"
  assert_eq "[46,48,44]" "$(mine_jq "$issues" '{"44":[46],"46":[],"48":[]}' | jq -c .order)"
  assert_eq "46" "$(mine_jq "$issues" '{"44":[46],"46":[],"48":[]}' | jq -r .next.number)"
}

test_mine_not_checked_is_not_suggested() {
  local issues out
  issues="$(jq -s . <(mi 45 New 3 5))"
  out="$(mine_jq "$issues" '{}')"
  assert_eq "null" "$(printf '%s' "$out" | jq -c .next)"
  assert_eq "null" "$(printf '%s' "$out" | jq -c '.groups[0].tasks[0].blocked_by')"
}

test_mine_reviews_and_unreadable() {
  local issues
  issues="$(jq -s . <(mi 45 New 3 5))"
  assert_json_eq '[{"number":48,"title":"Comment form","author":"an-nguyen","url":"u48"}]' \
    "$(mine_jq "$issues" '{}' "$S5" '[{"number":48,"title":"Comment form","user":{"login":"an-nguyen"},"html_url":"u48"}]' | jq -c .reviews)"
  assert_eq "null" "$(mine_jq "$issues" '{}' "$S5" null | jq -c .reviews)"
}

test_mine_without_open_sprint() {
  local issues out
  issues="$(jq -s . <(mi 51 New 1 ''))"
  out="$(mine_jq "$issues" '{"51":[]}' null)"
  assert_eq "backlog" "$(printf '%s' "$out" | jq -r '[.groups[].key] | join(" ")')"
  assert_eq "null null" "$(printf '%s' "$out" | jq -r '"\(.sprint) \(.next)"')"
}

# ---------- scrum mine ----------

mine_env() {
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2026-11-25
  printf '%s' "$MS" > "$FAKE_GH_DIR/ms.json"
  route 'api --paginate repos/acme/blog/milestones*' ms.json
  route_json 'api user' '{"login":"tuandt"}'
  jq -s . <(mi 42 'In progress' 3 5) <(mi 45 New 3 5) <(mi 47 New 1 5) <(mi 60 New 3 6) <(mi 51 New 1 '') <(mi 9 New 1 5 '' pr) > "$FAKE_GH_DIR/mine.json"
  route 'api --paginate repos/acme/blog/issues?assignee=tuandt&state=open*' mine.json
  route_json 'api --paginate repos/acme/blog/issues/45/dependencies/blocked_by*' '[{"number":42,"state":"open"},{"number":3,"state":"closed"}]'
  route_json 'api --paginate repos/acme/blog/issues/*/dependencies/blocked_by*' '[]'
  route_json 'api -X GET search/issues -f q=repo:acme/blog is:pr is:open review-requested:tuandt*' \
    '{"total_count":1,"items":[{"number":48,"title":"Comment form","user":{"login":"an-nguyen"},"html_url":"u48","pull_request":{}}]}'
}

test_cmd_mine_tasks_everywhere() {
  mine_env
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Open tasks of @tuandt: 5 tasks, 11 points"
  assert_contains "$OUT" "  #42  3 pt  Sprint 5  Task 42"
  assert_contains "$OUT" "  #45  3 pt  Sprint 5  Task 45  (blocked by #42)"
  assert_contains "$OUT" "  #60  3 pt  Sprint 6  Task 60"
  assert_contains "$OUT" "  #51  1 pt  backlog  Task 51"
  assert_not_contains "$OUT" "#9 "
  assert_contains "$OUT" "Next: continue #42 Task 42."
  assert_contains "$OUT" "  #48  Comment form  by @an-nguyen"
  assert_eq "" "$(gh_writes)"
}

test_cmd_mine_group_order() {
  mine_env
  run_scrum mine --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "in_progress current sprint backlog" "$(printf '%s' "$OUT" | jq -r '[.groups[].key] | join(" ")')"
  assert_eq "tuandt" "$(printf '%s' "$OUT" | jq -r .login)"
  assert_eq "42" "$(printf '%s' "$OUT" | jq -r .next.number)"
  assert_eq "48" "$(printf '%s' "$OUT" | jq -r '.reviews[0].number')"
}

test_cmd_mine_without_open_sprint() {
  mine_env
  printf '[{"number":4,"title":"Sprint 4","state":"closed","description":""}]' > "$FAKE_GH_DIR/ms.json"
  jq -s . <(mi 51 New 1 '') > "$FAKE_GH_DIR/mine.json"
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "  #51  1 pt  backlog  Task 51"
  assert_contains "$OUT" "no sprint is open"
}

test_cmd_mine_other_user() {
  mine_env
  route_json 'api --paginate repos/acme/blog/issues?assignee=an-nguyen&state=open*' '[]'
  route_json 'api -X GET search/issues -f q=repo:acme/blog is:pr is:open review-requested:an-nguyen*' '{"items":[]}'
  run_scrum mine --user @an-nguyen
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" "issues?assignee=an-nguyen&state=open"
  assert_not_contains "$(gh_calls)" "api user"
  assert_contains "$OUT" "@an-nguyen has no open tasks."
  assert_contains "$OUT" "Pull requests waiting for review by @an-nguyen: none."
}

test_cmd_mine_no_tasks() {
  mine_env
  printf '[]' > "$FAKE_GH_DIR/mine.json"
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "@tuandt has no open tasks."
}

test_cmd_mine_search_fails() {
  mine_env
  route_first 'api -X GET search/issues*' '!fail'
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#42"
  assert_contains "$OUT" "could not be read from GitHub"
  run_scrum mine --json
  assert_eq "null" "$(printf '%s' "$OUT" | jq -c .reviews)"
}

test_cmd_mine_unknown_option() {
  mine_env
  run_scrum mine --all
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "unknown option for mine"
}

# ---------- spec scenarios checked end to end (tests added for the team-and-backlog-tasks change) ----------

# Scenario "Xem việc của người khác": the other person's open tasks are listed.
test_cmd_mine_other_user_lists_their_tasks() {
  mine_env
  mi 44 New 2 5 > "$T/a.json"; mi 52 New 1 '' > "$T/b.json"
  jq -s 'map(.assignees = [{login: "an-nguyen"}])' "$T/a.json" "$T/b.json" > "$FAKE_GH_DIR/an.json"
  route_first 'api --paginate repos/acme/blog/issues?assignee=an-nguyen&state=open*' an.json
  route_json 'api -X GET search/issues -f q=repo:acme/blog is:pr is:open review-requested:an-nguyen*' '{"items":[]}'
  run_scrum mine --user an-nguyen
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Open tasks of @an-nguyen: 2 tasks, 3 points"
  assert_contains "$OUT" "  #44  2 pt  Sprint 5  Task 44"
  assert_contains "$OUT" "  #52  1 pt  backlog  Task 52"
  assert_not_contains "$OUT" "#42"
  assert_eq "" "$(gh_writes)"
}

# Scenario "Đề xuất task không bị chặn", end to end: no task in progress, #45 blocked by the open
# #42 (someone else's), #47 not blocked -> #47.
test_cmd_mine_suggests_the_unblocked_task() {
  mine_env
  mi 45 New 3 5 > "$T/a.json"; mi 47 New 1 5 > "$T/b.json"
  jq -s . "$T/a.json" "$T/b.json" > "$FAKE_GH_DIR/mine.json"
  run_scrum mine --json
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '{"number":47,"title":"Task 47","action":"start"}' "$(printf '%s' "$OUT" | jq -c .next)"
  assert_eq "[42]" "$(printf '%s' "$OUT" | jq -c '[.groups[].tasks[] | select(.number == 45) | .blocked_by[]]')"
  run_scrum mine
  assert_contains "$OUT" "#47"
  assert_contains "$OUT" "(blocked by #42)"
}

# Scenario "JSON": valid JSON with login, groups, the next task and the reviews.
test_cmd_mine_json_has_every_part() {
  mine_env
  run_scrum mine --json
  assert_status 0 "$STATUS" "$ERR"
  printf '%s' "$OUT" | jq -e . >/dev/null || _fail "not JSON"
  assert_eq "true" "$(printf '%s' "$OUT" | jq -r 'has("login") and has("groups") and has("next") and has("reviews")')"
  assert_eq "array array" "$(printf '%s' "$OUT" | jq -r '"\(.groups | type) \(.reviews | type)"')"
}

# No open sprint and no tasks at all: still exit 0.
test_cmd_mine_no_sprint_and_no_tasks() {
  mine_env
  printf '[]' > "$FAKE_GH_DIR/ms.json"
  printf '[]' > "$FAKE_GH_DIR/mine.json"
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "@tuandt has no open tasks."
}

# Scenario "Không đọc được", with no open sprint: the task part is still printed.
test_cmd_mine_search_fails_without_open_sprint() {
  mine_env
  printf '[]' > "$FAKE_GH_DIR/ms.json"
  mi 51 New 1 '' | jq -s . > "$FAKE_GH_DIR/mine.json"
  route_first 'api -X GET search/issues*' '!fail'
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#51"
  assert_contains "$OUT" "could not be read from GitHub"
}

# ---------- review fixes ----------

test_mine_done_label_is_not_new_in_the_sprint() {
  local issues out
  mi 45 New 3 5 > "$T/a.json"; mi 46 Done 1 5 > "$T/b.json"
  issues="$(jq -s . "$T/a.json" "$T/b.json")"
  out="$(mine_jq "$issues" '{"45":[],"46":[]}')"
  assert_eq "current:45 sprint:46" "$(printf '%s' "$out" | jq -r '[.groups[] | "\(.key):\(.tasks | map(.number) | join(","))"] | join(" ")')"
}

# Blockers are read first for the New tasks of the open sprint, even past the first 50 numbers.
test_cmd_mine_reads_blockers_of_the_sprint_first() {
  mine_env
  jq -n '[range(1; 56) | {number: ., title: "B\(.)", state: "open", body: "", milestone: null,
           labels: [{name: "status: New"}], assignees: [{login: "tuandt"}]}]
         + [{number: 100, title: "Sprint task", state: "open", body: "", milestone: {number: 5, title: "Sprint 5"},
             labels: [{name: "status: New"}], assignees: [{login: "tuandt"}]}]' > "$FAKE_GH_DIR/mine.json"
  run_scrum mine --json
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" "issues/100/dependencies/blocked_by"
  assert_eq "100" "$(printf '%s' "$OUT" | jq -r .next.number)"
  assert_eq "50" "$(grep -c 'dependencies/blocked_by' "$FAKE_GH_LOG")"
}

# ---------- time (delta my-work "Thời gian trong việc của một người") ----------

# mie NUMBER STATUS MILESTONE WORK REVIEW  Like mi (1 point), with an estimate block.
mie() {
  mi "$1" "$2" 1 "$3" | jq -c --argjson w "$4" --argjson r "$5" \
    '.body = "Text\n\n<!-- scrum:estimate -->\nAI ~\($w)m\n<!-- {\"work_minutes\":\($w),\"review_minutes\":\($r),\"by\":\"ai\"} -->\n<!-- /scrum:estimate -->"'
}

# "Có ước lượng": #102 (20 + 15), #103 (15 + 15) blocked by #102 -> 20 + 5 + 15 + 5 = 45, review 30.
test_mine_time_by_waves() {
  local issues out
  issues="$(jq -s . <(mie 102 New 5 20 15) <(mie 103 New 5 15 15))"
  out="$(mine_jq "$issues" '{"102":[],"103":[102]}')"
  assert_json_eq '{"tasks":2,"estimated":2,"missing":0,"missing_numbers":[],"work_minutes":45,"review_minutes":30,"waves":2}' \
    "$(printf '%s' "$out" | jq -c .time)"
  assert_json_eq '{"work_minutes":20,"review_minutes":15,"by":"ai"}' "$(printf '%s' "$out" | jq -c '.groups[0].tasks[0].estimate')"
}

test_mine_time_parallel_and_other_sprints_left_out() {
  local issues
  issues="$(jq -s . <(mie 102 'In progress' 5 20 15) <(mie 103 New 5 15 15) <(mie 104 New 6 60 60) <(mie 105 New '' 60 60))"
  assert_json_eq '{"work_minutes":25,"review_minutes":30,"tasks":2}' \
    "$(mine_jq "$issues" '{"102":[],"103":[]}' | jq -c '.time | {work_minutes, review_minutes, tasks}')"
}

# "Có task chưa ước lượng"
test_mine_time_counts_tasks_without_estimate() {
  local issues
  issues="$(jq -s . <(mie 102 New 5 20 15) <(mi 104 New 1 5))"
  assert_json_eq '{"estimated":1,"missing":1,"missing_numbers":[104]}' \
    "$(mine_jq "$issues" '{}' | jq -c '.time | {estimated, missing, missing_numbers}')"
}

test_mine_time_null_without_open_sprint() {
  assert_eq "null" "$(mine_jq "$(jq -s . <(mie 102 New '' 20 15))" '{}' null | jq -c .time)"
}

test_cmd_mine_shows_time() {
  mine_env
  jq -s . <(mie 102 New 5 20 15) <(mie 103 New 5 15 15) <(mi 104 New 1 5) > "$FAKE_GH_DIR/mine.json"
  printf '[{"number":102,"state":"open"}]' > "$FAKE_GH_DIR/blk103.json"
  route_first 'api --paginate repos/acme/blog/issues/103/dependencies/blocked_by*' blk103.json
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "  #102  1 pt  Sprint 5  Task 102  [AI 20m, review 15m]"
  assert_contains "$OUT" "Time left in Sprint 5: about 45m of work (2 waves, each as long as its longest task plus the merge) and 30m of review."
  assert_contains "$OUT" "1 task without a time estimate, not counted: #104."
}

test_cmd_mine_no_estimate_at_all() {
  mine_env
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Time left in Sprint 5: 3 tasks without a time estimate."
}

# "Khối hỏng" in scrum mine: the task counts as without an estimate and the command does not stop.
test_cmd_mine_broken_estimate_block() {
  mine_env
  jq -s . <(mie 102 New 5 20 15) <(mi 104 New 1 5 | jq -c '.body = "Text\n\n<!-- scrum:estimate -->\n<!-- {\"work_minutes\":20 -->\n<!-- /scrum:estimate -->"') > "$FAKE_GH_DIR/mine.json"
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "1 task without a time estimate, not counted: #104."
}

# change ai-run: ai-ready New tasks of the open sprint, and the hint to /scrum-github:run
test_mine_ai_ready_tasks() {
  local issues out
  issues="$(jq -s . <(mi 45 New 3 5 ai-ready) <(mi 47 New 1 5) <(mi 60 New 3 6 ai-ready))"
  out="$(mine_jq "$issues" '{"45":[],"47":[]}')"
  assert_eq "[45]" "$(printf '%s' "$out" | jq -c .ai_ready)"
  assert_eq "true" "$(printf '%s' "$out" | jq -c '.groups[0].tasks[0].ai_ready')"
}

test_cmd_mine_points_to_run() {
  mine_env
  jq -s . <(mi 45 New 3 5 ai-ready) <(mi 47 New 1 5) > "$FAKE_GH_DIR/mine.json"
  run_scrum mine
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "AI agents can work one of them (labelled ai-ready): #45. Run them: /scrum-github:run"
}
