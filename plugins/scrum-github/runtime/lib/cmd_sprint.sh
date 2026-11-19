# shellcheck shell=bash
# scrum sprint new | scrum sprint close

# create_sprint REPO MILESTONES ARGS_JSON -> prints the created milestone JSON
create_sprint() {
  local repo="$1" ms="$2" args="$3" plan err body
  plan="$(jqlib sprint-new-plan -n --argjson ms "$ms" --argjson cfg "$CONFIG_JSON" \
    --argjson args "$args" --arg today "$(today)")"
  err="$(printf '%s' "$plan" | jq -r '.error // empty')"
  [ -z "$err" ] || die "$err"
  printf '%s' "$plan" | jq -r '.warnings[] | "scrum: warning: " + .' >&2
  body="$(printf '%s' "$plan" | jq -c '{title, description, due_on, state: "open"}')"
  printf '%s' "$body" | gh_send POST "repos/$repo/milestones" \
    | jq -c --argjson p "$plan" '. + {_start: $p.start, _end: $p.end}'
}

cmd_sprint_new() {
  local title="" start="" length="" goal=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="${2:-}"; shift ;;
      --start) start="${2:-}"; shift ;;
      --length) length="${2:-}"; shift ;;
      --goal) goal="${2:-}"; shift ;;
      *) die "unknown option for sprint new: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  local repo ms args created
  repo="$(repo_slug)"
  ms="$(fetch_milestones "$repo")"
  args="$(jq -n --arg t "$title" --arg s "$start" --arg l "$length" --arg g "$goal" '{
    title: (if $t == "" then null else $t end),
    start: (if $s == "" then null else $s end),
    length: (if $l == "" then null else ($l | tonumber? // $l) end),
    goal: $g }')"
  created="$(create_sprint "$repo" "$ms" "$args")"
  printf '%s' "$created" | jq -r '"Created \(.title) (\(._start) to \(._end)): \(.html_url // "")"'
  # A hint only: if the backlog cannot be read, the sprint is still created.
  . "$SCRUM_ROOT/lib/cmd_backlog.sh"
  local waiting
  if waiting="$(backlog_count "$repo" 2>/dev/null)" && [ "${waiting:-0}" -gt 0 ]; then
    info "Next: choose tasks for $(printf '%s' "$created" | jq -r .title) from the backlog ($waiting waiting): /scrum-github:sprint-fill (or: scrum sprint fill)"
  fi
}

cmd_sprint_close() {
  local name="" yes=0 create_next=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes|-y) yes=1 ;;
      --create-next) create_next=1 ;;
      -*) die "unknown option for sprint close: $1" ;;
      *) name="$1" ;;
    esac
    shift
  done
  require_tools
  load_config
  local repo ms sprint number issues plan title
  repo="$(repo_slug)"
  ms="$(fetch_milestones "$repo")"
  sprint="$(resolve_sprint "$ms" "$name")"
  number="$(printf '%s' "$sprint" | jq -r .number)"
  title="$(printf '%s' "$sprint" | jq -r .title)"
  issues="$(fetch_milestone_issues "$repo" "$number")"
  plan="$(jqlib close-plan -n --argjson ms "$ms" --argjson cfg "$CONFIG_JSON" \
    --argjson sprint "$sprint" --argjson issues "$issues" --arg today "$(today)")"

  if [ "$(printf '%s' "$plan" | jq -r .already_closed)" = "true" ]; then
    info "$title is already closed. Nothing to do."
    return 0
  fi

  printf '%s' "$plan" | jq -r --argjson cfg "$CONFIG_JSON" '
    def pts: if . == null then "unestimated" else "\(.) pt\(if . == 1 then "" else "s" end)" end;
    "Closing \(.sprint.title) (\(.sprint.start) to \(.sprint.end))",
    "Velocity: \(.velocity) points from \(.done | length) done task\(if (.done | length) == 1 then "" else "s" end)"
      + (if (.unestimated_done | length) > 0 then " (\(.unestimated_done | length) done without points: \(.unestimated_done | map("#\(.)") | join(", ")))" else "" end),
    (if (.done | length) > 0 then "Done:", (.done[] | "  #\(.number) \(.title) (\(.points | pts))") else empty end),
    (if (.carry | length) > 0 then
       "Carry over to \(.next.title)\(if .next.exists then "" else " (does not exist yet; would be created: \(.next.start) to \(.next.end))" end):",
       (.carry[] | "  #\(.number) \(.title) (\(.points | pts), \($cfg.statuses[.status] // .status))")
     else "Nothing to carry over." end),
    (if (.dropped | length) > 0 then "Not planned (not counted): \(.dropped | map("#\(.)") | join(", "))" else empty end)'

  local carry_count next_exists next_title next_number
  carry_count="$(printf '%s' "$plan" | jq '.carry | length')"
  next_exists="$(printf '%s' "$plan" | jq -r '.next.exists')"
  next_title="$(printf '%s' "$plan" | jq -r '.next.title')"

  if [ "$yes" != 1 ]; then
    info ""
    if [ "$carry_count" -gt 0 ] && [ "$next_exists" != "true" ]; then
      info "Nothing changed. To apply, run again with --yes --create-next ($next_title will be created)."
    else
      info "Nothing changed. To apply, run again with --yes."
    fi
    return 0
  fi

  if [ "$carry_count" -gt 0 ] && [ "$next_exists" != "true" ] && [ "$create_next" != 1 ]; then
    die "$next_title does not exist yet. Run again with --create-next to create it, or create it first with: scrum sprint new"
  fi

  if [ "$carry_count" -gt 0 ]; then
    if [ "$next_exists" = "true" ]; then
      next_number="$(printf '%s' "$plan" | jq -r '.next.number')"
    else
      local args created
      args="$(printf '%s' "$plan" | jq -c --argjson cfg "$CONFIG_JSON" \
        '{title: .next.title, start: .next.start, length: $cfg.sprint.length_days, goal: ""}')"
      created="$(create_sprint "$repo" "$ms" "$args")"
      next_number="$(printf '%s' "$created" | jq -r .number)"
      info "Created $next_title."
    fi
    printf '%s' "$plan" | jq -r '.carry[].number' | while IFS= read -r n; do
      jq -n --argjson m "$next_number" '{milestone: $m}' | gh_send PATCH "repos/$repo/issues/$n" >/dev/null
      jq -n --arg t "$title" '{body: "Carried over from \($t)"}' | gh_send POST "repos/$repo/issues/$n/comments" >/dev/null
      info "Moved #$n to $next_title."
    done
  fi

  printf '%s' "$plan" | jq -c '{description, state: "closed"}' | gh_send PATCH "repos/$repo/milestones/$number" >/dev/null
  info "Closed $title. Velocity: $(printf '%s' "$plan" | jq -r .velocity) points."
  post_sprint_summary "$repo" "$ms" "$sprint" "$issues" "$plan" \
    || warn "the sprint summary was not posted on the digest issue; the sprint is closed"
}

# post_sprint_summary REPO MILESTONES SPRINT ISSUES PLAN  The summary as a comment on the
# sprint's digest issue. Every step returns 1 on failure: the caller only warns.
post_sprint_summary() {
  local repo="$1" ms="$2" sprint="$3" issues="$4" plan="$5" burndown body n
  . "$SCRUM_ROOT/lib/cmd_report.sh" || return 1
  . "$SCRUM_ROOT/lib/cmd_digest.sh" || return 1
  history_issues "$repo" "$sprint" "$issues" || return 1
  burndown="$(jqlib burndown -n --argjson cfg "$CONFIG_JSON" --argjson sprint "$sprint" --argjson issues "$HISSUES" \
    --arg today "$(today)" --argjson off "$(tz_offset)")" || return 1
  body="$(jqlib sprint-summary -n --argjson plan "$plan" --argjson ms "$ms" --argjson sprint "$sprint" \
    --argjson burndown "$burndown" --argjson strings "$(strings_json)" --argjson cfg "$CONFIG_JSON")" || return 1
  find_digest_issue "$repo" "$sprint" "$issues" || return 1
  n="$(printf '%s' "$DIGEST_ISSUE" | jq -r .number)" || return 1
  printf '%s' "$body" | jq -c '{body}' | gh_send POST "repos/$repo/issues/$n/comments" >/dev/null || return 1
  info "Posted the sprint summary on #$n."
}

# ---------- sprint fill ----------

cmd_sprint_fill() {
  local name="" capacity=null add="" yes=0 repo ms sprint issues plan title n add_json
  while [ $# -gt 0 ]; do
    case "$1" in
      --capacity) capacity="${2:-}"; shift
        case "$capacity" in ""|*[!0-9]*) die "--capacity needs a whole number of points" ;; esac ;;
      --add) add="$add,${2:-}"; shift ;;
      --yes|-y) yes=1 ;;
      -*) die "unknown option for sprint fill: $1" ;;
      *) name="$1" ;;
    esac
    shift
  done
  add_json="$(printf '%s' "$add" | tr ',' '\n' | sed 's/^#//; /^$/d' | jq -R -s -c 'split("\n") | map(select(. != "")) |
    map(if test("^[0-9]+$") then tonumber else error("not an issue number: \(.)") end) | unique')" \
    || die "--add takes issue numbers, for example --add 30,33"

  require_tools
  load_config
  repo="$(repo_slug)"
  ms="$(fetch_milestones "$repo")"
  sprint="$(resolve_sprint "$ms" "$name")"
  title="$(printf '%s' "$sprint" | jq -r .title)"
  [ "$(printf '%s' "$sprint" | jq -r .state)" = open ] || die "$title is closed"
  issues="$(fetch_milestone_issues "$repo" "$(printf '%s' "$sprint" | jq -r .number)")"
  . "$SCRUM_ROOT/lib/cmd_backlog.sh"
  fetch_backlog "$repo"
  plan="$(jqlib sprint-fill -n --argjson ms "$ms" --argjson sprint "$sprint" --argjson issues "$issues" \
    --argjson backlog "$BACKLOG" --argjson add "$add_json" --argjson capacity "$capacity" --argjson cfg "$CONFIG_JSON")"

  printf '%s' "$plan" | jq -r '
    "\(.sprint.title) (\(.sprint.start // "?") to \(.sprint.end // "?"))",
    ( if .capacity_source == "option" then "Capacity: \(.capacity) points (--capacity)"
      elif .capacity_source == "velocity" then "Capacity: \(.capacity) points (average velocity of \(.velocity.sprints | map("\(.title): \(.velocity)") | join(", ")))"
      else "Capacity: unknown: no closed sprint has recorded a velocity yet. Pass --capacity N to set one." end ),
    "Planned: \(.planned) points\(if .free == null then "" else "; free: \(.free) points" end)"'
  if [ "$add_json" = "[]" ]; then
    info ""
    print_backlog
    return 0
  fi
  printf '%s' "$plan" | jq -r '
    "", "To add:",
    (.adding.tasks[] | "  #\(.number)  \(if .points == null then "-" else "\(.points) pt" end)  \(.title)"),
    "After adding: \(.after)\(if .capacity == null then "" else " of \(.capacity)" end) points",
    (if (.warnings | length) > 0 then "", "Warnings:", (.warnings[] | "  - " + .) else empty end)'
  if [ "$(printf '%s' "$plan" | jq '.errors | length')" != 0 ]; then
    printf '%s' "$plan" | jq -r '.errors[] | "scrum: error: " + .' >&2
    die "nothing was changed"
  fi
  if [ "$yes" != 1 ]; then
    info ""; info "Nothing changed. To apply, run again with --yes."
    return 0
  fi
  info ""
  for n in $(printf '%s' "$plan" | jq -r '.adding.tasks[].number'); do
    jq -n --argjson m "$(printf '%s' "$sprint" | jq .number)" '{milestone: $m}' | gh_send PATCH "repos/$repo/issues/$n" >/dev/null
    comment_issue "$repo" "$n" "Moved from the backlog to $title."
    info "Added #$n to $title."
    project_touch "$repo" "$n"
  done
}
