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
  assert_contains "$ERR" "/scrum-github:scrum-init"
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
  mkdir -p "$T/bin" "$T/sys"
  ln -s "$(command -v jq)" "$T/bin/jq"
  ln -s "$(command -v git)" "$T/bin/git"
  # The system directories without yq: some runners install it in /usr/bin.
  local d f
  for d in /usr/bin /bin; do
    for f in "$d"/*; do
      [ "${f##*/}" = yq ] || [ -e "$T/sys/${f##*/}" ] || ln -s "$f" "$T/sys/${f##*/}"
    done
  done
  set +e
  ERR="$(PATH="$T/bin:$T/sys" "$BASH" "$SCRUM" sprint new 2>&1 >/dev/null)"; STATUS=$?
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
  assert_json_eq '{"dir":"docs/plans","context_file":"docs/project-context.md","hours_per_point":null,"context_stale_commits":50}' \
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
