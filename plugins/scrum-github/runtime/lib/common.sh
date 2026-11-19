# shellcheck shell=bash
# Shared helpers. Sourced by bin/scrum. Bash 3.2 compatible: no associative arrays,
# no mapfile, no ${var,,}; lists travel as JSON and are handled by jq.

JQ_LIB="$SCRUM_ROOT/lib/jq"
SHARE_DIR="$SCRUM_ROOT/share"

die()  { printf 'scrum: error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'scrum: warning: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

# The gh binary. Tests point SCRUM_GH at a fake that records calls.
ghx() { "${SCRUM_GH:-gh}" "$@"; }

# GET every page of a list endpoint and return one JSON array.
gh_get_all() {
  ghx api --paginate "$1" | jq -s 'map(if type == "array" then . else [.] end) | add // []'
}

# GET a single object.
gh_get() { ghx api "$1"; }

# Write call with a JSON body read from stdin: gh_send METHOD PATH <<< "$json"
gh_send() { ghx api -X "$1" "$2" --input -; }

# gh for GitHub Projects: SCRUM_PROJECT_TOKEN when set (the workflows' GITHUB_TOKEN cannot
# reach Projects), otherwise gh's own login (needs: gh auth refresh -s project).
ghp() {
  if [ -n "${SCRUM_PROJECT_TOKEN:-}" ]; then GH_TOKEN="$SCRUM_PROJECT_TOKEN" ghx "$@"; else ghx "$@"; fi
}
ghp_send() { ghp api -X "$1" "$2" --input -; }

# gh_graphql NAME [gh -f/-F options]  Run share/graphql/NAME.graphql with the project token.
gh_graphql() {
  local q="$1"; shift
  ghp api graphql -F "query=@$SHARE_DIR/graphql/$q.graphql" "$@"
}

# Run a jq program from lib/jq with that directory on the module path.
jqlib() {
  local prog="$1"; shift
  jq -L "$JQ_LIB" "$@" -f "$JQ_LIB/$prog.jq"
}

# True inside the Claude Code sandbox, which blocks gh's keychain and network access. The
# variable is observed, not documented; without it messages fall back to the usual advice.
in_claude_sandbox() { [ "${SANDBOX_RUNTIME:-}" = 1 ]; }

# Check required tools. Pass "nogh" to skip gh checks (offline commands).
require_tools() {
  local mode="${1:-}"
  command -v jq >/dev/null 2>&1 || die "jq is required. Install it: brew install jq (macOS) or apt-get install jq"
  if ! command -v yq >/dev/null 2>&1; then
    die "yq is required (mikefarah v4). Install it: brew install yq, or download from https://github.com/mikefarah/yq/releases"
  fi
  case "$(yq --version 2>&1)" in
    *mikefarah*) ;;
    *) die "the installed yq is not mikefarah/yq v4 (found: $(yq --version 2>&1 | head -1)). Install it: brew install yq" ;;
  esac
  [ "$mode" = "nogh" ] && return 0
  if [ -z "${SCRUM_GH:-}" ]; then
    command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required. Install it: brew install gh, see https://cli.github.com"
  fi
  if ! ghx auth status >/dev/null 2>&1; then
    if in_claude_sandbox; then
      die "gh reports no valid login. Inside the Claude Code sandbox gh cannot read its token from the keychain or reach GitHub, so this may be the sandbox: run the command outside the sandbox. If it still fails, run: gh auth login -h github.com -s repo,workflow. To check everything at once: /scrum-github:doctor"
    fi
    die "gh is not logged in. Run: gh auth login -h github.com -s repo,workflow"
  fi
}

# owner/name of the target repository.
repo_slug() {
  if [ -n "${SCRUM_REPO:-}" ]; then printf '%s' "$SCRUM_REPO"; return; fi
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then printf '%s' "$GITHUB_REPOSITORY"; return; fi
  local slug
  slug="$(ghx repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
  [ -n "$slug" ] || die "cannot tell which GitHub repo to use. Run inside a clone with a GitHub remote, or set SCRUM_REPO=owner/name"
  printf '%s' "$slug"
}

# remote_workflows REPO  Names of the files in .github/workflows on the default branch of the
# GitHub repository, one per line; nothing when the folder does not exist there (404).
# Returns 1 when GitHub could not be read for another reason.
remote_workflows() {
  local json err
  err="$(mktemp "${TMPDIR:-/tmp}/scrum-gh.XXXXXX")"
  if ! json="$(ghx api "repos/$1/contents/.github/workflows" 2>"$err")"; then
    if grep -q '404' "$err"; then rm -f "$err"; return 0; fi
    rm -f "$err"; return 1
  fi
  rm -f "$err"
  printf '%s' "$json" | jq -r 'if type == "array" then .[].name else empty end' 2>/dev/null || true
}

# Root of the target repository working tree.
repo_dir() {
  if [ -n "${SCRUM_REPO_DIR:-}" ]; then printf '%s' "$SCRUM_REPO_DIR"; return; fi
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# comment_issue REPO NUMBER TEXT  Post a comment on an issue.
comment_issue() { jq -n --arg b "$3" '{body: $b}' | gh_send POST "repos/$1/issues/$2/comments" >/dev/null; }

# write_atomic FILE  Writes stdin to FILE through a temporary file in the same directory, so
# FILE is always complete (a rename within one file system is atomic).
write_atomic() {
  local file="$1" tmp
  tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")"
  if ! cat > "$tmp"; then rm -f "$tmp"; return 1; fi
  mv -f "$tmp" "$file"
}

# Today's date (YYYY-MM-DD) in the configured time zone.
today() {
  if [ -n "${SCRUM_TODAY:-}" ]; then printf '%s' "$SCRUM_TODAY"; return; fi
  TZ="$(config_get '.timezone')" date +%Y-%m-%d
}

# Current UTC offset of the configured time zone, in seconds.
tz_offset() {
  local z sign hh mm
  z="$(TZ="$(config_get '.timezone')" date +%z)"   # e.g. +0700 or -0330
  sign="${z:0:1}"; hh="${z:1:2}"; mm="${z:3:2}"
  local secs=$(( (10#$hh * 3600) + (10#$mm * 60) ))
  if [ "$sign" = "-" ]; then secs=$(( -secs )); fi
  printf '%s' "$secs"
}

# Current time as an ISO 8601 UTC timestamp.
now_iso() {
  if [ -n "${SCRUM_NOW:-}" ]; then printf '%s' "$SCRUM_NOW"; return; fi
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Fetch milestones (all states) and issues of one milestone.
fetch_milestones() { gh_get_all "repos/$1/milestones?state=all&per_page=100"; }
fetch_milestone_issues() { gh_get_all "repos/$1/issues?milestone=$2&state=all&per_page=100"; }

# Resolve a sprint by title (or the current sprint when the title is empty).
# Prints the milestone JSON, or dies with guidance.
resolve_sprint() {
  local milestones="$1" title="${2:-}" result
  result="$(jqlib sprint-resolve -n \
    --argjson ms "$milestones" --argjson cfg "$CONFIG_JSON" \
    --arg title "$title" --arg today "$(today)")"
  if [ "$result" = "null" ]; then
    if [ -n "$title" ]; then die "no sprint named \"$title\""; fi
    die "there is no open sprint. Create one first: /scrum-github:sprint-new (or: scrum sprint new)"
  fi
  printf '%s' "$result"
}

# Load configuration (sets CONFIG_JSON). Defined in config.sh.
# shellcheck source=config.sh
. "$SCRUM_ROOT/lib/config.sh"

# set_status REPO ISSUE_JSON ROLE  Move an issue to one status (exactly one status label).
# One PUT replaces the label set, so the issue never has zero or two statuses.
set_status() {
  local res
  res="$(printf '%s' "$2" | jqlib status-labels --argjson cfg "$CONFIG_JSON" --arg role "$3")"
  if [ "$(printf '%s' "$res" | jq -r .changed)" = "true" ]; then
    printf '%s' "$res" | jq -c '{labels}' \
      | gh_send PUT "repos/$1/issues/$(printf '%s' "$2" | jq -r .number)/labels" >/dev/null
    project_touch "$1" "$(printf '%s' "$2" | jq -r .number)"
  fi
}

# GitHub Projects board sync (project_touch and friends).
# shellcheck source=project.sh
. "$SCRUM_ROOT/lib/project.sh"
