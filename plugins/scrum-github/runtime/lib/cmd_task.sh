# shellcheck shell=bash
# scrum task new | scrum task start

# create_task REPO TASK_JSON MILESTONE_NUMBER [PARENT_NUMBER] -> prints the created issue JSON
create_task() {
  local payload err
  if [ -n "${4:-}" ]; then
    payload="$(jqlib task-payload -n --argjson cfg "$CONFIG_JSON" --argjson task "$2" --argjson milestone "$3" --arg parent "$4")"
  else
    payload="$(jqlib task-payload -n --argjson cfg "$CONFIG_JSON" --argjson task "$2" --argjson milestone "$3")"
  fi
  err="$(printf '%s' "$payload" | jq -r '.error // empty')"
  [ -z "$err" ] || die "$err"
  printf '%s' "$payload" | gh_send POST "repos/$1/issues"
}

cmd_task_new() {
  local title="" body="" points="" assignees="" sprint_name="" bug=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="${2:-}"; shift ;;
      --body) body="${2:-}"; shift ;;
      --points) points="${2:-}"; shift ;;
      --assignee) assignees="$assignees${2:-}
"; shift ;;
      --sprint) sprint_name="${2:-}"; shift ;;
      --bug) bug=true ;;
      *) die "unknown option for task new: $1" ;;
    esac
    shift
  done
  [ -n "$title" ] || die "a task needs a title: scrum task new --title \"...\""
  case "$points" in ""|*[!0-9]*) [ -z "$points" ] || die "points must be a whole number (got \"$points\")" ;; esac

  require_tools
  load_config
  local repo task ms sprint number created
  repo="$(repo_slug)"
  task="$(jq -n --arg t "$title" --arg b "$body" --arg p "$points" --arg a "$assignees" --argjson bug "$bug" '{
    title: $t, body: $b,
    points: (if $p == "" then null else ($p | tonumber) end),
    assignees: ($a | split("\n") | map(select(. != "") | ltrimstr("@"))),
    bug: $bug }')"
  # Check the points before any network call.
  jqlib task-payload -n --argjson cfg "$CONFIG_JSON" --argjson task "$task" --argjson milestone 0 \
    | jq -r '.error // empty' | { read -r e || true; [ -z "$e" ] || die "$e"; }

  ms="$(fetch_milestones "$repo")"
  sprint="$(resolve_sprint "$ms" "$sprint_name")"
  [ "$(printf '%s' "$sprint" | jq -r .state)" = "open" ] || die "$(printf '%s' "$sprint" | jq -r .title) is closed"
  number="$(printf '%s' "$sprint" | jq -r .number)"
  created="$(create_task "$repo" "$task" "$number")"
  printf '%s' "$created" | jq -r --arg s "$(printf '%s' "$sprint" | jq -r .title)" \
    '"Created #\(.number) \(.title) in \($s): \(.html_url // "")"'
  project_touch "$repo" "$(printf '%s' "$created" | jq -r .number)"
}

cmd_task_start() {
  local n="${1:-}"
  n="${n#\#}"
  case "$n" in ""|*[!0-9]*) die "usage: scrum task start ISSUE_NUMBER" ;; esac

  require_tools
  load_config
  local repo issue branch login default dir
  repo="$(repo_slug)"
  issue="$(gh_get "repos/$repo/issues/$n")" || die "cannot read issue #$n"
  if [ "$(printf '%s' "$issue" | jq 'has("pull_request")')" = "true" ]; then die "#$n is a pull request, not a task"; fi
  [ "$(printf '%s' "$issue" | jq -r .state)" = "open" ] || die "#$n is closed. Reopen it first if the work is not finished."

  branch="$(printf '%s' "$issue" | jqlib branch-name -r --argjson cfg "$CONFIG_JSON")"
  login="$(gh_get user | jq -r .login)"
  dir="$(repo_dir)"

  # Branch first: if git refuses (for example uncommitted changes), nothing on GitHub has changed yet.
  if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$dir" checkout -q "$branch" || die "cannot check out $branch"
    info "Checked out existing branch $branch."
  else
    default="$(ghx repo view "$repo" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)"
    [ -n "$default" ] || default="main"
    git -C "$dir" fetch -q origin "$default" 2>/dev/null || true
    if git -C "$dir" rev-parse --verify -q "origin/$default" >/dev/null; then
      git -C "$dir" checkout -q -b "$branch" "origin/$default" || die "cannot create $branch"
    else
      git -C "$dir" checkout -q -b "$branch" "$default" || die "cannot create $branch from $default"
    fi
    info "Created branch $branch from $default."
  fi

  local assigned
  assigned="$(printf '%s' "$issue" | jq -r '[.assignees[]?.login] | join(", ")')"
  if [ -z "$assigned" ]; then
    jq -n --arg l "$login" '{assignees: [$l]}' | gh_send POST "repos/$repo/issues/$n/assignees" >/dev/null
    info "Assigned #$n to $login."
  elif ! printf '%s' "$issue" | jq -e --arg l "$login" 'any(.assignees[]?; .login == $l)' >/dev/null; then
    info "Note: #$n is assigned to $assigned; leaving the assignee as it is."
  fi

  set_status "$repo" "$issue" in_progress
  info "#$n $(printf '%s' "$issue" | jq -r .title) is now $(config_get .statuses.in_progress)."
  info "When you open the pull request, write \"Closes #$n\" in its description."
}
