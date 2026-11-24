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
  route_json 'api --paginate repos/acme/blog/releases*' '[]'
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
  assert_contains "$OUT" "run again with 1.5.0 and --yes"
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
  run_scrum release 1.5.0 --yes
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
  run_scrum release 1.5.0 --yes
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
  run_scrum release 1.5.0 --draft --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "true" "$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r .draft)"
  assert_contains "$OUT" "Created the draft release v1.5.0"
}

test_cmd_release_notes_file() {
  release_env
  printf 'Hand-written notes\n' > "$T/notes.md"
  run_scrum release 1.5.0 --notes-file "$T/notes.md" --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "Hand-written notes" "$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r .body)"
}

test_cmd_release_already_released_stops() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  printf '[{"tag_name":"v1.5.0","draft":false,"html_url":"https://github.com/acme/blog/releases/tag/v1.5.0"}]' > "$FAKE_GH_DIR/released.json"
  route_first 'api --paginate repos/acme/blog/releases*' 'released.json'
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "v1.5.0 is already released"
  assert_eq "" "$(gh_writes)"
}

test_cmd_release_failed_after_the_tag_then_rerun_creates_only_the_release() {
  release_env
  route_first 'api -X POST repos/acme/blog/releases *' '!fail'
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "tag v1.5.0 exists on GitHub, but its release was not created"
  assert_contains "$ERR" "scrum release 1.5.0 --yes"
  # The rerun: tag v1.5.0 now exists (on main), without a release.
  : > "$FAKE_GH_LOG"
  sed -i.bak '1d' "$FAKE_GH_DIR/routes"
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  route_json 'api repos/acme/blog/compare/v1.5.0...main' '{"status":"identical","base_commit":{"commit":{"committer":{"date":"2026-11-20T08:00:00Z"}}}}'
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
  run_scrum release 1.5.0 --yes
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

# ---------- spec scenarios and edge cases end to end (test engineer) ----------

# spec "Several tags": the highest semver, not the lexical order, through scrum release.
test_cmd_release_several_tags_highest_semver() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags3.json'
  printf '[{"name":"v0.9.0"},{"name":"v0.11.0"},{"name":"v0.10.0"}]' > "$FAKE_GH_DIR/tags3.json"
  route_json 'api repos/acme/blog/compare/v0.11.0...main' '{"status":"identical","base_commit":{"commit":{"committer":{"date":"2026-11-10T08:00:00Z"}}}}'
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "v0.11.0 v0.12.0" "$(printf '%s' "$OUT" | jq -r '"\(.previous.tag) \(.tag)"')"
  assert_not_contains "$(gh_calls)" "compare/v0.9.0" "only the highest tag on the branch is compared"
}

# Pre-release and odd tags are not version tags.
test_version_tags_ignore_pre_releases_and_odd_names() {
  local out
  out="$(printf '%s' '[{"name":"v1.2"},{"name":"v1.2.3-rc1"},{"name":"release-1"},{"name":"v2.0.0-beta.1"},{"name":"v1.2.3"},{"name":"V1.9.9"},{"name":"vv1.0.0"}]' \
    | jq -c -L "$PLUGIN_DIR/runtime/lib/jq" 'include "scrum"; version_tags("v") | map(.name)')"
  assert_eq '["v1.2.3"]' "$out"
}

# spec "No tag yet": the first release reads every closed issue and suggests release.first_version.
test_cmd_release_first_release_without_tags() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'notags.json'
  printf '[{"name":"nightly"},{"name":"v1.2.3-rc1"}]' > "$FAKE_GH_DIR/notags.json"
  route_json 'api --paginate repos/acme/blog/issues/9/timeline*' '[]'
  run_scrum release
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Previous version: none"
  assert_contains "$OUT" "New version: v0.1.0: the first release"
  assert_not_contains "$OUT" "Full changelog"
  assert_contains "$(gh_calls)" "issues?state=closed&per_page=100"
  assert_not_contains "$(gh_calls)" "since="
  assert_eq "" "$(gh_writes)"
}

# tag_prefix "": tags without a prefix are the version tags, the new tag has no prefix.
test_cmd_release_with_empty_tag_prefix() {
  release_env
  printf 'version: 1\nrelease:\n  tag_prefix: ""\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_first 'api --paginate repos/acme/blog/tags*' 'tags4.json'
  printf '[{"name":"1.4.2"},{"name":"v9.0.0"}]' > "$FAKE_GH_DIR/tags4.json"
  route_json 'api repos/acme/blog/compare/1.4.2...main' '{"status":"ahead","base_commit":{"commit":{"committer":{"date":"2026-11-10T08:00:00Z"}}}}'
  run_scrum release 1.5.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" 'STDIN {"tag":"1.5.0","message":"Release 1.5.0"'
  assert_contains "$(gh_calls)" 'STDIN {"ref":"refs/tags/1.5.0"'
  assert_contains "$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r .body)" "compare/1.4.2...1.5.0"
}

# Tags without the prefix count when the prefix is "v" (spec: <tag_prefix>X.Y.Z or X.Y.Z).
test_cmd_release_unprefixed_tag_with_v_prefix() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags5.json'
  printf '[{"name":"1.4.2"}]' > "$FAKE_GH_DIR/tags5.json"
  route_json 'api repos/acme/blog/compare/1.4.2...main' '{"status":"ahead","base_commit":{"commit":{"committer":{"date":"2026-11-10T08:00:00Z"}}}}'
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "1.4.2 v1.5.0" "$(printf '%s' "$OUT" | jq -r '"\(.previous.tag) \(.tag)"')"
}

# Label names are compared case-insensitively: BREAKING bumps major, Bug alone bumps patch.
test_cmd_release_label_case() {
  release_env
  printf '%s' "$( { rel_issue 12 'BREAKING' 2026-11-15T10:00:00Z; rel_issue 14 Bug; } | issues)" > "$FAKE_GH_DIR/closed.json"
  route_json 'api --paginate repos/acme/blog/issues/12/timeline*' '[]'
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "v2.0.0 major [12] [14]" "$(printf '%s' "$OUT" | jq -c -r '"\(.tag) \(.bump) \(.reasons.breaking | tojson) \(.reasons.bugs | tojson)"')"
  printf '%s' "$(rel_issue 14 Bug | issues)" > "$FAKE_GH_DIR/closed.json"
  run_scrum release --json
  assert_eq "v1.4.3 patch" "$(printf '%s' "$OUT" | jq -r '"\(.tag) \(.bump)"')"
}

# Not planned, epics, features, meta issues and pull requests are left out through the command.
test_cmd_release_leaves_out_non_tasks() {
  release_env
  printf '%s' "$( { rel_issue 12; rel_issue 13 '' 2026-11-16T10:00:00Z not_planned; rel_issue 20 'type: feature'
                    rel_issue 21 'type: epic'; rel_issue 22 'scrum: meta'
                    rel_issue 23 | jq -c '. + {pull_request: {url: "x"}}'; } | issues)" > "$FAKE_GH_DIR/closed.json"
  route_json 'api --paginate repos/acme/blog/issues/12/timeline*' '[]'
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[12]" "$(printf '%s' "$OUT" | jq -c '[.tasks[].number]')"
}

# --sprint twice: the Done tasks of both sprints, and nothing else.
test_cmd_release_two_sprints() {
  release_env
  route_json 'api --paginate repos/acme/blog/milestones*' \
    '[{"number":5,"title":"Sprint 5","state":"closed","description":"scrum:start=2026-11-02 end=2026-11-06"},{"number":6,"title":"Sprint 6","state":"closed","description":"scrum:start=2026-11-09 end=2026-11-13"},{"number":7,"title":"Sprint 7","state":"open","description":"scrum:start=2026-11-16 end=2026-11-20"}]'
  route_json 'api --paginate repos/acme/blog/issues?milestone=5*' "$( { rel_issue 31; rel_issue 32 '' 2026-11-05T10:00:00Z not_planned; } | issues)"
  route_json 'api --paginate repos/acme/blog/issues?milestone=6*' "$(rel_issue 33 bug | issues)"
  route_json 'api --paginate repos/acme/blog/issues?milestone=7*' "$(rel_issue 34 | issues)"
  route_json 'api --paginate repos/acme/blog/issues/3*/timeline*' '[]'
  run_scrum release --sprint "Sprint 5" --sprint "Sprint 6" --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[31,33]" "$(printf '%s' "$OUT" | jq -c '[.tasks[].number]')"
  assert_not_contains "$(gh_calls)" "milestone=7"
  assert_eq "" "$(gh_writes)"
}

# --sprint with no Done task: nothing to release, exit 0, no writes even with --yes.
test_cmd_release_sprint_without_done_tasks() {
  release_env
  route_json 'api --paginate repos/acme/blog/milestones*' '[{"number":5,"title":"Sprint 5","state":"closed","description":""}]'
  route_json 'api --paginate repos/acme/blog/issues?milestone=5*' "$(rel_issue 32 '' 2026-11-05T10:00:00Z not_planned | issues)"
  run_scrum release 1.5.0 --sprint "Sprint 5" --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Nothing to release"
  assert_eq "" "$(gh_writes)"
}

# Empty groups are not printed by the command: only bug fixes.
test_cmd_release_only_bugs_prints_only_bug_fixes() {
  release_env
  printf '%s' "$(rel_issue 14 bug | issues)" > "$FAKE_GH_DIR/closed.json"
  run_scrum release
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "## Bug fixes"
  assert_not_contains "$OUT" "## Features"
  assert_not_contains "$OUT" "## Breaking changes"
}

# language: vi gives Vietnamese headings in the notes sent to GitHub.
test_cmd_release_notes_in_vietnamese() {
  release_env
  printf 'version: 1\nlanguage: vi\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum release 1.5.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  local body
  body="$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r .body)"
  assert_contains "$body" "## Tính năng"
  assert_contains "$body" "## Sửa lỗi"
  assert_contains "$body" "**Toàn bộ thay đổi**"
}

# spec "Preview": no write call, also with --draft, --notes-file or a given version.
test_cmd_release_preview_with_options_writes_nothing() {
  release_env
  printf 'Notes\n' > "$T/notes.md"
  run_scrum release --draft
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "New version: v1.5.0 (draft)"
  run_scrum release --notes-file "$T/notes.md"
  assert_status 0 "$STATUS" "$ERR"
  run_scrum release 2.0.0 --draft --notes-file "$T/notes.md" --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "v2.0.0 given true" "$(printf '%s' "$OUT" | jq -r '"\(.tag) \(.bump) \(.draft)"')"
  assert_eq "" "$(gh_writes)"
}

# A given version must be semver: the command stops with --yes and writes nothing.
test_cmd_release_not_semver_given_stops() {
  release_env
  run_scrum release 1.5 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "1.5 is not a version"
  assert_eq "" "$(gh_writes)"
}

# spec "Tag already released": also stops in the preview, and a version given with its prefix.
test_cmd_release_already_released_preview_and_prefixed_version() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  printf '[{"tag_name":"v1.5.0","draft":false,"html_url":"https://github.com/acme/blog/releases/tag/v1.5.0"}]' > "$FAKE_GH_DIR/released.json"
  route_first 'api --paginate repos/acme/blog/releases*' 'released.json'
  run_scrum release v1.5.0
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "v1.5.0 is already released"
  assert_eq "" "$(gh_writes)"
}

# spec "Release failed after the tag": the rerun does not touch the tag (no tag, no ref, no PATCH).
test_cmd_release_rerun_leaves_the_tag_alone() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  route_json 'api repos/acme/blog/compare/v1.5.0...main' '{"status":"identical","base_commit":{"commit":{"committer":{"date":"2026-11-20T08:00:00Z"}}}}'
  run_scrum release 1.5.0
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Tag v1.5.0 already exists (from an earlier run)"
  assert_eq "" "$(gh_writes)" "the preview of a rerun writes nothing"
  run_scrum release 1.5.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "repos/acme/blog/releases" "$(gh_writes | sed 's/.*-X POST \([^ ]*\).*/\1/' | paste -sd '|' -)"
  assert_not_contains "$(gh_calls)" "git/ref/heads/main"
  assert_eq "v1.5.0" "$(grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //' | jq -r .tag_name)"
}

# A 403 on the release read when the tag exists: stop, write nothing.
test_cmd_release_cannot_read_release_of_existing_tag() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  route_first 'api --paginate repos/acme/blog/releases*' '!403'
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "/scrum-github:doctor"
  assert_eq "" "$(gh_writes)"
}

# A task whose timeline cannot be read is still released, without pull request numbers.
test_cmd_release_timeline_unreadable_keeps_the_task() {
  release_env
  route_first 'api --paginate repos/acme/blog/issues/12/timeline*' '!fail'
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "null" "$(printf '%s' "$OUT" | jq -c '.tasks[] | select(.number == 12) | .prs')"
  assert_contains "$(printf '%s' "$OUT" | jq -r .notes)" "- Task 12 (#12)"
}

# When the tags are readable but no tag can be compared with the default branch, the previous
# version is unknown: the command must not fall back to a first release (release.first_version).
test_cmd_release_compare_failure_is_not_a_first_release() {
  release_env
  route_first 'api repos/acme/blog/compare/*' '!fail'
  run_scrum release --json
  case "$STATUS:$OUT" in
    1:*) ;;
    *) assert_not_contains "$(printf '%s' "$OUT" | jq -r .bump)" "first" "v1.4.2 exists: not a first release" ;;
  esac
  assert_eq "" "$(gh_writes)"
}

# ---------- review fixes ----------

pub_body() { grep '^STDIN {"tag_name"' "$FAKE_GH_LOG" | sed 's/^STDIN //'; }

# 1. A draft release is not returned by GET releases/tags/{tag}: the list (drafts too) is read.
test_cmd_release_draft_release_already_there_stops() {
  release_env
  route_first 'api --paginate repos/acme/blog/releases*' 'drafts.json'
  printf '[{"tag_name":"v1.5.0","draft":true}]' > "$FAKE_GH_DIR/drafts.json"
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "v1.5.0 is already released as a draft"
  assert_eq "" "$(gh_writes)"
}

test_cmd_release_draft_of_an_existing_tag_stops() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  route_first 'api --paginate repos/acme/blog/releases*' 'drafts.json'
  printf '[{"tag_name":"v1.5.0","draft":true}]' > "$FAKE_GH_DIR/drafts.json"
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "draft"
  assert_eq "" "$(gh_writes)"
}

test_cmd_release_release_made_since_the_preview_stops_before_writing() {
  release_env
  printf '[]' > "$FAKE_GH_DIR/none.json"
  printf '[{"tag_name":"v1.5.0","draft":true}]' > "$FAKE_GH_DIR/drafts.json"
  route_first 'api --paginate repos/acme/blog/releases*' 'none.json,drafts.json'
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "already released as a draft"
  assert_eq "" "$(gh_writes)"
}

# 2. --yes publishes the previewed version: it must be given.
test_cmd_release_yes_needs_the_version() {
  release_env
  run_scrum release --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--yes needs the version to publish"
  assert_not_contains "$(gh_calls)" "repos/acme/blog"
}

# 3. Tag names go into URL paths encoded: a prefix with "/".
test_cmd_release_tag_prefix_with_a_slash() {
  release_env
  printf 'version: 1\nrelease:\n  tag_prefix: "release/"\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_first 'api --paginate repos/acme/blog/tags*' 'tags6.json'
  printf '[{"name":"release/1.4.2"}]' > "$FAKE_GH_DIR/tags6.json"
  route_json 'api repos/acme/blog/compare/release%2F1.4.2...main' '{"status":"ahead","base_commit":{"commit":{"committer":{"date":"2026-11-10T08:00:00Z"}}}}'
  run_scrum release 1.5.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" "api repos/acme/blog/git/ref/tags/release%2F1.5.0"
  assert_contains "$(gh_calls)" 'STDIN {"ref":"refs/tags/release/1.5.0"'
  assert_eq "release/1.5.0" "$(pub_body | jq -r .tag_name)"
}

# 4. The boundary is when the tag was made, not its commit: a task closed by the last merge,
# 2 seconds after the head commit but before the tag, belongs to the previous release.
test_cmd_release_boundary_is_the_tagger_date() {
  release_env
  printf '%s' "$( { rel_issue 12; rel_issue 15 '' 2026-11-10T08:00:02Z; } | issues)" > "$FAKE_GH_DIR/closed.json"
  route_json 'api --paginate repos/acme/blog/issues/15/timeline*' '[]'
  route_first 'api repos/acme/blog/git/ref/tags/v1.4.2' 'ref142.json'
  printf '{"object":{"type":"tag","sha":"t142"}}' > "$FAKE_GH_DIR/ref142.json"
  route_json 'api repos/acme/blog/git/tags/t142' '{"tagger":{"date":"2026-11-10T08:05:00Z"}}'
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[12] 2026-11-10T08:05:00Z" "$(printf '%s' "$OUT" | jq -c -r '"\([.tasks[].number] | tojson) \(.previous.date)"')"
  assert_contains "$(gh_calls)" "since=2026-11-10T08:05:00Z"
}

test_cmd_release_boundary_of_a_lightweight_tag_is_its_release() {
  release_env
  printf '%s' "$( { rel_issue 12; rel_issue 15 '' 2026-11-10T08:00:02Z; } | issues)" > "$FAKE_GH_DIR/closed.json"
  route_first 'api --paginate repos/acme/blog/releases*' 'rels.json'
  printf '[{"tag_name":"v1.4.2","draft":false,"created_at":"2026-11-10T09:00:00Z"}]' > "$FAKE_GH_DIR/rels.json"
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[12]" "$(printf '%s' "$OUT" | jq -c '[.tasks[].number]')"
}

test_cmd_release_rerun_bound_is_the_tagger_date() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  route_json 'api repos/acme/blog/compare/v1.5.0...main' '{"status":"identical","base_commit":{"commit":{"committer":{"date":"2026-11-20T08:00:00Z"}}}}'
  route_first 'api repos/acme/blog/git/ref/tags/v1.5.0' 'ref150.json'
  printf '{"object":{"type":"tag","sha":"t150"}}' > "$FAKE_GH_DIR/ref150.json"
  route_json 'api repos/acme/blog/git/tags/t150' '{"tagger":{"date":"2026-11-21T08:00:00Z"}}'
  printf '%s' "$( { rel_issue 12; rel_issue 16 '' 2026-11-20T09:00:00Z; rel_issue 17 '' 2026-11-22T09:00:00Z; } | issues)" > "$FAKE_GH_DIR/closed.json"
  route_json 'api --paginate repos/acme/blog/issues/1[67]/timeline*' '[]'
  run_scrum release 1.5.0 --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[12,16]" "$(printf '%s' "$OUT" | jq -c '[.tasks[].number]')"
}

# 5. Version tags exist but none is confirmed on the branch: stop, never a first release.
test_cmd_release_compare_failure_stops_with_since_hint() {
  release_env
  route_first 'api repos/acme/blog/compare/*' '!fail'
  run_scrum release --json
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--since TAG"
  assert_contains "$ERR" "comparison failed"
}

test_cmd_release_no_tag_on_the_branch_stops() {
  release_env
  route_first 'api repos/acme/blog/compare/*' 'diverged.json'
  printf '{"status":"diverged","base_commit":{"commit":{"committer":{"date":"2026-11-10T08:00:00Z"}}}}' > "$FAKE_GH_DIR/diverged.json"
  run_scrum release
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "none of the version tags is on main"
}

test_cmd_release_tag_check_cap_stops() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'many.json'
  jq -nc '[range(1; 22) | {name: "v0.\(.).0"}]' > "$FAKE_GH_DIR/many.json"
  route_first 'api repos/acme/blog/compare/*' 'diverged.json'
  printf '{"status":"behind","base_commit":{"commit":{"committer":{"date":"2026-11-10T08:00:00Z"}}}}' > "$FAKE_GH_DIR/diverged.json"
  run_scrum release
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "more than 20 tags"
  assert_eq "20" "$(gh_calls | grep -c 'compare/')"
}

# 6. After a failed release, the hint repeats the command with its options.
test_cmd_release_rerun_hint_keeps_the_options() {
  release_env
  route_first 'api -X POST repos/acme/blog/releases *' '!fail'
  route_json 'api --paginate repos/acme/blog/milestones*' '[{"number":5,"title":"Sprint 5","state":"closed","description":""}]'
  route_json 'api --paginate repos/acme/blog/issues?milestone=5*' "$(rel_issue 12 | issues)"
  run_scrum release 1.5.0 --draft --sprint "Sprint 5" --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" 'with the same options: scrum release 1.5.0 --draft --sprint Sprint\ 5 --yes'
}

# 7. An existing tag given as VERSION must be on the default branch.
test_cmd_release_existing_tag_not_on_the_branch_stops() {
  release_env
  route_first 'api --paginate repos/acme/blog/tags*' 'tags2.json'
  printf '[{"name":"v1.5.0"},{"name":"v1.4.2"}]' > "$FAKE_GH_DIR/tags2.json"
  route_json 'api repos/acme/blog/compare/v1.5.0...main' '{"status":"diverged","base_commit":{"commit":{"committer":{"date":"2026-11-20T08:00:00Z"}}}}'
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "tag v1.5.0 exists but is not on main"
  assert_eq "" "$(gh_writes)"
}

# 8. 403 hints on the ref and the release; the wording after a tag object without a ref.
test_cmd_release_ref_failure_says_the_tag_object_is_harmless() {
  release_env
  route_first 'api -X POST repos/acme/blog/git/refs *' '!403'
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "/scrum-github:doctor"
  assert_contains "$ERR" "no ref points to it"
  assert_not_contains "$ERR" "Nothing was changed"
  assert_not_contains "$(gh_writes)" "releases"
}

test_cmd_release_forbidden_release_points_to_doctor() {
  release_env
  route_first 'api -X POST repos/acme/blog/releases *' '!403'
  run_scrum release 1.5.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "contents: write"
  assert_contains "$ERR" "/scrum-github:doctor"
}

test_gh_status_404_needs_the_http_status() {
  local f="$T/err"
  printf 'gh: Not Found (HTTP 404)\n' > "$f"
  ( SCRUM_ROOT="$PLUGIN_DIR/runtime"; . "$PLUGIN_DIR/runtime/lib/common.sh"; . "$PLUGIN_DIR/runtime/lib/cmd_release.sh"
    gh_status_404 "$f" ) || _fail "HTTP 404 not seen"
  printf 'gh: rate limit, retry in 404 seconds\n' > "$f"
  ( SCRUM_ROOT="$PLUGIN_DIR/runtime"; . "$PLUGIN_DIR/runtime/lib/common.sh"; . "$PLUGIN_DIR/runtime/lib/cmd_release.sh"
    ! gh_status_404 "$f" ) || _fail "a bare 404 taken as HTTP 404"
}

# 9. --json --yes: stdout is one JSON value, the progress lines go to stderr.
test_cmd_release_json_yes_prints_one_json_value() {
  release_env
  run_scrum release 1.5.0 --json --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "1" "$(printf '%s' "$OUT" | jq -s length)"
  assert_eq "https://github.com/acme/blog/releases/tag/v1.5.0 true" "$(printf '%s' "$OUT" | jq -r '"\(.published.url) \(.published.tag_created)"')"
  assert_contains "$ERR" "Published release v1.5.0"
}

# 10. A sprint that does not exist: a clear error, no jq error.
test_cmd_release_unknown_sprint() {
  release_env
  route_json 'api --paginate repos/acme/blog/milestones*' '[{"number":5,"title":"Sprint 5","state":"closed","description":""}]'
  run_scrum release --sprint "Sprint 99"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" 'no sprint named "Sprint 99"'
  assert_not_contains "$ERR" "jq:"
}

# 11. "@name" in a title notifies nobody.
test_notes_quiet_mentions() {
  local notes
  plan_of "$(rel_issue 12 | jq -c '.title = "Thanks @alice and @acme/devs, mail a@b.com, `@bob`"' | issues)" "$PREV"
  notes="$(notes_of "$PLAN")"
  assert_contains "$notes" '- Thanks `@alice` and `@acme/devs`, mail a@b.com, `@bob` (#12)'
}

# 12. A pull request with no body is not a closing one; a closing commit maps to its pull request.
test_timeline_prs_needs_a_closing_body() {
  local tl
  tl='[{"event":"cross-referenced","source":{"issue":{"number":45,"pull_request":{"merged_at":"x"}}}}]'
  assert_eq "[]" "$(printf '%s' "$tl" | jq -c -L "$PLUGIN_DIR/runtime/lib/jq" 'include "scrum"; timeline_prs("acme/blog"; 12)')"
}

test_cmd_release_pr_from_the_closing_commit() {
  release_env
  route_first 'api --paginate repos/acme/blog/issues/14/timeline*' 'tl14.json'
  printf '[{"event":"closed","commit_id":"abc999"}]' > "$FAKE_GH_DIR/tl14.json"
  route_json 'api repos/acme/blog/commits/abc999/pulls' '[{"number":50,"merged_at":"x","merge_commit_sha":"abc999"},{"number":51,"merged_at":"x","merge_commit_sha":"other"}]'
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[50]" "$(printf '%s' "$OUT" | jq -c '.tasks[] | select(.number == 14) | .prs')"
}

# ---------- presets with a working branch (spec release-pr) ----------

# open_issue NUMBER LABELS_CSV  An open task with these labels.
open_issue() {
  jq -nc --argjson n "$1" --arg l "${2:-}" '{number: $n, title: "Task \($n)", state: "open", state_reason: null, body: "",
    labels: ($l | split(",") | map(select(. != "")) | map({name: .})), assignees: []}'
}

# pr_env [PRESET]  Preset standard (or environments): v1.3.0 on main; #12 (PR #40, merge aaa111)
# and #13 (PR #41, merge bbb222) In review on develop, both contained in the head of develop
# (dev999); PR #42 "chore: bump actions" without a task, merged in v1.3.0...dev999.
pr_env() {
  setup_fake_gh
  setup_repo "$(printf 'version: 1\nbranching:\n  preset: %s\nstatuses:\n  in_review: In review\n' "${1:-standard}")"
  export SCRUM_TODAY=2026-11-24
  route 'auth status*' "auth.txt"
  cp "$FIXTURES/gh-auth-status.txt" "$FAKE_GH_DIR/auth.txt"
  route_json 'api --paginate repos/acme/blog/tags*' '[{"name":"v1.3.0"}]'
  route_json 'api repos/acme/blog/compare/v1.3.0...main' '{"status":"ahead","base_commit":{"commit":{"committer":{"date":"2026-11-01T08:00:00Z"}}}}'
  route 'api repos/acme/blog/git/ref/tags/*' '!404'
  route_json 'api --paginate repos/acme/blog/releases*' '[]'
  route_json 'api --paginate repos/acme/blog/pulls?state=open*' '[]'
  route_json 'api repos/acme/blog/git/ref/heads/develop' '{"object":{"sha":"dev999"}}'
  route_json 'api repos/acme/blog/git/ref/heads/staging' '{"object":{"sha":"stg777"}}'
  route_json 'api --paginate repos/acme/blog/issues?state=open&labels=on%3A%20develop&per_page=100' \
    "$( { open_issue 12 'status: In review,on: develop'; open_issue 13 'status: In review,on: develop'; } | issues)"
  route_json 'api --paginate repos/acme/blog/issues?state=open&labels=on%3A%20staging&per_page=100' '[]'
  route_json 'api --paginate repos/acme/blog/issues/12/timeline*' \
    '[{"event":"cross-referenced","source":{"issue":{"number":40,"body":"Closes #12","pull_request":{"merged_at":"2026-11-15T09:00:00Z"}}}}]'
  route_json 'api --paginate repos/acme/blog/issues/13/timeline*' \
    '[{"event":"cross-referenced","source":{"issue":{"number":41,"body":"Closes #13","pull_request":{"merged_at":"2026-11-16T09:00:00Z"}}}}]'
  route_json 'api repos/acme/blog/pulls/40' '{"number":40,"merge_commit_sha":"aaa111"}'
  route_json 'api repos/acme/blog/pulls/41' '{"number":41,"merge_commit_sha":"bbb222"}'
  route_json 'api repos/acme/blog/compare/aaa111...dev999' '{"status":"ahead"}'
  route_json 'api repos/acme/blog/compare/bbb222...dev999' '{"status":"ahead"}'
  route_json 'api repos/acme/blog/compare/v1.3.0...dev999' '{"status":"ahead","commits":[{"sha":"aaa111"},{"sha":"bbb222"},{"sha":"ccc333"}]}'
  route_json 'api repos/acme/blog/pulls?state=closed&base=develop*' '[
    {"number":40,"title":"feat: a","body":"Closes #12","merged_at":"x","merge_commit_sha":"aaa111","head":{"ref":"feat/12-a"},"base":{"ref":"develop"}},
    {"number":42,"title":"chore: bump actions","body":"","merged_at":"x","merge_commit_sha":"ccc333","head":{"ref":"deps"},"base":{"ref":"develop"}},
    {"number":43,"title":"Back-merge main into develop","body":"","merged_at":"x","merge_commit_sha":"ccc333","head":{"ref":"main"},"base":{"ref":"develop"}},
    {"number":44,"title":"never merged","body":"","merged_at":null,"merge_commit_sha":"ccc333","head":{"ref":"x"},"base":{"ref":"develop"}},
    {"number":45,"title":"old","body":"","merged_at":"x","merge_commit_sha":"zzz000","head":{"ref":"y"},"base":{"ref":"develop"}}]'
  route 'api repos/acme/blog/branches/*' '!404'
  route_json 'api -X POST repos/acme/blog/git/refs *' '{"ref":"refs/heads/release/v1.4.0"}'
  route_json 'api repos/acme/blog/git/commits/*' '{"sha":"dev999","tree":{"sha":"tree0"}}'
  route_json 'api -X POST repos/acme/blog/git/trees *' '{"sha":"tree1"}'
  route_json 'api -X POST repos/acme/blog/git/commits *' '{"sha":"c0ffee1"}'
  route_json 'api -X PATCH repos/acme/blog/git/refs/heads/* *' '{}'
  route_json 'api -X POST repos/acme/blog/pulls *' '{"number":50,"html_url":"https://github.com/acme/blog/pull/50"}'
}
write_paths() { gh_writes | sed 's/.*-X \([A-Z]*\) \([^ ]*\).*/\1 \2/' | paste -sd '|' -; }
stdin_of() { grep "^STDIN $1" "$FAKE_GH_LOG" | sed 's/^STDIN //'; }

# spec "Tasks of a release", "Pull requests without a task" (Dependency update): preview only.
test_release_pr_preview_lists_contained_tasks_and_other() {
  pr_env
  run_scrum release
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "New version: v1.4.0: minor, new in #12, #13 (not bugs)"
  assert_contains "$OUT" "Release pull request: release/v1.4.0 from develop (dev999) into main"
  assert_contains "$OUT" "#12  feature  Task 12  PR #40"
  assert_contains "$OUT" $'## Other\n\n- chore: bump actions (#42)'
  assert_not_contains "$OUT" "Back-merge main"
  assert_not_contains "$OUT" "never merged"
  assert_not_contains "$OUT" "(#45)"
  assert_eq "" "$(gh_writes)" "the preview writes nothing"
  assert_not_contains "$(gh_calls)" "api repos/acme/blog --"
}

test_release_pr_json() {
  pr_env
  run_scrum release --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq 'v1.4.0 minor [12,13] [42] pull_request release/v1.4.0 dev999' \
    "$(printf '%s' "$OUT" | jq -r '"\(.tag) \(.bump) \([.tasks[].number] | tojson) \([.other[].number] | tojson) \(.mode) \(.release_branch) \(.start.sha)"')"
}

# spec "Release pull request" (Standard): branch at the head of develop, pull request, no tag.
test_release_pr_standard_opens_the_pull_request_and_no_tag() {
  pr_env
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "POST repos/acme/blog/git/refs|POST repos/acme/blog/pulls" "$(write_paths)"
  assert_eq '{"ref":"refs/heads/release/v1.4.0","sha":"dev999"}' "$(stdin_of '{"ref"')"
  assert_eq "Release v1.4.0 release/v1.4.0 main" "$(stdin_of '{"title"' | jq -r '"\(.title) \(.head) \(.base)"')"
  local body
  body="$(stdin_of '{"title"' | jq -r .body)"
  assert_contains "$body" $'<!-- scrum-release-notes -->\n## Features'
  assert_contains "$body" $'- chore: bump actions (#42)\n\n**Full changelog**: https://github.com/acme/blog/compare/v1.3.0...v1.4.0\n<!-- /scrum-release-notes -->'
  assert_not_contains "$(gh_writes)" "git/tags"
  assert_not_contains "$(gh_writes)" "releases"
  assert_contains "$OUT" "Opened the release pull request #50: https://github.com/acme/blog/pull/50"
}

# spec "Release pull request" (Environments) and "Environments, task not promoted".
test_release_pr_environments_starts_at_staging() {
  pr_env environments
  route_first 'api --paginate repos/acme/blog/issues?state=open&labels=on%3A%20staging&per_page=100' 'staging.json'
  route_first 'api --paginate repos/acme/blog/issues?state=open&labels=on%3A%20develop&per_page=100' 'develop.json'
  open_issue 12 'status: In review,on: staging' | issues > "$FAKE_GH_DIR/staging.json"
  open_issue 13 'status: In review,on: develop' | issues > "$FAKE_GH_DIR/develop.json"
  route_json 'api repos/acme/blog/compare/aaa111...stg777' '{"status":"ahead"}'
  route_json 'api repos/acme/blog/compare/bbb222...stg777' '{"status":"behind"}'
  route_json 'api repos/acme/blog/compare/v1.3.0...stg777' '{"status":"ahead","commits":[{"sha":"aaa111"}]}'
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq '{"ref":"refs/heads/release/v1.4.0","sha":"stg777"}' "$(stdin_of '{"ref"')"
  assert_contains "$OUT" "#12  feature  Task 12"
  assert_not_contains "$OUT" "Task 13"
}

# spec "Release up to a commit" and "Task merged after the release point".
test_release_pr_from_a_commit() {
  pr_env
  route_json 'api repos/acme/blog/commits/abc123' '{"sha":"abc123full"}'
  route_json 'api repos/acme/blog/compare/aaa111...abc123full' '{"status":"ahead"}'
  route_json 'api repos/acme/blog/compare/bbb222...abc123full' '{"status":"behind"}'
  route_json 'api repos/acme/blog/compare/v1.3.0...abc123full' '{"status":"ahead","commits":[{"sha":"aaa111"}]}'
  run_scrum release 1.4.0 --from abc123
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "from abc123 (abc123f)"
  assert_contains "$OUT" "#12  feature"
  assert_not_contains "$OUT" "Task 13"
  run_scrum release 1.4.0 --from abc123 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_calls)" '"sha":"abc123full"'
}

# spec "Nothing to release" (release-pr).
test_release_pr_nothing_to_release_creates_nothing() {
  pr_env
  route_first 'api repos/acme/blog/compare/aaa111...dev999' 'behind.json'
  route_first 'api repos/acme/blog/compare/bbb222...dev999' 'behind.json'
  route_first 'api repos/acme/blog/compare/v1.3.0...dev999' 'empty.json'
  printf '{"status":"behind"}' > "$FAKE_GH_DIR/behind.json"
  printf '{"status":"identical","commits":[]}' > "$FAKE_GH_DIR/empty.json"
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Nothing to release"
  assert_eq "" "$(gh_writes)"
}

# spec "Release already open".
test_release_pr_already_open_stops_and_names_it() {
  pr_env
  route_first 'api --paginate repos/acme/blog/pulls?state=open*' 'open.json'
  printf '[{"number":49,"title":"Release v1.3.1","html_url":"https://github.com/acme/blog/pull/49","head":{"ref":"release/v1.3.1"},"base":{"ref":"main"}}]' > "$FAKE_GH_DIR/open.json"
  run_scrum release 1.4.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "#49 Release v1.3.1"
  assert_contains "$ERR" "https://github.com/acme/blog/pull/49"
  assert_eq "" "$(gh_writes)"
}

# spec "Version file": one commit with the new version, on the release branch, before the pull request.
test_release_pr_version_file_and_changelog_in_one_commit() {
  pr_env
  printf 'version: 1\nbranching:\n  preset: standard\nstatuses:\n  in_review: In review\nrelease:\n  version_files:\n    - path: package.json\n    - path: pyproject.toml\n      pattern: '"'"'version = "{version}"'"'"'\n  changelog: CHANGELOG.md\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_json 'api repos/acme/blog/contents/package.json?ref=dev999' \
    "$(jq -nc --arg c "$(printf '{\n  "name": "blog",\n  "version": "1.3.0"\n}\n' | base64)" '{content: $c}')"
  route_json 'api repos/acme/blog/contents/pyproject.toml?ref=dev999' \
    "$(jq -nc --arg c "$(printf '[project]\nversion = "1.3.0"\n' | base64)" '{content: $c}')"
  route 'api repos/acme/blog/contents/CHANGELOG.md*' '!404'
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "POST repos/acme/blog/git/refs|POST repos/acme/blog/git/trees|POST repos/acme/blog/git/commits|PATCH repos/acme/blog/git/refs/heads/release%2Fv1.4.0|POST repos/acme/blog/pulls" "$(write_paths)"
  local tree
  tree="$(stdin_of '{"base_tree"')"
  assert_eq "tree0" "$(printf '%s' "$tree" | jq -r .base_tree)"
  assert_eq "1.4.0" "$(printf '%s' "$tree" | jq -r '.tree[] | select(.path == "package.json") | .content | fromjson | .version')"
  assert_contains "$(printf '%s' "$tree" | jq -r '.tree[] | select(.path == "pyproject.toml") | .content')" 'version = "1.4.0"'
  assert_contains "$(printf '%s' "$tree" | jq -r '.tree[] | select(.path == "CHANGELOG.md") | .content')" $'## v1.4.0 (2026-11-24)\n\n### Features'
  assert_eq '{"message":"Release v1.4.0","tree":"tree1","parents":["dev999"]}' "$(stdin_of '{"message"')"
  assert_eq '{"sha":"c0ffee1","force":false}' "$(stdin_of '{"sha":"c0ffee1"')"
}

# Neither version_files nor changelog: no extra commit.
test_release_pr_no_files_no_commit() {
  pr_env
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$(gh_writes)" "git/trees"
  assert_not_contains "$(gh_writes)" "git/commits"
}

# spec "File without a version": stops before the branch is created, naming the file.
test_release_pr_file_without_a_version_stops_before_the_branch() {
  pr_env
  printf 'version: 1\nbranching:\n  preset: standard\nstatuses:\n  in_review: In review\nrelease:\n  version_files:\n    - path: pyproject.toml\n      pattern: '"'"'version = "{version}"'"'"'\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  route_json 'api repos/acme/blog/contents/pyproject.toml?ref=dev999' \
    "$(jq -nc --arg c "$(printf '[project]\nname = "x"\n' | base64)" '{content: $c}')"
  run_scrum release 1.4.0 --yes
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "pyproject.toml has no version to replace"
  assert_eq "" "$(gh_writes)"
}

# Only untasked pull requests: a patch (spec "Pull requests without a task").
test_release_plan_only_untasked_prs_is_a_patch() {
  PLAN="$(jqt release-plan -n --argjson cfg "$(defaults)" --argjson prev "$PREV" --argjson issues '[]' --argjson since null \
    --argjson until null --arg version "" --argjson contained '[]' --argjson other '[{"number":40,"title":"chore: bump"}]')"
  assert_eq "false patch v1.4.3 [40]" "$(pv '"\(.nothing) \(.bump) \(.tag) \([.other[].number] | tojson)"')"
}

# spec "Dependency update": a feature and an untasked pull request: minor, Other in the notes.
test_release_plan_feature_and_untasked_is_minor() {
  PLAN="$(jqt release-plan -n --argjson cfg "$(defaults)" --argjson prev "$PREV" \
    --argjson issues "$(open_issue 12 'status: In review' | issues)" --argjson since null --argjson until null --arg version "" \
    --argjson contained '[12]' --argjson other '[{"number":40,"title":"chore: bump actions"}]')"
  assert_eq "minor v1.5.0" "$(pv '"\(.bump) \(.tag)"')"
  assert_contains "$(notes_of "$PLAN")" $'## Other\n\n- chore: bump actions (#40)'
  assert_contains "$(notes_of "$PLAN" '{}' '{}' vi)" "## Khác"
}

# spec "Trunk releases as before": tag and release, no pull request, no branch.
test_release_trunk_opens_no_pull_request() {
  release_env
  run_scrum release 1.5.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$(gh_writes)" "pulls"
  assert_not_contains "$(gh_calls)" "refs/heads/release"
  assert_contains "$(gh_writes)" "git/tags"
  assert_contains "$(gh_writes)" "releases"
}

test_release_trunk_refuses_from() {
  release_env
  run_scrum release --from abc123
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--from is for presets with a working branch"
}

# ---------- version files (design 7) ----------

vf() { jqt version-files -n "$@"; }

test_version_file_pattern_first_match_of_the_previous_version() {
  local out
  out="$(vf --arg step pattern --arg content $'a = "1.3.0"\nversion = "1.3.0"\nversion = "1.3.0"\n' --arg pattern 'version = "{version}"' --arg prev 1.3.0 --arg version 1.4.0)"
  assert_eq '"a = \"1.3.0\"\nversion = \"1.4.0\"\nversion = \"1.3.0\"\n"' "$(printf '%s' "$out" | jq -c .content)"
  out="$(vf --arg step pattern --arg content $'version = "1.2.0"\n' --arg pattern 'version = "{version}"' --arg prev 1.3.0 --arg version 1.4.0)"
  assert_eq missing "$(printf '%s' "$out" | jq -r .status)"
  out="$(vf --arg step pattern --arg content $'version = "1.4.0"\n' --arg pattern 'version = "{version}"' --arg prev 1.3.0 --arg version 1.4.0)"
  assert_eq current "$(printf '%s' "$out" | jq -r .status)" "a file that already holds the new version is left alone"
}

test_version_file_json_top_level_version() {
  assert_eq '"changed" "1.4.0" "1.0.0"' "$(vf --arg step json --arg content '{"version":"1.3.0","dep":{"version":"1.0.0"}}' --arg version 1.4.0 \
    | jq -r '"\(.status | tojson) \(.object.version | tojson) \(.object.dep.version | tojson)"')"
  assert_eq missing "$(vf --arg step json --arg content '{"name":"x"}' --arg version 1.4.0 | jq -r .status)"
}

test_changelog_after_the_title() {
  local out
  out="$(vf --arg step changelog --arg content $'# Changelog\n\n## v1.3.0 (2026-01-01)\n\nold\n' --arg tag v1.4.0 --arg date 2026-11-24 --arg notes $'## Features\n\n- A (#1)')"
  assert_eq '"# Changelog\n\n## v1.4.0 (2026-11-24)\n\n### Features\n\n- A (#1)\n\n## v1.3.0 (2026-01-01)\n\nold\n"' "$(printf '%s' "$out" | jq -c .content)"
  out="$(vf --arg step changelog --arg content "$(printf '%s' "$out" | jq -j .content)" --arg tag v1.4.0 --arg date 2026-11-24 --arg notes x)"
  assert_eq current "$(printf '%s' "$out" | jq -r .status)"
}

# ---------- scrum release finish (spec "Publishing on merge", "Back-merge ...") ----------

# finish_env [PRESET] [HEAD] [BODY]  "Release v1.4.0" (#50, merge m111) merged into main; #12 In
# review on develop, contained in m111; main (m111) is not in develop yet.
finish_env() {
  pr_env "${1:-standard}"
  local body="${3:-$'Merging this pull request publishes v1.4.0.\n\n<!-- scrum-release-notes -->\n## Features\n\n- Task 12 (#12, PR #40)\n<!-- /scrum-release-notes -->'}"
  jq -nc --arg h "${2:-release/v1.4.0}" --arg b "$body" \
    '{action: "closed", pull_request: {number: 50, merged: true, merge_commit_sha: "m111", head: {ref: $h}, base: {ref: "main"}, body: $b}}' > "$T/event.json"
  export GITHUB_EVENT_PATH="$T/event.json"
  route_first 'api --paginate repos/acme/blog/issues?state=open&labels=on%3A%20develop&per_page=100' 'dev-issues.json'
  open_issue 12 'status: In review,on: develop,bug' | issues > "$FAKE_GH_DIR/dev-issues.json"
  route_json 'api repos/acme/blog/compare/aaa111...m111' '{"status":"ahead"}'
  route_json 'api repos/acme/blog/compare/v1.3.0...m111' '{"status":"ahead","commits":[]}'
  route_json 'api repos/acme/blog/issues/12' "$(open_issue 12 'status: In review,on: develop,bug')"
  route_json 'api -X POST repos/acme/blog/git/tags *' '{"sha":"tagobj1"}'
  route_json 'api -X POST repos/acme/blog/releases *' '{"html_url":"https://github.com/acme/blog/releases/tag/v1.4.0"}'
  route_json 'api -X PUT repos/acme/blog/issues/*/labels *' '[]'
  route_json 'api -X PATCH repos/acme/blog/issues/* *' '{}'
  route_json 'api repos/acme/blog/git/ref/heads/main' '{"object":{"sha":"m111"}}'
  route_json 'api repos/acme/blog/compare/m111...develop' '{"status":"behind"}'
  route_json 'api repos/acme/blog/compare/m111...staging' '{"status":"diverged"}'
  route_first 'api -X POST repos/acme/blog/pulls *' 'bm.json'
  printf '{"number":51,"html_url":"https://github.com/acme/blog/pull/51"}' > "$FAKE_GH_DIR/bm.json"
}

# spec "Release merged" and "After a release in standard".
test_release_finish_publishes_sets_done_and_back_merges() {
  finish_env
  run_scrum release finish
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "POST repos/acme/blog/git/tags|POST repos/acme/blog/git/refs|POST repos/acme/blog/releases|PUT repos/acme/blog/issues/12/labels|PATCH repos/acme/blog/issues/12|POST repos/acme/blog/pulls" "$(write_paths)"
  assert_eq '{"tag":"v1.4.0","message":"Release v1.4.0","object":"m111","type":"commit"}' "$(stdin_of '{"tag":"v1.4.0"')"
  assert_eq '{"ref":"refs/tags/v1.4.0","sha":"tagobj1"}' "$(stdin_of '{"ref":"refs/tags')"
  assert_eq $'## Features\n\n- Task 12 (#12, PR #40)' "$(stdin_of '{"tag_name"' | jq -r .body)"
  assert_eq '["bug","status: Done"]' "$(stdin_of '{"labels"' | jq -c '.labels | sort')"
  assert_eq '{"state":"closed","state_reason":"completed"}' "$(stdin_of '{"state"')"
  assert_eq "Back-merge main into develop main develop" "$(stdin_of '{"title":"Back-merge' | jq -r '"\(.title) \(.head) \(.base)"')"
  assert_contains "$(stdin_of '{"title":"Back-merge' | jq -r .body)" "merge commit"
}

# spec "Workflow runs twice": already published, nothing changes.
test_release_finish_twice_changes_nothing() {
  finish_env
  route_first 'api repos/acme/blog/git/ref/tags/v1.4.0' 'tagref.json'
  printf '{"object":{"type":"tag","sha":"tagobj1"}}' > "$FAKE_GH_DIR/tagref.json"
  route_first 'api --paginate repos/acme/blog/releases*' 'rels.json'
  printf '[{"tag_name":"v1.4.0","draft":false}]' > "$FAKE_GH_DIR/rels.json"
  printf '[]' > "$FAKE_GH_DIR/dev-issues.json"
  # #12 was set Done and closed by the first run.
  route_first 'api repos/acme/blog/issues/12' 'done12.json'
  printf '{"number":12,"state":"closed","state_reason":"completed","labels":[{"name":"status: Done"}]}' > "$FAKE_GH_DIR/done12.json"
  route_first 'api --paginate repos/acme/blog/pulls?state=open&per_page=100&head=acme%3Amain&base=develop' 'bmopen.json'
  printf '[{"number":51,"title":"Back-merge main into develop","html_url":"https://github.com/acme/blog/pull/51","head":{"ref":"main"},"base":{"ref":"develop"}}]' > "$FAKE_GH_DIR/bmopen.json"
  run_scrum release finish
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "v1.4.0 is already published"
  assert_contains "$OUT" "already open: #51"
  assert_eq "" "$(gh_writes)"
}

# spec "Release pull request closed without merging".
test_release_finish_closed_without_merging_does_nothing() {
  finish_env
  jq -c '.pull_request.merged = false' "$T/event.json" > "$T/e2.json"
  export GITHUB_EVENT_PATH="$T/e2.json"
  run_scrum release finish
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "closed without merging"
  assert_eq "" "$(gh_writes)"
}

# A pull request that is neither a release nor a hotfix: nothing.
test_release_finish_ignores_other_pull_requests() {
  finish_env standard feat/12-a
  run_scrum release finish
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "not a release or hotfix pull request"
  assert_eq "" "$(gh_writes)"
}

# The notes markers were removed by hand: the notes are regenerated from the contained tasks.
test_release_finish_regenerates_notes_without_markers() {
  finish_env standard release/v1.4.0 "Edited by hand"
  run_scrum release finish
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(stdin_of '{"tag_name"' | jq -r .body)" "- Task 12 (#12, PR #40)"
  assert_contains "$(stdin_of '{"tag_name"' | jq -r .body)" "## Bug fixes"
}

# spec "Hotfix merged" and back-merge "Environments": main into staging and into develop.
test_release_finish_hotfix_in_environments() {
  finish_env environments hotfix/31-payment-fails $'Fix the payment.\n\nCloses #31\n\n<!-- scrum-release-tag: v1.3.1 -->'
  route_json 'api repos/acme/blog/issues/31' "$(open_issue 31 'status: In review,bug')"
  printf '[]' > "$FAKE_GH_DIR/dev-issues.json"
  run_scrum release finish
  assert_status 0 "$STATUS" "$ERR"
  assert_eq '{"tag":"v1.3.1","message":"Release v1.3.1","object":"m111","type":"commit"}' "$(stdin_of '{"tag":"v1.3.1"')"
  assert_contains "$(stdin_of '{"tag_name"' | jq -r .body)" "Task 31 (#31)"
  assert_contains "$(write_paths)" "PATCH repos/acme/blog/issues/31"
  assert_eq "main staging|main develop" "$(stdin_of '{"title":"Back-merge' | jq -r '"\(.head) \(.base)"' | paste -sd '|' -)"
}

# spec "Already open" (back-merge).
test_release_finish_back_merge_already_open() {
  finish_env
  route_first 'api --paginate repos/acme/blog/pulls?state=open&per_page=100&head=acme%3Amain&base=develop' 'bmopen.json'
  printf '[{"number":51,"title":"Back-merge main into develop","html_url":"https://github.com/acme/blog/pull/51","head":{"ref":"main"},"base":{"ref":"develop"}}]' > "$FAKE_GH_DIR/bmopen.json"
  run_scrum release finish
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$(write_paths)" "POST repos/acme/blog/pulls"
}

test_release_workflow_template() {
  local f="$PLUGIN_DIR/templates/github/workflows/scrum-release.yml" s
  s="$(cat "$f")"
  assert_eq "# Generated by scrum-github." "$(head -1 "$f" | cut -c1-28)"
  assert_contains "$s" "pull_request_target:"
  assert_contains "$s" "types: [closed]"
  assert_contains "$s" "branches: ['{{RELEASE_BRANCH}}']"
  assert_contains "$s" "github.event.pull_request.merged == true"
  assert_contains "$s" "startsWith(github.head_ref, 'release/')"
  assert_contains "$s" "startsWith(github.head_ref, 'hotfix/')"
  assert_contains "$s" "contents: write"
  assert_contains "$s" "pull-requests: write"
  assert_contains "$s" "issues: write"
  assert_contains "$s" "actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0"
  assert_contains "$s" "sparse-checkout: .github"
  assert_contains "$s" ".github/scrum/bin/scrum release finish"
  assert_not_contains "$s" "github.event.pull_request.head" "never the code of the pull request"
}

# Review fix: a release pull request merged with squash contains none of develop's merge commits;
# finish takes the tasks its notes list that still wait on a branch, and warns.
test_release_finish_squashed_release_uses_the_notes() {
  finish_env
  printf '[]' > "$FAKE_GH_DIR/dev-issues.json"
  run_scrum release finish
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$ERR" "squashed"
  assert_contains "$(write_paths)" "PUT repos/acme/blog/issues/12/labels"
}
