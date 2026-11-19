# scripts/vendor-sync.sh (design 11)

VSYNC="$PLUGIN_DIR/scripts/vendor-sync.sh"

fake_source() { # fake_source DIR  A vendor/pocock tree like aidw's
  local d="$1" s
  mkdir -p "$d"
  for s in grilling to-spec domain-modeling to-tickets grill-me; do
    mkdir -p "$d/$s"; printf -- '---\nname: %s\n---\nBody of %s\n' "$s" "$s" > "$d/$s/SKILL.md"
  done
  printf 'extra\n' > "$d/to-tickets/NOTES.md"
  printf 'MIT License\n' > "$d/LICENSE"
  cat > "$d/UPSTREAM.md" <<'EOF'
# Upstream: mattpocock/skills

- Commit: `abc123def` (ref `main`)

## Skills

- `grilling` <- `skills/productivity/grilling`
- `to-spec` <- `skills/engineering/to-spec`
EOF
}

test_vendor_sync_copies_four_skills_and_license() {
  fake_source "$T/src"
  VENDOR_DEST="$T/dest" VENDOR_SYNC_DATE=2026-11-19 bash "$VSYNC" "$T/src" >/dev/null
  local s
  for s in grilling to-spec domain-modeling to-tickets; do
    assert_eq "" "$(diff -r "$T/src/$s" "$T/dest/$s")" "$s copied verbatim"
  done
  [ ! -e "$T/dest/grill-me" ] || _fail "only the four skills are copied"
  assert_eq "" "$(diff "$T/src/LICENSE" "$T/dest/LICENSE")"
  local up; up="$(cat "$T/dest/UPSTREAM.md")"
  assert_contains "$up" 'https://github.com/mattpocock/skills'
  assert_contains "$up" '- Commit: `abc123def`'
  assert_contains "$up" '- Synced: 2026-11-19'
  assert_contains "$up" 'aidw'
  assert_contains "$up" '- `grilling` <- `skills/productivity/grilling`'
  assert_contains "$up" '- `to-tickets`'
}

test_vendor_sync_second_run_changes_nothing() {
  fake_source "$T/src"
  VENDOR_DEST="$T/dest" VENDOR_SYNC_DATE=2026-11-19 bash "$VSYNC" "$T/src" >/dev/null
  local before after
  before="$(cd "$T/dest" && find . -type f | sort | xargs cat | cksum)"
  VENDOR_DEST="$T/dest" VENDOR_SYNC_DATE=2026-12-01 bash "$VSYNC" "$T/src" >/dev/null
  after="$(cd "$T/dest" && find . -type f | sort | xargs cat | cksum)"
  assert_eq "$before" "$after"
}

test_vendor_sync_new_commit_updates_date() {
  fake_source "$T/src"
  VENDOR_DEST="$T/dest" VENDOR_SYNC_DATE=2026-11-19 bash "$VSYNC" "$T/src" >/dev/null
  sed -i.bak 's/abc123def/fff999/' "$T/src/UPSTREAM.md"
  VENDOR_DEST="$T/dest" VENDOR_SYNC_DATE=2026-12-01 bash "$VSYNC" "$T/src" >/dev/null
  assert_contains "$(cat "$T/dest/UPSTREAM.md")" '- Synced: 2026-12-01'
  assert_contains "$(cat "$T/dest/UPSTREAM.md")" 'fff999'
}

test_vendor_sync_missing_skill_fails() {
  fake_source "$T/src"
  rm -rf "$T/src/to-spec"
  set +e
  err="$(VENDOR_DEST="$T/dest" bash "$VSYNC" "$T/src" 2>&1 >/dev/null)"; rc=$?
  set -e
  assert_status 1 "$rc"
  assert_contains "$err" "to-spec"
  [ ! -e "$T/dest" ] || _fail "nothing is written"
}
