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
  # shellcheck disable=SC2046  # one login per word
  warn_unknown_logins $(printf '%s' "$task" | jq -r '.assignees[]')

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

# ---------- list, move, estimate, assign, drop ----------

# issue_number ARG  "12", "#12" -> 12, or dies.
issue_number() {
  local n="${1#\#}"
  case "$n" in ""|*[!0-9]*) die "not an issue number: $1" ;; esac
  printf '%s' "$n"
}

# task_issue REPO N  Prints the issue, or dies when it is a pull request, closed, or not a task.
task_issue() {
  local issue
  issue="$(gh_get "repos/$1/issues/$2")" || die "cannot read issue #$2"
  if [ "$(printf '%s' "$issue" | jq 'has("pull_request")')" = true ]; then die "#$2 is a pull request, not a task"; fi
  [ "$(printf '%s' "$issue" | jq -r .state)" = open ] || die "#$2 is closed"
  [ "$(printf '%s' "$issue" | jq -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum"; is_task($cfg)')" = true ] \
    || die "#$2 is not a task (it is a feature, epic or meta issue)"
  printf '%s' "$issue"
}

cmd_task_list() {
  local mine=0 sprint_name="" backlog=0 status="" json=0 repo issues me="" sprint list
  while [ $# -gt 0 ]; do
    case "$1" in
      --mine) mine=1 ;;
      --sprint) sprint_name="${2:-}"; shift ;;
      --backlog) backlog=1 ;;
      --status) status="${2:-}"; shift ;;
      --json) json=1 ;;
      *) die "unknown option for task list: $1" ;;
    esac
    shift
  done
  case "$status" in
    ""|new|in_progress|done) ;;
    in_review) ;;   # checked once the configuration is loaded
    *) die "--status must be new, in_progress, in_review or done" ;;
  esac
  [ "$backlog" = 0 ] || [ -z "$sprint_name" ] || die "use --sprint or --backlog, not both"
  require_tools
  load_config
  if [ "$status" = in_review ] && [ "$(config_get '(.statuses.in_review // "") != ""')" != true ]; then
    die "there is no In review status. Turn it on with statuses.in_review in .github/scrum.yml, then run init"
  fi
  repo="$(repo_slug)"
  if [ "$backlog" = 1 ]; then
    . "$SCRUM_ROOT/lib/cmd_backlog.sh"
    issues="$(backlog_issues "$repo")"
  else
    sprint="$(resolve_sprint "$(fetch_milestones "$repo")" "$sprint_name")"
    issues="$(fetch_milestone_issues "$repo" "$(printf '%s' "$sprint" | jq -r .number)")"
  fi
  [ "$mine" = 0 ] || me="$(gh_get user | jq -r .login)"
  list="$(printf '%s' "$issues" | jqlib task-list --argjson cfg "$CONFIG_JSON" --arg me "$me" --arg status "$status")"
  if [ "$json" = 1 ]; then printf '%s\n' "$list"; return 0; fi
  printf '%s' "$list" | jq -r '
    if length == 0 then "No tasks match."
    else .[] | "  #\(.number)  \(.status)  \(if .points == null then "-" else "\(.points) pt" end)  \(if (.assignees | length) == 0 then "-" else (.assignees | map("@" + .) | join(", ")) end)  \(.title)"
    end'
}

cmd_task_move() {
  local nums="" target="" backlog=0 repo n issues="" issue sprint="" ms to_title to_number from
  while [ $# -gt 0 ]; do
    case "$1" in
      --sprint) target="${2:-}"; [ -n "$target" ] || die "--sprint needs a sprint name"; shift ;;
      --backlog) backlog=1 ;;
      -*) die "unknown option for task move: $1" ;;
      *) for n in $(printf '%s' "$1" | tr ',' ' '); do nums="$nums $(issue_number "$n")"; done ;;
    esac
    shift
  done
  [ -n "$nums" ] || die "usage: scrum task move N... --sprint SPRINT | --backlog"
  if [ "$backlog" = 1 ] && [ -n "$target" ]; then die "use --sprint or --backlog, not both"; fi
  [ "$backlog" = 1 ] || [ -n "$target" ] || die "say where to: --sprint SPRINT or --backlog"
  require_tools
  load_config
  repo="$(repo_slug)"
  if [ "$backlog" = 1 ]; then
    to_title="the backlog"; to_number=null
  else
    ms="$(fetch_milestones "$repo")"
    sprint="$(resolve_sprint "$ms" "$target")"
    to_title="$(printf '%s' "$sprint" | jq -r .title)"
    [ "$(printf '%s' "$sprint" | jq -r .state)" = open ] || die "$to_title is closed"
    to_number="$(printf '%s' "$sprint" | jq -r .number)"
  fi
  # Check every task before changing any.
  for n in $nums; do issues="$issues$(task_issue "$repo" "$n" | jq -c .)"$'\n'; done
  printf '%s' "$issues" | while IFS= read -r issue; do
    [ -n "$issue" ] || continue
    n="$(printf '%s' "$issue" | jq -r .number)"
    from="$(printf '%s' "$issue" | jq -r '.milestone.title // "the backlog"')"
    if [ "$(printf '%s' "$issue" | jq -r '.milestone.number // "null"')" = "$to_number" ]; then
      info "#$n is already in $to_title."
      continue
    fi
    jq -n --argjson m "$to_number" '{milestone: $m}' | gh_send PATCH "repos/$repo/issues/$n" >/dev/null
    comment_issue "$repo" "$n" "Moved from $from to $to_title."
    info "Moved #$n from $from to $to_title."
    project_touch "$repo" "$n"
  done
}

cmd_task_estimate() {
  local n p repo issue res err
  [ $# -eq 2 ] || die "usage: scrum task estimate N POINTS"
  n="$(issue_number "$1")"; p="$2"
  case "$p" in ""|*[!0-9]*) die "points must be a whole number (got \"$p\")" ;; esac
  require_tools
  load_config
  # The scale first, before any network call.
  err="$(printf '{}' | jqlib points-labels --argjson cfg "$CONFIG_JSON" --argjson points "$p" | jq -r '.error // empty')"
  [ -z "$err" ] || die "$err"
  repo="$(repo_slug)"
  issue="$(task_issue "$repo" "$n")"
  res="$(printf '%s' "$issue" | jqlib points-labels --argjson cfg "$CONFIG_JSON" --argjson points "$p")"
  if [ "$(printf '%s' "$res" | jq -r .changed)" != true ]; then info "#$n already has $p points."; return 0; fi
  printf '%s' "$res" | jq -c '{labels}' | gh_send PUT "repos/$repo/issues/$n/labels" >/dev/null
  info "#$n now has $p points."
  project_touch "$repo" "$n"
}

cmd_task_assign() {
  local n="" logins="" unassign=0 repo body
  while [ $# -gt 0 ]; do
    case "$1" in
      --unassign) unassign=1 ;;
      -*) die "unknown option for task assign: $1" ;;
      *) if [ -z "$n" ]; then n="$(issue_number "$1")"; else logins="$logins ${1#@}"; fi ;;
    esac
    shift
  done
  [ -n "$n" ] && [ -n "$logins" ] || die "usage: scrum task assign N LOGIN... [--unassign]"
  require_tools
  load_config
  repo="$(repo_slug)"
  task_issue "$repo" "$n" >/dev/null
  # shellcheck disable=SC2086  # one login per word
  [ "$unassign" = 1 ] || warn_unknown_logins $logins
  # shellcheck disable=SC2086  # one login per word
  body="$(jq -n '{assignees: $ARGS.positional}' --args $logins)"
  if [ "$unassign" = 1 ]; then
    printf '%s' "$body" | gh_send DELETE "repos/$repo/issues/$n/assignees" >/dev/null
    info "Unassigned$(printf ' @%s' $logins) from #$n."
  else
    printf '%s' "$body" | gh_send POST "repos/$repo/issues/$n/assignees" >/dev/null
    info "Assigned #$n to$(printf ' @%s' $logins)."
  fi
}

cmd_task_drop() {
  local n="" reason="" repo
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="${2:-}"; shift ;;
      -*) die "unknown option for task drop: $1" ;;
      *) n="$(issue_number "$1")" ;;
    esac
    shift
  done
  [ -n "$n" ] || die "usage: scrum task drop N [--reason TEXT]"
  require_tools
  load_config
  repo="$(repo_slug)"
  task_issue "$repo" "$n" >/dev/null
  if [ -n "$reason" ]; then comment_issue "$repo" "$n" "Dropped (not planned): $reason"; fi
  printf '{"state":"closed","state_reason":"not_planned"}' | gh_send PATCH "repos/$repo/issues/$n" >/dev/null
  info "#$n is closed as not planned; it no longer counts in points or velocity."
  project_touch "$repo" "$n"
}
