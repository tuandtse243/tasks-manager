# shellcheck shell=bash
# scrum project init | scrum project sync  (GitHub Projects board; see lib/project.sh)

project_require_enabled() {
  project_enabled || die "the project board is off. Turn it on in .github/scrum.yml (project: enabled: true, owner, number), then run: scrum init"
}

project_require_token() {
  if ! project_token_ok; then
    local msg
    msg="SCRUM_PROJECT_TOKEN is not set. $(project_token_help)"
    printf '::error title=Project token missing::%s\n' "$msg"
    die "$msg"
  fi
}

cmd_project_init() {
  local dry=0 allow=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=1 ;;
      --allow-builtin-workflows) allow=1 ;;
      *) die "unknown option for project init: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  project_require_enabled
  project_require_token
  local repo problems conflicts fields name type res
  repo="$(repo_slug)"
  [ "$dry" = 1 ] && info "Dry run: nothing will be written."

  project_load_meta || die "$PROJECT_ERR. $(project_token_help)"
  info "Project: $(pm .title) ($(pm .url))"

  # Checks that change nothing: the Status field, its options and the field types.
  problems="$(printf '%s' "$PROJECT_META" | jq -r --arg sf "$(config_get .project.status_field)" '
    (if .status_field == null then "there is no single select field \"\($sf)\"" else empty end),
    (.missing_options[] | "the field has no option \"\(.)\""),
    (.wrong_types[])')"
  if [ -n "$problems" ]; then
    printf 'scrum: error: the project does not match .github/scrum.yml:\n' >&2
    printf '%s\n' "$problems" | sed 's/^/  - /' >&2
    printf 'Add the missing options to the board (column menu > Edit), or change project.status_options in .github/scrum.yml.\n' >&2
    exit 1
  fi

  conflicts="$(pm '.conflicts | join(", ")')"
  if [ -n "$conflicts" ]; then
    if [ "$allow" = 1 ]; then
      warn "built-in project workflows that change Status are on: $conflicts. They move cards without the sync knowing, which can change task statuses the wrong way."
    else
      die "turn off these built-in workflows of the project (project menu > Workflows): $conflicts. They change Status on their own, and the sync would copy that onto the labels. To go ahead anyway: scrum project init --allow-builtin-workflows"
    fi
  fi

  info "Fields:"
  fields="$(pm '.missing_fields[] | "\(.name)\t\(.type)"')"
  if [ -z "$fields" ]; then
    info "  unchanged     $(config_get .project.status_field), $(config_get .project.synced_field)$(config_get '.project.points_field // empty | ", " + .')"
  fi
  printf '%s\n' "$fields" | while IFS="$(printf '\t')" read -r name type; do
    [ -n "$name" ] || continue
    if [ "$dry" = 1 ]; then info "  would create  $name ($(printf '%s' "$type" | tr 'A-Z' 'a-z'))"; continue; fi
    res="$(gh_graphql create-field -f project="$(pm .id)" -f name="$name" -f type="$type" 2>&1)" \
      || die "cannot create the field \"$name\": $res"
    info "  created       $name ($(printf '%s' "$type" | tr 'A-Z' 'a-z'))"
  done
  if [ -n "$fields" ] && [ "$dry" != 1 ]; then
    PROJECT_META=""
    project_load_meta || die "$PROJECT_ERR"
  fi

  info "Items:"
  project_sync_all "$repo" "$dry" || die "$PROJECT_ERR"
  info "  $PROJECT_ADDED added, $PROJECT_CHANGED changed, $PROJECT_UNCHANGED unchanged"
  if [ "$dry" = 1 ]; then
    info ""; info "Nothing was written. Run without --dry-run to apply."
  else
    info ""
    info "In the project views, hide the field \"$(config_get .project.synced_field)\": the sync uses it for bookkeeping."
  fi
}

cmd_project_sync() {
  local issue=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue) issue="${2:-}"; issue="${issue#\#}"; shift ;;
      *) die "unknown option for project sync: $1" ;;
    esac
    shift
  done
  case "$issue" in ""|*[!0-9]*) [ -z "$issue" ] || die "--issue needs an issue number" ;; esac
  require_tools
  load_config
  if ! project_enabled; then
    info "The project board is off (project.enabled: false). Nothing to sync."
    return 0
  fi
  project_require_token
  local repo
  repo="$(repo_slug)"
  # A token that cannot read the project is the usual failure: say how to fix it.
  project_load_meta || die "$PROJECT_ERR. $(project_token_help)"
  if [ -n "$issue" ]; then
    project_sync_issue "$repo" "$issue" || die "$PROJECT_ERR"
    info "#$issue: synced with the board."
  else
    project_sync_all "$repo" || die "$PROJECT_ERR"
    info "Board sync: $PROJECT_ADDED added, $PROJECT_CHANGED changed, $PROJECT_UNCHANGED unchanged."
  fi
}
