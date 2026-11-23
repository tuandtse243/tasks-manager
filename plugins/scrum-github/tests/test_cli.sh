# Dispatcher behaviour.

test_help_without_command() {
  run_scrum
  assert_status 0 "$STATUS"
  assert_contains "$OUT" "Usage: scrum <command>"
}

test_unknown_command_fails() {
  run_scrum frobnicate
  assert_status 2 "$STATUS"
  assert_contains "$ERR" 'unknown command "frobnicate"'
}

test_version() {
  run_scrum --version
  assert_eq "$(cat "$PLUGIN_DIR/runtime/VERSION")" "$OUT"
}

# jq 1.8.2 aborts at compile time when an included library includes another (jqlang/jq#3636).
test_jq_libraries_include_nothing() {
  local lib name
  for name in $(sed -n 's/^include "\([^"]*\)";.*/\1/p' "$PLUGIN_DIR"/runtime/lib/jq/*.jq | sort -u); do
    lib="$PLUGIN_DIR/runtime/lib/jq/$name.jq"
    [ -f "$lib" ] || _fail "included library $name.jq does not exist"
    ! grep -qE '^(include|import) ' "$lib" || _fail "$name.jq includes another library"
  done
}

# The plugin's bin/ is on the PATH in Claude Code; bin/scrum forwards to runtime/bin/scrum.
test_bin_scrum_forwards_to_the_runtime() {
  [ -x "$PLUGIN_DIR/bin/scrum" ] || _fail "bin/scrum is not executable"
  assert_eq "$(cat "$PLUGIN_DIR/runtime/VERSION")" "$("$PLUGIN_DIR/bin/scrum" --version)"
}

test_bin_scrum_works_through_a_symlink() {
  mkdir -p "$T/a/b"
  ln -s "$PLUGIN_DIR/bin/scrum" "$T/a/scrum"
  ln -s ../scrum "$T/a/b/scrum"
  assert_eq "$(cat "$PLUGIN_DIR/runtime/VERSION")" "$("$T/a/scrum" --version)"
  assert_eq "$(cat "$PLUGIN_DIR/runtime/VERSION")" "$("$T/a/b/scrum" --version)"
}

# Skills define `scrum` as the full plugin path from the first call (a bare `scrum` is not on the
# PATH after a local-scope install or right after installing), and never name runtime/bin/scrum.
test_skills_call_scrum_by_full_path() {
  local f def='means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum"'
  for f in "$PLUGIN_DIR"/skills/*/SKILL.md; do
    if grep -q '`scrum ' "$f"; then
      grep -qF "$def" "$f" || _fail "$f runs scrum without defining the full path"
    fi
    ! grep -q 'runtime/bin/scrum' "$f" || _fail "$f names runtime/bin/scrum"
  done
}

test_skills_point_to_doctor_not_the_old_sandbox_line() {
  local f
  for f in "$PLUGIN_DIR"/skills/*/SKILL.md; do
    ! grep -q 'cannot read its keychain token inside the Claude Code sandbox' "$f" \
      || _fail "$f still has the old sandbox line"
  done
}

# The transition skill scrum-init was removed in 0.6.0, as announced in 0.5.0.
test_the_old_init_name_is_gone() {
  local hits
  hits="$(grep -rl 'scrum-init' "$PLUGIN_DIR/skills" "$PLUGIN_DIR/agents" "$PLUGIN_DIR/reference" "$PLUGIN_DIR/runtime" || true)"
  assert_eq "" "$hits"
}

# spec my-work "Skill việc của tôi": runs scrum mine, offers task-start and waits for the user.
test_my_tasks_skill() {
  local f="$PLUGIN_DIR/skills/my-tasks/SKILL.md"
  [ -f "$f" ] || _fail "no skills/my-tasks/SKILL.md"
  assert_eq "name: my-tasks" "$(sed -n 2p "$f")"
  assert_contains "$(cat "$f")" '`scrum mine`'
  assert_contains "$(cat "$f")" '/scrum-github:task-start N'
  assert_contains "$(cat "$f")" 'Run it only after the user agrees'
}
