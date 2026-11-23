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
