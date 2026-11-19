# spec: sprint-lifecycle

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }

new_plan() { # new_plan MILESTONES ARGS TODAY
  jqt sprint-new-plan -n --argjson ms "$1" --argjson cfg "$(defaults)" --argjson args "$2" --arg today "$3"
}

test_first_sprint_from_the_guide() {
  local plan
  plan="$(new_plan '[]' '{"start":"2014-09-22","length":5,"goal":"Register, login, post, comment"}' 2014-09-20)"
  assert_eq "Sprint 1" "$(printf '%s' "$plan" | jq -r .title)"
  assert_eq "2014-09-26" "$(printf '%s' "$plan" | jq -r .end)"
  assert_eq "2014-09-26T12:00:00Z" "$(printf '%s' "$plan" | jq -r .due_on)"
  assert_contains "$(printf '%s' "$plan" | jq -r .description)" "**Goal:** Register, login, post, comment"
  assert_contains "$(printf '%s' "$plan" | jq -r .description)" "<!-- scrum:start=2014-09-22 end=2014-09-26 -->"
}

test_next_sprint_number() {
  local ms plan
  ms='[{"number":1,"title":"Sprint 1","state":"closed","description":""},{"number":2,"title":"Sprint 2","state":"open","description":""},{"number":3,"title":"Release prep","state":"open","description":""}]'
  plan="$(new_plan "$ms" '{}' 2014-10-06)"
  assert_eq "Sprint 3" "$(printf '%s' "$plan" | jq -r .title)"
  assert_eq "2014-10-06" "$(printf '%s' "$plan" | jq -r .start)" "start defaults to today"
  assert_eq "2014-10-10" "$(printf '%s' "$plan" | jq -r .end)"
}

test_duplicate_title_rejected() {
  local plan
  plan="$(new_plan "$(cat "$FIXTURES/milestones.json")" '{"title":"sprint 1"}' 2014-09-20)"
  assert_eq 'a sprint named "sprint 1" already exists' "$(printf '%s' "$plan" | jq -r .error)"
}

test_overlap_warns() {
  local plan
  plan="$(new_plan "$(cat "$FIXTURES/milestones.json")" '{"start":"2014-09-25"}' 2014-09-20)"
  assert_eq "null" "$(printf '%s' "$plan" | jq -r .error)"
  assert_contains "$(printf '%s' "$plan" | jq -r '.warnings[0]')" 'overlap with open sprint "Sprint 1"'
}

test_bad_start_date() {
  assert_contains "$(new_plan '[]' '{"start":"22/09/2014"}' 2014-09-20 | jq -r .error)" "YYYY-MM-DD"
}

resolve() { jqt sprint-resolve -n --argjson ms "$1" --argjson cfg "$(defaults)" --arg title "${3:-}" --arg today "$2"; }

test_current_sprint_contains_today() {
  local ms
  ms="$(jq '. + [{"number":2,"title":"Sprint 2","state":"open","description":"<!-- scrum:start=2014-09-29 end=2014-10-03 -->"}]' "$FIXTURES/milestones.json")"
  assert_eq "Sprint 1" "$(resolve "$ms" 2014-09-24 | jq -r .title)"
  assert_eq "Sprint 2" "$(resolve "$ms" 2014-09-30 | jq -r .title)"
  assert_eq "Sprint 1" "$(resolve "$ms" 2014-09-28 | jq -r .title)" "between sprints: open sprint ending first"
  assert_eq "Sprint 2" "$(resolve "$ms" 2014-09-24 "sprint 2" | jq -r .title)" "by name"
}

test_no_open_sprint() {
  assert_eq "null" "$(resolve '[{"number":1,"title":"Sprint 1","state":"closed","description":""}]' 2014-09-24)"
}

test_milestone_without_markers_uses_github_dates() {
  local info
  info="$(jq -L "$PLUGIN_DIR/runtime/lib/jq" -c 'include "scrum"; sprint_info' <<'EOF'
{"number": 9, "title": "Hand made", "state": "open", "description": null, "created_at": "2014-09-01T10:00:00Z", "due_on": "2014-09-12T07:00:00Z"}
EOF
)"
  assert_eq "2014-09-01" "$(printf '%s' "$info" | jq -r .start)"
  assert_eq "2014-09-12" "$(printf '%s' "$info" | jq -r .end)"
}

close_plan() { # close_plan MILESTONES SPRINT ISSUES
  jqt close-plan -n --argjson ms "$1" --argjson cfg "$(defaults)" --argjson sprint "$2" --argjson issues "$3" --arg today 2014-09-26
}

test_velocity_counts_completed_tasks_only() {
  local ms plan
  ms="$(cat "$FIXTURES/milestones.json")"
  plan="$(close_plan "$ms" "$(jq '.[0]' <<<"$ms")" "$(cat "$FIXTURES/issues-sprint1.json")")"
  assert_eq "10" "$(jq -r .velocity <<<"$plan")" "7 + 3; not the PR, feature, meta or not-planned task"
  assert_eq "[1,2]" "$(jq -c '[.done[].number]' <<<"$plan")"
  assert_eq "[3,4]" "$(jq -c '[.carry[].number]' <<<"$plan")"
  assert_eq "[7]" "$(jq -c .dropped <<<"$plan")"
  assert_eq "Sprint 2" "$(jq -r .next.title <<<"$plan")"
  assert_eq "false" "$(jq -r .next.exists <<<"$plan")"
  assert_eq "2014-09-27" "$(jq -r .next.start <<<"$plan")"
  assert_contains "$(jq -r .description <<<"$plan")" "<!-- scrum:velocity=10 -->"
}

test_velocity_eleven_example() {
  local issues plan
  issues='[
    {"number":1,"title":"a","state":"closed","state_reason":"completed","labels":[{"name":"points: 7"}]},
    {"number":2,"title":"b","state":"closed","state_reason":"completed","labels":[{"name":"points: 3"}]},
    {"number":3,"title":"c","state":"closed","state_reason":"completed","labels":[{"name":"points: 1"}]},
    {"number":4,"title":"d","state":"open","labels":[{"name":"points: 3"},{"name":"status: In progress"}]},
    {"number":5,"title":"e","state":"closed","state_reason":"completed","labels":[]}]'
  plan="$(close_plan "$(cat "$FIXTURES/milestones.json")" "$(jq '.[0]' "$FIXTURES/milestones.json")" "$issues")"
  assert_eq "11" "$(jq -r .velocity <<<"$plan")"
  assert_eq "[5]" "$(jq -c .unestimated_done <<<"$plan")"
}

test_velocity_marker_replaced_not_duplicated() {
  local sprint plan
  sprint='{"number":1,"title":"Sprint 1","state":"open","description":"x\n\n<!-- scrum:start=2014-09-22 end=2014-09-26 -->\n\n**Velocity:** 4 points\n<!-- scrum:velocity=4 -->"}'
  plan="$(close_plan "[$sprint]" "$sprint" '[]')"
  assert_eq "1" "$(jq -r '.description | [match("scrum:velocity"; "g")] | length' <<<"$plan")"
  assert_contains "$(jq -r .description <<<"$plan")" "scrum:velocity=0"
}

# ---------- commands ----------

sprint_env() {
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2014-09-26
  route 'api --paginate repos/acme/blog/milestones*' milestones.json
  cp "$FIXTURES/milestones.json" "$FAKE_GH_DIR/milestones.json"
  route 'api --paginate repos/acme/blog/issues?milestone=1&*' issues.json
  cp "$FIXTURES/issues-sprint1.json" "$FAKE_GH_DIR/issues.json"
}

test_cmd_sprint_new_posts_milestone() {
  sprint_env
  route_json 'api -X POST repos/acme/blog/milestones*' '{"number":2,"title":"Sprint 2","html_url":"https://github.com/acme/blog/milestone/2"}'
  run_scrum sprint new --start 2014-09-29 --goal "Polish"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Created Sprint 2 (2014-09-29 to 2014-10-03)"
  local body; body="$(gh_calls | grep '^STDIN' | sed 's/^STDIN //')"
  assert_eq "Sprint 2" "$(jq -r .title <<<"$body")"
  assert_eq "2014-10-03T12:00:00Z" "$(jq -r .due_on <<<"$body")"
  assert_contains "$(jq -r .description <<<"$body")" "scrum:start=2014-09-29 end=2014-10-03"
}

test_cmd_sprint_new_duplicate_writes_nothing() {
  sprint_env
  run_scrum sprint new --title "Sprint 1"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "already exists"
  assert_eq "" "$(gh_writes)"
}

test_cmd_close_without_yes_changes_nothing() {
  sprint_env
  run_scrum sprint close
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Velocity: 10 points from 2 done tasks"
  assert_contains "$OUT" "#4 Add a comment (3 pts, New)"
  assert_contains "$OUT" "--yes --create-next"
  assert_eq "" "$(gh_writes)"
}

test_cmd_close_needs_create_next_when_no_next_sprint() {
  sprint_env
  run_scrum sprint close --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "Sprint 2 does not exist yet"
  assert_eq "" "$(gh_writes)"
}

test_cmd_close_creates_next_and_carries_over() {
  sprint_env
  route_json 'api -X POST repos/acme/blog/milestones*' '{"number":2,"title":"Sprint 2"}'
  run_scrum sprint close --yes --create-next
  assert_status 0 "$STATUS" "$ERR"
  local log; log="$(gh_calls)"
  assert_contains "$log" '"title":"Sprint 2"'
  assert_contains "$log" "scrum:start=2014-09-27 end=2014-10-01"
  assert_contains "$log" "api -X PATCH repos/acme/blog/issues/3 --input -"
  assert_contains "$log" "api -X PATCH repos/acme/blog/issues/4 --input -"
  assert_contains "$log" '{"milestone":2}'
  assert_contains "$log" '"body":"Carried over from Sprint 1"'
  assert_contains "$log" "api -X PATCH repos/acme/blog/milestones/1 --input -"
  assert_contains "$log" '"state":"closed"'
  assert_contains "$log" 'scrum:velocity=10'
  assert_eq "2" "$(gh_writes | grep -c 'issues/[34]/comments')"
}

test_cmd_close_uses_existing_next_sprint() {
  sprint_env
  jq '. + [{"number":2,"title":"Sprint 2","state":"open","description":"<!-- scrum:start=2014-09-29 end=2014-10-03 -->"}]' \
    "$FIXTURES/milestones.json" > "$FAKE_GH_DIR/milestones.json"
  run_scrum sprint close "Sprint 1" --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$(gh_calls)" "-X POST repos/acme/blog/milestones"
  assert_contains "$(gh_calls)" '{"milestone":2}'
}

test_cmd_close_already_closed() {
  sprint_env
  jq '.[0].state = "closed"' "$FIXTURES/milestones.json" > "$FAKE_GH_DIR/milestones.json"
  run_scrum sprint close "Sprint 1" --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Sprint 1 is already closed"
  assert_eq "" "$(gh_writes)"
}

# ---------- sprint fill (delta sprint-lifecycle) ----------

fill_ms() { # closed sprints with the given velocities, then the open Sprint 9
  jq -nc --args '[ ($ARGS.positional | to_entries[] | {number: (.key + 1), title: "Sprint \(.key + 1)", state: "closed",
      closed_at: "2026-0\(.key + 1)-28T00:00:00Z", description: "<!-- scrum:velocity=\(.value) -->"}),
    {number: 9, title: "Sprint 9", state: "open", description: "<!-- scrum:start=2026-11-16 end=2026-11-27 -->"} ]' "$@"
}
fill_issue() { # NUMBER POINTS STATUS
  jq -nc --argjson n "$1" --arg p "$2" --arg s "${3:-New}" '{number: $n, title: "T\($n)", state: "open", body: "",
    labels: ([{name: "status: \($s)"}] + (if $p == "" then [] else [{name: "points: \($p)"}] end)), assignees: []}'
}
fill_backlog() { # JSON of backlog.jq for tasks "N:POINTS:BLOCKERS" (BLOCKERS: comma list, "-" = not checked)
  jq -nc --args '{tasks: [$ARGS.positional[] | split(":") | {number: (.[0] | tonumber), title: "T\(.[0])",
      points: (if .[1] == "" then null else (.[1] | tonumber) end), assignees: [], parent: null,
      blocked_by: (if .[2] == "-" then null elif .[2] == "" then [] else (.[2] | split(",") | map(tonumber)) end)}]}' "$@"
}
fill_plan() { # MILESTONES SPRINT_ISSUES BACKLOG ADD CAPACITY
  jqt sprint-fill -n --argjson ms "$1" --argjson sprint "$(printf '%s' "$1" | jq -c '.[] | select(.state == "open")')" \
    --argjson issues "$2" --argjson backlog "$3" --argjson add "$4" --argjson capacity "$5" --argjson cfg "$(defaults)"
}

test_fill_capacity_from_velocity() {
  local p
  p="$(fill_plan "$(fill_ms 99 10 12 14)" "$( { fill_issue 1 3; fill_issue 2 1; fill_issue 3 1 Done; } | jq -sc .)" "$(fill_backlog '30:3:')" '[]' null)"
  assert_eq "12 velocity 5 7" "$(printf '%s' "$p" | jq -r '"\(.capacity) \(.capacity_source) \(.planned) \(.free)"')"
  assert_eq '["Sprint 2","Sprint 3","Sprint 4"]' "$(printf '%s' "$p" | jq -c '[.velocity.sprints[].title]')"
}

test_fill_without_velocity() {
  local p
  p="$(fill_plan "$(fill_ms)" '[]' "$(fill_backlog '30:3:')" '[]' null)"
  assert_eq "null null null" "$(printf '%s' "$p" | jq -r '"\(.capacity) \(.capacity_source) \(.free)"')"
}

test_fill_capacity_option_wins() {
  local p
  p="$(fill_plan "$(fill_ms 10 12 14)" '[]' "$(fill_backlog '30:3:')" '[]' 8)"
  assert_eq "8 option" "$(printf '%s' "$p" | jq -r '"\(.capacity) \(.capacity_source)"')"
}

test_fill_over_capacity_unestimated_and_blocked() {
  local p
  p="$(fill_plan "$(fill_ms 6)" "$(fill_issue 1 4 | jq -sc .)" "$(fill_backlog '30:3:' '33::30' '34:1:-' '35:0:1')" '[33,34,35]' null)"
  assert_eq "[]" "$(printf '%s' "$p" | jq -c .errors)"
  assert_contains "$(printf '%s' "$p" | jq -c .warnings)" "#33 has no points"
  assert_contains "$(printf '%s' "$p" | jq -c .warnings)" "#33 is blocked by #30, not in Sprint 9"
  assert_contains "$(printf '%s' "$p" | jq -c .warnings)" "#34: its blockers were not checked"
  assert_not_contains "$(printf '%s' "$p" | jq -c .warnings)" "#35 is blocked"
  p="$(fill_plan "$(fill_ms 6)" "$(fill_issue 1 4 | jq -sc .)" "$(fill_backlog '30:3:')" '[30]' null)"
  assert_contains "$(printf '%s' "$p" | jq -c .warnings)" "over capacity by 1 point (capacity 6, planned 4, adding 3)"
}

test_fill_unknown_number_is_an_error() {
  local p
  p="$(fill_plan "$(fill_ms 6)" '[]' "$(fill_backlog '30:3:')" '[30,31]' null)"
  assert_contains "$(printf '%s' "$p" | jq -c .errors)" "#31 is not an open task in the backlog"
}

fill_env() {
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2026-11-19
  fill_ms 10 12 14 > "$FAKE_GH_DIR/ms.json"
  { fill_issue 1 3; fill_issue 2 2; } | jq -s . > "$FAKE_GH_DIR/sprint.json"
  { fill_issue 30 3; fill_issue 33 ''; } | jq -s 'map(. + {milestone: null})' > "$FAKE_GH_DIR/backlog.json"
  route 'api --paginate repos/acme/blog/milestones*' ms.json
  route 'api --paginate repos/acme/blog/issues?milestone=9*' sprint.json
  route 'api --paginate repos/acme/blog/issues?milestone=none*' backlog.json
  route_json 'api --paginate repos/acme/blog/issues/33/dependencies/blocked_by*' '[{"number":30,"state":"open"}]'
}

test_cmd_fill_shows_capacity_and_backlog() {
  fill_env
  run_scrum sprint fill
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Capacity: 12 points (average velocity of Sprint 1: 10, Sprint 2: 12, Sprint 3: 14)"
  assert_contains "$OUT" "Planned: 5 points; free: 7 points"
  assert_contains "$OUT" "#33  -  -  T33  (blocked by #30)"
  assert_eq "" "$(gh_writes)"
}

test_cmd_fill_preview_writes_nothing() {
  fill_env
  run_scrum sprint fill --add 30,33
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "After adding: 8 of 12 points"
  assert_contains "$OUT" "#33 has no points"
  assert_contains "$OUT" "run again with --yes"
  assert_eq "" "$(gh_writes)"
}

test_cmd_fill_yes_moves_and_comments() {
  fill_env
  run_scrum sprint fill --add 30 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" '-X PATCH repos/acme/blog/issues/30'
  assert_contains "$(gh_calls)" 'STDIN {"milestone":9}'
  assert_contains "$(gh_calls)" 'Moved from the backlog to Sprint 9.'
  assert_contains "$OUT" "Added #30 to Sprint 9."
}

test_cmd_fill_unknown_number_writes_nothing() {
  fill_env
  run_scrum sprint fill --add 30,31 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "#31 is not an open task in the backlog"
  assert_eq "" "$(gh_writes)"
}

test_cmd_fill_without_velocity_suggests_capacity() {
  fill_env
  fill_ms > "$FAKE_GH_DIR/ms.json"
  run_scrum sprint fill
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Capacity: unknown"
  assert_contains "$OUT" "--capacity N"
  assert_contains "$OUT" "Backlog: 2 tasks"
}

# delta sprint-lifecycle "Gợi ý lập kế hoạch sau khi tạo sprint"
test_cmd_sprint_new_suggests_fill_when_backlog_has_tasks() {
  sprint_env
  route_json 'api -X POST repos/acme/blog/milestones*' '{"number":2,"title":"Sprint 2","html_url":"u"}'
  route_json 'api --paginate repos/acme/blog/issues?milestone=none*' '[{"number":30,"state":"open","milestone":null,"labels":[],"assignees":[]},{"number":31,"state":"open","milestone":null,"labels":[{"name":"type: feature"}],"assignees":[]}]'
  run_scrum sprint new --start 2014-09-29
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "from the backlog (1 waiting): /scrum-github:sprint-fill"
}

test_cmd_sprint_new_no_hint_with_empty_backlog() {
  sprint_env
  route_json 'api -X POST repos/acme/blog/milestones*' '{"number":2,"title":"Sprint 2","html_url":"u"}'
  route_json 'api --paginate repos/acme/blog/issues?milestone=none*' '[]'
  run_scrum sprint new --start 2014-09-29
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$OUT" "sprint-fill"
}

# ---------- sprint summary on close (delta sprint-lifecycle "Đóng sprint") ----------

close_env() { # Sprint 1 with Sprint 2 open next, and Sprint 0 closed with velocity 8
  sprint_env
  jq '. + [{"number":2,"title":"Sprint 2","state":"open","description":"<!-- scrum:start=2014-09-29 end=2014-10-03 -->"},
           {"number":0,"title":"Sprint 0","state":"closed","closed_at":"2014-09-19T18:00:00Z","description":"<!-- scrum:start=2014-09-15 end=2014-09-19 -->\n<!-- scrum:velocity=8 -->"}]' \
    "$FIXTURES/milestones.json" > "$FAKE_GH_DIR/milestones.json"
}

test_cmd_close_posts_summary_on_digest_issue() {
  close_env
  run_scrum sprint close "Sprint 1" --yes
  assert_status 0 "$STATUS" "$ERR"
  local body; body="$(gh_calls | grep -A1 'issues/8/comments' | sed -n 's/^STDIN //p' | jq -r .body)"
  assert_contains "$body" "<!-- scrum:summary -->"
  assert_contains "$body" "## Sprint 1 summary"
  assert_contains "$body" "**Velocity:** 10 points. The sprint before: 8 (Sprint 0: 8)."
  assert_contains "$body" "- #2 Login (3 pts)"
  assert_contains "$body" "### Carried over to the next sprint"
  assert_contains "$body" "- #4 Add a comment (3 pts, New)"
  assert_contains "$OUT" "Posted the sprint summary on #8."
}

test_cmd_close_summary_failure_is_a_warning() {
  close_env
  route_first 'api -X POST repos/acme/blog/issues/8/comments*' '!fail'
  run_scrum sprint close "Sprint 1" --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$ERR" "the sprint summary was not posted"
  assert_contains "$(gh_calls)" '"state":"closed"'
}

test_cmd_close_summary_in_vietnamese() {
  close_env
  printf 'version: 1\nlanguage: vi\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum sprint close "Sprint 1" --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" "Tổng kết Sprint 1"
}
