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

# spec ai-run "Mỗi task một worktree local", "Xác nhận trước khi chạy" (design 1, 2, 8).
test_run_skill() {
  local f="$PLUGIN_DIR/skills/run/SKILL.md" s
  [ -f "$f" ] || _fail "no skills/run/SKILL.md"
  assert_eq "name: run" "$(sed -n 2p "$f")"
  s="$(cat "$f")"
  assert_contains "$s" '`scrum run plan'
  assert_contains "$s" "With \`--dry-run\`, stop here"
  assert_contains "$s" 'The agents will run code on this machine'
  assert_contains "$s" "**Wait for the user's answer.**"
  assert_contains "$s" '`subagent_type: "scrum-github:implementer"`'
  assert_contains "$s" '`isolation: "worktree"`'
  assert_contains "$s" 'never more than K agents run'
  assert_contains "$s" '**Check out the integration branch**'
  assert_contains "$s" 'scrum run record N --done --branch'
  assert_contains "$s" '`scrum run merge N`'
  assert_contains "$s" 'Do not start the next wave on a red test.'
  assert_contains "$s" 'scrum run finish --wave W'
  assert_contains "$s" 'scrum run status --json'
  # the confirmation comes before start
  [ "$(grep -n 'Wait for the user' "$f" | head -1 | cut -d: -f1)" -lt "$(grep -n '^Run `scrum run start' "$f" | cut -d: -f1)" ] \
    || _fail "the skill starts the run before the user confirms"
}

test_implementer_agent() {
  local f="$PLUGIN_DIR/agents/implementer.md" s
  [ -f "$f" ] || _fail "no agents/implementer.md"
  assert_eq "name: implementer" "$(sed -n 2p "$f")"
  assert_eq "tools: Read, Write, Edit, Glob, Grep, Bash" "$(grep '^tools:' "$f")"
  s="$(cat "$f")"
  assert_contains "$s" "Never push"
  assert_contains "$s" "Do only this task."
  assert_contains "$s" '"result": "done"'
  assert_contains "$s" '"look_closely"'
  assert_contains "$s" '"manual_test"'
}

# Review fixes: agent text stays off command lines, the confirmed plan is what starts, records one
# at a time, the base commit is checked, the agent's times and dependencies.
test_run_skill_and_agent_safety() {
  local s a
  s="$(cat "$PLUGIN_DIR/skills/run/SKILL.md")"
  a="$(cat "$PLUGIN_DIR/agents/implementer.md")"
  assert_contains "$s" "Never put text written by an agent or taken from an issue on a command line"
  assert_contains "$s" "--expect N,N,..."
  assert_contains "$s" "one at
a time, never several at once"
  assert_contains "$s" "scrum run record N --failed --notes <file>"
  assert_not_contains "$s" '--reason "<reason>"'
  assert_contains "$s" "commit noted in step 1"
  assert_contains "$s" "which other people may have written"
  assert_contains "$s" "hold work
that is not merged anywhere"
  assert_contains "$a" "git merge-base --is-ancestor <base commit> HEAD"
  assert_contains "$a" "worktree not based on the integration branch"
  assert_contains "$a" "install the dependencies there"
  assert_contains "$a" '"started_at"'
  assert_contains "$a" "Never push"
}

# spec release "Preview and confirmation": preview, why this version, edits, then --yes after a yes.
test_release_skill() {
  local f="$PLUGIN_DIR/skills/release/SKILL.md" s
  [ -f "$f" ] || _fail "no skills/release/SKILL.md"
  assert_eq "name: release" "$(sed -n 2p "$f")"
  s="$(cat "$f")"
  assert_contains "$s" '`scrum release [VERSION] [--sprint S]… [--since TAG] [--draft] --json`'
  assert_contains "$s" "why this one"
  assert_contains "$s" "--notes-file FILE"
  assert_contains "$s" "Never put the notes or any text taken from an issue on a command line."
  assert_contains "$s" 'where `<version>` is the `version` of the last preview'
  assert_contains "$s" 'write the `notes` of the last preview, unchanged, to a file'
  assert_contains "$s" "run that same command again, with the
same options"
  assert_contains "$s" "Never pass \`--yes\` without the user's confirmation in this conversation."
  # the confirmation comes before publishing
  [ "$(grep -n "Wait for the user's answer" "$f" | cut -d: -f1)" -lt "$(grep -n '\*\*Publish exactly what was previewed.\*\*' "$f" | cut -d: -f1)" ] \
    || _fail "the skill publishes before the user confirms"
}

# branching-and-release-flow: the new commands are in the help, and unknown subcommands fail.
test_new_branch_commands_are_listed() {
  run_scrum help
  local c
  for c in "protect " "promote " "hotfix NUMBER" "hotfix prepare" "sync " "branches " "cleanup " "release finish"; do
    assert_contains "$OUT" "  $c"
  done
}

test_unknown_subcommands_still_fail() {
  run_scrum task frobnicate
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "unknown task command"
  run_scrum hotfix
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "usage: scrum hotfix NUMBER"
}
