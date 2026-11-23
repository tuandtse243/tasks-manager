# spec: team

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }
team_cfg() { defaults | jq -c '.team = [{"login":"tuandt","areas":["backend"],"capacity":10},{"login":"an-nguyen","areas":["frontend"]}]'; }
jqs() { jq -n -L "$PLUGIN_DIR/runtime/lib/jq" --argjson cfg "$1" "include \"scrum\"; $2"; }

# issue NUMBER STATUS POINTS ASSIGNEE [STATE]
issue() {
  jq -nc --argjson n "$1" --arg s "$2" --arg p "$3" --arg a "$4" --arg st "${5:-open}" '{
    number: $n, title: "Task \($n)", state: $st, body: "", milestone: {number: 5, title: "Sprint 5"},
    labels: ([{name: "status: \($s)"}] + (if $p == "" then [] else [{name: "points: \($p)"}] end)),
    assignees: (if $a == "" then [] else [{login: $a}] end) }'
}

# ---------- jq ----------

test_team_from_config() {
  assert_json_eq '{"source":"config","members":[{"login":"tuandt","areas":["backend"],"capacity":10},{"login":"an-nguyen","areas":["frontend"],"capacity":null}]}' \
    "$(jqs "$(team_cfg)" 'team_list($cfg; ["someone-else"])')"
}

test_team_from_github_when_not_declared() {
  assert_json_eq '{"source":"github","members":[{"login":"tuandt","areas":[],"capacity":null},{"login":"minh-ho","areas":[],"capacity":null}]}' \
    "$(jqs "$(defaults)" 'team_list($cfg; [{"login":"tuandt"},{"login":"minh-ho"}])')"
}

test_unknown_logins() {
  assert_eq '["tuandtt"]' "$(jqs "$(team_cfg)" 'unknown_logins($cfg; ["TuanDT", "@an-nguyen", "tuandtt", "tuandtt"])' | jq -c .)"
  assert_eq '[]' "$(jqs "$(defaults)" 'unknown_logins($cfg; ["bob"])' | jq -c .)" "no team: no warning"
}

test_team_load_in_sprint() {
  local issues out
  issues="$(jq -s . <(issue 1 New 3 tuandt) <(issue 2 'In progress' 3 TuanDT) <(issue 3 New '' tuandt) \
    <(issue 4 Done 1 tuandt closed) <(issue 5 New 1 an-nguyen) <(issue 6 New 3 bob))"
  # open: #1, #2 (login in another case), #3 (no points); points include the done #4
  out="$(jq -n -L "$PLUGIN_DIR/runtime/lib/jq" --argjson cfg "$(team_cfg)" --argjson assignees null \
    --argjson sprint '{"number":5,"title":"Sprint 5"}' --argjson issues "$issues" -f "$PLUGIN_DIR/runtime/lib/jq/team.jq")"
  assert_json_eq '{"tasks":3,"points":7,"done_points":1}' "$(printf '%s' "$out" | jq -c '.members[0].load')"
  assert_json_eq '{"tasks":1,"points":1,"done_points":0}' "$(printf '%s' "$out" | jq -c '.members[1].load')"
  assert_eq "Sprint 5" "$(printf '%s' "$out" | jq -r .sprint.title)"
}

test_team_no_sprint_has_no_load() {
  local out
  out="$(jq -n -L "$PLUGIN_DIR/runtime/lib/jq" --argjson cfg "$(team_cfg)" --argjson assignees null \
    --argjson sprint null --argjson issues '[]' -f "$PLUGIN_DIR/runtime/lib/jq/team.jq")"
  assert_eq "null null" "$(printf '%s' "$out" | jq -r '"\(.sprint) \(.members[0].load)"')"
}

# ---------- scrum team ----------

team_env() { # team_env YAML
  setup_fake_gh
  setup_repo "$1"
  export SCRUM_TODAY=2026-11-25
  printf '[{"number":5,"title":"Sprint 5","state":"open","description":"<!-- scrum:start=2026-11-23 end=2026-12-04 -->"}]' > "$FAKE_GH_DIR/ms.json"
  route 'api --paginate repos/acme/blog/milestones*' ms.json
  jq -s . <(issue 42 New 3 tuandt) <(issue 43 'In progress' 7 tuandt) <(issue 44 New 1 an-nguyen) > "$FAKE_GH_DIR/s5.json"
  route 'api --paginate repos/acme/blog/issues?milestone=5*' s5.json
  route_json 'api --paginate repos/acme/blog/assignees*' '[{"login":"tuandt"},{"login":"minh-ho"}]'
}

TEAM_YAML='team:
  - login: tuandt
    areas: [backend]
    capacity: 10
  - login: an-nguyen
    areas: [frontend]'

test_cmd_team_from_config_with_load() {
  team_env "$TEAM_YAML"
  run_scrum team
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Team (from team in .github/scrum.yml): 2 members"
  assert_contains "$OUT" "Load in Sprint 5:"
  assert_contains "$OUT" "@tuandt  [backend]  2 open tasks, 10 / 10 pt"
  assert_contains "$OUT" "@an-nguyen  [frontend]  1 open task, 1 pt, no capacity set"
  assert_not_contains "$(gh_calls)" "assignees" "GitHub's list is read only when team is empty"
  assert_eq "" "$(gh_writes)"
}

test_cmd_team_falls_back_to_github() {
  team_env 'version: 1'
  run_scrum team --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "github" "$(printf '%s' "$OUT" | jq -r .source)"
  assert_eq "tuandt,minh-ho" "$(printf '%s' "$OUT" | jq -r '[.members[].login] | join(",")')"
  assert_json_eq '{"tasks":2,"points":10,"done_points":0}' "$(printf '%s' "$OUT" | jq -c '.members[0].load')"
  assert_eq "null" "$(printf '%s' "$OUT" | jq -c '.members[1].capacity')"
  run_scrum team
  assert_contains "$OUT" "from GitHub"
  assert_eq "" "$(gh_writes)"
}

test_cmd_team_without_open_sprint() {
  team_env "$TEAM_YAML"
  printf '[{"number":4,"title":"Sprint 4","state":"closed","description":""}]' > "$FAKE_GH_DIR/ms.json"
  run_scrum team
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "There is no open sprint, so no load is shown."
  assert_contains "$OUT" "@tuandt  [backend]  capacity 10 pt"
  assert_not_contains "$(gh_calls)" "issues?milestone"
}

test_cmd_team_json_shape() {
  team_env "$TEAM_YAML"
  run_scrum team --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "config" "$(printf '%s' "$OUT" | jq -r .source)"
  assert_json_eq '{"login":"tuandt","areas":["backend"],"capacity":10,"load":{"tasks":2,"points":10,"done_points":0}}' \
    "$(printf '%s' "$OUT" | jq -c '.members[0]')"
}

# The scenarios "Có sprint đang mở" and "Thành viên không có capacity", with their numbers.
test_cmd_team_spec_numbers() {
  team_env "points:
  scale: [1, 2, 3, 5, 8]
$TEAM_YAML"
  jq -s . <(issue 42 New 3 tuandt) <(issue 43 New 5 tuandt) <(issue 44 New 2 an-nguyen) > "$FAKE_GH_DIR/s5.json"
  run_scrum team
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "@tuandt  [backend]  2 open tasks, 8 / 10 pt"
  assert_contains "$OUT" "@an-nguyen  [frontend]  1 open task, 2 pt, no capacity set"
}

test_cmd_team_unknown_option() {
  team_env "$TEAM_YAML"
  run_scrum team --all
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "unknown option for team"
}
