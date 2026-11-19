# scrum uninstall (delta repo-bootstrap "Gỡ cài đặt")

installed_repo() { # a repo after scrum init, with a fresh gh log
  setup_fake_gh
  setup_repo
  route 'api --paginate repos/acme/blog/labels*' "labels.json"
  cp "$FIXTURES/labels-github-default.json" "$FAKE_GH_DIR/labels.json"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  : > "$FAKE_GH_LOG"
}

GENERATED=".github/ISSUE_TEMPLATE/task.yml .github/pull_request_template.md .github/workflows/scrum-status-sync.yml .github/workflows/scrum-pr-link-check.yml .github/workflows/scrum-daily-digest.yml"

tree_of() { (cd "$SCRUM_REPO_DIR" && find . -type f | sort | xargs cksum); }

test_uninstall_removes_unedited_files() {
  installed_repo
  run_scrum uninstall --yes
  assert_status 0 "$STATUS" "$ERR"
  local f
  for f in $GENERATED .github/scrum; do
    [ ! -e "$SCRUM_REPO_DIR/$f" ] || _fail "$f not removed"
  done
  [ -f "$SCRUM_REPO_DIR/.github/scrum.yml" ] || _fail "scrum.yml removed"
  assert_contains "$OUT" "keep    .github/scrum.yml"
  assert_contains "$OUT" "git add -A .github"
}

test_uninstall_keeps_edited_file() {
  installed_repo
  printf '\nOur own section\n' >> "$SCRUM_REPO_DIR/.github/pull_request_template.md"
  run_scrum uninstall --yes
  assert_status 0 "$STATUS" "$ERR"
  [ -f "$SCRUM_REPO_DIR/.github/pull_request_template.md" ] || _fail "edited PR template removed"
  assert_contains "$OUT" "keep    .github/pull_request_template.md (changed since scrum init wrote it)"
  [ ! -e "$SCRUM_REPO_DIR/.github/workflows/scrum-status-sync.yml" ] || _fail "unedited workflow kept"
}

test_uninstall_without_yes_changes_nothing() {
  installed_repo
  local before; before="$(tree_of)"
  run_scrum uninstall
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "remove  .github/workflows/scrum-status-sync.yml"
  assert_contains "$OUT" "run again with --yes"
  assert_eq "$before" "$(tree_of)"
}

test_uninstall_dry_run_changes_nothing() {
  installed_repo
  local before; before="$(tree_of)"
  run_scrum uninstall --dry-run --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "remove  .github/scrum/"
  assert_contains "$OUT" "Dry run: nothing changed."
  assert_eq "$before" "$(tree_of)"
}

test_uninstall_never_calls_github() {
  installed_repo
  run_scrum uninstall --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_calls)" "no gh call"
  assert_contains "$OUT" "keep    labels, milestones and issues on GitHub"
}

test_uninstall_removes_board_workflow_after_board_is_off() {
  installed_repo
  printf 'project:\n  enabled: true\n  owner: acme\n  number: 1\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  [ -f "$SCRUM_REPO_DIR/.github/workflows/scrum-project-sync.yml" ] || _fail "board workflow not installed"
  printf 'version: 1\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum uninstall --yes
  [ ! -e "$SCRUM_REPO_DIR/.github/workflows/scrum-project-sync.yml" ] || _fail "board workflow kept"
}

test_uninstall_on_a_repo_without_scrum() {
  setup_fake_gh
  setup_repo
  run_scrum uninstall --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Nothing to remove"
}
