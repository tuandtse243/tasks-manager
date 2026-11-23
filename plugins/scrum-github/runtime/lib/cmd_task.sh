# shellcheck shell=bash
# scrum task new | scrum task start

# create_task REPO TASK_JSON MILESTONE_NUMBER [PARENT_NUMBER] -> prints the created issue JSON
create_task() {
  local payload err strings
  strings="$(strings_json)"
  if [ -n "${4:-}" ]; then
    payload="$(jqlib task-payload -n --argjson cfg "$CONFIG_JSON" --argjson task "$2" --argjson milestone "$3" --arg parent "$4" --argjson strings "$strings")"
  else
    payload="$(jqlib task-payload -n --argjson cfg "$CONFIG_JSON" --argjson task "$2" --argjson milestone "$3" --argjson strings "$strings")"
  fi
  err="$(printf '%s' "$payload" | jq -r '.error // empty')"
  [ -z "$err" ] || die "$err"
  printf '%s' "$payload" | gh_send POST "repos/$1/issues"
}

cmd_task_new() {
  local title="" body="" points="" assignees="" sprint_name="" bug=false backlog=0 work="" review="" by="" est err
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="${2:-}"; shift ;;
      --work) work="${2:-}"; [ -n "$work" ] || die "--work needs a duration, for example 25m"; shift ;;
      --review) review="${2:-}"; [ -n "$review" ] || die "--review needs a duration, for example 20m"; shift ;;
      --by) by="${2:-}"; [ -n "$by" ] || die "--by needs ai or human"; shift ;;
      --backlog) backlog=1 ;;
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
  if [ "$backlog" = 1 ] && [ -n "$sprint_name" ]; then die "use --sprint or --backlog, not both"; fi
  case "$points" in ""|*[!0-9]*) [ -z "$points" ] || die "points must be a whole number (got \"$points\")" ;; esac

  # The time flags before anything else (spec time-estimate "Định dạng thời lượng"); jq first,
  # gh later (require_tools nogh calls nothing).
  require_tools nogh
  est="$(jqlib estimate-flags -n --arg work "$work" --arg review "$review" --arg by "$by")"
  err="$(printf '%s' "$est" | jq -r '.error // empty')"
  [ -z "$err" ] || die "$err"

  require_tools
  load_config
  local repo task ms sprint number created
  repo="$(repo_slug)"
  task="$(jq -n --arg t "$title" --arg b "$body" --arg p "$points" --arg a "$assignees" --argjson bug "$bug" \
      --argjson est "$(printf '%s' "$est" | jq -c .estimate)" '{
    title: $t, body: $b,
    points: (if $p == "" then null else ($p | tonumber) end),
    assignees: ($a | split("\n") | map(select(. != "") | ltrimstr("@"))),
    bug: $bug }
    + (if $est == null then {} else {estimate: $est} end)')"
  # Check the points before any network call.
  jqlib task-payload -n --argjson cfg "$CONFIG_JSON" --argjson task "$task" --argjson milestone 0 \
    | jq -r '.error // empty' | { read -r e || true; [ -z "$e" ] || die "$e"; }
  warn_unknown_logins "$(printf '%s' "$task" | jq -c '.assignees')"

  # --sprint S: that sprint (an unknown or closed one is an error). Neither flag: the open sprint,
  # or the backlog when no sprint is open. --backlog: the backlog (design 3).
  local where="the backlog"
  number=null
  if [ "$backlog" = 0 ]; then
    ms="$(fetch_milestones "$repo")"
    if [ -n "$sprint_name" ]; then
      sprint="$(resolve_sprint "$ms" "$sprint_name")"
    else
      sprint="$(jqlib sprint-resolve -n --argjson ms "$ms" --argjson cfg "$CONFIG_JSON" --arg title "" --arg today "$(today)")"
    fi
    if [ "$sprint" != null ]; then
      [ "$(printf '%s' "$sprint" | jq -r .state)" = "open" ] || die "$(printf '%s' "$sprint" | jq -r .title) is closed"
      number="$(printf '%s' "$sprint" | jq -r .number)"
      where="$(printf '%s' "$sprint" | jq -r .title)"
    fi
  fi
  created="$(create_task "$repo" "$task" "$number")"
  printf '%s' "$created" | jq -r --arg s "$where" '"Created #\(.number) \(.title) in \($s): \(.html_url // "")"'
  if [ "$backlog" = 0 ] && [ "$number" = null ]; then
    info "There is no open sprint, so the task is in the backlog. Create a sprint with /scrum-github:sprint-new, then move it: scrum task move $(printf '%s' "$created" | jq -r .number) --sprint SPRINT"
  fi
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

# scrum task estimate N [POINTS] [--work D] [--review D] [--by ai|human]
# Points stay on the label; the time estimate is the "estimate" block of the body (spec time-estimate).
cmd_task_estimate() {
  local usage="usage: scrum task estimate N [POINTS] [--work D] [--review D] [--by ai|human]"
  local n="" p="" work="" review="" by="" repo issue res err est touched=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --work) work="${2:-}"; [ -n "$work" ] || die "--work needs a duration, for example 25m"; shift ;;
      --review) review="${2:-}"; [ -n "$review" ] || die "--review needs a duration, for example 20m"; shift ;;
      --by) by="${2:-}"; [ -n "$by" ] || die "--by needs ai or human"; shift ;;
      -[0-9]*) die "points must be a whole number (got \"$1\")" ;;
      -*) die "unknown option for task estimate: $1" ;;
      *) if [ -z "$n" ]; then n="$(issue_number "$1")"
         elif [ -z "$p" ]; then p="$1"
         else die "$usage"; fi ;;
    esac
    shift
  done
  [ -n "$n" ] || die "$usage"
  if [ -z "$p" ] && [ -z "$work" ] && [ -z "$review" ] && [ -z "$by" ]; then
    die "nothing to change: give points, or at least one of --work, --review, --by. $usage"
  fi
  case "$p" in *[!0-9]*) die "points must be a whole number (got \"$p\")" ;; esac
  require_tools nogh
  est="$(jqlib estimate-flags -n --arg work "$work" --arg review "$review" --arg by "$by" --argjson partial true)"
  err="$(printf '%s' "$est" | jq -r '.error // empty')"
  [ -z "$err" ] || die "$err"
  require_tools
  load_config
  # The scale first, before any network call.
  if [ -n "$p" ]; then
    err="$(printf '{}' | jqlib points-labels --argjson cfg "$CONFIG_JSON" --argjson points "$p" | jq -r '.error // empty')"
    [ -z "$err" ] || die "$err"
  fi
  repo="$(repo_slug)"
  issue="$(task_issue "$repo" "$n")"
  # A --by alone on a task without a time estimate is an error: check it before writing anything.
  # The issue goes on stdin: its body can be longer than one command-line argument may be.
  est="$(printf '%s' "$issue" | jqlib estimate-flags --arg work "$work" --arg review "$review" --arg by "$by" \
    --argjson strings "$(strings_json)")"
  err="$(printf '%s' "$est" | jq -r '.error // empty')"
  [ -z "$err" ] || die "$err"

  if [ -n "$p" ]; then
    res="$(printf '%s' "$issue" | jqlib points-labels --argjson cfg "$CONFIG_JSON" --argjson points "$p")"
    if [ "$(printf '%s' "$res" | jq -r .changed)" != true ]; then
      info "#$n already has $p points."
    else
      printf '%s' "$res" | jq -c '{labels}' | gh_send PUT "repos/$repo/issues/$n/labels" >/dev/null
      info "#$n now has $p points."
      touched=1
    fi
  fi
  if [ "$(printf '%s' "$est" | jq -r .given)" = true ]; then
    if [ "$(printf '%s' "$est" | jq -r .changed)" = true ]; then
      printf '%s' "$est" | jq -c '{body}' | gh_send PATCH "repos/$repo/issues/$n" >/dev/null
      info "#$n time estimate: $(printf '%s' "$est" | jq -r .summary)."
    else
      info "#$n already has this time estimate: $(printf '%s' "$est" | jq -r .summary)."
    fi
  fi
  [ "$touched" = 0 ] || project_touch "$repo" "$n"
}

cmd_task_assign() {
  local n="" logins='[]' unassign=0 repo body who
  while [ $# -gt 0 ]; do
    case "$1" in
      --unassign) unassign=1 ;;
      -*) die "unknown option for task assign: $1" ;;
      *) if [ -z "$n" ]; then n="$(issue_number "$1")"; else logins="$(jq -nc --argjson l "$logins" --arg x "${1#@}" '$l + [$x]')"; fi ;;
    esac
    shift
  done
  [ -n "$n" ] && [ "$logins" != '[]' ] || die "usage: scrum task assign N LOGIN... [--unassign]"
  require_tools
  load_config
  repo="$(repo_slug)"
  task_issue "$repo" "$n" >/dev/null
  [ "$unassign" = 1 ] || warn_unknown_logins "$logins"
  body="$(jq -nc --argjson l "$logins" '{assignees: $l}')"
  who="$(printf '%s' "$logins" | jq -r 'map(" @" + .) | join("")')"
  if [ "$unassign" = 1 ]; then
    printf '%s' "$body" | gh_send DELETE "repos/$repo/issues/$n/assignees" >/dev/null
    info "Unassigned$who from #$n."
  else
    printf '%s' "$body" | gh_send POST "repos/$repo/issues/$n/assignees" >/dev/null
    info "Assigned #$n to$who."
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
