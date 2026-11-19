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
