# shellcheck shell=bash
# scrum doctor: read-only checks of the tools, the repository, what init installed and the board.
# Every check records one line; doctor-report.jq prints them at the end. Nothing stops at the
# first problem, so require_tools and load_config (which die) are not used here.

# shellcheck source=cmd_init.sh
. "$SCRUM_ROOT/lib/cmd_init.sh"

# check GROUP ID STATUS MESSAGE [FIX]   STATUS: ok | warn | error | skip
check() {
  jq -nc --arg g "$1" --arg i "$2" --arg s "$3" --arg m "$4" --arg f "${5:-}" \
    '{group: $g, id: $i, status: $s, message: $m} + (if $f == "" then {} else {fix: $f} end)' >> "$CHECKS"
}

# version_lt A B  True when version A is older than B (numeric dot parts).
version_lt() {
  [ "$(jq -n --arg a "$1" --arg b "$2" \
    '($a | split(".") | map(tonumber? // 0)) < ($b | split(".") | map(tonumber? // 0))')" = true ]
}

doctor_tools() {
  local v out rc scopes
  check tools jq ok "jq: $(jq --version 2>&1)"
  if ! command -v yq >/dev/null 2>&1; then
    check tools yq error "yq is not installed" "brew install yq (or download mikefarah/yq v4 from https://github.com/mikefarah/yq/releases)"
  else
    v="$(yq --version 2>&1 | head -1)"
    case "$v" in
      *mikefarah*) YQ_OK=1; check tools yq ok "yq: $v" ;;
      *) check tools yq error "the yq on the PATH is not mikefarah/yq v4 (found: $v)" "brew install yq, and remove the other yq from the PATH (for example: pip uninstall yq)" ;;
    esac
  fi

  if [ -z "${SCRUM_GH:-}" ] && ! command -v gh >/dev/null 2>&1; then
    check tools gh error "GitHub CLI (gh) is not installed" "brew install gh, see https://cli.github.com"
    check tools gh-login skip "needs gh"
    check tools gh-scopes skip "needs gh"
    return 0
  fi
  check tools gh ok "gh is installed"

  rc=0; out="$(ghx auth status --active 2>&1)" || rc=$?
  case "$out" in *"unknown flag"*) rc=0; out="$(ghx auth status 2>&1)" || rc=$? ;; esac
  if [ "$rc" != 0 ] || printf '%s' "$out" | grep -qi 'token .* is invalid\|failed to log in'; then
    if in_claude_sandbox; then
      check tools gh-login error "gh reports no valid login, and this runs inside the Claude Code sandbox, which blocks gh from reading its token in the keychain and from reaching GitHub" \
        "Run this command outside the sandbox (you will be asked to approve it), or adjust the sandbox with /sandbox"
    else
      check tools gh-login error "gh is not logged in" "gh auth login -h github.com -s repo,workflow"
    fi
    check tools gh-scopes skip "needs a working gh login"
    return 0
  fi
  GH_OK=1
  check tools gh-login ok "gh is logged in"

  scopes="$(printf '%s\n' "$out" | sed -n "s/.*Token scopes: *//p" | head -1)"
  if [ -z "$scopes" ]; then
    check tools gh-scopes warn "cannot read the token's scopes (a fine-grained token or GH_TOKEN?); needs repo and workflow access" "gh auth refresh -h github.com -s repo,workflow"
    return 0
  fi
  case "$scopes" in
    *"'repo'"*) ;;
    *) check tools gh-scopes error "the gh token has no 'repo' scope (has: $scopes)" "gh auth refresh -h github.com -s repo,workflow"; return 0 ;;
  esac
  local missing=""
  case "$scopes" in *"'workflow'"*) ;; *) missing="workflow" ;; esac
  if [ "$CFG_OK" = 1 ] && project_enabled; then
    case "$scopes" in *"'project'"*) ;; *) missing="${missing:+$missing,}project" ;; esac
  fi
  if [ -n "$missing" ]; then
    check tools gh-scopes warn "the gh token lacks the scope(s) $missing (has: $scopes)" "gh auth refresh -h github.com -s $missing"
  else
    check tools gh-scopes ok "gh token scopes: $scopes"
  fi
}

doctor_repo() {
  local cfgfile="$DIR/.github/scrum.yml" err existing plan
  if git -C "$DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    check repo git ok "git repository: $DIR"
  else
    check repo git error "$DIR is not inside a git repository" "Run this from a clone of the repository you want to manage"
  fi

  if [ "$GH_OK" != 1 ]; then
    check repo remote skip "needs a working gh login"
  else
    REPO="${SCRUM_REPO:-${GITHUB_REPOSITORY:-}}"
    [ -n "$REPO" ] || REPO="$(cd "$DIR" && ghx repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
    if [ -n "$REPO" ]; then check repo remote ok "GitHub repository: $REPO"
    else check repo remote error "no GitHub remote found for this working tree" "git remote add origin https://github.com/OWNER/NAME.git (or set SCRUM_REPO=owner/name)"; fi
  fi

  if [ ! -f "$cfgfile" ]; then
    check repo config error "no .github/scrum.yml: Scrum on GitHub is not set up here" "/scrum-github:init (or: scrum init)"
  elif [ "$YQ_OK" != 1 ]; then
    check repo config skip "needs mikefarah/yq to read .github/scrum.yml"
  elif [ "$CFG_OK" = 1 ]; then
    check repo config ok ".github/scrum.yml is valid"
  else
    err="$(sed 's/^scrum: error: //' "$CFG_ERR")"
    check repo config error "$err" "Fix .github/scrum.yml; the keys and defaults are in the plugin README (Configuration)"
  fi

  if [ "$CFG_OK" != 1 ] || [ "$GH_OK" != 1 ] || [ -z "$REPO" ]; then
    check repo labels skip "needs a valid configuration, a gh login and a GitHub remote"
    return 0
  fi
  if ! existing="$(gh_get_all "repos/$REPO/labels?per_page=100" 2>/dev/null)"; then
    check repo labels warn "cannot read the labels of $REPO" "Check that gh can read the repository: gh repo view $REPO"
    return 0
  fi
  plan="$(jqlib label-plan -n --argjson cfg "$CONFIG_JSON" --argjson existing "$existing")"
  if [ "$(printf '%s' "$plan" | jq '(.create | length) + (.update | length)')" = 0 ]; then
    check repo labels ok "all configured labels exist"
  else
    check repo labels warn "$(printf '%s' "$plan" | jq -r '
      [ (if (.create | length) > 0 then "missing labels: \([.create[].name] | join(", "))" else empty end),
        (if (.update | length) > 0 then "labels with another name, color or description: \([.update[].name] | join(", "))" else empty end)
      ] | join("; ")')" "/scrum-github:init (or: scrum init)"
  fi
}

doctor_install() {
  local ver="$DIR/.github/scrum/VERSION" have want remote src rel name stale="" edited="" absent="" notpushed=""
  want="$(cat "$SCRUM_ROOT/VERSION")"
  if [ ! -f "$ver" ]; then
    check install runtime error "the runtime is not installed (.github/scrum/ is missing)" "/scrum-github:init (or: scrum init)"
  else
    have="$(tr -d '[:space:]' < "$ver")"
    if [ "$have" = "$want" ]; then check install runtime ok "runtime .github/scrum v$have matches the plugin"
    elif version_lt "$have" "$want"; then check install runtime warn "runtime .github/scrum v$have is older than the plugin (v$want)" "/scrum-github:init (or: scrum init), then commit and push .github/"
    else check install runtime warn "runtime .github/scrum v$have is newer than the plugin (v$want)" "Update the plugin: /plugin update scrum-github@tasks-manager"; fi
  fi

  if [ "$CFG_OK" != 1 ]; then
    check install files skip "needs a valid configuration"
    check install workflows skip "needs a valid configuration"
    return 0
  fi

  VARS="$(template_vars)"
  record_load
  while IFS="$(printf '\t')" read -r src rel; do
    if [ ! -f "$DIR/$rel" ]; then absent="$absent $rel"
    elif ! render_template "$src" "$VARS" | cmp -s - "$DIR/$rel"; then
      if is_pristine_by_record "$rel"; then stale="$stale $rel"; else edited="$edited $rel"; fi
    fi
  done <<EOF
$(managed_files)
EOF
  if [ -n "$absent" ]; then
    check install files error "missing generated files:$absent" "/scrum-github:init (or: scrum init)"
  fi
  if [ -n "$stale" ]; then
    check install files warn "out of date with the configuration or the plugin:$stale" "/scrum-github:init (or: scrum init) updates them, then commit and push .github/"
  fi
  if [ -n "$edited" ]; then
    check install files warn "changed by hand, so init keeps them as they are:$edited" "To replace one with the current template: scrum init --force-file PATH"
  fi
  if [ -z "$absent$stale$edited" ]; then
    check install files ok "generated files match the configuration"
  fi

  if [ "$GH_OK" != 1 ] || [ -z "$REPO" ]; then
    check install workflows skip "needs a gh login and a GitHub remote"
    return 0
  fi
  if ! remote="$(remote_workflows "$REPO")"; then
    check install workflows warn "cannot read .github/workflows on the default branch of $REPO" "Check that gh can read the repository: gh repo view $REPO"
    return 0
  fi
  local missing=""
  while IFS="$(printf '\t')" read -r src rel; do
    case "$rel" in
      .github/workflows/scrum-project-sync.yml) continue ;;   # checked with the board
      .github/workflows/*) ;;
      *) continue ;;
    esac
    name="${rel##*/}"
    if ! printf '%s\n' "$remote" | grep -qx "$name"; then
      if [ -f "$DIR/$rel" ]; then notpushed="$notpushed $rel"; else missing="$missing $rel"; fi
    fi
  done <<EOF
$(managed_files)
EOF
  if [ -n "$notpushed" ]; then
    check install workflows error "not on the default branch of $REPO yet (they exist only in this working tree):$notpushed" \
      "git add .github && git commit -m \"Set up Scrum on GitHub\" && git push (to the default branch, or through a pull request)"
  fi
  if [ -n "$missing" ]; then
    check install workflows error "workflows missing on the default branch of $REPO:$missing" "/scrum-github:init (or: scrum init), then commit and push .github/"
  fi
  if [ -z "$notpushed$missing" ]; then
    check install workflows ok "workflows are on the default branch of $REPO"
  fi
}

# is_pristine_by_record REL  True when the file's hash is the one init recorded.
is_pristine_by_record() {
  local recorded
  recorded="$(record_get "$1")"
  [ -n "$recorded" ] && [ "$(file_hash "$DIR/$1")" = "$recorded" ]
}

doctor_board() {
  local secrets
  if [ "$CFG_OK" != 1 ]; then
    check board board skip "needs a valid configuration"; return 0
  fi
  if ! project_enabled; then
    check board board skip "the project board is off (project.enabled: false)"; return 0
  fi
  if [ "$GH_OK" != 1 ] || [ -z "$REPO" ]; then
    check board secret skip "needs a gh login and a GitHub remote"
    check board workflow skip "needs a gh login and a GitHub remote"
    return 0
  fi
  if ! secrets="$(ghx api "repos/$REPO/actions/secrets" 2>/dev/null)"; then
    check board secret warn "cannot list the secrets of $REPO, so SCRUM_PROJECT_TOKEN was not checked (needs admin access to the repository)" \
      "Ask an admin to check Settings → Secrets and variables → Actions"
  elif printf '%s' "$secrets" | jq -e '[.secrets[]?.name] | index("SCRUM_PROJECT_TOKEN")' >/dev/null 2>&1; then
    check board secret ok "repository secret SCRUM_PROJECT_TOKEN exists"
  else
    check board secret error "the repository secret SCRUM_PROJECT_TOKEN is missing, so the board sync workflow cannot reach the board" "/scrum-github:project-setup"
  fi
  local remote
  if ! remote="$(remote_workflows "$REPO")"; then
    check board workflow warn "cannot read .github/workflows on the default branch of $REPO" "Check that gh can read the repository: gh repo view $REPO"
  elif printf '%s\n' "$remote" | grep -qx scrum-project-sync.yml; then
    check board workflow ok "scrum-project-sync.yml is on the default branch"
  elif [ -f "$DIR/.github/workflows/scrum-project-sync.yml" ]; then
    check board workflow error "scrum-project-sync.yml is not on the default branch yet (it exists only in this working tree)" "git add .github && git commit -m \"Turn on the project board\" && git push"
  else
    check board workflow error "scrum-project-sync.yml is missing" "/scrum-github:init (or: scrum init), then commit and push .github/"
  fi
}

cmd_doctor() {
  local json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      *) die "unknown option for doctor: $1" ;;
    esac
    shift
  done
  if ! command -v jq >/dev/null 2>&1; then
    printf 'Tools\n  error  jq is not installed\n         fix: brew install jq (macOS) or apt-get install jq\n\n1 error. Install jq, then run scrum doctor again for the other checks.\n'
    exit 1
  fi

  DIR="$(repo_dir)"
  YQ_OK=0; GH_OK=0; CFG_OK=0; REPO=""
  CHECKS="$(mktemp "${TMPDIR:-/tmp}/scrum-doctor.XXXXXX")"
  CFG_ERR="$(mktemp "${TMPDIR:-/tmp}/scrum-doctor-cfg.XXXXXX")"
  # shellcheck disable=SC2064  # expand now: the paths are fixed
  trap "rm -f '$CHECKS' '$CFG_ERR'" EXIT

  # The configuration first (quietly): the scope and board checks depend on it.
  if command -v yq >/dev/null 2>&1 && [ -f "$DIR/.github/scrum.yml" ]; then
    local cfg
    if cfg="$( { load_config "$DIR/.github/scrum.yml" >/dev/null; printf '%s' "$CONFIG_JSON"; } 2>"$CFG_ERR" )" && [ -n "$cfg" ]; then
      CONFIG_JSON="$cfg"; CFG_OK=1
    fi
  fi

  doctor_tools
  doctor_repo
  doctor_install
  doctor_board

  local report
  report="$(jqlib doctor-report -s < "$CHECKS")"
  if [ "$json" = 1 ]; then
    printf '%s\n' "$report"
  else
    printf '%s' "$report" | jqlib doctor-text -r
  fi
  [ "$(printf '%s' "$report" | jq .errors)" = 0 ]
}
