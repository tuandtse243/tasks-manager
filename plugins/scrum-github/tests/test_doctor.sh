# scrum doctor (spec: setup-diagnostics)

# A repo after scrum init and a push: every check passes.
doctor_env() {
  setup_fake_gh
  setup_repo
  git init -q "$SCRUM_REPO_DIR"
  route 'auth status*' "auth.txt"
  route 'api --paginate repos/acme/blog/labels*' "labels.json"
  route 'api repos/acme/blog/contents/.github/workflows' "workflows.json"
  route 'api repos/acme/blog/actions/secrets' "secrets.json"
  cp "$FIXTURES/gh-auth-status.txt" "$FAKE_GH_DIR/auth.txt"
  cp "$FIXTURES/labels-github-default.json" "$FAKE_GH_DIR/labels.json"
  cp "$FIXTURES/remote-workflows.json" "$FAKE_GH_DIR/workflows.json"
  cp "$FIXTURES/actions-secrets.json" "$FAKE_GH_DIR/secrets.json"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  cp "$FIXTURES/labels-after-init.json" "$FAKE_GH_DIR/labels.json"
  : > "$FAKE_GH_LOG"
}

board_on() { # turn the board on and reinstall, with the board workflow pushed
  printf 'project:\n  enabled: true\n  owner: acme\n  number: 1\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  jq '. + [{"name":"scrum-project-sync.yml"}]' "$FIXTURES/remote-workflows.json" > "$FAKE_GH_DIR/workflows.json"
  sed "s/'workflow'/'workflow', 'project'/" "$FIXTURES/gh-auth-status.txt" > "$FAKE_GH_DIR/auth.txt"
  : > "$FAKE_GH_LOG"
}

doctor_json() { run_scrum doctor --json; }
check_of() { printf '%s' "$OUT" | jq -c --arg id "$1" '[.checks[] | select(.id == $id)]'; }
status_of() { printf '%s' "$OUT" | jq -r --arg id "$1" '[.checks[] | select(.id == $id) | .status] | join(",")'; }

test_doctor_all_ok() {
  doctor_env
  run_scrum doctor
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Everything looks fine."
  assert_not_contains "$OUT" "error "
  assert_not_contains "$OUT" "warn "
}

test_doctor_reports_several_errors() {
  setup_fake_gh
  setup_repo
  route 'auth status*' "auth.txt"
  cp "$FIXTURES/gh-auth-status.txt" "$FAKE_GH_DIR/auth.txt"
  PATH="$(path_without_yq)" run_scrum doctor
  assert_status 1 "$STATUS"
  assert_contains "$OUT" "yq is not installed"
  assert_contains "$OUT" "fix: brew install yq"
  assert_contains "$OUT" "no .github/scrum.yml"
  assert_contains "$OUT" "fix: /scrum-github:init"
}

test_doctor_gh_not_logged_in_skips_github_checks() {
  doctor_env
  route_first 'auth status*' '!fail'
  doctor_json
  assert_status 1 "$STATUS"
  assert_eq "error" "$(status_of gh-login)"
  assert_contains "$(check_of gh-login)" "gh auth login"
  assert_eq "skip" "$(status_of labels)"
  assert_eq "skip" "$(status_of workflows)"
  assert_contains "$(check_of labels)" "gh login"
  assert_not_contains "$(gh_calls)" "labels"
}

test_doctor_warnings_only_exit_zero() {
  doctor_env
  sed "s/, 'workflow'//" "$FIXTURES/gh-auth-status.txt" > "$FAKE_GH_DIR/auth.txt"
  doctor_json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "warn" "$(status_of gh-scopes)"
  assert_eq "0" "$(printf '%s' "$OUT" | jq .errors)"
}

test_doctor_writes_nothing() {
  doctor_env
  rm -rf "$SCRUM_REPO_DIR/.github/scrum"
  printf 'digest:\n  cron: "1 2 * * *"\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  local before; before="$(cd "$SCRUM_REPO_DIR" && find . -path ./.git -prune -o -type f -print | sort | xargs cksum)"
  run_scrum doctor
  assert_status 1 "$STATUS"
  assert_eq "" "$(gh_writes)" "no GitHub writes"
  assert_eq "$before" "$(cd "$SCRUM_REPO_DIR" && find . -path ./.git -prune -o -type f -print | sort | xargs cksum)"
}

test_doctor_json_for_missing_yq() {
  doctor_env
  PATH="$(path_without_yq)" run_scrum doctor --json
  assert_status 1 "$STATUS"
  printf '%s' "$OUT" | jq -e . >/dev/null || _fail "not JSON: $OUT"
  assert_eq "error" "$(status_of yq)"
  assert_contains "$(check_of yq)" '"fix":"brew install yq'
  [ "$(printf '%s' "$OUT" | jq .errors)" -gt 0 ] || _fail "errors not counted"
}

test_doctor_python_yq_is_an_error() {
  doctor_env
  mkdir -p "$T/py"
  printf '#!/bin/sh\necho "yq 3.2.1"\n' > "$T/py/yq"; chmod +x "$T/py/yq"
  PATH="$T/py:$PATH" doctor_json
  assert_eq "error" "$(status_of yq)"
  assert_contains "$(check_of yq)" "found: yq 3.2.1"
  assert_contains "$(check_of yq)" "brew install yq"
}

test_doctor_missing_workflow_scope() {
  doctor_env
  sed "s/, 'workflow'//" "$FIXTURES/gh-auth-status.txt" > "$FAKE_GH_DIR/auth.txt"
  doctor_json
  assert_contains "$(check_of gh-scopes)" "gh auth refresh -h github.com -s workflow"
}

test_doctor_board_on_missing_project_scope() {
  doctor_env
  board_on
  cp "$FIXTURES/gh-auth-status.txt" "$FAKE_GH_DIR/auth.txt"
  doctor_json
  assert_eq "warn" "$(status_of gh-scopes)"
  assert_contains "$(check_of gh-scopes)" "-s project"
}

test_doctor_sandbox_login_failure() {
  doctor_env
  route_first 'auth status*' '!fail'
  SANDBOX_RUNTIME=1 doctor_json
  assert_eq "error" "$(status_of gh-login)"
  assert_contains "$(check_of gh-login)" "Claude Code sandbox"
  assert_contains "$(check_of gh-login)" "outside the sandbox"
  assert_not_contains "$(check_of gh-login)" "gh auth login"
}

test_doctor_login_failure_outside_sandbox() {
  doctor_env
  route_first 'auth status*' '!fail'
  doctor_json
  assert_contains "$(check_of gh-login)" "gh auth login"
  assert_not_contains "$(check_of gh-login)" "sandbox"
}

test_doctor_invalid_config() {
  doctor_env
  printf 'points:\n  scale: "abc"\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  doctor_json
  assert_status 1 "$STATUS"
  assert_eq "error" "$(status_of config)"
  assert_contains "$(check_of config)" "points.scale"
}

test_doctor_missing_label() {
  doctor_env
  jq 'map(select(.name != "type: epic"))' "$FIXTURES/labels-after-init.json" > "$FAKE_GH_DIR/labels.json"
  doctor_json
  assert_eq "warn" "$(status_of labels)"
  assert_contains "$(check_of labels)" "missing labels: type: epic"
  assert_contains "$(check_of labels)" "/scrum-github:init"
}

test_doctor_workflow_only_in_working_tree() {
  doctor_env
  printf '[{"name":"scrum-daily-digest.yml"},{"name":"scrum-pr-link-check.yml"}]' > "$FAKE_GH_DIR/workflows.json"
  doctor_json
  assert_eq "error" "$(status_of workflows)"
  assert_contains "$(check_of workflows)" "not on the default branch"
  assert_contains "$(check_of workflows)" ".github/workflows/scrum-status-sync.yml"
  assert_contains "$(check_of workflows)" "git push"
}

test_doctor_runtime_older_than_plugin() {
  doctor_env
  printf '0.0.1\n' > "$SCRUM_REPO_DIR/.github/scrum/VERSION"
  doctor_json
  assert_eq "warn" "$(status_of runtime)"
  assert_contains "$(check_of runtime)" "v0.0.1 is older"
  assert_contains "$(check_of runtime)" "/scrum-github:init"
}

test_doctor_file_stale_after_config_change() {
  doctor_env
  printf 'digest:\n  cron: "30 2 * * 1-5"\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  doctor_json
  assert_eq "warn" "$(status_of files)"
  assert_contains "$(check_of files)" "out of date"
  assert_contains "$(check_of files)" ".github/workflows/scrum-daily-digest.yml"
}

test_doctor_board_secret_missing() {
  doctor_env
  board_on
  printf '{"total_count":0,"secrets":[]}' > "$FAKE_GH_DIR/secrets.json"
  doctor_json
  assert_status 1 "$STATUS"
  assert_eq "error" "$(status_of secret)"
  assert_contains "$(check_of secret)" "/scrum-github:project-setup"
}

test_doctor_board_secrets_not_readable() {
  doctor_env
  board_on
  route_first 'api repos/acme/blog/actions/secrets' '!fail'
  doctor_json
  assert_eq "warn" "$(status_of secret)"
  assert_contains "$(check_of secret)" "admin"
}

test_doctor_board_on_all_ok() {
  doctor_env
  board_on
  doctor_json
  assert_status 0 "$STATUS" "$OUT"
  assert_eq "ok" "$(status_of secret)"
  assert_eq "ok" "$(status_of workflow)"
}

test_doctor_board_off_skips_board() {
  doctor_env
  doctor_json
  assert_eq "skip" "$(status_of board)"
  assert_not_contains "$(gh_calls)" "actions/secrets"
}
