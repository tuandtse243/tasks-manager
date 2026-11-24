# shellcheck shell=bash
# scrum init: config file, labels, templates, workflows and the vendored runtime. Idempotent.

# render_template FILE VARS_JSON  -> prints FILE with {{KEY}} replaced by VARS_JSON.KEY
render_template() {
  jq -Rrs --argjson v "$2" \
    'reduce ($v | to_entries[]) as $e (.; gsub("\\{\\{" + $e.key + "\\}\\}"; $e.value | tostring))' "$1"
}

# Template variables. Branch names come from the preset (jq/scrum.jq). CHECKOUT_REF is the
# branch that scheduled and issue-triggered workflows check out: the working branch, or empty
# (the default branch, as before) when the configuration has no branching block.
template_vars() {
  printf '%s' "$CONFIG_JSON" | jq -c -L "$JQ_LIB" 'include "scrum"; . as $cfg | branching($cfg) as $b | {
    STATUS_NEW_LABEL: ((.statuses.label_prefix + .statuses.new) | tojson),
    POINTS_OPTIONS: ([.points.scale[] | "        - \(tostring | tojson)"] | join("\n")),
    NO_TASK_LABEL: .labels.no_task,
    DIGEST_CRON: .digest.cron,
    PROJECT_POLL_CRON: .project.poll_cron,
    WORKING_BRANCH: $b.working,
    RELEASE_BRANCH: $b.release,
    STAGING_BRANCH: ($b.staging // ""),
    CHECKOUT_REF: (if .branching.preset == null then "" else $b.working end),
    TAG_PREFIX: (.release.tag_prefix // "v"),
    LOCATION_PREFIX: location_prefix($cfg),
    CODEOWNERS_LINE: ([.governance.codeowners[]? | select(. != "") | if startswith("@") or test("@") then . else "@" + . end]
      | if length == 0 then "# * @your-org/your-team" else "* " + join(" ") end)
  }'
}

# managed_files [all]  Prints "TEMPLATE<TAB>PATH" for every file init installs (needs CONFIG_JSON).
# "all" also lists the board and release workflows when they are off: they may remain from
# when they were on.
managed_files() {
  local tpl="$SCRUM_ROOT/../templates/github"
  printf '%s\t%s\n' \
    "$tpl/ISSUE_TEMPLATE/task.yml" ".github/ISSUE_TEMPLATE/task.yml" \
    "$tpl/pull_request_template.md" ".github/pull_request_template.md" \
    "$tpl/workflows/scrum-status-sync.yml" ".github/workflows/scrum-status-sync.yml" \
    "$tpl/workflows/scrum-pr-link-check.yml" ".github/workflows/scrum-pr-link-check.yml" \
    "$tpl/workflows/scrum-daily-digest.yml" ".github/workflows/scrum-daily-digest.yml"
  if [ "${1:-}" = all ] || project_enabled; then
    printf '%s\t%s\n' "$tpl/workflows/scrum-project-sync.yml" ".github/workflows/scrum-project-sync.yml"
  fi
  # The release workflow (release finish) exists only with a working branch.
  if [ -f "$tpl/workflows/scrum-release.yml" ] && { [ "${1:-}" = all ] || has_working_branch; }; then
    printf '%s\t%s\n' "$tpl/workflows/scrum-release.yml" ".github/workflows/scrum-release.yml"
  fi
}

# ---------- governance files (spec repo-governance "Governance files") ----------
# Installed only when the project has none at any place GitHub reads it from; never updated or
# overwritten afterwards, and not recorded in files.json: from then on they are the project's.
# governance_files  Prints "TEMPLATE<TAB>PATH<TAB>OTHER PLACES (space separated)".
governance_files() {
  local tpl="$SCRUM_ROOT/../templates/governance" preset
  preset="$(branch_role preset)"
  printf '%s\t%s\t%s\n' \
    "$tpl/CODEOWNERS" ".github/CODEOWNERS" "CODEOWNERS docs/CODEOWNERS" \
    "$tpl/CONTRIBUTING-$preset.md" ".github/CONTRIBUTING.md" "CONTRIBUTING.md docs/CONTRIBUTING.md" \
    "$tpl/SECURITY.md" ".github/SECURITY.md" "SECURITY.md docs/SECURITY.md" \
    "$tpl/dependabot.yml" ".github/dependabot.yml" ".github/dependabot.yaml"
}

# governance_existing REL OTHERS  Prints the path the project already has for this file, if any.
governance_existing() {
  local p
  for p in "$1" $2; do
    if [ -f "$DIR/$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

# install_governance  (uses DIR, DRY, VARS)
install_governance() {
  local src rel others have
  while IFS="$(printf '\t')" read -r src rel others; do
    [ -n "$src" ] || continue
    if have="$(governance_existing "$rel" "$others")"; then
      info "  skipped       $rel (the project has $have; left unchanged)"
    elif [ "$DRY" = 1 ]; then
      info "  would create  $rel"
    else
      mkdir -p "$(dirname "$DIR/$rel")"
      render_template "$src" "$VARS" > "$DIR/$rel"
      info "  created       $rel"
      FILES_CHANGED=1
    fi
  done <<EOF
$(governance_files)
EOF
}

# ---------- record of generated files: .github/scrum/files.json ----------
# Maps each managed path to the git blob hash of the content init last wrote (or found identical),
# so a later run can tell a file the user edited from one that is only out of date.
RECORD_FILE=".github/scrum/files.json"

file_hash() { git hash-object "$1"; }

# record_load  Sets RECORD from $DIR/.github/scrum/files.json ({} when missing or unreadable).
record_load() {
  RECORD='{}'
  if [ -f "$DIR/$RECORD_FILE" ]; then
    RECORD="$(jq -c '.files // {} | with_entries(select(.value | type == "string"))' "$DIR/$RECORD_FILE" 2>/dev/null)" \
      || RECORD='{}'
  fi
}
record_get() { printf '%s' "$RECORD" | jq -r --arg p "$1" '.[$p] // ""'; }
record_set() { RECORD="$(printf '%s' "$RECORD" | jq -c --arg p "$1" --arg h "$2" '.[$p] = $h')"; }
record_save() { printf '%s' "$RECORD" | jq '{version: 1, files: .}' | write_atomic "$DIR/$RECORD_FILE"; }

# is_pristine REL TEMPLATE  True when the file is what init last wrote, or what it would write now.
is_pristine() {
  local dest="$DIR/$1" recorded tmp rc=1
  recorded="$(record_get "$1")"
  if [ -n "$recorded" ] && [ "$(file_hash "$dest")" = "$recorded" ]; then return 0; fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/scrum-render.XXXXXX")"
  render_template "$2" "$VARS" > "$tmp"
  if cmp -s "$tmp" "$dest"; then rc=0; fi
  rm -f "$tmp"
  return "$rc"
}

# install_file SRC_TEMPLATE REL_PATH  (uses DIR, DRY, FORCE, FORCE_FILES, VARS, RECORD)
install_file() {
  local src="$1" rel="$2" dest tmp forced=0 recorded
  dest="$DIR/$rel"
  tmp="$(mktemp "${TMPDIR:-/tmp}/scrum-render.XXXXXX")"
  render_template "$src" "$VARS" > "$tmp"
  if [ "$FORCE" = 1 ]; then forced=1; fi
  case "$FORCE_FILES" in *"|$rel|"*) forced=1 ;; esac
  recorded="$(record_get "$rel")"
  if [ ! -f "$dest" ]; then
    if [ "$DRY" = 1 ]; then info "  would create  $rel"
    else mkdir -p "$(dirname "$dest")"; cp "$tmp" "$dest"; info "  created       $rel"; fi
    record_set "$rel" "$(file_hash "$tmp")"
    FILES_CHANGED=1
  elif cmp -s "$tmp" "$dest"; then
    info "  unchanged     $rel"
    record_set "$rel" "$(file_hash "$dest")"
  elif [ -n "$recorded" ] && [ "$(file_hash "$dest")" = "$recorded" ]; then
    # Not edited since init wrote it: only the configuration or the template changed.
    if [ "$DRY" = 1 ]; then info "  would update  $rel"
    else cp "$tmp" "$dest"; info "  updated       $rel"; fi
    record_set "$rel" "$(file_hash "$tmp")"
    FILES_CHANGED=1
  elif [ "$forced" = 1 ]; then
    if [ "$DRY" = 1 ]; then info "  would overwrite $rel"
    else cp "$tmp" "$dest"; info "  overwritten   $rel"; fi
    record_set "$rel" "$(file_hash "$tmp")"
    FILES_CHANGED=1
  else
    info "  conflict      $rel (not the version init wrote; kept. Overwrite with: --force-file $rel)"
    CONFLICTS=1
  fi
  rm -f "$tmp"
}

sync_labels() {
  local existing plan
  existing="$(gh_get_all "repos/$REPO/labels?per_page=100")"
  plan="$(jqlib label-plan -n --argjson cfg "$CONFIG_JSON" --argjson existing "$existing")"

  info "Labels:"
  printf '%s' "$plan" | jq -r '
    (.create[] | "  \(if $dry then "would create " else "created      " end)  \(.name)"),
    (.update[] | "  \(if $dry then "would update " else "updated      " end)  \(.name)\(if .current != .name then " (was \(.current))" else "" end)"),
    (if (.unchanged | length) > 0 then "  unchanged     \(.unchanged | join(", "))" else empty end),
    (.obsolete[] | "  obsolete      \(.) (no longer in the configuration; not deleted)")' \
    --argjson dry "$( [ "$DRY" = 1 ] && echo true || echo false )"

  [ "$DRY" = 1 ] && return 0
  printf '%s' "$plan" | jq -c '.create[]' | while IFS= read -r item; do
    printf '%s' "$item" | gh_send POST "repos/$REPO/labels" >/dev/null
  done
  printf '%s' "$plan" | jq -c '.update[]' | while IFS= read -r item; do
    local path body
    path="repos/$REPO/labels/$(printf '%s' "$item" | jq -r '.current | @uri')"
    body="$(printf '%s' "$item" | jq -c '{new_name: .name, color, description}')"
    printf '%s' "$body" | gh_send PATCH "$path" >/dev/null
  done
}

sync_runtime() {
  local target="$DIR/.github/scrum" new old
  new="$(cat "$SCRUM_ROOT/VERSION")"
  old="$(cat "$target/VERSION" 2>/dev/null || echo "none")"
  if [ "$DRY" = 1 ]; then
    info "Runtime: would install .github/scrum v$new (installed: $old)"
    return 0
  fi
  rm -rf "$target"
  mkdir -p "$target"
  cp -R "$SCRUM_ROOT/bin" "$SCRUM_ROOT/lib" "$SCRUM_ROOT/share" "$SCRUM_ROOT/VERSION" "$target/"
  cat > "$target/GENERATED.md" <<EOF
# Generated by scrum-github v$new. Do not edit.

The workflows in .github/workflows run these scripts. Every \`scrum init\` replaces this folder.
EOF
  if [ "$old" = "$new" ]; then info "Runtime: .github/scrum v$new (up to date)"
  else info "Runtime: installed .github/scrum v$new (was: $old)"; FILES_CHANGED=1; fi
}

cmd_init() {
  DRY=0; FORCE=0; FORCE_FILES="|"; FILES_CHANGED=0; CONFLICTS=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY=1 ;;
      --force) FORCE=1 ;;
      --force-file) [ $# -ge 2 ] || die "--force-file needs a path"; FORCE_FILES="$FORCE_FILES$2|"; shift ;;
      *) die "unknown option for init: $1" ;;
    esac
    shift
  done

  require_tools
  local tpl="$SCRUM_ROOT/../templates"
  [ -d "$tpl" ] || die "templates not found. Run init from the plugin (scrum-github/runtime/bin/scrum init), not from .github/scrum"

  DIR="$(repo_dir)"
  REPO="$(repo_slug)"
  local cfgfile="$DIR/.github/scrum.yml"

  [ "$DRY" = 1 ] && info "Dry run: nothing will be written."
  info "Repository: $REPO ($DIR)"

  if [ -f "$cfgfile" ]; then
    load_config "$cfgfile"
    info "Config: .github/scrum.yml exists, keeping it"
  elif [ "$DRY" = 1 ]; then
    load_config "$tpl/scrum.yml"
    info "Config: would create .github/scrum.yml with defaults"
  else
    load_config "$tpl/scrum.yml"
    mkdir -p "$DIR/.github"
    cp "$tpl/scrum.yml" "$cfgfile"
    FILES_CHANGED=1
    info "Config: created .github/scrum.yml with defaults"
  fi

  sync_labels

  VARS="$(template_vars)"
  record_load   # before sync_runtime, which replaces .github/scrum/
  info "Files:"
  local src rel
  while IFS="$(printf '\t')" read -r src rel; do
    install_file "$src" "$rel"
  done <<EOF
$(managed_files)
EOF
  install_governance

  sync_runtime
  [ "$DRY" = 1 ] || record_save

  if [ "$DRY" = 1 ]; then
    info ""; info "Nothing was written. Run without --dry-run to apply."
  elif [ "$FILES_CHANGED" = 1 ] || [ -n "$(git -C "$DIR" status --porcelain -- .github 2>/dev/null)" ]; then
    info ""
    info "Next: commit and push .github/ so the workflows run on GitHub:"
    info "  git add .github && git commit -m \"Set up Scrum on GitHub\" && git push"
  fi
  if [ "$CONFLICTS" = 1 ]; then
    info "Some files were kept because they differ from the template (see 'conflict' above)."
  fi
  if project_enabled; then
    info ""
    if ghx api "repos/$REPO/actions/secrets" 2>/dev/null \
        | jq -e '[.secrets[]?.name] | index("SCRUM_PROJECT_TOKEN")' >/dev/null 2>&1; then
      info "Project board: the secret SCRUM_PROJECT_TOKEN is set; check the board with: scrum project init"
    else
      info "Project board: add the repository secret SCRUM_PROJECT_TOKEN, then run: scrum project init"
    fi
  fi
}
