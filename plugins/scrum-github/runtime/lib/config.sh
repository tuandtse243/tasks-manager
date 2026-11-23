# shellcheck shell=bash
# Configuration: .github/scrum.yml -> JSON (yq) -> merged with defaults and validated (jq).

CONFIG_JSON=""

config_path() { printf '%s/.github/scrum.yml' "$(repo_dir)"; }

# merge_config RAW_JSON -> prints merged JSON. RAW_JSON may be "null" (empty file).
# A team login written with "@" is read without it.
merge_config() {
  jq -n --argjson d "$(cat "$SHARE_DIR/defaults.json")" --argjson u "$1" \
    'if ($u | type) == "object" or $u == null then $d * ($u // {}) else error("top level must be a mapping") end
     | if (.team | type) == "array"
       then .team |= map(if type == "object" and (.login | type) == "string" then .login |= ltrimstr("@") else . end)
       else . end'
}

# load_config [FILE]  Sets CONFIG_JSON or dies. Without FILE uses .github/scrum.yml.
load_config() {
  local file="${1:-$(config_path)}" raw merged errors
  if [ ! -f "$file" ]; then
    die "no Scrum configuration found at .github/scrum.yml. Run /scrum-github:init first (or: scrum init)"
  fi
  if ! raw="$(yq -o=json '.' "$file" 2>&1)"; then
    die "cannot read $file: $raw"
  fi
  [ -n "$raw" ] || raw="null"
  if ! merged="$(merge_config "$raw" 2>&1)"; then
    die "invalid configuration in $file: ${merged#jq: error (at <unknown>): }"
  fi
  errors="$(printf '%s' "$merged" | jqlib validate-config | jq -r '.[]')"
  if [ -n "$errors" ]; then
    printf 'scrum: error: invalid configuration in %s:\n' "$file" >&2
    printf '%s\n' "$errors" | sed 's/^/  - /' >&2
    exit 1
  fi
  CONFIG_JSON="$merged"
}

# config_get JQ_PATH  Reads one value from the loaded configuration (raw output).
config_get() { printf '%s' "$CONFIG_JSON" | jq -r "$1"; }

# load_config_or_defaults  Like load_config, but a repo without .github/scrum.yml uses the defaults
# (for offline commands that may run before scrum init, such as scrum context).
load_config_or_defaults() {
  if [ -f "$(config_path)" ]; then load_config; else CONFIG_JSON="$(cat "$SHARE_DIR/defaults.json")"; fi
}
