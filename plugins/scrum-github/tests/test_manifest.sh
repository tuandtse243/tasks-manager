# Plugin and marketplace manifests, and the changelog that goes with the version.

REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

test_manifests_are_valid_json() {
  jq -e . "$PLUGIN_JSON" >/dev/null || _fail "plugin.json is not valid JSON"
  jq -e . "$MARKETPLACE_JSON" >/dev/null || _fail "marketplace.json is not valid JSON"
}

test_plugin_json_has_required_fields() {
  local f v
  for f in name version description repository homepage license; do
    v="$(jq -r --arg f "$f" '.[$f] // "" | strings' "$PLUGIN_JSON")"
    [ -n "$v" ] || _fail "plugin.json has no \"$f\""
  done
}

test_plugin_version_matches_runtime_version() {
  assert_eq "$(tr -d '[:space:]' < "$PLUGIN_DIR/runtime/VERSION")" \
    "$(jq -r .version "$PLUGIN_JSON")" "plugin.json version differs from runtime/VERSION"
}

test_marketplace_source_points_to_the_plugin() {
  local name src
  name="$(jq -r .name "$PLUGIN_JSON")"
  src="$(jq -r --arg n "$name" '.plugins[] | select(.name == $n) | .source' "$MARKETPLACE_JSON")"
  [ -n "$src" ] || _fail "marketplace.json has no plugin named $name"
  [ -f "$REPO_ROOT/$src/.claude-plugin/plugin.json" ] \
    || _fail "marketplace source $src has no .claude-plugin/plugin.json"
}

# delta repo-governance "Installed workflows pin actions": every `uses:` of an installed workflow
# template, of a deployment template and of this repository's own workflows names a 40-character
# commit SHA with the version in a comment. Local actions (./...) need no SHA.
test_workflows_pin_actions_by_commit_sha() {
  local f line bad="" n=0
  for f in "$PLUGIN_DIR"/templates/github/workflows/*.yml "$REPO_ROOT"/.github/workflows/*.yml \
           $(find "$PLUGIN_DIR/templates/deploy" -name '*.yml' 2>/dev/null); do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      n=$((n + 1))
      printf '%s\n' "$line" | grep -Eq 'uses:[[:space:]]*("|'"'"')?(\./|[^@[:space:]]+@[0-9a-f]{40}("|'"'"')?[[:space:]]+#[[:space:]]*v?[0-9])' \
        || bad="$bad, ${f#"$REPO_ROOT"/}: $(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
    done <<EOF
$(grep -E '^[[:space:]]*(-[[:space:]]*)?uses:' "$f" || true)
EOF
  done
  [ "$n" -gt 0 ] || _fail "no uses: line found; the test reads nothing"
  assert_eq "" "${bad#, }" "actions not pinned to a full commit SHA with a version comment"
}

test_pin_check_rejects_a_tag() {
  printf '      - uses: actions/checkout@v4\n' | grep -Eq 'uses:[[:space:]]*("|'"'"')?(\./|[^@[:space:]]+@[0-9a-f]{40}("|'"'"')?[[:space:]]+#[[:space:]]*v?[0-9])' \
    && _fail "a tag passed the pin check"
  printf '      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262\n' | grep -Eq 'uses:[[:space:]]*("|'"'"')?(\./|[^@[:space:]]+@[0-9a-f]{40}("|'"'"')?[[:space:]]+#[[:space:]]*v?[0-9])' \
    && _fail "a SHA without its version comment passed the pin check"
  return 0
}

test_changelog_has_the_current_version() {
  local v
  v="$(tr -d '[:space:]' < "$PLUGIN_DIR/runtime/VERSION")"
  grep -q "^## \[$v\]" "$PLUGIN_DIR/CHANGELOG.md" || _fail "CHANGELOG.md has no heading for $v"
  assert_eq "$v" "$(grep -m1 -o '^## \[[0-9][^]]*\]' "$PLUGIN_DIR/CHANGELOG.md" | tr -d '#[] ')" \
    "the newest CHANGELOG entry is not the current version"
}

# The listing icon: a square PNG of 512 to 2048 px (SVG and WebP are not accepted).
test_plugin_icon_is_a_square_png() {
  local icon="$PLUGIN_DIR/.claude-plugin/icon.png" sig w h
  [ -f "$icon" ] || _fail "no .claude-plugin/icon.png"
  sig="$(od -An -tx1 -N8 "$icon" | tr -d ' \n')"
  assert_eq "89504e470d0a1a0a" "$sig" "icon.png is not a PNG"
  w=$((16#$(od -An -tx1 -j16 -N4 "$icon" | tr -d ' \n')))
  h=$((16#$(od -An -tx1 -j20 -N4 "$icon" | tr -d ' \n')))
  assert_eq "$w" "$h" "icon.png is not square"
  [ "$w" -ge 512 ] && [ "$w" -le 2048 ] || _fail "icon.png is ${w}px, not 512 to 2048"
  [ "$(wc -c < "$icon")" -lt 2097152 ] || _fail "icon.png is 2 MB or more"
}
