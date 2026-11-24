# shellcheck shell=bash
# GitHub Projects (v2) board sync. Sourced by common.sh.
# The "status: ..." labels are the source of truth; the board's Status field mirrors them and can be
# changed on the board. The text field "Synced status" holds the status of the last sync, which tells
# which side changed. Decisions are pure jq (the project board section of lib/jq/scrum.jq).
#
# These functions never exit: they return 1 and leave a message in PROJECT_ERR, so the best-effort
# hooks can carry on. Callers check every return code (errexit does not apply inside `if`).

PROJECT_META=""
PROJECT_ERR=""

project_enabled() { [ "$(config_get .project.enabled)" = "true" ]; }

# Inside GitHub Actions the workflow token cannot reach Projects: a secret is needed.
project_token_ok() { [ "${GITHUB_ACTIONS:-}" != "true" ] || [ -n "${SCRUM_PROJECT_TOKEN:-}" ]; }

project_token_help() {
  printf 'Check the repository secret SCRUM_PROJECT_TOKEN: a valid, unexpired token with Projects read and write on %s and Issues read and write on this repository (a classic token needs the scopes "repo" and "project"). On your own machine run instead: gh auth refresh -s project' \
    "$(config_get .project.owner)"
}

pm() { printf '%s' "$PROJECT_META" | jq -r "$1"; }

# Field names for item queries. A field that does not exist reads as null, so "-" turns points off.
project_field_names() {
  PF_STATUS="$(config_get .project.status_field)"
  PF_SYNCED="$(config_get .project.synced_field)"
  PF_POINTS="$(config_get '.project.points_field // "-"')"
}

# Read the project and its fields into PROJECT_META (once per run).
project_load_meta() {
  [ -n "$PROJECT_META" ] && return 0
  local raw errf owner number meta
  owner="$(config_get .project.owner)"; number="$(config_get .project.number)"
  errf="$(mktemp "${TMPDIR:-/tmp}/scrum-gql.XXXXXX")"
  if ! raw="$(gh_graphql project -f owner="$owner" -F number="$number" 2>"$errf")"; then
    PROJECT_ERR="cannot read project #$number of $owner: $(head -3 "$errf" | tr '\n' ' ')"
    rm -f "$errf"; return 1
  fi
  rm -f "$errf"
  if ! meta="$(printf '%s' "$raw" | jqlib project-meta --argjson cfg "$CONFIG_JSON" 2>/dev/null)"; then
    PROJECT_ERR="unexpected answer from GitHub when reading project #$number of $owner"; return 1
  fi
  if [ "$(printf '%s' "$meta" | jq -r .found)" != "true" ]; then
    PROJECT_ERR="project #$number of $owner was not found, or the token cannot see it"; return 1
  fi
  PROJECT_META="$meta"
}

# The fields a sync needs exist and have the right type.
project_check_ready() {
  local problems
  problems="$(printf '%s' "$PROJECT_META" | jq -r --arg sf "$(config_get .project.status_field)" '
    (if .status_field == null then "the field \"\($sf)\" does not exist" else empty end),
    (.wrong_types[]),
    (.missing_options[] | "the board has no column \"\(.)\""),
    (if .synced_field == null and (.wrong_types | length) == 0 then "the bookkeeping text field does not exist" else empty end)')"
  if [ -n "$problems" ]; then
    PROJECT_ERR="the project is not ready: $(printf '%s' "$problems" | paste -sd ';' - | sed 's/;/; /g'). Run: scrum project init"
    return 1
  fi
}

# project_fetch_items REPO OUTFILE  All items of the board, normalized, into OUTFILE.
project_fetch_items() {
  local repo="$1" out="$2" pages page after="" id
  project_field_names
  id="$(pm .id)"
  pages="$(mktemp "${TMPDIR:-/tmp}/scrum-items.XXXXXX")"
  while :; do
    if [ -n "$after" ]; then
      page="$(gh_graphql items -f project="$id" -f status="$PF_STATUS" -f synced="$PF_SYNCED" -f points="$PF_POINTS" -f after="$after" 2>/dev/null)" \
        || { PROJECT_ERR="cannot read the items of the project"; rm -f "$pages"; return 1; }
    else
      page="$(gh_graphql items -f project="$id" -f status="$PF_STATUS" -f synced="$PF_SYNCED" -f points="$PF_POINTS" 2>/dev/null)" \
        || { PROJECT_ERR="cannot read the items of the project"; rm -f "$pages"; return 1; }
    fi
    printf '%s' "$page" | jq -c '.data.node.items.nodes // []' >> "$pages" \
      || { PROJECT_ERR="unexpected answer from GitHub when reading project items"; rm -f "$pages"; return 1; }
    [ "$(printf '%s' "$page" | jq -r '.data.node.items.pageInfo.hasNextPage // false')" = "true" ] || break
    after="$(printf '%s' "$page" | jq -r '.data.node.items.pageInfo.endCursor')"
  done
  jq -s 'add // []' "$pages" | jqlib project-items --arg repo "$repo" > "$out"
  rm -f "$pages"
}

# project_add_issue NODE_ID  Prints the new item id.
project_add_issue() {
  local res
  res="$(gh_graphql add-item -f project="$(pm .id)" -f content="$1" 2>/dev/null)" || return 1
  printf '%s' "$res" | jq -r '.data.addProjectV2ItemById.item.id // empty'
}

# project_apply OPS_FILE REPO [DRY]  Run the planned ops. Issue changes first (labels, then close or
# reopen), board fields after; an issue whose change failed gets no board update this time.
project_apply() {
  local ops="$1" repo="$2" dry="${3:-0}" rc=0 failed=" " line op n rest docs doc
  if [ "$dry" = 1 ]; then
    jq -r '.[] | select(.msg) | "  would: " + .msg' "$ops"
    return 0
  fi
  rest="$(mktemp "${TMPDIR:-/tmp}/scrum-ops.XXXXXX")"
  jq -c '.[] | select(.op == "set_labels" or .op == "close" or .op == "reopen" or .op == "comment")' "$ops" > "$rest"
  while IFS= read -r line; do
    op="$(printf '%s' "$line" | jq -r .op)"; n="$(printf '%s' "$line" | jq -r .number)"
    case "$failed" in *" $n "*) continue ;; esac
    if case "$op" in
         set_labels) printf '%s' "$line" | jq -c '{labels}' | ghp_send PUT "repos/$repo/issues/$n/labels" >/dev/null 2>&1 ;;
         close) printf '{"state":"closed","state_reason":"completed"}' | ghp_send PATCH "repos/$repo/issues/$n" >/dev/null 2>&1 ;;
         reopen) printf '{"state":"open"}' | ghp_send PATCH "repos/$repo/issues/$n" >/dev/null 2>&1 ;;
         comment) printf '%s' "$line" | jq -c '{body}' | ghp_send POST "repos/$repo/issues/$n/comments" >/dev/null 2>&1 ;;
       esac
    then
      info "  $(printf '%s' "$line" | jq -r .msg)"
    else
      warn "#$n: $op failed; the board is left as it is for now"
      failed="$failed$n "; rc=1
    fi
  done < "$rest"
  rm -f "$rest"

  docs="$(jq -c --arg failed "$failed" \
    '[.[] | select((.number | tostring) as $n | ($failed | contains(" " + $n + " ")) | not)]' "$ops" \
    | jqlib project-mutations --argjson meta "$PROJECT_META")"
  local count i=0 board_ok=1
  count="$(printf '%s' "$docs" | jq length)"
  while [ "$i" -lt "$count" ]; do
    doc="$(printf '%s' "$docs" | jq -r ".[$i]")"
    if ! ghp api graphql -f query="$doc" >/dev/null 2>&1; then board_ok=0; rc=1; fi
    i=$((i + 1))
  done
  if [ "$board_ok" = 1 ]; then
    jq -r --arg failed "$failed" '.[] | select(.op == "set_status" or .op == "set_points" or .op == "clear_points")
      | select((.number | tostring) as $n | ($failed | contains(" " + $n + " ")) | not) | "  " + .msg' "$ops"
  else
    warn "some board updates failed; the next sync will retry them"
  fi
  return "$rc"
}

# project_run_plan ITEMS_FILE REPO [DRY]  Plan, print warnings and apply.
project_run_plan() {
  local items="$1" repo="$2" dry="${3:-0}" plan ops
  plan="$(jqlib project-sync-plan --argjson cfg "$CONFIG_JSON" --argjson meta "$PROJECT_META" < "$items")" \
    || { PROJECT_ERR="cannot plan the sync"; return 1; }
  printf '%s' "$plan" | jq -r '.warnings[]' | while IFS= read -r w; do warn "$w"; done
  # shellcheck disable=SC2034  # read by cmd_project.sh
  PROJECT_CHANGED="$(printf '%s' "$plan" | jq '.changed | length')"
  # shellcheck disable=SC2034  # read by cmd_project.sh
  PROJECT_UNCHANGED="$(printf '%s' "$plan" | jq '.unchanged')"
  ops="$(mktemp "${TMPDIR:-/tmp}/scrum-ops.XXXXXX")"
  printf '%s' "$plan" | jq '.ops' > "$ops"
  if ! project_apply "$ops" "$repo" "$dry"; then
    rm -f "$ops"; PROJECT_ERR="some changes could not be applied"; return 1
  fi
  rm -f "$ops"
}

# project_sync_issue REPO NUMBER  Sync one issue; add it to the board when it is a task of an open sprint.
project_sync_issue() {
  local repo="$1" n="$2" raw item items
  project_load_meta || return 1
  project_check_ready || return 1
  project_field_names
  raw="$(gh_graphql issue-item -f owner="${repo%%/*}" -f name="${repo#*/}" -F number="$n" \
           -f status="$PF_STATUS" -f synced="$PF_SYNCED" -f points="$PF_POINTS" 2>/dev/null)" \
    || { PROJECT_ERR="cannot read #$n"; return 1; }
  item="$(printf '%s' "$raw" | jq -c --arg p "$(pm .id)" '
    .data.repository.issue as $i
    | if $i == null then null else
        ([$i.projectItems.nodes[]? | select(.project.id == $p)] | .[0]) as $it
        | (if $it then $it else {id: null, type: "ISSUE", status: null, synced: null, points: null} end)
          + {content: ($i | del(.projectItems))}
      end')" || { PROJECT_ERR="unexpected answer from GitHub for #$n"; return 1; }
  [ "$item" != "null" ] || { PROJECT_ERR="#$n was not found"; return 1; }

  if [ "$(printf '%s' "$item" | jq -r .id)" = "null" ]; then
    local addable node id
    addable="$(printf '%s' "$item" | jq -L "$JQ_LIB" -r --argjson cfg "$CONFIG_JSON" \
      'include "scrum"; normalize_item | is_task($cfg) and (is_not_planned | not) and (.milestone.state // "") == "OPEN"')"
    if [ "$addable" != "true" ]; then
      return 0
    fi
    node="$(printf '%s' "$item" | jq -r .content.id)"
    id="$(project_add_issue "$node")" && [ -n "$id" ] || { PROJECT_ERR="cannot add #$n to the board"; return 1; }
    info "  #$n: added to the board"
    item="$(printf '%s' "$item" | jq -c --arg id "$id" '.id = $id')"
  fi
  items="$(mktemp "${TMPDIR:-/tmp}/scrum-items.XXXXXX")"
  printf '[%s]' "$item" | jqlib project-items --arg repo "$repo" > "$items"
  project_run_plan "$items" "$repo" || { rm -f "$items"; return 1; }
  rm -f "$items"
}

# project_sync_all REPO [DRY]  Every item of the board, plus the tasks of open sprints not on it yet.
project_sync_all() {
  local repo="$1" dry="${2:-0}" items ms open issues missing line node id n added=0
  project_load_meta || return 1
  if [ "$dry" != 1 ]; then project_check_ready || return 1; fi
  items="$(mktemp "${TMPDIR:-/tmp}/scrum-items.XXXXXX")"
  project_fetch_items "$repo" "$items" || { rm -f "$items"; return 1; }

  # Tasks of open sprints that are not on the board yet.
  ms="$(fetch_milestones "$repo")" || { PROJECT_ERR="cannot read the sprints"; rm -f "$items"; return 1; }
  missing="$(mktemp "${TMPDIR:-/tmp}/scrum-missing.XXXXXX")"
  for open in $(printf '%s' "$ms" | jq -r '.[] | select(.state == "open") | .number'); do
    issues="$(fetch_milestone_issues "$repo" "$open")" || { PROJECT_ERR="cannot read the tasks of milestone $open"; rm -f "$items" "$missing"; return 1; }
    printf '%s' "$issues" | jq -L "$JQ_LIB" -c --argjson cfg "$CONFIG_JSON" --slurpfile have "$items" --arg repo "$repo" '
      include "scrum";
      ($have[0] | map(.number)) as $on
      | .[] | select(is_task($cfg) and (is_not_planned | not)) | select(.number as $n | $on | index($n) == null)
      | {item_id: null, node_id, number, repo: $repo, state, state_reason, labels: [.labels[]? | {name}],
         milestone: (.milestone | if . then {number, state: (.state | ascii_upcase)} else null end),
         board: null, synced: null, points: null}' >> "$missing"
  done
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="$(printf '%s' "$line" | jq -r .number)"
    if [ "$dry" = 1 ]; then
      info "  would: #$n: add to the board"
      line="$(printf '%s' "$line" | jq -c '.item_id = "(new)"')"
    else
      node="$(printf '%s' "$line" | jq -r .node_id)"
      if ! id="$(project_add_issue "$node")" || [ -z "$id" ]; then
        warn "#$n: cannot add it to the board"; continue
      fi
      info "  #$n: added to the board"
      line="$(printf '%s' "$line" | jq -c --arg id "$id" '.item_id = $id')"
    fi
    added=$((added + 1))
    jq -c --argjson x "$line" '. + [$x]' "$items" > "$items.new" && mv "$items.new" "$items"
  done < "$missing"
  rm -f "$missing"
  # shellcheck disable=SC2034  # read by cmd_project.sh
  PROJECT_ADDED="$added"

  project_run_plan "$items" "$repo" "$dry" || { rm -f "$items"; return 1; }
  rm -f "$items"
}

# project_touch REPO NUMBER  Best effort, for commands and workflows that just changed an issue.
# Never fails: the scheduled sync repairs whatever this could not do.
project_touch() {
  project_enabled || return 0
  if ! project_token_ok; then
    warn "#$2: the project board was not updated because SCRUM_PROJECT_TOKEN is not set; the scheduled sync will catch up"
    return 0
  fi
  if ! project_sync_issue "$1" "$2"; then
    warn "#$2: the project board was not updated ($PROJECT_ERR); the scheduled sync will catch up"
  fi
  return 0
}
