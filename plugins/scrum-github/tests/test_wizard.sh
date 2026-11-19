# wizards/project-board.sh (spec: project-board-sync, Trình hướng dẫn bật board)

WIZARD="$PLUGIN_DIR/wizards/project-board.sh"
TEMPLATE="$PLUGIN_DIR/vendor/pocock/wizard/template.sh"
TOKEN="ghp_wizardtesttoken123"

library_of() { sed '/^# STAGES/,$d' "$1"; }
stages_of() { sed -n '/^# STAGES/,$p' "$1"; }

test_wizard_library_is_the_vendored_template() {
  [ -n "$(library_of "$TEMPLATE")" ] || _fail "the template has no STAGES marker"
  assert_eq "$(library_of "$TEMPLATE" | cksum)" "$(library_of "$WIZARD" | cksum)" \
    "the part above STAGES differs from vendor/pocock/wizard/template.sh; rebuild the wizard"
}

test_wizard_parses_and_is_executable() {
  bash -n "$WIZARD"
  [ -x "$WIZARD" ] || _fail "the wizard is not executable"
}

test_wizard_stage_count_matches() {
  local total; total="$(stages_of "$WIZARD" | sed -n 's/^TOTAL_STAGES=\([0-9]*\).*/\1/p')"
  assert_eq "$(stages_of "$WIZARD" | grep -c '^stage ')" "$total"
}

test_wizard_keeps_the_token_out_of_files() {
  assert_eq "0" "$(stages_of "$WIZARD" | grep -c 'write_env' || true)" "no value goes to a .env file"
  assert_eq "1" "$(stages_of "$WIZARD" | grep -c '^ *set_secret SCRUM_PROJECT_TOKEN ')"
}

# ---------- running it with typed answers on stdin ----------

have_yq() { command -v yq >/dev/null 2>&1 && yq --version 2>/dev/null | grep -q mikefarah; }

# A stand-in for gh, handed to the wizard as an exported function so PATH stays as it is.
gh() {
  printf '%s\n' "$*" >> "$T/gh.log"
  case "$1 $2" in
    "auth status") return "$FAKE_GH_AUTH" ;;
    "secret set") cat > "$T/gh.stdin" ;;
  esac
  return 0
}

wizard_env() { # wizard_env [auth-status-exit-code]
  mkdir -p "$T/repo/.github"
  export FAKE_GH_AUTH="${1:-0}"
  export -f gh
  : > "$T/gh.log"
  cp "$PLUGIN_DIR/templates/scrum.yml" "$T/repo/.github/scrum.yml"
}

# Answers, in order: start, owner, organization?, project exists, number, workflows off,
# token, after the secret, write the block?, after the block, refresh gh?, last pause.
run_wizard() { # run_wizard WRITE_BLOCK(y|n)
  set +e
  OUT="$(cd "$T/repo" && printf '%s\n' "" "acme" "n" "" "7" "" "$TOKEN" "" "$1" "" "n" "" \
    | "$BASH" "$WIZARD" 2>"$T/stderr")"; STATUS=$?
  ERR="$(cat "$T/stderr")"
  set -e
}

test_wizard_sets_the_secret_and_writes_the_block() {
  have_yq || { echo "skipped: yq v4 not installed" >&2; return 0; }
  wizard_env
  run_wizard y
  assert_status 0 "$STATUS" "$ERR"
  local cfg="$T/repo/.github/scrum.yml"
  assert_eq "true acme 7" "$(yq '[.project.enabled, .project.owner, .project.number] | join(" ")' "$cfg")"
  assert_eq "!!int" "$(yq '.project.number | tag' "$cfg")"
  # Only the project block is added: every line of the template, blank ones and comments
  # included, is still there in the same order.
  assert_eq "" "$(diff "$PLUGIN_DIR/templates/scrum.yml" "$cfg" | grep '^<' || true)" "no line of the config is lost"
  assert_eq "5" "$(diff "$PLUGIN_DIR/templates/scrum.yml" "$cfg" | grep -c '^>')" "a blank line and the four lines of the block are added"
  assert_eq "1" "$(grep -c '^secret set SCRUM_PROJECT_TOKEN$' "$T/gh.log")"
  assert_eq "$TOKEN" "$(cat "$T/gh.stdin")" "the token reaches gh on stdin"
  assert_eq "" "$(grep -rl "$TOKEN" "$T/repo" || true)" "no file in the repository holds the token"
  assert_not_contains "$OUT$ERR" "$TOKEN"
  assert_not_contains "$(cat "$T/gh.log")" "$TOKEN"
  assert_contains "$OUT" "project init --dry-run"
  assert_contains "$OUT" "gh auth refresh -s project"
}

test_wizard_updates_an_existing_project_block() {
  have_yq || { echo "skipped: yq v4 not installed" >&2; return 0; }
  wizard_env
  local cfg="$T/repo/.github/scrum.yml"
  printf '# top\nversion: 1\n\n# board\nproject:\n  enabled: false\n  owner: old   # who\n  number: 2\n\n# end\ncolors: {}\n' > "$cfg"
  run_wizard y
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "true acme 7" "$(yq '[.project.enabled, .project.owner, .project.number] | join(" ")' "$cfg")"
  assert_eq "11" "$(wc -l < "$cfg" | tr -d ' ')" "same number of lines, blank ones kept"
  assert_contains "$(cat "$cfg")" "# who"
  assert_contains "$(cat "$cfg")" "# end"
}

test_wizard_rewrites_a_block_it_cannot_edit_by_line() {
  have_yq || { echo "skipped: yq v4 not installed" >&2; return 0; }
  wizard_env
  local cfg="$T/repo/.github/scrum.yml"
  printf 'version: 1\nproject: {enabled: false, owner: old, number: 2}\n' > "$cfg"
  run_wizard y
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "true acme 7 1" "$(yq '[.project.enabled, .project.owner, .project.number, .version] | join(" ")' "$cfg")"
}

test_wizard_adds_missing_keys_to_a_partial_block() {
  have_yq || { echo "skipped: yq v4 not installed" >&2; return 0; }
  wizard_env
  local cfg="$T/repo/.github/scrum.yml"
  printf 'project:\n  poll_cron: "0 * * * *"\n' > "$cfg"
  run_wizard y
  assert_status 0 "$STATUS" "$ERR"
  assert_eq 'true acme 7 0 * * * *' "$(yq '[.project.enabled, .project.owner, .project.number, .project.poll_cron] | join(" ")' "$cfg")"
}

test_wizard_declined_block_leaves_config_alone() {
  have_yq || { echo "skipped: yq v4 not installed" >&2; return 0; }
  wizard_env
  local before; before="$(cat "$T/repo/.github/scrum.yml")"
  run_wizard n
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "$before" "$(cat "$T/repo/.github/scrum.yml")"
  assert_contains "$OUT" "still to do by hand"
  assert_contains "$OUT" "project block in .github/scrum.yml"
}

test_wizard_gh_not_ready_is_reported_not_fatal() {
  have_yq || { echo "skipped: yq v4 not installed" >&2; return 0; }
  wizard_env 1
  run_wizard y
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "0" "$(grep -c '^secret set' "$T/gh.log" || true)"
  assert_contains "$OUT" "still to do by hand"
  assert_contains "$OUT" "gh secret set SCRUM_PROJECT_TOKEN"
}

test_wizard_needs_a_prepared_repository() {
  mkdir -p "$T/empty"
  set +e
  OUT="$(cd "$T/empty" && "$BASH" "$WIZARD" </dev/null 2>"$T/stderr")"; STATUS=$?
  set -e
  assert_status 1 "$STATUS"
  assert_contains "$(cat "$T/stderr")" ".github/scrum.yml not found"
}
