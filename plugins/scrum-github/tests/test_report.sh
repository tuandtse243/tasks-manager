# spec: sprint-reporting

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }
sprint1() { jq '.[0]' "$FIXTURES/milestones.json"; }

progress_of() { # progress_of ISSUES TODAY
  jqt progress -n --argjson cfg "$(defaults)" --argjson sprint "$(sprint1)" --argjson issues "$1" --arg today "$2"
}

test_progress_example_from_the_guide() {
  local p david
  p="$(progress_of "$(cat "$FIXTURES/issues-sprint1.json")" 2014-09-24)"
  david="$(jq -c '.rows[] | select(.assignee == "david") | {new: .new.count, in_progress: .in_progress.count, done: .done.count}' <<<"$p")"
  assert_eq '{"new":1,"in_progress":1,"done":1}' "$david"
  assert_eq '{"count":1,"points":3}' "$(jq -c '.rows[] | select(.assignee == "david") | .done' <<<"$p")"
  assert_eq "4" "$(jq -r .total.total.count <<<"$p")" "PR, feature, meta and not-planned excluded"
  assert_eq "14" "$(jq -r .total.total.points <<<"$p")"
  assert_eq "71" "$(jq -r .pct_done <<<"$p")" "10 of 14 points"
  assert_eq "3" "$(jq -r .days_left <<<"$p")"
}

test_progress_shared_task_counted_once() {
  local issues p
  issues='[{"number":1,"title":"Pair","state":"open","labels":[{"name":"points: 3"}],"assignees":[{"login":"david"},{"login":"ruby"}]},
           {"number":2,"title":"Solo","state":"open","labels":[],"assignees":[]}]'
  p="$(progress_of "$issues" 2014-09-22)"
  assert_eq '["david","ruby","Unassigned"]' "$(jq -c '[.rows[].assignee]' <<<"$p")"
  assert_eq "2" "$(jq -r .total.total.count <<<"$p")"
  assert_eq "1" "$(jq -r .unestimated <<<"$p")"
}

test_progress_table_text() {
  local table
  table="$(progress_of "$(cat "$FIXTURES/issues-sprint1.json")" 2014-09-24 | jqt progress-table -r)"
  assert_contains "$table" "Sprint 1  (2014-09-22 to 2014-09-26, 3 days left)"
  assert_contains "$table" "david     1 (3 pts)  1 (1 pt)     1 (3 pts)   3 (7 pts)"
  assert_contains "$table" "Done: 71% of points (10 of 14)."
}

burn() { jqt burndown -n --argjson cfg "$(defaults)" --argjson sprint "$(sprint1)" --argjson issues "$(cat "$FIXTURES/issues-sprint1.json")" --arg today "$1" --argjson off "${2:-0}"; }

test_burndown_example() {
  local b; b="$(burn 2014-09-26)"
  assert_eq "14" "$(jq -r .total <<<"$b")"
  assert_eq '[14,11,11,4,4]' "$(jq -c '[.days[].remaining]' <<<"$b")"
  assert_eq '[14,10.5,7,3.5,0]' "$(jq -c '[.days[].ideal]' <<<"$b")"
}

test_burndown_mid_sprint_stops_today() {
  assert_eq '[14,11,11,null,null]' "$(burn 2014-09-24 | jq -c '[.days[].remaining]')"
}

test_burndown_uses_time_zone() {
  # #2 closed 2014-09-23T10:00Z and #1 2014-09-25T09:00Z.
  # UTC+14: the 24th and the 25th local. UTC-12: the 22nd and the 24th local.
  assert_eq '[14,14,11,4,4]' "$(burn 2014-09-26 50400 | jq -c '[.days[].remaining]')" "UTC+14"
  assert_eq '[11,11,4,4,4]' "$(burn 2014-09-26 -43200 | jq -c '[.days[].remaining]')" "UTC-12"
}

# ---------- commands ----------

report_env() {
  setup_fake_gh
  setup_repo 'version: 1'
  export SCRUM_TODAY=2014-09-24 SCRUM_NOW=2014-09-24T08:00:00Z
  jq '. + [{"number":0,"title":"Sprint 0","state":"closed","description":"<!-- scrum:start=2014-09-15 end=2014-09-19 -->\n<!-- scrum:velocity=11 -->"}]' \
    "$FIXTURES/milestones.json" > "$FAKE_GH_DIR/milestones.json"
  route 'api --paginate repos/acme/blog/milestones*' milestones.json
  route 'api --paginate repos/acme/blog/issues?milestone=1&*' issues.json
  cp "$FIXTURES/issues-sprint1.json" "$FAKE_GH_DIR/issues.json"
}

test_cmd_status_table() {
  report_env
  run_scrum status
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Sprint 1  (2014-09-22 to 2014-09-26, 3 days left)"
  assert_contains "$OUT" "ruby"
  assert_eq "" "$(gh_writes)" "status never writes"
}

test_cmd_status_other_sprint_by_name() {
  report_env
  route_json 'api --paginate repos/acme/blog/issues?milestone=0&*' '[]'
  run_scrum status "Sprint 0" --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "Sprint 0" "$(jq -r .sprint.title <<<"$OUT")"
}

test_cmd_report_writes_self_contained_html() {
  report_env
  # a title that tries to break out of the script element
  jq '.[2].title = "Fix </script><script>alert(1)</script> <!-- x"' "$FIXTURES/issues-sprint1.json" > "$FAKE_GH_DIR/issues.json"
  run_scrum report
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Wrote scrum-reports/sprint-1.html"
  local html="$T/scrum-reports/sprint-1.html"
  [ -f "$html" ] || _fail "report not written"
  if grep -Eo '(src|href)="[^"]*"' "$html" | grep -q 'http'; then _fail "report loads an external resource"; fi
  if grep -q '<link' "$html"; then _fail "report links a stylesheet"; fi
  assert_eq "2" "$(grep -c '</script>' "$html")" "only the two real script elements close"
  local data
  data="$(sed -n 's/^<script id="scrum-data" type="application\/json">\(.*\)<\/script>$/\1/p' "$html")"
  assert_eq "Sprint 1" "$(jq -r .progress.sprint.title <<<"$data")"
  assert_eq '[14,11,11,null,null]' "$(jq -c '[.burndown.days[].remaining]' <<<"$data")"
  assert_eq '[{"title":"Sprint 0","velocity":11}]' "$(jq -c '[.velocity[] | {title, velocity}]' <<<"$data")"
  assert_eq "Register, login, post, comment" "$(jq -r .goal <<<"$data")"
}

digest_body() { # digest_body COMMENTS TODAY
  jqt digest -n --argjson cfg "$(defaults)" --argjson sprint "$(sprint1)" --argjson issues "$(cat "$FIXTURES/issues-sprint1.json")" \
    --argjson comments "$1" --arg today "$2" --argjson off 0 | jq -r .body
}

test_digest_first_day_counts_from_sprint_start() {
  local body; body="$(digest_body '[]' 2014-09-24)"
  assert_contains "$body" "<!-- scrum:digest -->"
  assert_contains "$body" "## Sprint 1 digest, 2014-09-24"
  assert_contains "$body" "**Remaining:** 4 of 14 points. 3 days left (ends 2014-09-26)."
  assert_contains "$body" "### Done since the start of the sprint"
  assert_contains "$body" "- #2 Login (3 pts), @david"
  assert_contains "$body" "- @david: #3 Write a post (1 pt)"
  assert_contains "$body" "- 1 task, 3 pts"
}

test_digest_next_day_only_new_closures() {
  local body
  body="$(digest_body '[{"body":"<!-- scrum:digest -->\nold","created_at":"2014-09-24T01:00:00Z"},{"body":"hi","created_at":"2014-09-26T00:00:00Z"}]' 2014-09-25)"
  assert_contains "$body" "### Done since the last digest"
  assert_contains "$body" "- #1 Sign up via email, Facebook, LinkedIn (7 pts), @ruby"
  assert_not_contains "$body" "#2 Login"
}

digest_env() {
  report_env
  export SCRUM_TODAY=2014-09-24
}

test_cmd_digest_creates_issue_first_day() {
  digest_env
  jq 'map(select(.number != 8))' "$FIXTURES/issues-sprint1.json" > "$FAKE_GH_DIR/issues.json"
  route_json 'api -X POST repos/acme/blog/issues --input -' '{"number":30,"title":"Sprint 1 digest"}'
  run_scrum digest
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" '"title":"Sprint 1 digest"'
  assert_contains "$(gh_calls)" '"labels":["scrum: meta"],"milestone":1'
  assert_contains "$(gh_calls)" 'api -X POST repos/acme/blog/issues/30/comments --input -'
}

test_cmd_digest_reuses_issue() {
  digest_env
  route_json 'api --paginate repos/acme/blog/issues/8/comments*' '[]'
  run_scrum digest
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$(gh_calls)" "-X POST repos/acme/blog/issues --input"
  assert_contains "$(gh_calls)" 'api -X POST repos/acme/blog/issues/8/comments --input -'
}

test_cmd_digest_no_open_sprint() {
  digest_env
  jq 'map(.state = "closed")' "$FAKE_GH_DIR/milestones.json" > "$FAKE_GH_DIR/m2.json"; mv "$FAKE_GH_DIR/m2.json" "$FAKE_GH_DIR/milestones.json"
  run_scrum digest
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "There is no open sprint. Nothing posted."
  assert_eq "" "$(gh_writes)"
}

test_cmd_digest_disabled() {
  digest_env
  printf 'digest:\n  enabled: false\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum digest
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "turned off"
  assert_eq "" "$(gh_writes)"
}

# delta work-plan "Epic không tính điểm"
test_progress_excludes_epic_and_feature() {
  local issues p
  issues='[{"number":1,"title":"Epic","state":"open","labels":[{"name":"type: epic"}],"assignees":[]},
           {"number":2,"title":"Feature","state":"open","labels":[{"name":"type: feature"},{"name":"points: 7"}],"assignees":[]},
           {"number":3,"title":"A","state":"open","labels":[{"name":"points: 3"}],"assignees":[]},
           {"number":4,"title":"B","state":"open","labels":[{"name":"points: 3"},{"name":"type: epic-ish"}],"assignees":[]}]'
  p="$(progress_of "$issues" 2014-09-22)"
  assert_eq "6" "$(jq -r .total.total.points <<<"$p")"
  assert_eq "2" "$(jq -r .total.total.count <<<"$p")"
}

test_epic_is_not_a_task_for_status_sync() {
  local d
  d="$(jq -n -L "$PLUGIN_DIR/runtime/lib/jq" --argjson cfg "$(defaults)" 'include "scrum"; {labels: [{name: "type: epic"}]} | is_task($cfg)')"
  assert_eq "false" "$d"
}

# ---------- working days (delta sprint-reporting) ----------

jqs() { jq -n -L "$PLUGIN_DIR/runtime/lib/jq" --argjson cfg "$(defaults)" "include \"scrum\"; $1"; }

test_days_left_skips_the_weekend() {
  # Friday 2026-11-20, sprint ends Tuesday 2026-11-24: Friday, Monday, Tuesday.
  assert_eq "3" "$(jqs '{start: "2026-11-16", end: "2026-11-24"} as $s | days_left($cfg; $s; "2026-11-20")')"
  assert_eq "0" "$(jqs '{start: "2026-11-16", end: "2026-11-24"} as $s | days_left($cfg; $s; "2026-11-25")')"
}

test_ideal_is_flat_over_the_weekend() {
  # Monday 2026-11-16 to Friday 2026-11-27: 10 working days, 18 points.
  local ideal
  ideal="$(jqs '{start: "2026-11-16", end: "2026-11-27"} as $s | [range(0; 12) as $i | ideal_at($cfg; $s; 18; ($s.start | add_days($i)))]' | jq -c .)"
  assert_eq '[18,16,14,12,10,8,8,8,6,4,2,0]' "$ideal" "Sat 21, Sun 22 and Mon 23 stay at 8"
}

test_working_days_from_config() {
  assert_eq "6" "$(jq -n -L "$PLUGIN_DIR/runtime/lib/jq" --argjson cfg "$(defaults | jq '.sprint.working_days = [1,2,3,4,5,6]')" \
    'include "scrum"; working_days_between($cfg; "2026-11-16"; "2026-11-22")')"
}
