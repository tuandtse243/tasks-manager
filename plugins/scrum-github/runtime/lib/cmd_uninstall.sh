# shellcheck shell=bash
# scrum uninstall: remove what scrum init installed in the working tree, keep what the user
# changed. Local only: nothing on GitHub (labels, milestones, issues) is touched.

# shellcheck source=cmd_init.sh
. "$SCRUM_ROOT/lib/cmd_init.sh"

cmd_uninstall() {
  local dry=0 yes=0 src rel removing="" kept=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=1 ;;
      --yes|-y) yes=1 ;;
      *) die "unknown option for uninstall: $1" ;;
    esac
    shift
  done

  require_tools nogh
  DIR="$(repo_dir)"
  load_config_or_defaults
  # shellcheck disable=SC2034  # read by is_pristine (cmd_init.sh)
  VARS="$(template_vars)"
  record_load

  info "Repository: $DIR"
  while IFS="$(printf '\t')" read -r src rel; do
    [ -f "$DIR/$rel" ] || continue
    if is_pristine "$rel" "$src"; then
      info "  remove  $rel"
      removing="$removing$rel"$'\n'
    else
      info "  keep    $rel (changed since scrum init wrote it)"
      kept=1
    fi
  done <<EOF
$(managed_files all)
EOF
  if [ -d "$DIR/.github/scrum" ]; then
    info "  remove  .github/scrum/ (the runtime the workflows run, and the record of generated files)"
    removing="$removing.github/scrum"$'\n'
  fi
  if [ -f "$DIR/.github/scrum.yml" ]; then
    info "  keep    .github/scrum.yml (your configuration; delete it yourself if you no longer need it)"
  fi
  info "  keep    labels, milestones and issues on GitHub (uninstall does not touch GitHub)"

  if [ -z "$removing" ]; then
    info ""; info "Nothing to remove: Scrum on GitHub is not installed in this working tree."
    return 0
  fi
  if [ "$dry" = 1 ]; then
    info ""; info "Dry run: nothing changed."
    return 0
  fi
  if [ "$yes" != 1 ]; then
    info ""; info "Nothing changed. To apply, run again with --yes."
    return 0
  fi

  printf '%s' "$removing" | while IFS= read -r rel; do
    [ -n "$rel" ] && rm -rf "${DIR:?}/$rel"
  done
  rmdir "$DIR/.github/ISSUE_TEMPLATE" "$DIR/.github/workflows" 2>/dev/null || true
  info ""
  info "Removed. Commit and push the removal so the workflows stop running on GitHub:"
  info "  git add -A .github && git commit -m \"Remove Scrum on GitHub\" && git push"
  if [ "$kept" = 1 ]; then
    info "Files marked 'keep' above were changed by hand; delete them yourself if you no longer need them."
  fi
}
