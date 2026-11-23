# scrum release (spec: release)

defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }

# rel_issue NUMBER [LABELS_CSV] [CLOSED_AT] [STATE_REASON] [BODY]
rel_issue() {
  jq -nc --argjson n "$1" --arg l "${2:-}" --arg c "${3:-2026-11-15T10:00:00Z}" --arg r "${4:-completed}" --arg b "${5:-}" '{
    number: $n, title: "Task \($n)", state: "closed", state_reason: $r, closed_at: $c, body: $b,
    labels: ($l | split(",") | map(select(. != "")) | map({name: .})), assignees: [] }'
}
issues() { jq -sc . ; }

# plan_of ISSUES [PREV_JSON] [VERSION] [SINCE_JSON] [CFG]  -> sets PLAN
plan_of() {
  PLAN="$(jqt release-plan -n --argjson cfg "${5:-$(defaults)}" --argjson prev "${2:-null}" \
    --argjson issues "$1" --argjson since "${4:-null}" --argjson until null --arg version "${3:-}")"
}
pv() { printf '%s' "$PLAN" | jq -r "$1"; }

PREV='{"name":"v1.4.2","version":[1,4,2],"date":"2026-11-10T08:00:00Z"}'

# ---------- previous version (spec "Previous version") ----------

test_version_tags_highest_semver_first() {
  local out
  out="$(printf '%s' '[{"name":"v0.9.0"},{"name":"v0.11.0"},{"name":"v0.10.0"},{"name":"latest"},{"name":"v1.0"},{"name":"0.8.0"}]' \
    | jq -c -L "$PLUGIN_DIR/runtime/lib/jq" 'include "scrum"; version_tags("v") | map(.name)')"
  assert_eq '["v0.11.0","v0.10.0","v0.9.0","0.8.0"]' "$out"
}

test_version_tags_without_prefix() {
  local out
  out="$(printf '%s' '[{"name":"1.2.3"},{"name":"v2.0.0"},{"name":"release-3.0.0"}]' \
    | jq -c -L "$PLUGIN_DIR/runtime/lib/jq" 'include "scrum"; version_tags("") | map(.name)')"
  assert_eq '["1.2.3"]' "$out"
  out="$(printf '%s' '[{"name":"1.2.3"},{"name":"v1.2.3"}]' \
    | jq -c -L "$PLUGIN_DIR/runtime/lib/jq" 'include "scrum"; version_tags("v") | map(.name)')"
  assert_eq '["v1.2.3"]' "$out" "the same version twice keeps the prefixed tag"
}

test_no_tag_suggests_first_version() {
  plan_of "$(rel_issue 12 | issues)"
  assert_eq "0.1.0 v0.1.0 first null" "$(pv '"\(.version) \(.tag) \(.bump) \(.previous)"')"
}

test_first_version_from_config_and_empty_prefix() {
  plan_of "$(rel_issue 12 | issues)" null "" null "$(defaults | jq -c '.release.first_version = "1.0.0" | .release.tag_prefix = ""')"
  assert_eq "1.0.0 1.0.0" "$(pv '"\(.version) \(.tag)"')"
}

# ---------- gather done tasks (spec "Gather done tasks") ----------

test_since_previous_tag_keeps_completed_after_it() {
  plan_of "$( { rel_issue 12 '' 2026-11-15T10:00:00Z; rel_issue 13 '' 2026-11-16T10:00:00Z not_planned
                rel_issue 11 '' 2026-11-09T10:00:00Z; } | issues)" "$PREV" "" '"2026-11-10T08:00:00Z"'
  assert_eq "[12]" "$(pv '[.tasks[].number] | tojson')"
}

test_epics_features_meta_and_prs_left_out() {
  local list
  list="$( { rel_issue 12; rel_issue 20 'type: feature'; rel_issue 21 'type: epic'; rel_issue 22 'scrum: meta'
             rel_issue 23 | jq -c '. + {pull_request: {url: "x"}}'; rel_issue 12; } | issues)"
  plan_of "$list" "$PREV"
  assert_eq "[12]" "$(pv '[.tasks[].number] | tojson')"
}

test_nothing_to_release() {
  plan_of "$(rel_issue 13 '' 2026-11-16T10:00:00Z not_planned | issues)" "$PREV" "" '"2026-11-10T08:00:00Z"'
  assert_eq "true" "$(pv .nothing)"
}

test_until_bounds_tasks_of_an_existing_tag() {
  PLAN="$(jqt release-plan -n --argjson cfg "$(defaults)" --argjson prev "$PREV" --argjson since '"2026-11-10T08:00:00Z"' \
    --argjson until '"2026-11-20T00:00:00Z"' --arg version 1.5.0 \
    --argjson issues "$( { rel_issue 12; rel_issue 14 '' 2026-11-21T10:00:00Z; } | issues)")"
  assert_eq "[12]" "$(pv '[.tasks[].number] | tojson')"
}

# ---------- suggested version (spec "Suggested version") ----------

test_only_bugs_bump_patch() {
  plan_of "$( { rel_issue 12 bug; rel_issue 13 Bug; } | issues)" "$PREV"
  assert_eq "v1.4.3 patch" "$(pv '"\(.tag) \(.bump)"')"
}

test_a_feature_bumps_minor() {
  plan_of "$( { rel_issue 12 bug; rel_issue 13; } | issues)" "$PREV"
  assert_eq "v1.5.0 minor [13]" "$(pv '"\(.tag) \(.bump) \(.reasons.features | tojson)"')"
}

test_a_breaking_change_bumps_major() {
  plan_of "$( { rel_issue 12 bug; rel_issue 13; rel_issue 14 'Breaking,bug'; } | issues)" "$PREV"
  assert_eq "v2.0.0 major [14]" "$(pv '"\(.tag) \(.bump) \(.reasons.breaking | tojson)"')"
  assert_eq "breaking" "$(pv '.tasks[] | select(.number == 14) | .kind')"
}

test_given_version_must_be_greater() {
  plan_of "$(rel_issue 12 | issues)" "$PREV" 1.4.0
  assert_contains "$(pv .error)" "must be greater than v1.4.2"
  plan_of "$(rel_issue 12 | issues)" "$PREV" 1.4.2
  assert_contains "$(pv .error)" "must be greater than v1.4.2"
}

test_given_version_must_be_semver() {
  plan_of "$(rel_issue 12 | issues)" "$PREV" 1.5
  assert_contains "$(pv .error)" "1.5 is not a version"
}

test_given_version_with_or_without_prefix() {
  plan_of "$(rel_issue 12 bug | issues)" "$PREV" v2.1.0
  assert_eq "null v2.1.0 given 1.4.3" "$(pv '"\(.error) \(.tag) \(.bump) \(.suggested)"')"
  plan_of "$(rel_issue 12 bug | issues)" "$PREV" 2.1.0
  assert_eq "v2.1.0" "$(pv .tag)"
}

test_parent_from_body_or_sub_issue_link() {
  plan_of "$( { rel_issue 12 '' 2026-11-15T10:00:00Z completed $'Text\n\nPart of #10'
                rel_issue 13 | jq -c '. + {parent_issue_url: "https://api.github.com/repos/acme/blog/issues/11"}'; } | issues)" "$PREV"
  assert_eq '[10,11]' "$(pv '[.tasks[].parent] | tojson')"
}

test_timeline_prs_merged_closing_pull_requests() {
  local tl
  tl='[{"event":"cross-referenced","source":{"issue":{"number":40,"body":"Closes #12","pull_request":{"merged_at":"2026-11-15T09:00:00Z"},"repository":{"full_name":"acme/blog"}}}},
       {"event":"cross-referenced","source":{"issue":{"number":41,"body":"Closes #12","pull_request":{"merged_at":null}}}},
       {"event":"cross-referenced","source":{"issue":{"number":42,"body":"See #12","pull_request":{"merged_at":"2026-11-15T09:00:00Z"}}}},
       {"event":"cross-referenced","source":{"issue":{"number":43,"body":"Fixes #12","pull_request":{"merged_at":"x"},"repository":{"full_name":"other/repo"}}}},
       {"event":"cross-referenced","source":{"issue":{"number":44,"body":"Closes #12"}}},
       {"event":"closed","commit_id":"abc"}]'
  assert_eq "[40]" "$(printf '%s' "$tl" | jq -c -L "$PLUGIN_DIR/runtime/lib/jq" 'include "scrum"; timeline_prs("acme/blog"; 12)')"
}

# ---------- release notes (spec "Release notes") ----------

strings() { jq -c --arg l "$1" '.[$l]' "$PLUGIN_DIR/runtime/share/strings.json"; }
# notes_of PLAN [PRS] [PARENTS] [LANG]
notes_of() {
  local prs="${2:-}" parents="${3:-}"
  [ -n "$prs" ] || prs='{}'
  [ -n "$parents" ] || parents='{}'
  jqt release-notes -r -n --argjson plan "$1" --argjson prs "$prs" --argjson parents "$parents" \
    --argjson strings "$(strings "${4:-en}")" --arg repo acme/blog
}

test_notes_parent_feature_and_bug_fixes() {
  local notes expected
  plan_of "$( { rel_issue 12 '' 2026-11-15T10:00:00Z completed 'Part of #10'
                rel_issue 13 '' 2026-11-15T10:00:00Z completed 'Part of #10'
                rel_issue 14 bug; } | issues)" "$PREV"
  notes="$(notes_of "$PLAN" '{"12":[40],"13":[41,42],"14":null}' '{"10":"Comments"}')"
  expected="$(printf '%s\n' '## Features' '' '### Comments' '' '- Task 12 (#12, PR #40)' '- Task 13 (#13, PR #41, #42)' '' \
    '## Bug fixes' '' '- Task 14 (#14)' '' '**Full changelog**: https://github.com/acme/blog/compare/v1.4.2...v1.5.0')"
  assert_eq "$expected" "$notes"
}

test_notes_groups_in_order_and_empty_groups_left_out() {
  local notes
  plan_of "$( { rel_issue 15 bug; rel_issue 16 breaking; rel_issue 17 '' 2026-11-15T10:00:00Z completed 'Part of #9'; rel_issue 18; } | issues)"
  notes="$(notes_of "$PLAN")"
  assert_eq "## Breaking changes|## Features|### #9|## Bug fixes" "$(printf '%s\n' "$notes" | grep '^#' | paste -sd '|' -)"
  assert_contains "$notes" $'## Features\n\n- Task 18 (#18)\n\n### #9\n\n- Task 17 (#17)'
  assert_not_contains "$notes" "Full changelog" "no previous tag, no compare link"
  plan_of "$(rel_issue 15 bug | issues)" "$PREV"
  notes="$(notes_of "$PLAN")"
  assert_not_contains "$notes" "## Features"
  assert_not_contains "$notes" "## Breaking"
}

test_notes_in_vietnamese() {
  local notes
  plan_of "$( { rel_issue 15 bug; rel_issue 16 breaking; rel_issue 18; } | issues)" "$PREV"
  notes="$(notes_of "$PLAN" '{}' '{}' vi)"
  assert_contains "$notes" "## Thay đổi không tương thích"
  assert_contains "$notes" "## Tính năng"
  assert_contains "$notes" "## Sửa lỗi"
  assert_contains "$notes" "**Toàn bộ thay đổi**"
}

# ---------- scrum release with a fake gh ----------

# release_env: tags v1.4.2 (on main, 2026-11-10) and v1.3.0; #12 a feature closed by PR #40, #14 a bug.
release_env() {
  setup_fake_gh
  setup_repo 'version: 1'
  route 'auth status*' "auth.txt"
  cp "$FIXTURES/gh-auth-status.txt" "$FAKE_GH_DIR/auth.txt"
  route_json 'api repos/acme/blog' '{"default_branch":"main"}'
  route_json 'api --paginate repos/acme/blog/tags*' '[{"name":"v1.3.0"},{"name":"v1.4.2"},{"name":"nightly"}]'
  route_json 'api repos/acme/blog/compare/v1.4.2...main' '{"status":"ahead","base_commit":{"commit":{"committer":{"date":"2026-11-10T08:00:00Z"}}}}'
  route_json 'api repos/acme/blog/compare/v1.3.0...main' '{"status":"ahead","base_commit":{"commit":{"committer":{"date":"2026-10-01T08:00:00Z"}}}}'
  printf '%s' "$( { rel_issue 12 '' 2026-11-15T10:00:00Z completed 'Part of #10'; rel_issue 14 bug
                    rel_issue 13 '' 2026-11-16T10:00:00Z not_planned; rel_issue 9 '' 2026-11-09T10:00:00Z; } | issues)" > "$FAKE_GH_DIR/closed.json"
  route 'api --paginate repos/acme/blog/issues?state=closed*' "closed.json"
  route_json 'api --paginate repos/acme/blog/issues/12/timeline*' \
    '[{"event":"cross-referenced","source":{"issue":{"number":40,"body":"Closes #12","pull_request":{"merged_at":"2026-11-15T09:00:00Z"}}}}]'
  route_json 'api --paginate repos/acme/blog/issues/14/timeline*' '[]'
  route_json 'api repos/acme/blog/issues/10' '{"number":10,"title":"Comments"}'
  route 'api repos/acme/blog/git/ref/tags/*' '!404'
  route 'api repos/acme/blog/releases/tags/*' '!404'
  route_json 'api repos/acme/blog/git/ref/heads/main' '{"object":{"sha":"abc1234def"}}'
  route_json 'api -X POST repos/acme/blog/git/tags *' '{"sha":"tag5678"}'
  route_json 'api -X POST repos/acme/blog/git/refs *' '{"ref":"refs/tags/v1.5.0"}'
  route_json 'api -X POST repos/acme/blog/releases *' '{"html_url":"https://github.com/acme/blog/releases/tag/v1.5.0"}'
}

test_cmd_release_preview_writes_nothing() {
  release_env
  run_scrum release
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Previous version: v1.4.2 (2026-11-10)"
  assert_contains "$OUT" "New version: v1.5.0: minor, new in #12 (not bugs)"
  assert_contains "$OUT" "#12  feature  Task 12  PR #40"
  assert_contains "$OUT" "### Comments"
  assert_contains "$OUT" "- Task 14 (#14)"
  assert_contains "$OUT" "compare/v1.4.2...v1.5.0"
  assert_not_contains "$OUT" "Task 13"
  assert_not_contains "$OUT" "Task 9 "
  assert_contains "$OUT" "run again with --yes"
  assert_contains "$(gh_calls)" "issues?state=closed&since=2026-11-10T08:00:00Z"
  assert_eq "" "$(gh_writes)" "no GitHub writes"
}

test_cmd_release_json() {
  release_env
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "v1.5.0 minor v1.4.2 [40]" "$(printf '%s' "$OUT" | jq -r '"\(.tag) \(.bump) \(.previous.tag) \(.tasks[0].prs | tojson)"')"
  assert_eq "Comments" "$(printf '%s' "$OUT" | jq -r '.tasks[0].parent_title')"
  assert_contains "$(printf '%s' "$OUT" | jq -r .notes)" "## Bug fixes"
  assert_eq "" "$(gh_writes)"
}

test_cmd_release_skips_a_tag_not_on_the_default_branch() {
  release_env
  route_first 'api repos/acme/blog/compare/v1.4.2...main' 'diverged.json'
  printf '{"status":"diverged","base_commit":{"commit":{"committer":{"date":"2026-11-10T08:00:00Z"}}}}' > "$FAKE_GH_DIR/diverged.json"
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "v1.3.0 v1.4.0" "$(printf '%s' "$OUT" | jq -r '"\(.previous.tag) \(.tag)"')"
}

test_cmd_release_nothing_to_release() {
  release_env
  printf '%s' "$(rel_issue 13 '' 2026-11-16T10:00:00Z not_planned | issues)" > "$FAKE_GH_DIR/closed.json"
  run_scrum release --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Nothing to release: no task was completed since v1.4.2."
  assert_eq "" "$(gh_writes)"
}

test_cmd_release_invalid_version_stops() {
  release_env
  run_scrum release 1.4.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "must be greater than v1.4.2"
  assert_eq "" "$(gh_writes)"
}

test_cmd_release_creates_tag_ref_and_release_in_order() {
  release_env
  run_scrum release --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "repos/acme/blog/git/tags|repos/acme/blog/git/refs|repos/acme/blog/releases" \
    "$(gh_writes | sed 's/.*-X POST \([^ ]*\).*/\1/' | paste -sd '|' -)"
  assert_contains "$(gh_calls)" 'STDIN {"tag":"v1.5.0","message":"Release v1.5.0","object":"abc1234def","type":"commit"}'
  assert_contains "$(gh_calls)" 'STDIN {"ref":"refs/tags/v1.5.0","sha":"tag5678"}'
  assert_eq "v1.5.0 false" "$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r '"\(.tag_name) \(.draft)"')"
  assert_contains "$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r .body)" "- Task 12 (#12, PR #40)"
  assert_contains "$OUT" "Created tag v1.5.0 on main (abc1234)."
  assert_contains "$OUT" "Published release v1.5.0: https://github.com/acme/blog/releases/tag/v1.5.0"
}

test_cmd_release_draft() {
  release_env
  run_scrum release --draft --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "true" "$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r .draft)"
  assert_contains "$OUT" "Created the draft release v1.5.0"
}

test_cmd_release_notes_file() {
  release_env
  printf 'Hand-written notes\n' > "$T/notes.md"
  run_scrum release --notes-file "$T/notes.md" --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "Hand-written notes" "$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r .body)"
}

test_cmd_release_already_released_stops() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  printf '{"html_url":"https://github.com/acme/blog/releases/tag/v1.5.0"}' > "$FAKE_GH_DIR/released.json"
  route_first 'api repos/acme/blog/releases/tags/v1.5.0' 'released.json'
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "v1.5.0 is already released"
  assert_eq "" "$(gh_writes)"
}

test_cmd_release_failed_after_the_tag_then_rerun_creates_only_the_release() {
  release_env
  route_first 'api -X POST repos/acme/blog/releases *' '!fail'
  run_scrum release --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "tag v1.5.0 exists on GitHub, but its release was not created"
  assert_contains "$ERR" "scrum release 1.5.0 --yes"
  # The rerun: tag v1.5.0 now exists (on main), without a release.
  : > "$FAKE_GH_LOG"
  sed -i.bak '1d' "$FAKE_GH_DIR/routes"
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  route_json 'api repos/acme/blog/commits/v1.5.0' '{"commit":{"committer":{"date":"2026-11-20T08:00:00Z"}}}'
  run_scrum release 1.5.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "repos/acme/blog/releases" "$(gh_writes | sed 's/.*-X POST \([^ ]*\).*/\1/' | paste -sd '|' -)"
  assert_contains "$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r .body)" "compare/v1.4.2...v1.5.0"
  assert_contains "$OUT" "Published release v1.5.0"
}

test_cmd_release_by_sprint() {
  release_env
  route_json 'api --paginate repos/acme/blog/milestones*' \
    '[{"number":5,"title":"Sprint 5","state":"closed","description":"scrum:start=2026-11-09 end=2026-11-13"},{"number":6,"title":"Sprint 6","state":"open","description":"scrum:start=2026-11-16 end=2026-11-20"}]'
  route_json 'api --paginate repos/acme/blog/issues?milestone=5*' "$( { rel_issue 9 '' 2026-11-09T10:00:00Z; rel_issue 13 '' 2026-11-12T10:00:00Z not_planned; } | issues)"
  route_json 'api --paginate repos/acme/blog/issues/9/timeline*' '[]'
  run_scrum release --sprint "Sprint 5" --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[9]" "$(printf '%s' "$OUT" | jq -c '[.tasks[].number]')"
  assert_not_contains "$(gh_calls)" "issues?state=closed"
}

test_cmd_release_forbidden_tag_points_to_doctor() {
  release_env
  route_first 'api -X POST repos/acme/blog/git/tags *' '!403'
  run_scrum release --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "contents: write"
  assert_contains "$ERR" "/scrum-github:doctor"
  assert_eq "repos/acme/blog/git/tags" "$(gh_writes | sed 's/.*-X POST \([^ ]*\).*/\1/' | paste -sd '|' -)" "no ref, no release"
}

test_cmd_release_since_tag() {
  release_env
  run_scrum release --since v1.3.0 --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "v1.3.0 [9,12,14]" "$(printf '%s' "$OUT" | jq -c -r '"\(.previous.tag) \([.tasks[].number] | tojson)"')"
  run_scrum release --since v9.9.9
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "no version tag named v9.9.9"
}
