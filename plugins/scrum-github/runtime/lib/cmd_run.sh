# shellcheck shell=bash
# scrum run: work my tasks with AI agents (spec ai-run, design 1-7). The runtime does the parts
# that touch git and GitHub; the skill /scrum-github:run starts the agents. The state of a run is
# kept in .scrum/run/<id>.json in the repository (excluded from git), so a run can be resumed.
. "$SCRUM_ROOT/lib/cmd_backlog.sh"   # blocked_map, BACKLOG_BLOCKED_LIMIT
. "$SCRUM_ROOT/lib/cmd_team.sh"      # open_sprint

# ---------- choosing the tasks ----------

# run_num ARG  "#0102" -> 102 (leading zeros dropped), or dies when it is not an issue number.
run_num() {
  local n="${1#\#}"
  case "$n" in ""|*[!0-9]*) die "not an issue number: $1" ;; esac
  n="$(printf '%s' "$n" | sed 's/^0*//')"
  [ -n "$n" ] || die "not an issue number: $1"
  printf '%s' "$n"
}

# run_numbers_json "102,107 103"  -> [102,107,103], or dies on a word that is not a number.
run_numbers_json() {
  local list='[]' n
  for n in $(printf '%s' "$1" | tr ',' ' '); do
    n="$(run_num "$n")" || exit 1
    list="$(jq -nc --argjson l "$list" --argjson n "$n" '$l + [$n]')"
  done
  printf '%s' "$list"
}

# run_optval OPTION VALUE  The value of an option, or dies when it is missing.
run_optval() {
  case "$2" in ""|--*) die "$1 needs a value" ;; esac
  printf '%s' "$2"
}

# run_count VALUE OPTION  A whole number greater than 0 (leading zeros dropped), or dies.
run_count() {
  local k
  case "$1" in ""|*[!0-9]*) die "$2 must be a whole number greater than 0 (got \"$1\")" ;; esac
  k="$(printf '%s' "$1" | sed 's/^0*//')"
  [ -n "$k" ] || die "$2 must be a whole number greater than 0 (got \"$1\")"
  printf '%s' "$k"
}

# run_select REPO LOGIN NUMBERS_JSON|null  Prints the output of run-select.jq (read-only).
run_select() {
  local repo="$1" login="$2" numbers="$3" ms sprint issues n one cands blocked
  ms="$(fetch_milestones "$repo")" || die "cannot read the sprints (milestones) of $repo"
  sprint="$(open_sprint "$ms")"
  if [ "$numbers" = null ]; then
    issues="$(gh_get_all "repos/$repo/issues?assignee=$login&state=open&per_page=100")" || die "cannot read the issues of $repo"
  else
    issues='[]'
    for n in $(printf '%s' "$numbers" | jq -r '.[]'); do
      one="$(gh_get "repos/$repo/issues/$n" 2>/dev/null)" || one=""
      if [ -z "$one" ] || ! printf '%s' "$one" | jq -e 'type == "object" and .number != null' >/dev/null 2>&1; then
        one="$(jq -nc --argjson n "$n" '{number: $n, _unreadable: true}')"
      fi
      issues="$(printf '%s' "$issues" | jq -c --argjson i "$one" '. + [$i]')"
    done
  fi
  # First pass: the candidates, whose blockers are then read (one call each, at most
  # BACKLOG_BLOCKED_LIMIT; the others count as not read and are left out).
  cands="$(jqlib run-select -n --argjson cfg "$CONFIG_JSON" --arg login "$login" --argjson issues "$issues" \
    --argjson sprint "$sprint" --argjson blocked '{}' --argjson numbers "$numbers" \
    | jq -r --argjson max "$BACKLOG_BLOCKED_LIMIT" '.candidates[:$max][]')"
  # shellcheck disable=SC2086  # one number per word
  blocked="$(blocked_map "$repo" $cands)"
  jqlib run-select -n --argjson cfg "$CONFIG_JSON" --arg login "$login" --argjson issues "$issues" \
    --argjson sprint "$sprint" --argjson blocked "$blocked" --argjson numbers "$numbers"
}

# print_run_plan  The selection in RUN_SEL, for a person.
print_run_plan() {
  printf '%s' "$RUN_SEL" | jq -r -L "$JQ_LIB" 'include "scrum";
    def plural($n; $w): "\($n) \($w)\(if $n == 1 then "" else "s" end)";
    (.tasks | length) as $n
    | (if .mode == "default" and .sprint == null then
         "There is no open sprint, so no task is chosen. Name the tasks (scrum run plan N,N) or create a sprint with /scrum-github:sprint-new."
       elif $n == 0 then "No task to run."
       else "Run for @\(.login)\(if .sprint then " in \(.sprint.title)" else "" end): \(plural($n; "task")) in \(plural(.waves | length; "wave"))" end),
      (.tasks as $t | .waves | to_entries[] | .key as $i
       | "", "Wave \($i + 1)\(if $i > 0 then " (after wave \($i) is merged)" else "" end):",
         (.value[] as $num | $t[] | select(.number == $num) | "  #\(.number)  \(if .points == null then "-" else "\(.points) pt" end)  \(.title)\(estimate_brief)")),
      (if (.excluded | length) > 0 then "", "Not in this run:", (.excluded[] | "  #\(.number)  \(.title // "?"): \(.reason)") else empty end),
      (if $n == 0 then empty
       else .eta as $e
         | "",
           (if $e.estimated == 0 then "Time: no task has a time estimate. Add one: scrum task estimate N --work 25m --review 20m"
            else "Time: about \($e.work_minutes | fmt_duration) of work (\(plural($e.waves; "wave")), each as long as its longest task plus the merge) and \($e.review_minutes | fmt_duration) of review."
                 + (if $e.missing > 0 then " Not counted, without a time estimate: \($e.missing_numbers | map("#\(.)") | join(", "))." else "" end) end)
       end)'
}

# whoami_login  The GitHub login of the user, or dies.
whoami_login() {
  local login
  login="$(gh_get user | jq -r '.login // empty')" || login=""
  [ -n "$login" ] || die "cannot tell who you are on GitHub"
  printf '%s' "$login"
}

# scrum run plan [N,N...] [--json] [--dry-run]  Read-only.
cmd_run_plan() {
  local json=0 nums="" numbers=null repo login
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --dry-run) ;;   # plan never writes; accepted for the skill's --dry-run
      -*) die "unknown option for run plan: $1" ;;
      *) nums="$nums $1" ;;
    esac
    shift
  done
  [ -z "$nums" ] || numbers="$(run_numbers_json "$nums")"
  require_tools
  load_config
  repo="$(repo_slug)"
  login="$(whoami_login)"
  RUN_SEL="$(run_select "$repo" "$login" "$numbers")"
  if [ "$json" = 1 ]; then printf '%s\n' "$RUN_SEL"; else print_run_plan; fi
}

# ---------- the state file (.scrum/run/<id>.json, design 4) ----------

run_dir() { printf '%s/.scrum/run' "$(repo_dir)"; }
run_file() { printf '%s/%s.json' "$(run_dir)" "$1"; }

# run_ids  Ids of the saved runs, newest first (ids start with the time, so they sort).
run_ids() {
  local f
  for f in "$(run_dir)"/*.json; do
    [ -e "$f" ] || continue
    f="${f##*/}"; printf '%s\n' "${f%.json}"
  done | sort -r
}

# run_unfinished  Id of the newest run that is not finished, or nothing.
run_unfinished() {
  local id
  for id in $(run_ids); do
    if [ "$(jq -r '.finished_at == null' "$(run_file "$id")" 2>/dev/null)" = true ]; then printf '%s' "$id"; return 0; fi
  done
}

# run_resolve [ID]  The run to act on: the one named, else the unfinished one; or dies.
run_resolve() {
  local id="${1:-}"
  if [ -n "$id" ]; then
    [ -f "$(run_file "$id")" ] || die "there is no run $id in .scrum/run"
    printf '%s' "$id"; return 0
  fi
  id="$(run_unfinished)"
  [ -n "$id" ] || die "there is no unfinished run in .scrum/run. Start one with /scrum-github:run"
  printf '%s' "$id"
}

# run_lock FILE / run_unlock  One scrum run command at a time changes a state file: a lock
# folder next to it (mkdir is atomic), waited for up to 30 seconds, removed on exit.
RUN_LOCK=""
RUN_LOCK_TRIES="${SCRUM_RUN_LOCK_TRIES:-300}"
run_lock() {
  local lock="$1.lock" i=0
  while ! mkdir "$lock" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -lt "$RUN_LOCK_TRIES" ] || die "another scrum run command is changing this run (lock $lock). If none is running, remove that folder"
    sleep 0.1
  done
  RUN_LOCK="$lock"
  trap 'if [ -n "$RUN_LOCK" ]; then rmdir "$RUN_LOCK" 2>/dev/null; fi' EXIT
}
run_unlock() {
  if [ -n "$RUN_LOCK" ]; then rmdir "$RUN_LOCK" 2>/dev/null || true; fi
  RUN_LOCK=""
  trap - EXIT
}

# run_apply ID OP [jq args]  Applies one change of run-state.jq to the state file (read and
# written under the lock, written atomically) and sets RUN_EFFECTS; dies with the reason when the
# change is not allowed.
run_apply() {
  local id="$1" op="$2" file out err
  shift 2
  file="$(run_file "$id")"
  run_lock "$file"
  out="$(jqlib run-state --arg op "$op" --argjson strings "$(strings_json)" "$@" < "$file")" || die "cannot update run $id"
  err="$(printf '%s' "$out" | jq -r '.error // empty')"
  [ -z "$err" ] || die "$err"
  printf '%s\n' "$out" | jq '.state' | write_atomic "$file"
  run_unlock
  RUN_EFFECTS="$(printf '%s' "$out" | jq -c .effects)"
}

# run_task ID N  The task N of a run (JSON), or "null".
run_task() { jq -c --arg n "$2" '.tasks[$n]' "$(run_file "$1")"; }

# run_clean_tree DIR  Dies when tracked files have changes that are not committed.
run_clean_tree() {
  if [ -n "$(git -C "$1" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    die "the working tree has changes that are not committed. Commit or stash them first, then run this again"
  fi
}

# run_exclude_state DIR  Keeps .scrum/ out of git through .git/info/exclude (not .gitignore).
run_exclude_state() {
  local p
  p="$(cd "$1" && git rev-parse --git-path info/exclude)" || return 0
  case "$p" in /*) ;; *) p="$1/$p" ;; esac
  mkdir -p "$(dirname "$p")"
  grep -qxF '.scrum/' "$p" 2>/dev/null || printf '.scrum/\n' >> "$p"
}

# run_notes FILE  The agent's report as JSON: the object it wrote, or {text} for anything else.
run_notes() {
  [ -n "$1" ] || { printf 'null'; return 0; }
  [ -f "$1" ] || die "no notes file $1"
  if jq -e 'type == "object"' "$1" >/dev/null 2>&1; then jq -c . "$1"
  else jq -Rsc '{text: .}' "$1"; fi
}

# run_reason_from FILE  A failure reason from a file written by the skill: .reason of a JSON
# object, else the text itself; on one line, at most 500 characters. Agent text never goes on a
# command line (spec safety): the skill writes it to a file and passes the path.
run_reason_from() {
  [ -f "$1" ] || die "no file $1"
  if jq -e 'type == "object" and (.reason | type) == "string" and .reason != ""' "$1" >/dev/null 2>&1; then
    jq -r '.reason' "$1"
  elif jq -e 'type == "object"' "$1" >/dev/null 2>&1; then
    printf ''
  else
    cat "$1"
  fi | tr '\n\r\t' '   ' | sed 's/^ *//; s/ *$//' | cut -c1-500
}

# run_issue_to_new REPO N  Status back to New (after a failure).
run_issue_to_new() {
  local issue
  issue="$(gh_get "repos/$1/issues/$2")" || { warn "cannot read #$2 to move it back to $(config_get .statuses.new)"; return 0; }
  set_status "$1" "$issue" new || warn "cannot move #$2 back to $(config_get .statuses.new)"
}

# ---------- start ----------

# scrum run start [N,N...] [--max-parallel K] [--pr-per-wave]  (spec ai-run "Bắt đầu lần chạy")
cmd_run_start() {
  local nums="" numbers=null k="" per_wave=false expect="" repo login dir unfinished default base now id branch pattern sprint_title n issue file base_sha diff
  while [ $# -gt 0 ]; do
    case "$1" in
      --max-parallel) k="$(run_optval --max-parallel "${2:-}")"; shift ;;
      --expect) expect="$(run_optval --expect "${2:-}")"; shift ;;
      --pr-per-wave) per_wave=true ;;
      -*) die "unknown option for run start: $1" ;;
      *) nums="$nums $1" ;;
    esac
    shift
  done
  [ -z "$k" ] || k="$(run_count "$k" --max-parallel)"
  [ -z "$nums" ] || numbers="$(run_numbers_json "$nums")"
  [ -z "$expect" ] || expect="$(run_numbers_json "$expect")"
  require_tools
  load_config
  [ -n "$k" ] || k="$(config_get .run.max_parallel)"
  dir="$(repo_dir)"
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || die "$dir is not a git repository"
  # Nothing changes before these checks pass (spec "Có thay đổi chưa commit").
  run_clean_tree "$dir"
  unfinished="$(run_unfinished)"
  [ -z "$unfinished" ] || die "run $unfinished is not finished. Resume it with /scrum-github:run, or see it with: scrum run status $unfinished"

  repo="$(repo_slug)"
  login="$(whoami_login)"
  RUN_SEL="$(run_select "$repo" "$login" "$numbers")"
  if [ "$(printf '%s' "$RUN_SEL" | jq '.tasks | length')" = 0 ]; then
    print_run_plan >&2
    die "no task to run"
  fi
  # The run must be the plan the user confirmed (--expect, the skill always passes it).
  if [ -n "$expect" ]; then
    diff="$(printf '%s' "$RUN_SEL" | jq -r --argjson e "$expect" '([.tasks[].number] | sort) as $now | ($e | unique) as $want
      | if $now == $want then empty
        else "the tasks to run changed since the plan you confirmed: planned \($want | map("#\(.)") | join(", ")), now \($now | map("#\(.)") | join(", "))"
             + ([.excluded[] | select(.number as $x | $want | index($x)) | " (#\(.number): \(.reason))"] | join("")) end')"
    [ -z "$diff" ] || die "$diff. Nothing was changed; show the plan again: scrum run plan"
  fi

  default="$(ghx repo view "$repo" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)"
  [ -n "$default" ] || default="main"
  git -C "$dir" fetch -q origin "$default" 2>/dev/null \
    || warn "cannot fetch $default from origin; the integration branch starts from the copy of $default you already have"
  if git -C "$dir" rev-parse --verify -q "refs/remotes/origin/$default" >/dev/null; then base="origin/$default"
  elif git -C "$dir" rev-parse --verify -q "refs/heads/$default" >/dev/null; then base="$default"
  else die "cannot find the default branch $default (locally or on origin)"; fi

  now="$(now_iso)"
  id="$(printf '%s' "$now" | sed 's/^\([0-9]\{4\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\)T\([0-9]\{2\}\):\([0-9]\{2\}\).*/\1\2\3-\4\5/')-$login"
  [ ! -e "$(run_file "$id")" ] || die "a run $id already exists; wait a minute and start again"
  pattern="$(config_get .run.branch_pattern)"
  sprint_title="$(printf '%s' "$RUN_SEL" | jq -r '.sprint.title // ""')"
  branch="$(jq -rn -L "$JQ_LIB" --arg p "$pattern" --arg s "$sprint_title" --arg l "$login" --arg d "$(today)" \
    'include "scrum"; ($s | slug_text | if . == "" then "no-sprint" else . end) as $sl
     | $p | gsub("\\{sprint\\}"; $sl) | gsub("\\{login\\}"; $l) | gsub("\\{date\\}"; $d)')"
  git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "run.branch_pattern gives \"$branch\", which is not a valid branch name"
  [ "$branch" != "$default" ] || die "run.branch_pattern gives \"$branch\", the default branch; the integration branch must be another one"
  if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
    die "the branch $branch already exists. Delete it (git branch -D $branch) if its work is merged, or put {date} in run.branch_pattern"
  fi
  if git -C "$dir" rev-parse --verify -q "refs/remotes/origin/$branch" >/dev/null \
     && ! git -C "$dir" merge-base --is-ancestor "refs/remotes/origin/$branch" "$base" 2>/dev/null; then
    die "origin already has a branch $branch with other work; the run would overwrite it or fail to push. Delete it on origin if it is done, or put {date} in run.branch_pattern"
  fi
  # --no-track: the integration branch never has origin/<default> as its upstream, so a plain
  # git push from it cannot reach the default branch.
  git -C "$dir" checkout -q --no-track -b "$branch" "$base" || die "cannot create $branch from $base"
  base_sha="$(git -C "$dir" rev-parse HEAD)"
  info "Created the integration branch $branch from $base."

  mkdir -p "$(run_dir)"
  run_exclude_state "$dir"
  file="$(run_file "$id")"
  printf '%s' "$RUN_SEL" | jqlib run-state --arg op new --argjson strings "$(strings_json)" \
    --arg id "$id" --arg branch "$branch" --arg base "$default" --arg base_sha "$base_sha" --arg now "$now" --arg max_parallel "$k" \
    --arg pr_per_wave "$per_wave" --arg test_command "$(config_get .run.test_command)" --arg repo "$repo" \
    | jq '.state' | write_atomic "$file"
  info "Saved the run in .scrum/run/$id.json."

  # On GitHub, like task start: assign the tasks nobody has, then In progress (design 6).
  for n in $(printf '%s' "$RUN_SEL" | jq -r '.tasks[].number'); do
    issue="$(gh_get "repos/$repo/issues/$n")" || die "cannot read issue #$n"
    if [ "$(printf '%s' "$issue" | jq '[.assignees[]?] | length')" = 0 ]; then
      jq -n --arg l "$login" '{assignees: [$l]}' | gh_send POST "repos/$repo/issues/$n/assignees" >/dev/null
      info "Assigned #$n to $login."
    fi
    set_status "$repo" "$issue" in_progress
  done
  printf '%s' "$RUN_SEL" | jq -r --arg s "$(config_get .statuses.in_progress)" --arg id "$id" \
    '"Run \($id): \(.tasks | length) task\(if (.tasks | length) == 1 then "" else "s" end) in \(.waves | length) wave\(if (.waves | length) == 1 then "" else "s" end), now \($s): \(.tasks | map("#\(.number)") | join(", "))."'
}

# ---------- record ----------

# scrum run record N --started | --done --branch B [--notes FILE]
#                    | --failed (--reason R | --reason-file FILE | --notes FILE) [--run ID]
# --failed takes its reason from --reason, else from --reason-file, else from .reason of the
# --notes JSON: the skill never puts the agent's words on a command line.
cmd_run_record() {
  local usage="usage: scrum run record N --started | --done --branch B [--notes FILE] | --failed (--reason R | --reason-file FILE | --notes FILE) [--run ID]"
  local n="" what="" branch="" reason="" reason_file="" notes_file="" id="" notes repo body x st int base base_sha
  while [ $# -gt 0 ]; do
    case "$1" in
      --started) what="${what}started" ;;
      --done) what="${what}done" ;;
      --failed) what="${what}failed" ;;
      --branch) branch="$(run_optval --branch "${2:-}")"; shift ;;
      --reason) reason="$(run_optval --reason "${2:-}")"; shift ;;
      --reason-file) reason_file="$(run_optval --reason-file "${2:-}")"; shift ;;
      --notes) notes_file="$(run_optval --notes "${2:-}")"; shift ;;
      --run) id="$(run_optval --run "${2:-}")"; shift ;;
      -*) die "unknown option for run record: $1" ;;
      *) [ -z "$n" ] || die "$usage"; n="$(run_num "$1")" ;;
    esac
    shift
  done
  [ -n "$n" ] || die "$usage"
  case "$what" in started|done|failed) ;; *) die "$usage" ;; esac
  [ "$what" != "done" ] || [ -n "$branch" ] || die "--done needs --branch, the branch the agent worked on"
  if [ "$what" = failed ] && [ -z "$reason" ] && [ -n "$reason_file" ]; then reason="$(run_reason_from "$reason_file")"; fi
  if [ "$what" = failed ] && [ -z "$reason" ] && [ -n "$notes_file" ]; then reason="$(run_reason_from "$notes_file")"; fi
  [ "$what" != failed ] || [ -n "$reason" ] || die "--failed needs a reason: --reason, --reason-file, or --notes with a reason"
  notes="$(run_notes "$notes_file")"
  if [ "$what" = started ]; then require_tools nogh; else require_tools; fi
  load_config
  id="$(run_resolve "$id")"

  case "$what" in
    started)
      run_apply "$id" started --arg n "$n" --arg now "$(now_iso)"
      info "#$n is running (run $id)."
      ;;
    done)
      git -C "$(repo_dir)" rev-parse --verify -q "refs/heads/$branch" >/dev/null || die "there is no local branch $branch"
      # The branch must be the agent's: not the integration or default branch, and grown from
      # the commit the run started at.
      st="$(cat "$(run_file "$id")")"
      int="$(printf '%s' "$st" | jq -r .branch)"; base="$(printf '%s' "$st" | jq -r .base)"
      base_sha="$(printf '%s' "$st" | jq -r '.base_sha // empty')"
      if [ "$branch" = "$int" ] || [ "$branch" = "$base" ] || [ "$branch" = "origin/$base" ]; then
        die "$branch is the integration or default branch, not the branch the agent of #$n worked on"
      fi
      if [ -n "$base_sha" ] && ! git -C "$(repo_dir)" merge-base --is-ancestor "$base_sha" "refs/heads/$branch" 2>/dev/null; then
        die "the branch $branch does not start from the run's integration branch (it lacks $(printf '%s' "$base_sha" | cut -c1-12)); it is not the work of this run"
      fi
      run_apply "$id" "done" --arg n "$n" --arg now "$(now_iso)" --arg branch "$branch" --argjson notes "$notes"
      repo="$(jq -r .repo "$(run_file "$id")")"
      body="$(printf '%s' "$RUN_EFFECTS" | jq -r '.comment.body')"
      comment_issue "$repo" "$n" "$body" || warn "cannot post the actual time on #$n"
      info "#$n is done on $branch$(run_task "$id" "$n" | jq -r 'if .minutes == null then "" else " in \(.minutes) min" end'). Merge it: scrum run merge $n"
      ;;
    failed)
      run_apply "$id" failed --arg n "$n" --arg now "$(now_iso)" --arg reason "$reason" --argjson notes "$notes" \
        --arg status_new "$(config_get .statuses.new)"
      repo="$(jq -r .repo "$(run_file "$id")")"
      body="$(printf '%s' "$RUN_EFFECTS" | jq -r '.comment.body')"
      comment_issue "$repo" "$n" "$body" || warn "cannot post the reason on #$n"
      run_issue_to_new "$repo" "$n"
      info "#$n failed: $reason. It is back in $(config_get .statuses.new) and stays out of the pull request."
      for x in $(printf '%s' "$RUN_EFFECTS" | jq -r '.dropped[].number'); do
        body="$(printf '%s' "$RUN_EFFECTS" | jq -r --argjson x "$x" '.dropped[] | select(.number == $x) | .body')"
        comment_issue "$repo" "$x" "$body" || warn "cannot comment on #$x"
        run_issue_to_new "$repo" "$x"
        info "#$x is left out: it is blocked by #$n. It is back in $(config_get .statuses.new)."
      done
      ;;
  esac
}

# ---------- merge ----------

# scrum run merge N [--run ID]  (design 5; spec "Merge theo đợt")
cmd_run_merge() {
  local n="" id="" task dir int tbranch title before files log sha tip line reason
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) id="$(run_optval --run "${2:-}")"; shift ;;
      -*) die "unknown option for run merge: $1" ;;
      *) [ -z "$n" ] || die "usage: scrum run merge N [--run ID]"; n="$(run_num "$1")" ;;
    esac
    shift
  done
  [ -n "$n" ] || die "usage: scrum run merge N [--run ID]"
  require_tools nogh
  load_config
  id="$(run_resolve "$id")"
  task="$(run_task "$id" "$n")"
  [ "$task" != null ] || die "#$n is not a task of run $id"
  case "$(printf '%s' "$task" | jq -r .state)" in
    done|conflict) ;;
    *) die "#$n is $(printf '%s' "$task" | jq -r .state); only a task recorded as done can be merged" ;;
  esac
  tbranch="$(printf '%s' "$task" | jq -r .branch)"
  title="$(printf '%s' "$task" | jq -r .title)"
  int="$(jq -r .branch "$(run_file "$id")")"
  dir="$(repo_dir)"
  git -C "$dir" rev-parse --verify -q "refs/heads/$tbranch" >/dev/null || die "there is no local branch $tbranch for #$n"
  run_clean_tree "$dir"
  if [ "$(git -C "$dir" rev-parse --abbrev-ref HEAD)" != "$int" ]; then
    git -C "$dir" checkout -q "$int" || die "cannot check out the integration branch $int"
  fi
  before="$(git -C "$dir" rev-parse HEAD)"
  if [ "$(git -C "$dir" rev-list --count "$before..$tbranch")" = 0 ]; then
    # Already merged (for example the merge commit was made, then the command stopped): find the
    # merge commit whose second parent is the tip of the task branch, and record it.
    tip="$(git -C "$dir" rev-parse "$tbranch")"
    sha="$(git -C "$dir" rev-list --merges --parents "$tbranch..$before" | while read -r line; do
      set -- $line
      if [ "${3:-}" = "$tip" ]; then printf '%s' "$1"; break; fi
    done)"
    if [ -n "$sha" ]; then
      run_apply "$id" merged --arg n "$n" --arg now "$(now_iso)" --arg sha "$sha"
      info "#$n ($tbranch) is already merged into $int: $(git -C "$dir" rev-parse --short "$sha"). Recorded."
      return 0
    fi
    die "the branch $tbranch of #$n has no commit that $int does not have; nothing to merge. If the agent changed nothing: scrum run record $n --failed --reason \"no changes\""
  fi
  log="$(mktemp "${TMPDIR:-/tmp}/scrum-merge.XXXXXX")"
  if git -C "$dir" merge --no-ff -q -m "Merge #$n $title" "$tbranch" >"$log" 2>&1; then
    rm -f "$log"
    sha="$(git -C "$dir" rev-parse HEAD)"
    run_apply "$id" merged --arg n "$n" --arg now "$(now_iso)" --arg sha "$sha"
    info "Merged #$n ($tbranch) into $int: $(git -C "$dir" rev-parse --short HEAD)."
    return 0
  fi
  # Conflict (or any failure): undo the merge, so the integration branch stays as it was.
  files="$(git -C "$dir" diff --name-only --diff-filter=U 2>/dev/null || true)"
  git -C "$dir" merge --abort >/dev/null 2>&1 || git -C "$dir" reset -q --merge >/dev/null 2>&1 || true
  if [ "$(git -C "$dir" rev-parse HEAD)" != "$before" ]; then
    warn "$int moved during the merge; check it with: git log $int"
  fi
  if [ -n "$files" ]; then
    reason="merge conflict"
  else
    line="$(grep -v '^[[:space:]]*$' "$log" | head -1 | cut -c1-200)"
    reason="merge failed: ${line:-git merge failed}"
  fi
  run_apply "$id" conflict --arg n "$n" --arg now "$(now_iso)" --arg files "$files" --arg reason "$reason"
  {
    if [ -n "$files" ]; then
      printf 'scrum: error: merging #%s (%s) into %s conflicts in:\n' "$n" "$tbranch" "$int"
      printf '%s\n' "$files" | sed 's/^/  /'
      printf 'The merge was undone; %s is as it was. Either leave #%s out (scrum run record %s --failed --reason "merge conflict"),\n' "$int" "$n" "$n"
      printf 'or merge %s into %s, fix the conflict there, commit, and run: scrum run merge %s\n' "$int" "$tbranch" "$n"
    else
      printf 'scrum: error: merging #%s (%s) into %s failed:\n' "$n" "$tbranch" "$int"
      sed 's/^/  /' "$log"
      printf 'The merge was undone; %s is as it was. When git cannot sign the merge commit (commit.gpgsign) or a hook\n' "$int"
      printf 'refuses it, fix that and run: scrum run merge %s. Or leave #%s out (scrum run record %s --failed --reason "merge failed").\n' "$n" "$n" "$n"
    fi
  } >&2
  rm -f "$log"
  exit 1
}

# ---------- status ----------

# scrum run status [ID] [--json]  (spec "Chạy tiếp sau khi dừng")
cmd_run_status() {
  local id="" json=0 view
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      -*) die "unknown option for run status: $1" ;;
      *) id="$1" ;;
    esac
    shift
  done
  require_tools nogh
  load_config
  if [ -z "$id" ]; then
    id="$(run_unfinished)"
    [ -n "$id" ] || id="$(run_ids | head -1)"
    if [ -z "$id" ]; then
      if [ "$json" = 1 ]; then printf 'null\n'; else info "No run yet in .scrum/run. Start one with /scrum-github:run"; fi
      return 0
    fi
  fi
  [ -f "$(run_file "$id")" ] || die "there is no run $id in .scrum/run"
  view="$(jqlib run-state --arg op view --argjson strings '{}' < "$(run_file "$id")")"
  if [ "$json" = 1 ]; then printf '%s\n' "$view"; return 0; fi
  printf '%s' "$view" | jq -r '
    def mins: if .minutes == null then "" else "  (\(.minutes) min)" end;
    def why: if .reason == null then "" else ": \(.reason)" end;
    "Run \(.id) on \(.branch) (\(if .finished then "finished" else "not finished" end))\(if .sprint then ", \(.sprint.title)" else "" end)",
    (.waves[] | "", "Wave \(.wave):",
      (.tasks[] | "  #\(.number)  \(.state)  \(.title)\(mins)\(why)\(if (.conflict_files | length) > 0 then " in \(.conflict_files | join(", "))" else "" end)")),
    (if (.excluded | length) > 0 then "", "Left out at the start:", (.excluded[] | "  #\(.number)  \(.title // "?"): \(.reason)") else empty end),
    (if (.prs | length) > 0 then "", "Pull requests:", (.prs[] | "  #\(.number)\(if .wave then " (wave \(.wave))" else "" end)  \(.url // "")") else empty end),
    (if .finished or (.pr_due | length) == 0 then empty
     else "", "Next: open the pull request of wave \(.pr_due[0]): scrum run finish --wave \(.pr_due[0])" end),
    (if .finished or .next_wave != null or (.pr_due | length) > 0 then empty
     else "", "Next: every task is settled. Open the pull request: scrum run finish" end),
    (if .finished or .next_wave == null or (.pr_due | length) > 0 then empty
     else .next_wave as $nw | (.waves[] | select(.wave == $nw)) as $w
       | "", "Next: wave \($nw)"
         + (if ($w.to_run | length) > 0 then "; run \($w.to_run | map("#\(.)") | join(", "))" else "" end)
         + (if ($w.to_merge | length) > 0 then "; merge \($w.to_merge | map("#\(.)") | join(", "))" else "" end)
     end)'
}

# ---------- finish ----------

# scrum run finish [--wave W] [--run ID]  (design 7; spec "Một PR gói review", "Một PR mỗi đợt")
# Pushes the integration branch only (never the branch of a task) and opens the pull request.
# With --wave W the pull request holds the tasks of wave W: the integration branch at this point
# is pushed as <branch>-wave-W, based on the branch of the pull request of the wave before.
cmd_run_finish() {
  local id="" wave="" repo file st dir int waves pending merged n issue issues='{}' after=null base head pr body_file url number per_wave open_wave remote b on_origin=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --wave) wave="$(run_optval --wave "${2:-}")"; shift ;;
      --run) id="$(run_optval --run "${2:-}")"; shift ;;
      *) die "unknown option for run finish: $1" ;;
    esac
    shift
  done
  [ -z "$wave" ] || wave="$(run_count "$wave" --wave)"
  require_tools
  load_config
  id="$(run_resolve "$id")"
  file="$(run_file "$id")"
  st="$(cat "$file")"
  int="$(printf '%s' "$st" | jq -r .branch)"
  waves="$(printf '%s' "$st" | jq '.waves | length')"
  [ -z "$wave" ] || [ "$wave" -le "$waves" ] || die "run $id has $waves wave(s), not $wave"
  # One pull request per wave, never two for the same work.
  per_wave="$(printf '%s' "$st" | jq -r '.pr_per_wave')"
  if [ "$per_wave" = true ] && [ -z "$wave" ]; then
    die "run $id opens one pull request per wave. Use: scrum run finish --wave W$(printf '%s' "$st" | jq -r '[range(1; (.waves | length) + 1) as $w | select((.waves_closed // []) | index($w) | not) | $w] | if length > 0 then " (waves still without one: \(map(tostring) | join(", ")))" else "" end')"
  fi
  if [ "$per_wave" != true ] && [ -n "$wave" ]; then
    die "run $id opens one pull request for all its waves; use: scrum run finish (without --wave)"
  fi
  if [ -n "$wave" ]; then
    [ "$(printf '%s' "$st" | jq --argjson w "$wave" '(.waves_closed // []) | index($w) != null')" = false ] \
      || die "wave $wave of run $id is already closed$(printf '%s' "$st" | jq -r --argjson w "$wave" '[.prs[] | select(.wave == $w)] | if length > 0 then " (pull request #\(.[0].number))" else "" end')"
    open_wave="$(printf '%s' "$st" | jq -r --argjson w "$wave" '[range(1; $w) as $x | select((.waves_closed // []) | index($x) | not) | $x] | .[0] // empty')"
    [ -z "$open_wave" ] || die "wave $open_wave is not closed yet; first: scrum run finish --wave $open_wave"
  fi
  # Every task in the pull request's scope must be settled (merged, failed or left out) first.
  pending="$(printf '%s' "$st" | jq -r --arg w "$wave" '[.tasks[] | select($w == "" or .wave == ($w | tonumber))
    | select(.state != "merged" and .state != "failed" and .state != "excluded") | "#\(.number) (\(.state))"] | join(", ")')"
  [ -z "$pending" ] || die "not every task is settled: $pending. Merge each task that is done (scrum run merge N), or record it as failed, before finishing"
  merged="$(printf '%s' "$st" | jq -r --arg w "$wave" '[.tasks[] | select(.state == "merged" and ($w == "" or .wave == ($w | tonumber))) | .number] | sort | .[]')"
  if [ -z "$merged" ]; then
    info "No task of run $id${wave:+ in wave $wave} is merged, so nothing is pushed and no pull request is opened."
    if [ -n "$wave" ]; then run_apply "$id" wave_closed --arg wave "$wave" --arg now "$(now_iso)"
    else run_apply "$id" finish --arg now "$(now_iso)"; fi
    return 0
  fi
  repo="$(printf '%s' "$st" | jq -r .repo)"
  for n in $merged; do
    issue="$(gh_get "repos/$repo/issues/$n" 2>/dev/null)" || issue=""
    [ -n "$issue" ] || { warn "cannot read #$n; its acceptance criteria are left out of the description"; continue; }
    issues="$(printf '%s' "$issues" | jq -c --arg n "$n" --argjson i "$issue" '.[$n] = $i')"
  done

  base="$(printf '%s' "$st" | jq -r .base)"
  head="$int"
  if [ -n "$wave" ]; then
    head="$int-wave-$wave"
    after="$(printf '%s' "$st" | jq -c --argjson w "$wave" '[.prs[] | select(.wave != null and .wave < $w)] | sort_by(.wave) | .[-1] // null')"
    [ "$after" = null ] || base="$(printf '%s' "$after" | jq -r .head)"
  fi
  dir="$(repo_dir)"
  # Never push onto the default branch, nor over work on origin that is not in the local branch.
  if [ "$head" = "$base" ] || [ "$head" = "$(printf '%s' "$st" | jq -r .base)" ]; then
    die "$head is the base of the pull request; the run pushes only its integration branch"
  fi
  if [ "$head" != "$int" ]; then git -C "$dir" branch -f "$head" "$int" >/dev/null || die "cannot create $head"; fi
  git -C "$dir" fetch -q origin "refs/heads/$head:refs/remotes/origin/$head" >/dev/null 2>&1 || true
  if git -C "$dir" rev-parse --verify -q "refs/remotes/origin/$head" >/dev/null \
     && ! git -C "$dir" merge-base --is-ancestor "refs/remotes/origin/$head" "refs/heads/$head" 2>/dev/null; then
    die "origin/$head has commits that $head does not have; nothing was pushed. Look at them with: git log $head..origin/$head"
  fi
  # A task branch must never be on origin (spec "Không push nhánh task"): say so when one is.
  remote="$(git -C "$dir" ls-remote --heads origin 2>/dev/null | sed 's|.*refs/heads/||')" || remote=""
  for b in $(printf '%s' "$st" | jq -r '[.tasks[].branch | strings] | unique | .[]'); do
    if printf '%s\n' "$remote" | grep -qxF "$b"; then on_origin="$on_origin $b"; fi
  done
  [ -z "$on_origin" ] || warn "these task branches are on origin, though a run never pushes them:$on_origin. Check who pushed them, and delete them there if they are not wanted"
  pr="$(jqlib run-pr-body -n --argjson state "$st" --argjson issues "$issues" --argjson cfg "$CONFIG_JSON" \
    --argjson strings "$(strings_json)" --argjson wave "${wave:-null}" --argjson after "$after")"
  body_file="$(mktemp "${TMPDIR:-/tmp}/scrum-pr.XXXXXX")"
  printf '%s' "$pr" | jq -r .body > "$body_file"

  # Only the integration branch goes to the remote (spec "Không push nhánh task").
  git -C "$dir" push -q origin "refs/heads/$head:refs/heads/$head" || { rm -f "$body_file"; die "cannot push $head to origin"; }
  info "Pushed $head to origin."
  if ! url="$(ghx pr create --repo "$repo" --base "$base" --head "$head" --title "$(printf '%s' "$pr" | jq -r .title)" --body-file "$body_file")"; then
    die "pushed $head, but could not open the pull request. The description is in $body_file; open it with: gh pr create --base $base --head $head --body-file $body_file"
  fi
  rm -f "$body_file"
  url="$(printf '%s' "$url" | tail -1)"
  number="${url##*/}"
  case "$number" in ""|*[!0-9]*) number=null ;; esac
  run_apply "$id" pr --arg wave "$wave" --arg now "$(now_iso)" \
    --arg pr "$(jq -nc --argjson n "$number" --arg u "$url" --arg b "$base" --arg h "$head" '{number: $n, url: $u, base: $b, head: $h}')"
  info "Opened the pull request${wave:+ of wave $wave} into $base: $url"
  if [ "$after" != null ]; then info "It is based on #$(printf '%s' "$after" | jq -r .number) (wave $(printf '%s' "$after" | jq -r .wave)), which must be merged first."; fi
}
