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
