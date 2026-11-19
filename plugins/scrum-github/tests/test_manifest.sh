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

test_changelog_has_the_current_version() {
  local v
  v="$(tr -d '[:space:]' < "$PLUGIN_DIR/runtime/VERSION")"
  grep -q "^## \[$v\]" "$PLUGIN_DIR/CHANGELOG.md" || _fail "CHANGELOG.md has no heading for $v"
  assert_eq "$v" "$(grep -m1 -o '^## \[[0-9][^]]*\]' "$PLUGIN_DIR/CHANGELOG.md" | tr -d '#[] ')" \
    "the newest CHANGELOG entry is not the current version"
}
