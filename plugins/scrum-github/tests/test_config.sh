# spec: scrum-config

test_partial_file_merges_defaults() {
  setup_fake_gh
  setup_repo 'points:
  scale: [1, 2, 3, 5, 8]'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '[1,2,3,5,8]' "$(printf '%s' "$OUT" | jq -c .points.scale)"
  assert_eq "points: " "$(printf '%s' "$OUT" | jq -r .points.label_prefix)" "other points keys keep defaults"
  assert_eq "Sprint {n}" "$(printf '%s' "$OUT" | jq -r .sprint.name_pattern)"
  assert_eq "5" "$(printf '%s' "$OUT" | jq -r .sprint.length_days)"
  assert_eq "In progress" "$(printf '%s' "$OUT" | jq -r .statuses.in_progress)"
}

test_empty_file_uses_all_defaults() {
  setup_fake_gh
  setup_repo ''
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq "$(cat "$PLUGIN_DIR/runtime/share/defaults.json")" "$OUT"
}

test_missing_config_points_to_init() {
  setup_fake_gh
  setup_repo
  run_scrum sprint new
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "/scrum-github:init"
  assert_eq "" "$(gh_writes)" "no GitHub writes"
}

test_negative_point_rejected() {
  setup_fake_gh
  setup_repo 'points:
  scale: [0, -1, 3]'
  run_scrum sprint new
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "points.scale"
  assert_contains "$ERR" "-1"
  assert_eq "" "$(gh_writes)" "no GitHub writes"
}

test_validation_messages() {
  local cfg errs
  cfg="$(jq '.points.scale = [1,1,2.5] | .sprint.length_days = 0 | .statuses.done = "" | .statuses.in_progress = "new"' "$PLUGIN_DIR/runtime/share/defaults.json")"
  errs="$(printf '%s' "$cfg" | jqt validate-config | jq -r '.[]')"
  assert_contains "$errs" "points.scale: values must be non-negative whole numbers (got 2.5)"
  assert_contains "$errs" "points.scale: values must not repeat"
  assert_contains "$errs" "sprint.length_days"
  assert_contains "$errs" "statuses.done"
  assert_contains "$errs" "statuses: new, in_progress and done must be different"
}

test_valid_defaults_have_no_errors() {
  assert_eq "[]" "$(jqt validate-config < "$PLUGIN_DIR/runtime/share/defaults.json" | jq -c .)"
}

test_broken_yaml_reports_position() {
  setup_fake_gh
  setup_repo 'points:
  scale: [0, 1
sprint: ]'
  run_scrum config
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "cannot read"
  assert_contains "$ERR" "L2.C"
}

test_missing_yq_is_reported_before_github() {
  setup_fake_gh
  setup_repo 'version: 1'
  set +e
  ERR="$(PATH="$(path_without_yq)" "$BASH" "$SCRUM" sprint new 2>&1 >/dev/null)"; STATUS=$?
  set -e
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "yq is required (mikefarah v4)"
  assert_eq "" "$(gh_calls)" "gh never called"
}

test_python_yq_is_rejected() {
  setup_fake_gh
  setup_repo 'version: 1'
  mkdir -p "$T/bin"
  printf '#!/bin/sh\necho "yq 3.4.3"\n' > "$T/bin/yq"; chmod +x "$T/bin/yq"
  set +e
  ERR="$(PATH="$T/bin:$PATH" "$BASH" "$SCRUM" sprint new 2>&1 >/dev/null)"; STATUS=$?
  set -e
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "not mikefarah/yq v4"
}

test_gh_not_logged_in() {
  setup_fake_gh
  setup_repo 'version: 1'
  route 'auth status*' '!fail'
  run_scrum sprint new
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "gh auth login"
  assert_not_contains "$ERR" "sandbox"
  assert_eq "" "$(gh_writes)"
}

# delta scrum-config "gh báo lỗi trong sandbox"
test_gh_not_logged_in_inside_the_sandbox() {
  setup_fake_gh
  setup_repo 'version: 1'
  route 'auth status*' '!fail'
  SANDBOX_RUNTIME=1 run_scrum sprint new
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "Claude Code sandbox"
  assert_contains "$ERR" "outside the sandbox"
  assert_contains "$ERR" "/scrum-github:doctor"
  assert_eq "" "$(gh_writes)"
}

# ---------- project (board sync) ----------
# spec: project-board-sync (Cấu hình Project)

project_errors() { # project_errors PROJECT_JSON -> error lines
  jq --argjson p "$1" '.project = (.project * $p)' "$PLUGIN_DIR/runtime/share/defaults.json" \
    | jqt validate-config | jq -r '.[]'
}

test_project_off_by_default() {
  setup_fake_gh
  setup_repo 'version: 1'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "false" "$(printf '%s' "$OUT" | jq -r .project.enabled)"
  assert_eq "Todo" "$(printf '%s' "$OUT" | jq -r .project.status_options.new)"
}

test_project_off_ignores_missing_owner() {
  assert_eq "" "$(project_errors '{"enabled": false, "owner": null, "number": null}')"
}

test_project_on_needs_owner_and_number() {
  local e
  e="$(project_errors '{"enabled": true, "owner": "acme"}')"
  assert_contains "$e" "project.number"
  assert_not_contains "$e" "project.owner"
  e="$(project_errors '{"enabled": true, "number": 2}')"
  assert_contains "$e" "project.owner"
}

test_project_on_valid() {
  assert_eq "" "$(project_errors '{"enabled": true, "owner": "acme", "number": 2}')"
  assert_eq "" "$(project_errors '{"enabled": true, "owner": "acme", "number": 2, "points_field": null}')"
}

test_project_duplicate_options() {
  assert_contains "$(project_errors '{"enabled": true, "owner": "acme", "number": 2, "status_options": {"in_progress": "Todo"}}')" \
    "project.status_options"
}

test_project_bad_cron_and_number() {
  local e
  e="$(project_errors '{"enabled": true, "owner": "acme", "number": 0, "poll_cron": "*/15 * *"}')"
  assert_contains "$e" "project.poll_cron"
  assert_contains "$e" "project.number"
}

test_project_on_missing_number_stops_commands() {
  setup_fake_gh
  setup_repo 'project:
  enabled: true
  owner: acme'
  run_scrum sprint new
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "project.number"
  assert_eq "" "$(gh_writes)" "no GitHub writes"
}

# ---------- planning and labels.epic (delta scrum-config) ----------

test_planning_defaults_when_not_declared() {
  setup_fake_gh
  setup_repo 'version: 1'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '{"dir":"docs/plans","context_file":"docs/project-context.md","hours_per_point":null,"context_stale_commits":50,"merge_minutes":5}' \
    "$(printf '%s' "$OUT" | jq -c .planning)"
  assert_eq "type: epic" "$(printf '%s' "$OUT" | jq -r .labels.epic)"
}

config_error() { # config_error YAML -> stderr of scrum config, asserting a failure
  setup_fake_gh
  setup_repo "$1"
  run_scrum config
  assert_status 1 "$STATUS"
  printf '%s' "$ERR"
}

test_planning_hours_per_point_zero_rejected() {
  assert_contains "$(config_error 'planning:
  hours_per_point: 0')" "planning.hours_per_point"
}

test_planning_hours_per_point_fraction_allowed() {
  setup_fake_gh
  setup_repo 'planning:
  hours_per_point: 2.5'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
}

test_planning_stale_commits_negative_rejected() {
  assert_contains "$(config_error 'planning:
  context_stale_commits: -1')" "planning.context_stale_commits"
}

test_planning_dir_outside_repo_rejected() {
  assert_contains "$(config_error 'planning:
  dir: ../plans')" "planning.dir"
}

test_planning_paths_absolute_or_empty_rejected() {
  local errs
  errs="$(jq '.planning.dir = "/abs" | .planning.context_file = ""' "$PLUGIN_DIR/runtime/share/defaults.json" | jqt validate-config | jq -r '.[]')"
  assert_contains "$errs" "planning.dir: must be relative"
  assert_contains "$errs" "planning.context_file: must be a non-empty path"
}

test_planning_custom_dir_accepted() {
  setup_fake_gh
  setup_repo 'planning:
  dir: planning'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "planning" "$(printf '%s' "$OUT" | jq -r .planning.dir)"
}

test_epic_label_same_as_feature_rejected() {
  assert_contains "$(config_error 'labels:
  epic: "type: feature"')" "labels.epic"
}

test_epic_label_same_as_meta_or_no_task_rejected() {
  local errs
  errs="$(jq '.labels.epic = "no-task"' "$PLUGIN_DIR/runtime/share/defaults.json" | jqt validate-config | jq -r '.[]')"
  assert_contains "$errs" "labels.epic"
  errs="$(jq '.labels.epic = "Scrum: Meta"' "$PLUGIN_DIR/runtime/share/defaults.json" | jqt validate-config | jq -r '.[]')"
  assert_contains "$errs" "labels.epic"
}

# ---------- working days, attention, language, webhook format (delta scrum-config) ----------

errors_with() { jq "$1" "$PLUGIN_DIR/runtime/share/defaults.json" | jqt validate-config | jq -r '.[]'; }

test_new_keys_have_defaults() {
  assert_eq '[1,2,3,4,5] 2 15 en slack' "$(jq -r '"\(.sprint.working_days | tojson) \(.attention.stale_days) \(.attention.behind_percent) \(.language) \(.digest.webhook_format)"' "$PLUGIN_DIR/runtime/share/defaults.json")"
}

test_working_days_rejected() {
  assert_contains "$(errors_with '.sprint.working_days = [0, 1]')" "sprint.working_days: values must be 1 (Monday) to 7 (Sunday)"
  assert_contains "$(errors_with '.sprint.working_days = []')" "sprint.working_days: must be a non-empty list"
  assert_contains "$(errors_with '.sprint.working_days = [1, 1]')" "sprint.working_days: values must not repeat"
}

test_attention_thresholds_rejected() {
  assert_contains "$(errors_with '.attention.stale_days = -1')" "attention.stale_days: must be a whole number"
  assert_contains "$(errors_with '.attention.behind_percent = "x"')" "attention.behind_percent: must be a whole number"
}

test_language_rejected() {
  assert_contains "$(errors_with '.language = "fr"')" "language: must be en or vi"
}

test_webhook_format_rejected() {
  assert_contains "$(errors_with '.digest.webhook_format = "teams"')" "digest.webhook_format: must be slack or telegram"
}

test_template_matches_defaults_for_new_keys() {
  assert_eq "$(jq -c '{language, w: .sprint.working_days, attention, f: .digest.webhook_format}' "$PLUGIN_DIR/runtime/share/defaults.json")" \
    "$(yq -o=json '.' "$PLUGIN_DIR/templates/scrum.yml" | jq -c '{language, w: .sprint.working_days, attention, f: .digest.webhook_format}')"
}

# ---------- optional In review status (delta scrum-config) ----------

jqs_cfg() { jq -n -L "$PLUGIN_DIR/runtime/lib/jq" --argjson cfg "$1" "include \"scrum\"; $2"; }
review_cfg() { defaults_json | jq '.statuses.in_review = "In review"'; }
defaults_json() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }

test_in_review_off_by_default() {
  assert_eq "null" "$(jq -r .statuses.in_review "$PLUGIN_DIR/runtime/share/defaults.json")"
  assert_eq '["new","in_progress","done"]' "$(jqs_cfg "$(defaults_json)" 'roles($cfg)' | jq -c .)"
  assert_eq '["status: New","status: In progress","status: Done"]' "$(jqs_cfg "$(defaults_json)" 'status_labels($cfg)' | jq -c .)"
}

test_in_review_on_adds_a_fourth_role() {
  assert_eq '["new","in_progress","in_review","done"]' "$(jqs_cfg "$(review_cfg)" 'roles($cfg)' | jq -c .)"
  assert_eq '"in_review"' "$(jqs_cfg "$(review_cfg)" '{labels: [{name: "status: In review"}], state: "open"} | task_role($cfg)')"
  assert_eq '"new"' "$(jqs_cfg "$(defaults_json)" '{labels: [{name: "status: In review"}], state: "open"} | task_role($cfg)')" "off: an In review label means nothing"
}

test_in_review_validation() {
  assert_contains "$(errors_with '.statuses.in_review = "Done"')" "statuses: new, in_progress, in_review and done must be different"
  assert_contains "$(errors_with '.statuses.in_review = ""')" "statuses.in_review: must be a non-empty text"
  assert_contains "$(errors_with '.attention.review_days = "x"')" "attention.review_days: must be a whole number"
  assert_eq "" "$(errors_with '.statuses.in_review = "In review"')"
}

test_in_review_board_option_validation() {
  local base='.project.enabled = true | .project.owner = "acme" | .project.number = 1'
  assert_contains "$(errors_with "$base | .statuses.in_review = \"In review\" | .project.status_options.in_review = \"Done\"")" \
    "project.status_options: the options of the statuses in use must be different"
  assert_eq "" "$(errors_with "$base | .project.status_options.in_review = \"Done\"")" "off: the in_review option is not used"
}

# ---------- team (delta scrum-config "Khối team") ----------

test_team_empty_by_default() {
  setup_fake_gh
  setup_repo 'version: 1'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "[]" "$(printf '%s' "$OUT" | jq -c .team)"
}

test_team_full_member_accepted() {
  setup_fake_gh
  setup_repo 'team:
  - login: tuandt
    areas: [backend]
    capacity: 10
  - login: an-nguyen'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '[{"login":"tuandt","areas":["backend"],"capacity":10},{"login":"an-nguyen"}]' "$(printf '%s' "$OUT" | jq -c .team)"
}

test_team_duplicate_login_rejected() {
  local e
  e="$(config_error 'team:
  - login: TuanDT
  - login: tuandt')"
  assert_contains "$e" "team"
  assert_contains "$e" '"tuandt" is listed more than once'
}

test_team_capacity_zero_rejected() {
  local e
  e="$(config_error 'team:
  - login: tuandt
    capacity: 0')"
  assert_contains "$e" "team[0].capacity"
}

test_team_login_with_at_is_read_without_it() {
  setup_fake_gh
  setup_repo 'team:
  - login: "@tuandt"'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "tuandt" "$(printf '%s' "$OUT" | jq -r '.team[0].login')"
}

test_team_validation_messages() {
  assert_contains "$(errors_with '.team = [{"login": ""}]')" "team[0].login: is required"
  assert_contains "$(errors_with '.team = [{"login": "a b"}]')" "is not a GitHub login"
  assert_contains "$(errors_with '.team = [{"login": "a", "areas": "backend"}]')" "team[0].areas"
  assert_contains "$(errors_with '.team = [{"login": "a", "areas": [""]}]')" "team[0].areas"
  assert_contains "$(errors_with '.team = [{"login": "a", "capacity": "ten"}]')" "team[0].capacity"
  assert_contains "$(errors_with '.team = "tuandt"')" "team: must be a list"
  assert_contains "$(errors_with '.team = ["tuandt"]')" "team[0]: must be a mapping"
  assert_eq "" "$(errors_with '.team = [{"login": "a-1", "areas": ["web"], "capacity": 2.5}]')"
}

# The commented team example in the template is a valid configuration once uncommented.
test_template_team_example_is_valid() {
  setup_fake_gh
  setup_repo
  { cat "$PLUGIN_DIR/templates/scrum.yml"
    sed -n '/^# team:/,/^$/p' "$PLUGIN_DIR/templates/scrum.yml" | sed -e 's/^# //'
  } > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "tuandt,an-nguyen" "$(printf '%s' "$OUT" | jq -r '[.team[].login] | join(",")')"
  assert_eq "10" "$(printf '%s' "$OUT" | jq -r '.team[0].capacity')"
}

# ---------- time estimates (delta scrum-config) ----------

test_merge_minutes_defaults_to_5() {
  setup_fake_gh
  setup_repo 'version: 1'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "5" "$(printf '%s' "$OUT" | jq -r .planning.merge_minutes)"
}

test_merge_minutes_text_rejected() {
  assert_contains "$(config_error 'planning:
  merge_minutes: "x"')" "planning.merge_minutes"
}

test_merge_minutes_values() {
  assert_eq "" "$(errors_with '.planning.merge_minutes = 0')"
  assert_contains "$(errors_with '.planning.merge_minutes = -1')" "planning.merge_minutes"
  assert_contains "$(errors_with '.planning.merge_minutes = 2.5')" "planning.merge_minutes"
  assert_contains "$(errors_with '.planning.merge_minutes = null')" "planning.merge_minutes"
}

test_team_review_hours_negative_rejected() {
  local e
  e="$(config_error 'team:
  - login: an-nguyen
    review_hours: -1')"
  assert_contains "$e" "team[0].review_hours"
}

test_team_review_hours_values() {
  assert_eq "" "$(errors_with '.team = [{"login": "a", "review_hours": 1.5}]')"
  assert_contains "$(errors_with '.team = [{"login": "a", "review_hours": 0}]')" "team[0].review_hours"
  assert_contains "$(errors_with '.team = [{"login": "a", "review_hours": "2"}]')" "team[0].review_hours"
}

# ---------- run and labels.ai_ready (delta scrum-config, change ai-run) ----------

test_run_defaults_when_not_declared() {
  setup_fake_gh
  setup_repo 'version: 1'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '{"test_command":"","max_parallel":3,"branch_pattern":"run/{sprint}-{login}"}' "$(printf '%s' "$OUT" | jq -c .run)"
  assert_eq "ai-ready" "$(printf '%s' "$OUT" | jq -r .labels.ai_ready)"
}

test_run_max_parallel_zero_rejected() {
  assert_contains "$(config_error 'run:
  max_parallel: 0')" "run.max_parallel"
}

test_run_validation_messages() {
  assert_contains "$(errors_with '.run.max_parallel = 1.5')" "run.max_parallel"
  assert_contains "$(errors_with '.run.max_parallel = "3"')" "run.max_parallel"
  assert_contains "$(errors_with '.run.branch_pattern = ""')" "run.branch_pattern"
  assert_contains "$(errors_with '.run.test_command = 5')" "run.test_command"
  assert_contains "$(errors_with '.run = "x"')" "run: must be a mapping"
  assert_eq "" "$(errors_with '.run.test_command = "npm test" | .run.max_parallel = 1 | .run.branch_pattern = "ai/{date}-{login}"')"
}

test_ai_ready_label_must_differ() {
  assert_contains "$(errors_with '.labels.ai_ready = "Type: Feature"')" "labels.ai_ready"
  assert_contains "$(errors_with '.labels.ai_ready = "no-task"')" "labels.ai_ready"
  assert_contains "$(errors_with '.labels.ai_ready = ""')" "labels.ai_ready: must be a non-empty text"
}

test_template_matches_defaults_for_run() {
  assert_eq "$(jq -c '{run, a: .labels.ai_ready}' "$PLUGIN_DIR/runtime/share/defaults.json")" \
    "$(yq -o=json '.' "$PLUGIN_DIR/templates/scrum.yml" | jq -c '{run, a: .labels.ai_ready}')"
}

# ---------- release (delta scrum-config, change release) ----------

test_release_defaults_when_not_declared() {
  setup_fake_gh
  setup_repo 'version: 1'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "v breaking 0.1.0" "$(printf '%s' "$OUT" | jq -r '.release | "\(.tag_prefix) \(.breaking_label) \(.first_version)"')"
}

test_release_first_version_not_semver_rejected() {
  assert_contains "$(config_error 'release:
  first_version: "1.0"')" "release.first_version"
}

test_release_validation_messages() {
  assert_contains "$(errors_with '.release.breaking_label = ""')" "release.breaking_label"
  assert_contains "$(errors_with '.release.first_version = 1')" "release.first_version"
  assert_contains "$(errors_with '.release.first_version = "01.2.3"')" "release.first_version"
  assert_contains "$(errors_with '.release.tag_prefix = "v 1"')" "release.tag_prefix"
  assert_contains "$(errors_with '.release.tag_prefix = null')" "release.tag_prefix"
  assert_contains "$(errors_with '.release = "x"')" "release: must be a mapping"
  assert_eq "" "$(errors_with '.release.tag_prefix = "" | .release.first_version = "1.0.0" | .release.breaking_label = "major"')"
}

# The keys the template sets (version_files and changelog are commented out there).
test_template_matches_defaults_for_release() {
  local tpl
  tpl="$(yq -o=json '.' "$PLUGIN_DIR/templates/scrum.yml" | jq -c .release)"
  assert_eq "$(jq -c --argjson t "$tpl" '.release | with_entries(select(.key as $k | $t | has($k)))' "$PLUGIN_DIR/runtime/share/defaults.json")" "$tpl"
}

# ---------- spec scrum-config (branching-and-release-flow) ----------
# validate CONFIG_JQ_FILTER  The errors of the defaults changed by the filter, one per line.
validate_with() { jq "$1" "$PLUGIN_DIR/runtime/share/defaults.json" | jqt validate-config | jq -r '.[]'; }

test_branching_defaults() {
  setup_fake_gh
  setup_repo 'branching: {preset: standard}
statuses: {in_review: In review}'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '{"preset":"standard","main":"main","develop":"develop","staging":"staging","location_prefix":"on: ","stale_days":5}' \
    "$(printf '%s' "$OUT" | jq -c .branching)"
  assert_json_eq '{"preset":"standard","main":"main","develop":"develop","staging":null,"working":"develop","release":"main","lower":["develop"],"chain":["develop","main"]}' \
    "$(printf '%s' "$OUT" | jq -c -L "$PLUGIN_DIR/runtime/lib/jq" 'include "scrum"; branching(.)')"
}

test_branching_duplicate_names() {
  local errs
  errs="$(validate_with '.branching += {preset: "standard", develop: "main"} | .statuses.in_review = "In review"')"
  assert_contains "$errs" "branching.main and branching.develop: must be different branches"
}

test_branching_unknown_preset() {
  local errs
  errs="$(validate_with '.branching.preset = "gitflow"')"
  assert_contains "$errs" 'branching.preset: must be trunk, standard or environments (got "gitflow")'
}

test_branching_missing_review_status() {
  local errs
  errs="$(validate_with '.branching.preset = "standard"')"
  assert_contains "$errs" "statuses.in_review: must be set with branching.preset standard"
  errs="$(validate_with '.branching.preset = "trunk"')"
  assert_eq "" "$errs" "trunk needs no review status"
}

test_branching_stale_days_positive() {
  assert_contains "$(validate_with '.branching.stale_days = 0')" "branching.stale_days"
}

test_governance_solo_project() {
  assert_eq "" "$(validate_with '.governance.approvals = 0')"
}

test_governance_invalid_approvals() {
  assert_contains "$(validate_with '.governance.approvals = -1')" "governance.approvals: must be a whole number from 0 to 6"
  assert_contains "$(validate_with '.governance.approvals = 7')" "governance.approvals"
  assert_contains "$(validate_with '.governance.required_checks = "test"')" "governance.required_checks"
}

test_release_version_files_json_manifest() {
  assert_eq "" "$(validate_with '.release.version_files = [{path: "package.json"}]')"
}

test_release_version_files_pattern_without_placeholder() {
  local errs
  errs="$(validate_with '.release.version_files = [{path: "VERSION.txt", pattern: "version 1.0"}]')"
  assert_contains "$errs" "release.version_files[0].pattern: needs {version}"
  assert_contains "$(validate_with '.release.version_files = [{pattern: "v{version}"}]')" "release.version_files[0].path: is required"
  assert_contains "$(validate_with '.release.version_files = [{path: "pyproject.toml"}]')" "release.version_files[0].pattern: is required"
  assert_eq "" "$(validate_with '.release.version_files = [{path: "pyproject.toml", pattern: "version = \"{version}\""}] | .release.changelog = "CHANGELOG.md"')"
  assert_contains "$(validate_with '.release.changelog = "/etc/x"')" "release.changelog"
}

test_deploy_unknown_platform() {
  assert_contains "$(validate_with '.deploy.platform = "heroku"')" 'deploy.platform: must be none, vercel, cloudflare or docker (got "heroku")'
  assert_eq "" "$(validate_with '.deploy.platform = "docker"')"
}

test_attention_promote_days_default() {
  assert_eq "5" "$(jq -r .attention.promote_days "$PLUGIN_DIR/runtime/share/defaults.json")"
  assert_contains "$(validate_with '.attention.promote_days = 0')" "attention.promote_days"
}

test_shipped_template_validates_as_standard() {
  setup_fake_gh
  setup_repo "$(cat "$PLUGIN_DIR/templates/scrum.yml")"
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "standard" "$(printf '%s' "$OUT" | jq -r .branching.preset)"
  assert_eq "In review" "$(printf '%s' "$OUT" | jq -r .statuses.in_review)"
}

test_config_without_branching_is_trunk() {
  setup_fake_gh
  setup_repo 'version: 1'
  run_scrum config
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "null" "$(printf '%s' "$OUT" | jq -c .branching.preset)"
  assert_eq "trunk main main" "$(printf '%s' "$OUT" | jq -r -L "$PLUGIN_DIR/runtime/lib/jq" 'include "scrum"; branching(.) | "\(.preset) \(.working) \(.release)"')"
}
