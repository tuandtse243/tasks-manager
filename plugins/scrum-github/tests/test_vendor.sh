# scripts/vendor-sync.sh (spec: vendored-skills)

VSYNC="$PLUGIN_DIR/scripts/vendor-sync.sh"
VENDOR_ITEMS="grilling to-questionnaire to-spec to-tickets domain-modeling pr wizard"

fgit() { # fgit DIR args...  git with a fixed identity, no user or system config
  local d="$1"; shift
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$d" \
    -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"
}

upstream_path() { # upstream_path NAME -> the path of a vendored skill in the upstream repo
  case "$1" in
    grilling|to-questionnaire|grill-me) printf 'skills/productivity/%s' "$1" ;;
    *) printf 'skills/engineering/%s' "$1" ;;
  esac
}

fake_upstream() { # fake_upstream DIR  A git repository laid out like mattpocock/skills
  local d="$1" s p
  mkdir -p "$d"
  for s in $VENDOR_ITEMS grill-me triage; do
    p="$d/$(upstream_path "$s")"
    mkdir -p "$p/agents"
    printf -- '---\nname: %s\n---\nBody of %s\n' "$s" "$s" > "$p/SKILL.md"
    printf 'interface: {}\n' > "$p/agents/openai.yaml"
  done
  printf 'extra\n' > "$d/skills/engineering/to-tickets/NOTES.md"
  printf '#!/usr/bin/env bash\necho template\n' > "$d/skills/engineering/wizard/template.sh"
  printf '# Writing Agent Briefs\n' > "$d/skills/engineering/triage/AGENT-BRIEF.md"
  printf '# Out of scope\n' > "$d/skills/engineering/triage/OUT-OF-SCOPE.md"
  printf 'MIT License\n' > "$d/LICENSE"
  git init -q "$d"
  fgit "$d" add -A
  fgit "$d" commit -q -m "upstream"
}

head_of() { git -C "$1" rev-parse HEAD; }
tree_sum() { (cd "$1" && find . -type f | sort | xargs cat | cksum); }

vsync() { # vsync [args...]  -> sets OUT, ERR, STATUS; destination is $T/dest
  set +e
  OUT="$(VENDOR_DEST="$T/dest" bash "$VSYNC" "$@" 2>"$T/stderr")"; STATUS=$?
  ERR="$(cat "$T/stderr")"
  set -e
}

test_vendor_sync_copies_the_list_verbatim() {
  fake_upstream "$T/src"
  VENDOR_SYNC_DATE=2026-11-19 vsync "$T/src"
  assert_status 0 "$STATUS" "$ERR"
  local s
  for s in $VENDOR_ITEMS; do
    assert_eq "" "$(diff -r "$T/src/$(upstream_path "$s")" "$T/dest/$s")" "$s copied verbatim"
  done
  assert_eq "" "$(diff "$T/src/LICENSE" "$T/dest/LICENSE")"
}

test_vendor_sync_skips_skills_outside_the_list() {
  fake_upstream "$T/src"
  vsync "$T/src"
  [ ! -e "$T/dest/grill-me" ] || _fail "grill-me is not in the list"
}

test_vendor_sync_takes_one_file_of_triage() {
  fake_upstream "$T/src"
  vsync "$T/src"
  assert_eq "" "$(diff "$T/src/skills/engineering/triage/AGENT-BRIEF.md" "$T/dest/triage/AGENT-BRIEF.md")"
  assert_eq "AGENT-BRIEF.md" "$(ls "$T/dest/triage")" "only AGENT-BRIEF.md of triage"
}

test_vendor_sync_records_origin() {
  fake_upstream "$T/src"
  VENDOR_SYNC_DATE=2026-11-19 vsync "$T/src"
  local up; up="$(cat "$T/dest/UPSTREAM.md")"
  assert_contains "$up" 'https://github.com/mattpocock/skills'
  assert_contains "$up" "- Commit: \`$(head_of "$T/src")\`"
  assert_contains "$up" '- Synced: 2026-11-19'
  assert_contains "$up" 'MIT'
  assert_contains "$up" '- `grilling` <- `skills/productivity/grilling`'
  assert_contains "$up" '- `pr` <- `skills/engineering/pr`'
  assert_contains "$up" '- `triage/AGENT-BRIEF.md` <- `skills/engineering/triage/AGENT-BRIEF.md`'
  assert_not_contains "$up" 'aidw'
}

test_vendor_sync_second_run_changes_nothing() {
  fake_upstream "$T/src"
  VENDOR_SYNC_DATE=2026-11-19 vsync "$T/src"
  local before; before="$(tree_sum "$T/dest")"
  VENDOR_SYNC_DATE=2026-12-01 vsync "$T/src"
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "$before" "$(tree_sum "$T/dest")"
}

test_vendor_sync_new_commit_updates_origin() {
  fake_upstream "$T/src"
  VENDOR_SYNC_DATE=2026-11-19 vsync "$T/src"
  printf 'more\n' >> "$T/src/skills/engineering/pr/SKILL.md"
  fgit "$T/src" commit -q -am "change"
  VENDOR_SYNC_DATE=2026-12-01 vsync "$T/src"
  local up; up="$(cat "$T/dest/UPSTREAM.md")"
  assert_contains "$up" '- Synced: 2026-12-01'
  assert_contains "$up" "- Commit: \`$(head_of "$T/src")\`"
  assert_contains "$(cat "$T/dest/pr/SKILL.md")" "more"
}

test_vendor_sync_missing_item_fails_and_writes_nothing() {
  fake_upstream "$T/src"
  rm -rf "$T/src/skills/engineering/to-spec"
  vsync "$T/src"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "to-spec"
  [ ! -e "$T/dest" ] || _fail "nothing is written"
}

test_vendor_sync_missing_item_keeps_earlier_copy() {
  fake_upstream "$T/src"
  vsync "$T/src"
  local before; before="$(tree_sum "$T/dest")"
  rm "$T/src/skills/engineering/triage/AGENT-BRIEF.md"
  vsync "$T/src"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "AGENT-BRIEF.md"
  assert_eq "$before" "$(tree_sum "$T/dest")" "destination unchanged"
}

test_vendor_sync_rejects_a_source_that_is_not_upstream() {
  mkdir -p "$T/plain/skills"; printf 'MIT\n' > "$T/plain/LICENSE"
  vsync "$T/plain"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "$T/plain"
  [ ! -e "$T/dest" ] || _fail "nothing is written"

  mkdir -p "$T/noskills"; git init -q "$T/noskills"
  vsync "$T/noskills"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "$T/noskills"
  [ ! -e "$T/dest" ] || _fail "nothing is written"
}

test_vendor_sync_removes_items_no_longer_listed() {
  fake_upstream "$T/src"
  mkdir -p "$T/dest/old-skill"; printf 'old\n' > "$T/dest/old-skill/SKILL.md"
  vsync "$T/src"
  assert_status 0 "$STATUS" "$ERR"
  [ ! -e "$T/dest/old-skill" ] || _fail "an item outside the list is removed"
}

test_vendor_sync_clones_when_no_source_is_given() {
  fake_upstream "$T/src"
  mkdir -p "$T/tmp"
  set +e
  OUT="$(TMPDIR="$T/tmp" VENDOR_DEST="$T/dest" VENDOR_UPSTREAM_URL="file://$T/src" bash "$VSYNC" 2>"$T/stderr")"; STATUS=$?
  set -e
  assert_status 0 "$STATUS" "$(cat "$T/stderr")"
  assert_eq "" "$(diff -r "$T/src/skills/engineering/pr" "$T/dest/pr")"
  assert_contains "$(cat "$T/dest/UPSTREAM.md")" "- Commit: \`$(head_of "$T/src")\`"
  assert_eq "" "$(ls -A "$T/tmp")" "the temporary clone is removed"
}

test_vendored_skills_are_not_plugin_commands() {
  local d
  for d in "$PLUGIN_DIR"/vendor/pocock/*/; do
    d="$(basename "$d")"
    [ ! -e "$PLUGIN_DIR/skills/$d" ] || _fail "skills/$d has the name of a vendored skill"
  done
}

test_vendored_tree_matches_the_list() {
  local s
  for s in $VENDOR_ITEMS; do
    [ -f "$PLUGIN_DIR/vendor/pocock/$s/SKILL.md" ] || _fail "vendor/pocock/$s/SKILL.md is missing"
  done
  [ -f "$PLUGIN_DIR/vendor/pocock/triage/AGENT-BRIEF.md" ] || _fail "triage/AGENT-BRIEF.md is missing"
  [ -f "$PLUGIN_DIR/vendor/pocock/wizard/template.sh" ] || _fail "wizard/template.sh is missing"
  assert_not_contains "$(cat "$PLUGIN_DIR/vendor/pocock/UPSTREAM.md")" "aidw"
}
