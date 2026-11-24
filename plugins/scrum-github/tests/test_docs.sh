# The documentation stays in step with the code (change docs-by-role).

REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
PLUGIN_README="$PLUGIN_DIR/README.md"
GUIDE="$REPO_ROOT/docs/adoption-guide.md"

# Commands in `scrum --help`: the first word, or the first two for command groups.
help_commands() {
  "$BASH" "$SCRUM" --help | sed -n 's/^  \([a-z][a-z-]*\)\( \([a-z][a-z-]*\)\)\{0,1\}.*/\1 \3/p' \
    | awk '{ if ($1 ~ /^(sprint|task|plan|doc|context|project|run)$/) print $1" "$2; else print $1 }' | sort -u
}

test_every_command_in_help_is_in_the_readme() {
  local c missing=""
  while IFS= read -r c; do
    grep -qF "\`scrum $c" "$PLUGIN_README" || missing="$missing, $c"
  done <<EOF
$(help_commands)
EOF
  assert_eq "" "${missing#, }" "commands of scrum --help missing in the plugin README"
}

test_every_scrum_command_in_the_readme_exists() {
  local first known unknown=""
  known=" $(help_commands | awk '{print $1}' | sort -u | tr '\n' ' ') "
  for first in $(grep -o '`scrum [a-z][a-z-]*' "$PLUGIN_README" | sed 's/`scrum //' | sort -u); do
    case "$known" in *" $first "*) ;; *) unknown="$unknown, $first" ;; esac
  done
  assert_eq "" "${unknown#, }" "commands in the README that scrum does not have"
}

# Every `scrum …` command the adoption guide and the cheat sheets show exists in `scrum help`.
test_every_scrum_command_in_the_guides_exists() {
  local f first known unknown=""
  known=" $(help_commands | awk '{print $1}' | sort -u | tr '\n' ' ') "
  for f in "$GUIDE" "$REPO_ROOT"/docs/cheat-sheet-*.md "$REPO_ROOT/README.md"; do
    for first in $(grep -oE '(`|^ *)scrum [a-z][a-z-]*' "$f" | sed 's/.*scrum //' | sort -u); do
      case "$known" in *" $first "*) ;; *) unknown="$unknown, ${f#"$REPO_ROOT"/}: $first" ;; esac
    done
  done
  assert_eq "" "${unknown#, }" "commands in the guides that scrum does not have"
}

test_every_configuration_key_is_in_the_readme() {
  local cfg key missing=""
  cfg="$(awk '/^## Configuration/{f=1} f&&/^```yaml/{y=1;next} y&&/^```/{exit} y' "$PLUGIN_README")"
  for key in $(jq -r '[paths(scalars, arrays, nulls), paths(objects | select(length == 0))] | map(.[-1] | select(type == "string")) | unique[]' "$PLUGIN_DIR/runtime/share/defaults.json"); do
    printf '%s\n' "$cfg" | grep -qE "(^|[ {,])$key:" || missing="$missing, $key"
  done
  assert_eq "" "${missing#, }" "keys of defaults.json missing in the README Configuration block"
}

test_every_skill_is_in_the_guide() {
  local d name missing=""
  for d in "$PLUGIN_DIR"/skills/*/; do
    name="$(basename "$d")"
    grep -qF "| \`$name\` |" "$GUIDE" || missing="$missing, $name"
  done
  assert_eq "" "${missing#, }" "skills missing in the command table of the guide"
}

test_relative_links_point_to_files() {
  local f link target broken=""
  for f in "$REPO_ROOT/README.md" "$REPO_ROOT"/docs/*.md "$PLUGIN_README" "$PLUGIN_DIR/CHANGELOG.md" "$PLUGIN_DIR"/docs/*.md; do
    [ -f "$f" ] || continue
    while IFS= read -r link; do
      target="${link%%#*}"
      [ -n "$target" ] || continue
      [ -e "$(dirname "$f")/$target" ] || broken="$broken, ${f#"$REPO_ROOT"/} -> $link"
    done <<EOF
$(grep -o '\](\([^)]*\))' "$f" | sed 's/^](//; s/)$//' | grep -v '^[a-z][a-z]*:' | grep -v '^#' | grep -v '^<' || true)
EOF
  done
  assert_eq "" "${broken#, }" "relative links to missing files"
}
