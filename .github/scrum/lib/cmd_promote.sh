# shellcheck shell=bash
# scrum promote (working branch -> staging) and scrum hotfix (fix from the release branch)
# (spec branch-promotion). Reuses the release helpers (cmd_release.sh): location_issues, the
# version and notes of release-plan.jq / release-notes.jq, and the version files.

# shellcheck source=cmd_release.sh
. "$SCRUM_ROOT/lib/cmd_release.sh"

PROMOTION_START='<!-- scrum-promotion -->'
PROMOTION_END='<!-- /scrum-promotion -->'

# ---------- promote ----------

# scrum promote [--json] [--yes]: environments only. The tasks on the working branch that staging
# does not contain yet; with --yes the pull request from the working branch into staging. The
# location labels change when it is merged (scrum event), not here.
cmd_promote() {
  local json=0 yes=0 repo working staging wsha st open issues contents plan title body pr
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --yes|-y) yes=1 ;;
      *) die "unknown option for promote: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  if [ "$(branch_role preset)" != environments ]; then
    die "the $(branch_role preset) preset has no staging branch, so there is nothing to promote. To publish what is on $(branch_role working), release it: /scrum-github:release"
  fi
  repo="$(repo_slug)"
  working="$(branch_role working)"
  staging="$(branch_role staging)"

  open="$(open_prs "$repo" "$working" "$staging")" || die "cannot read the open pull requests of $repo. Check: /scrum-github:doctor"
  if [ "$(printf '%s' "$open" | jq length)" -gt 0 ]; then
    if [ "$json" = 1 ]; then
      printf '%s' "$open" | jq -c --arg w "$working" --arg s "$staging" '{working: $w, staging: $s, open: .[0] | {number, title, url: .html_url}, nothing: false, tasks: []}'
    else
      info "A promotion is already open: $(printf '%s' "$open" | jq -r '.[0] | "#\(.number) \(.title): \(.html_url)"'). Merge it (or close it) before opening another one."
    fi
    return 0
  fi

  wsha="$(branch_sha "$repo" "$working" 2>/dev/null)" || wsha=""
  [ -n "$wsha" ] || die "cannot read the head of $working on GitHub. Does the branch exist? /scrum-github:protect creates it."
  st="$(ref_contains "$repo" "$wsha" "$staging")" || die "cannot compare $working with $staging. Check: /scrum-github:doctor"
  case "$st" in
    ahead|identical)
      if [ "$json" = 1 ]; then
        jq -nc --arg w "$working" --arg s "$staging" '{working: $w, staging: $s, open: null, nothing: true, tasks: []}'
      else
        info "Nothing to promote: $staging already contains the head of $working (${wsha:0:7})."
      fi
      return 0 ;;
  esac

  issues="$(location_issues "$repo")" || die "cannot read the tasks In review of $repo. Check: /scrum-github:doctor"
  contents="$(branch_contents "$repo" "$staging" "$issues" "$(jq -nc --arg w "$working" '[$w]')")"
  plan="$(printf '%s' "$issues" | jq -c --argjson c "$contents" --arg w "$working" --arg s "$staging" --arg sha "$wsha" '
    {working: $w, staging: $s, sha: $sha, open: null, nothing: false,
     tasks: [.[] | select(.number as $n | $c.missing | index($n)) | {number, title}] | sort_by(.number),
     unknown: $c.unknown, truncated: $c.truncated}')"
  title="$(jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum"; promotion_title($cfg)')"

  if [ "$json" != 1 ]; then
    printf '%s' "$plan" | jq -r '
      "Promote \(.working) (\(.sha[0:7])) to \(.staging):",
      (if (.tasks | length) == 0 then "  No task In review is waiting on \(.working); its other commits are promoted."
       else "Tasks on \(.working) that \(.staging) does not have yet (\(.tasks | length)):", (.tasks[] | "  #\(.number)  \(.title)") end),
      (if (.unknown | length) > 0 then "Not checked (pull requests or a comparison could not be read): \(.unknown | map("#\(.)") | join(", "))" else empty end)'
  fi
  if [ "$(printf '%s' "$plan" | jq -r .truncated)" = true ]; then warn "only the first $BRANCH_CONTENTS_LIMIT tasks In review were checked: the list is incomplete"; fi
  if [ "$yes" != 1 ]; then
    if [ "$json" = 1 ]; then printf '%s\n' "$plan"; else info ""; info "Nothing changed. To open the promotion pull request \"$title\", run again with --yes."; fi
    return 0
  fi

  body="$(printf '%s' "$plan" | jq -r --arg s "$PROMOTION_START" --arg e "$PROMOTION_END" '
    "Promotes \(.working) to \(.staging) for testing. When it is merged, the tasks below move to \"on: \(.staging)\" (computed from the commits, not from this list).\n\n\($s)\n"
    + (if (.tasks | length) == 0 then "No task In review: other commits only." else (.tasks | map("- #\(.number) \(.title)") | join("\n")) end)
    + "\n\($e)"')"
  pr="$(jq -nc --arg t "$title" --arg h "$working" --arg b "$staging" --arg body "$body" '{title: $t, head: $h, base: $b, body: $body}' \
    | gh_send POST "repos/$repo/pulls")" || die "could not open the promotion pull request. Nothing was changed."
  if [ "$json" = 1 ]; then
    printf '%s' "$plan" | jq -c --argjson p "$pr" '. + {pull_request: {number: $p.number, url: $p.html_url}}'
  else
    info "Opened the promotion #$(printf '%s' "$pr" | jq -r .number): $(printf '%s' "$pr" | jq -r '.html_url // ""')"
  fi
}

# ---------- hotfix ----------

# scrum hotfix N: standard and environments. For an open task: hotfix/N-<slug> from the remote
# head of the release branch, assigned to me when nobody has it, In progress.
cmd_hotfix() {
  local n="${1:-}" repo issue release branch login dir assigned
  n="${n#\#}"
  case "$n" in ""|*[!0-9]*) die "usage: scrum hotfix NUMBER | scrum hotfix prepare [--json] [--yes]" ;; esac
  [ $# -le 1 ] || die "usage: scrum hotfix NUMBER"
  require_tools
  load_config
  release="$(branch_role release)"
  if ! has_working_branch; then
    die "the trunk preset needs no hotfix branch: task start already branches from $release. Run /scrum-github:task-start $n"
  fi
  repo="$(repo_slug)"
  issue="$(gh_get "repos/$repo/issues/$n")" || die "cannot read issue #$n"
  if [ "$(printf '%s' "$issue" | jq 'has("pull_request")')" = true ]; then die "#$n is a pull request, not a task"; fi
  [ "$(printf '%s' "$issue" | jq -r .state)" = open ] || die "#$n is closed: a hotfix is for an open task. Reopen it first if production still needs the fix. Nothing was changed."
  branch="$(printf '%s' "$issue" | jq -r -L "$JQ_LIB" 'include "scrum"; hotfix_branch(.number; .title | slug)')"
  dir="$(repo_dir)"

  # Branch first: if git refuses (uncommitted changes, no remote), nothing on GitHub has changed.
  if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$dir" checkout -q "$branch" || die "cannot check out $branch"
    info "Checked out existing branch $branch."
  else
    git -C "$dir" fetch -q origin "$release" 2>/dev/null || die "cannot fetch $release from origin: a hotfix starts from the remote head of $release. Nothing was changed."
    git -C "$dir" rev-parse --verify -q "origin/$release" >/dev/null || die "origin/$release does not exist. Nothing was changed."
    git -C "$dir" checkout -q -b "$branch" "origin/$release" || die "cannot create $branch from origin/$release. Nothing was changed on GitHub."
    info "Created branch $branch from origin/$release."
  fi

  login="$(gh_get user | jq -r .login)"
  assigned="$(printf '%s' "$issue" | jq -r '[.assignees[]?.login] | join(", ")')"
  if [ -z "$assigned" ]; then
    jq -n --arg l "$login" '{assignees: [$l]}' | gh_send POST "repos/$repo/issues/$n/assignees" >/dev/null
    info "Assigned #$n to $login."
  elif ! printf '%s' "$issue" | jq -e --arg l "$login" 'any(.assignees[]?; .login == $l)' >/dev/null; then
    info "Note: #$n is assigned to $assigned; leaving the assignee as it is."
  fi
  set_status "$repo" "$issue" in_progress
  info "#$n $(printf '%s' "$issue" | jq -r .title) is now $(config_get .statuses.in_progress)."
  info "When the fix is ready: scrum hotfix prepare (version and files), then open the pull request into $release with \"Closes #$n\" (/scrum-github:task-pr)."
}

# scrum hotfix prepare [--json] [--yes]: on a hotfix/* branch. The version the hotfix publishes
# (the labels of its task, a patch for a bug, after the highest version tag on the release branch)
# and the marker line for the pull request body; with --yes the version files and the changelog are
# written in the working tree and committed (one local commit, never pushed).
cmd_hotfix_prepare() {
  local json=0 yes=0 dir cur n repo release vtags prev rc issue plan notes changes
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --yes|-y) yes=1 ;;
      *) die "unknown option for hotfix prepare: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  has_working_branch || die "the trunk preset has no hotfix branch: release with /scrum-github:release"
  dir="$(repo_dir)"
  cur="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" || die "not in a git repository"
  case "$cur" in hotfix/*) ;; *) die "the current branch is $cur, not a hotfix branch (hotfix/N-...). Start one with: scrum hotfix N" ;; esac
  n="${cur#hotfix/}"; n="${n%%-*}"
  case "$n" in ""|*[!0-9]*) die "cannot read the task number from $cur (expected hotfix/N-<slug>)" ;; esac
  repo="$(repo_slug)"
  release="$(branch_role release)"

  vtags="$(release_version_tags "$repo")" || die "cannot read the tags of $repo. Check: /scrum-github:doctor"
  rc=0; prev="$(release_latest_tag "$repo" "$release" "$vtags")" || rc=$?
  case "$rc" in
    0) ;;
    2) die "cannot tell the previous version: GitHub did not confirm that any version tag is on $release. Check: /scrum-github:doctor" ;;
    *) die "none of the version tags is on $release, so the previous version is unknown" ;;
  esac
  issue="$(gh_get "repos/$repo/issues/$n")" || die "cannot read issue #$n"
  plan="$(jqlib release-plan -n --argjson cfg "$CONFIG_JSON" --argjson prev "$prev" --argjson issues "[$issue]" \
    --argjson since null --argjson until null --arg version "" --argjson contained "[$n]")"
  [ "$(printf '%s' "$plan" | jq -r .nothing)" != true ] || die "#$n is not a task (it is a feature, epic, meta issue or pull request)"
  notes="$(jqlib release-notes -r -n --argjson plan "$plan" --argjson prs '{}' --argjson parents '{}' \
    --argjson strings "$(strings_json)" --arg repo "$repo")"
  # files: what --yes would commit on this branch, as `scrum release` lists it ("Committed on it").
  plan="$(printf '%s' "$plan" | jq -c --argjson n "$n" --arg notes "$notes" --arg b "$cur" --argjson cfg "$CONFIG_JSON" '
    {tag, version, previous: (.previous.tag // null), task: $n, marker: "<!-- scrum-release-tag: \(.tag) -->",
     bump, branch: $b, notes: $notes, previous_version: (.previous.version // null),
     files: ([$cfg.release.version_files[]?.path] + (if $cfg.release.changelog then [$cfg.release.changelog] else [] end))}')"

  if [ "$yes" != 1 ]; then
    if [ "$json" = 1 ]; then printf '%s\n' "$plan"; return 0; fi
    printf '%s' "$plan" | jq -r '
      "Hotfix #\(.task) on \(.branch): publishes \(.tag) (\(.bump); previous: \(.previous // "none")).",
      (if (.files | length) > 0 then "Committed on it with --yes: \(.files | join(", "))"
       else "Nothing to commit with --yes: no release.version_files or release.changelog is configured." end),
      "Put this line in the pull request description: \(.marker)", "", "Release notes:", "", .notes'
    info ""
    info "Nothing changed. To write the version files and the changelog and commit them here, run again with --yes."
    return 0
  fi

  changes="$(release_file_changes local "$dir" "$(printf '%s' "$plan" | jq -r '.previous_version // ""')" \
    "$(printf '%s' "$plan" | jq -r .version)" "$(printf '%s' "$plan" | jq -r .tag)" "$notes")"
  local p
  if [ "$changes" = '[]' ]; then
    [ "$json" = 1 ] || info "Nothing to commit: no version file or changelog is configured, or they already hold $(printf '%s' "$plan" | jq -r .tag)."
  else
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      mkdir -p "$(dirname "$dir/$p")"
      printf '%s' "$changes" | jq -j --arg p "$p" '.[] | select(.path == $p) | .content' > "$dir/$p"
      git -C "$dir" add -- "$p" || die "cannot stage $p"
    done <<PATHS
$(printf '%s' "$changes" | jq -r '.[].path')
PATHS
    git -C "$dir" commit -q -m "Release $(printf '%s' "$plan" | jq -r .tag)" -m "Hotfix #$n." >/dev/null || die "cannot commit the version files"
    [ "$json" = 1 ] || info "Committed $(printf '%s' "$changes" | jq -r 'map(.path) | join(", ")') on $cur (not pushed)."
  fi
  if [ "$json" = 1 ]; then
    printf '%s' "$plan" | jq -c --argjson f "$changes" '. + {committed: [$f[].path]}'
  else
    info "Put this line in the pull request description: $(printf '%s' "$plan" | jq -r .marker)"
  fi
}
