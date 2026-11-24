# shellcheck shell=bash
# scrum release: publish a version from the Done tasks (spec release). release-plan.jq picks the
# tasks and the version, release-notes.jq writes the notes; this file reads GitHub and, only
# with --yes, creates the tag and the GitHub Release. Also used by next (release_latest_tag).
# Presets with a working branch (spec release-pr, design 7): --yes opens the release pull request
# from release/<tag> instead, and `scrum release finish` (the release workflow) publishes it.

RELEASE_TAG_CHECKS=20        # version tags checked for being on the release branch, newest first
RELEASE_TIMELINE_LIMIT=100   # tasks whose closing pull requests are read (one call each)
RELEASE_PARENT_LIMIT=50      # parent features whose title is read (one call each)
RELEASES_JSON=""             # every release of the repository (drafts too); read on demand when empty

# uri TEXT  TEXT encoded for one segment of a URL path (a tag "release/1.2.0" -> release%2F1.2.0).
uri() { jq -rn --arg s "$1" '$s | @uri'; }

# gh_status_404 FILE / gh_status_403 FILE  True when the gh error in FILE is that HTTP status.
gh_status_404() { grep -q 'HTTP 404' "$1"; }
gh_status_403() { grep -q 'HTTP 403' "$1"; }

# release_version_tags REPO  The version tags (release.tag_prefix), highest first: [{name, version}].
release_version_tags() {
  local tags
  tags="$(gh_get_all "repos/$1/tags?per_page=100")" || return 1
  printf '%s' "$tags" | jq -c -L "$JQ_LIB" --arg p "$(config_get '.release.tag_prefix')" 'include "scrum"; version_tags($p)'
}

# release_list REPO  Every release, drafts included (GET releases/tags/{tag} does not return drafts).
release_list() { gh_get_all "repos/$1/releases?per_page=100"; }

# release_of_tag RELEASES TAG  "draft" or "published" when TAG has a release, else nothing.
release_of_tag() {
  printf '%s' "$1" | jq -r --arg t "$2" '[.[]? | select(.tag_name == $t)] | if length == 0 then empty
    elif any(.[]; .draft != true) then "published" else "draft" end'
}

# release_tag_on_branch REPO TAG BRANCH  {status, date} of the tag against the branch: status
# "ahead" or "identical" means the tag is on the branch; date is the tag's commit date. Fails
# when GitHub does not answer with a status.
release_tag_on_branch() {
  local out
  out="$(gh_get "repos/$1/compare/$(uri "$2")...$(uri "$3")" | jq -c '{status, date: .base_commit.commit.committer.date}')" || return 1
  [ "$(printf '%s' "$out" | jq -r '.status // empty')" != "" ] || return 1
  printf '%s' "$out"
}

# release_tag_time REPO TAG COMMIT_DATE  When the tag was made, the boundary between two releases
# (a task closed by the last merge, before the tag, belongs to that tag): the tagger date of an
# annotated tag, else the creation time of its release, else the commit date.
release_tag_time() {
  local repo="$1" tag="$2" t="" ref sha
  ref="$(gh_get "repos/$repo/git/ref/tags/$(uri "$tag")" 2>/dev/null)" || ref=""
  if [ "$(printf '%s' "$ref" | jq -r '.object.type // empty' 2>/dev/null)" = tag ]; then
    sha="$(printf '%s' "$ref" | jq -r '.object.sha // empty')"
    t="$(gh_get "repos/$repo/git/tags/$sha" 2>/dev/null | jq -r '.tagger.date // empty' 2>/dev/null)" || t=""
  fi
  if [ -z "$t" ]; then
    [ -n "$RELEASES_JSON" ] || RELEASES_JSON="$(release_list "$repo" 2>/dev/null)" || RELEASES_JSON='[]'
    t="$(printf '%s' "$RELEASES_JSON" | jq -r --arg n "$tag" '[.[]? | select(.tag_name == $n) | .created_at // empty] | .[0] // empty' 2>/dev/null)" || t=""
  fi
  printf '%s' "${t:-$3}"
}

# release_latest_tag REPO BRANCH VTAGS [BELOW]  The highest version tag on the branch, lower than
# the version BELOW ([X, Y, Z]) when given: {name, version, commit_date, date}, date being its
# release_tag_time. Prints null when there is no such version tag at all. Returns 2 when version
# tags exist but none could be confirmed on the branch because GitHub did not answer or the
# RELEASE_TAG_CHECKS cap was reached, and 3 when every one was compared and none is on the branch.
release_latest_tag() {
  local repo="$1" branch="$2" vtags="$3" below="${4:-null}" names name cmp failed=0 total
  names="$(printf '%s' "$vtags" | jq -r --argjson b "$below" '.[] | select($b == null or .version < $b) | .name')"
  total="$(printf '%s' "$vtags" | jq --argjson b "$below" '[.[] | select($b == null or .version < $b)] | length')"
  [ "$total" -gt 0 ] || { printf 'null'; return 0; }
  for name in $(printf '%s\n' "$names" | head -n "$RELEASE_TAG_CHECKS"); do
    if ! cmp="$(release_tag_on_branch "$repo" "$name" "$branch" 2>/dev/null)"; then failed=1; continue; fi
    case "$(printf '%s' "$cmp" | jq -r .status)" in
      ahead|identical)
        printf '%s' "$vtags" | jq -c --arg n "$name" --argjson c "$cmp" --arg t "$(release_tag_time "$repo" "$name" "$(printf '%s' "$cmp" | jq -r '.date // ""')")" \
          '[.[] | select(.name == $n) | . + {commit_date: $c.date, date: (if $t == "" then $c.date else $t end)}] | .[0]'
        return 0 ;;
    esac
  done
  printf 'null'
  if [ "$failed" = 1 ] || [ "$total" -gt "$RELEASE_TAG_CHECKS" ]; then return 2; fi
  return 3
}

# release_prs REPO NUMBERS...  {"N": [merged pull requests that closed it] | null (not read)}:
# from the timeline, else the pull request whose merge commit closed the task.
release_prs() {
  local repo="$1" n tl list sha map='{}'
  shift
  for n in "$@"; do
    list=null
    if tl="$(gh_get_all "repos/$repo/issues/$n/timeline?per_page=100" 2>/dev/null)"; then
      list="$(printf '%s' "$tl" | jq -c -L "$JQ_LIB" --arg r "$repo" --argjson n "$n" 'include "scrum"; timeline_prs($r; $n)' 2>/dev/null)" || list=null
      sha="$(printf '%s' "$tl" | jq -r -L "$JQ_LIB" 'include "scrum"; timeline_closing_commit // empty' 2>/dev/null)" || sha=""
      if [ "$list" = '[]' ] && [ -n "$sha" ]; then
        list="$(gh_get "repos/$repo/commits/$(uri "$sha")/pulls" 2>/dev/null \
          | jq -c -L "$JQ_LIB" --arg s "$sha" 'include "scrum"; merge_commit_prs($s)' 2>/dev/null)" || list='[]'
        [ -n "$list" ] || list='[]'
      fi
    fi
    map="$(printf '%s' "$map" | jq -c --arg k "$n" --argjson v "${list:-null}" '.[$k] = $v')"
  done
  printf '%s' "$map"
}

# release_parents REPO ISSUES NUMBERS...  {"N": title} of the parent features; titles come from
# ISSUES when there, else from GitHub. A parent that cannot be read is left out (shown as #N).
release_parents() {
  local repo="$1" issues="$2" n title map='{}'
  shift 2
  for n in "$@"; do
    title="$(printf '%s' "$issues" | jq -r --argjson n "$n" '[.[] | select(.number == $n) | .title] | .[0] // empty')"
    [ -n "$title" ] || title="$(gh_get "repos/$repo/issues/$n" 2>/dev/null | jq -r '.title // empty' 2>/dev/null)" || title=""
    [ -n "$title" ] || continue
    map="$(printf '%s' "$map" | jq -c --arg k "$n" --arg v "$title" '.[$k] = $v')"
  done
  printf '%s' "$map"
}

# say TEXT  A line for a person: on stdout, or on stderr with --json so stdout stays one JSON value.
say() { if [ "${RELEASE_JSON_OUT:-0}" = 1 ]; then printf '%s\n' "$*" >&2; else printf '%s\n' "$*"; fi; }

cmd_release() {
  local version="" since_tag="" sprints='[]' draft=false notes_file="" json=0 yes=0 a from=""
  # The command as typed, for "run the same command again" after a failure.
  RELEASE_CMD="scrum release"
  for a in "$@"; do RELEASE_CMD="$RELEASE_CMD $(printf '%q' "$a")"; done
  while [ $# -gt 0 ]; do
    case "$1" in
      --since) since_tag="${2:-}"; shift; [ -n "$since_tag" ] || die "--since needs a tag name" ;;
      --sprint) [ -n "${2:-}" ] || die "--sprint needs a sprint name"
        sprints="$(printf '%s' "$sprints" | jq -c --arg s "$2" '. + [$s]')"; shift ;;
      --draft) draft=true ;;
      --notes-file) notes_file="${2:-}"; shift; [ -f "$notes_file" ] || die "--notes-file: no file at ${notes_file:-(empty)}" ;;
      --from) from="${2:-}"; shift; [ -n "$from" ] || die "--from needs a branch, tag or commit" ;;
      --json) json=1 ;;
      --yes|-y) yes=1 ;;
      -*) die "unknown option for release: $1" ;;
      *) [ -z "$version" ] || die "release takes one VERSION (got $version and $1)"; version="$1" ;;
    esac
    shift
  done
  # --yes publishes what was previewed: the version is pinned, never worked out again.
  if [ "$yes" = 1 ] && [ -z "$version" ]; then
    die "--yes needs the version to publish. Run the preview first (scrum release, same options, without --yes), then run it again with its version: scrum release X.Y.Z ... --yes"
  fi
  RELEASE_JSON_OUT="$json"
  require_tools
  load_config
  local repo branch vtags prefix given existing="" prev since=null until=null rc
  repo="$(repo_slug)"
  prefix="$(config_get '.release.tag_prefix')"
  # The release branch of the preset (trunk: main), never the default branch (design 1).
  branch="$(branch_role release)"
  if has_working_branch; then
    [ "$sprints" = '[]' ] || die "--sprint is for preset trunk: with a working branch the release holds the In review tasks on $(release_start_branch), or up to --from REF"
    [ "$draft" = false ] || die "--draft is for preset trunk: with a working branch the release workflow publishes the GitHub Release when the release pull request is merged"
  else
    [ -z "$from" ] || die "--from is for presets with a working branch (branching.preset standard or environments); trunk releases the head of $branch"
  fi
  vtags="$(release_version_tags "$repo")" || die "cannot read the tags of $repo. Check: /scrum-github:doctor"
  RELEASES_JSON="$(release_list "$repo")" || die "cannot read the releases of $repo. Check: /scrum-github:doctor"

  # A version whose tag already exists: released (stop) or left by a run that failed after
  # creating the tag (create only the release, design 6).
  given="$(jq -nc -L "$JQ_LIB" --arg v "$version" --arg p "$prefix" 'include "scrum"; $v | semver_of($p)')"
  if [ "$given" != null ]; then
    existing="$(printf '%s' "$vtags" | jq -r --argjson g "$given" '[.[] | select(.version == $g) | .name] | .[0] // empty')"
  fi
  if [ -n "$existing" ] && has_working_branch; then
    die "tag $existing already exists: that version is published (or being published by the release workflow). Choose a greater version. Nothing was changed."
  fi
  if [ -n "$existing" ]; then
    release_stop_if_released "$existing" "$RELEASES_JSON"
    local cmp
    cmp="$(release_tag_on_branch "$repo" "$existing" "$branch")" || die "cannot compare tag $existing with $branch. Check: /scrum-github:doctor"
    case "$(printf '%s' "$cmp" | jq -r .status)" in
      ahead|identical) ;;
      *) die "tag $existing exists but is not on $branch (GitHub compares it as $(printf '%s' "$cmp" | jq -r .status)): it points to a commit outside $branch. Nothing was changed." ;;
    esac
    until="$(jq -nc --arg t "$(release_tag_time "$repo" "$existing" "$(printf '%s' "$cmp" | jq -r '.date // ""')")" 'if $t == "" then null else $t end')"
  fi

  if [ -n "$since_tag" ]; then
    local scmp
    prev="$(printf '%s' "$vtags" | jq -c --arg n "$since_tag" '[.[] | select(.name == $n)] | .[0]')"
    [ "$prev" != null ] || die "no version tag named $since_tag in $repo (version tags look like ${prefix}1.2.3)"
    scmp="$(release_tag_on_branch "$repo" "$since_tag" "$branch")" || die "cannot compare $since_tag with $branch"
    prev="$(printf '%s' "$prev" | jq -c --argjson c "$scmp" --arg t "$(release_tag_time "$repo" "$since_tag" "$(printf '%s' "$scmp" | jq -r '.date // ""')")" \
      '. + {commit_date: $c.date, date: (if $t == "" then $c.date else $t end)}')"
  else
    rc=0
    if [ -n "$existing" ]; then prev="$(release_latest_tag "$repo" "$branch" "$vtags" "$given")" || rc=$?
    else prev="$(release_latest_tag "$repo" "$branch" "$vtags")" || rc=$?; fi
    case "$rc" in
      0) ;;
      2) die "cannot tell the previous version: GitHub did not confirm that any of the version tags is on $branch (a comparison failed, or more than $RELEASE_TAG_CHECKS tags were checked). Name it with --since TAG." ;;
      *) die "none of the version tags is on $branch, so the previous version is unknown. Name it with --since TAG." ;;
    esac
  fi

  if has_working_branch; then
    release_pr_main "$repo" "$branch" "$prev" "$version" "$json" "$yes" "$from" "$notes_file"
    return
  fi

  # The tasks: those of the named sprints, or those closed since the previous tag (design 2).
  local issues ms s q list
  if [ "$sprints" != '[]' ]; then
    ms="$(fetch_milestones "$repo")" || die "cannot read the sprints (milestones) of $repo. Check: /scrum-github:doctor"
    issues='[]'
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      q="$(resolve_sprint "$ms" "$s")" || exit 1
      list="$(fetch_milestone_issues "$repo" "$(printf '%s' "$q" | jq -r .number)")" || die "cannot read the tasks of $s. Check: /scrum-github:doctor"
      issues="$(jq -nc --argjson a "$issues" --argjson b "$list" '$a + $b')"
    done <<EOF
$(printf '%s' "$sprints" | jq -r '.[]')
EOF
  else
    since="$(printf '%s' "$prev" | jq -c '.date // null')"
    if [ "$since" = null ]; then
      issues="$(gh_get_all "repos/$repo/issues?state=closed&per_page=100")"
    else
      issues="$(gh_get_all "repos/$repo/issues?state=closed&since=$(printf '%s' "$since" | jq -r .)&per_page=100")"
    fi
  fi

  local plan
  plan="$(jqlib release-plan -n --argjson cfg "$CONFIG_JSON" --argjson prev "$prev" --argjson issues "$issues" \
    --argjson since "$since" --argjson until "$until" --arg version "$version")"
  if [ -n "$existing" ]; then plan="$(printf '%s' "$plan" | jq -c --arg t "$existing" '.tag = $t | .tag_exists = true')"
  else plan="$(printf '%s' "$plan" | jq -c '.tag_exists = false')"; fi
  [ "$(printf '%s' "$plan" | jq -r '.error // empty')" = "" ] || die "$(printf '%s' "$plan" | jq -r .error). Nothing was changed."
  # A release for the new tag may exist without the tag: a draft names a tag that is not created yet.
  release_stop_if_released "$(printf '%s' "$plan" | jq -r .tag)" "$RELEASES_JSON"

  if [ "$(printf '%s' "$plan" | jq -r .nothing)" = true ]; then
    if [ "$json" = 1 ]; then printf '%s\n' "$plan"; return 0; fi
    if [ "$sprints" != '[]' ]; then
      info "Nothing to release: $(printf '%s' "$sprints" | jq -r 'join(", ")') $(printf '%s' "$sprints" | jq -r 'if length == 1 then "has" else "have" end') no Done task."
    elif [ "$prev" = null ]; then
      info "Nothing to release: no task has been completed yet."
    else
      info "Nothing to release: no task was completed since $(printf '%s' "$prev" | jq -r .name)."
    fi
    return 0
  fi

  # Pull requests (capped, design 3) and parent feature titles, then the notes.
  local nums parents prs notes
  nums="$(printf '%s' "$plan" | jq -r --argjson max "$RELEASE_TIMELINE_LIMIT" '.tasks[:$max][] | .number')"
  # shellcheck disable=SC2086  # one number per word
  prs="$(release_prs "$repo" $nums)"
  nums="$(printf '%s' "$plan" | jq -r --argjson max "$RELEASE_PARENT_LIMIT" '[.tasks[] | select(.kind == "feature") | .parent | numbers] | unique | .[:$max][]')"
  # shellcheck disable=SC2086
  parents="$(release_parents "$repo" "$issues" $nums)"
  if [ -n "$notes_file" ]; then
    notes="$(cat "$notes_file")"
  else
    notes="$(jqlib release-notes -r -n --argjson plan "$plan" --argjson prs "$prs" --argjson parents "$parents" \
      --argjson strings "$(strings_json)" --arg repo "$repo")"
  fi
  plan="$(printf '%s' "$plan" | jq -c --argjson prs "$prs" --argjson parents "$parents" --arg notes "$notes" \
    --argjson draft "$draft" --arg branch "$branch" '
    .tasks |= map(. + {prs: $prs[.number | tostring], parent_title: (if .parent == null then null else $parents[.parent | tostring] end)})
    | . + {notes: $notes, draft: $draft, branch: $branch}')"

  if [ "$json" = 1 ]; then
    # With --yes the one JSON value is printed after publishing, with the result.
    [ "$yes" = 1 ] || printf '%s\n' "$plan"
  else
    printf '%s' "$plan" | jq -r '
      def nums: map("#\(.)") | join(", ");
      (if .previous == null then "Previous version: none (no version tag on \(.branch) yet)"
       else "Previous version: \(.previous.tag)\(if .previous.date then " (\(.previous.date[0:10]))" else "" end)" end),
      "New version: \(.tag)\(if .draft then " (draft)" else "" end): " + (
        if .bump == "first" then "the first release (release.first_version)"
        elif .bump == "major" then "major, breaking change in \(.reasons.breaking | nums)"
        elif .bump == "minor" then "minor, new in \(.reasons.features | nums) (not bugs)"
        elif .bump == "patch" then "patch, only bug fixes"
        else "given (suggested: \(.suggested))" end),
      (if .tag_exists then "Tag \(.tag) already exists (from an earlier run); --yes creates only its release." else empty end),
      "Tasks (\(.tasks | length)):",
      (.tasks[] | "  #\(.number)  \(.kind)  \(.title)"
        + (if .prs == null then "  (pull requests not read)" elif (.prs | length) > 0 then "  PR \(.prs | nums)" else "" end)),
      "", "Release notes:", "", .notes'
  fi

  if [ "$yes" != 1 ]; then
    [ "$json" = 1 ] || { info ""; info "Nothing changed. To publish $(printf '%s' "$plan" | jq -r .tag), run again with $(printf '%s' "$plan" | jq -r .version) and --yes."; }
    return 0
  fi
  release_publish "$repo" "$plan"
}

# release_stop_if_released TAG RELEASES  Stops when TAG already has a release (a draft too).
release_stop_if_released() {
  case "$(release_of_tag "$2" "$1")" in
    published) die "$1 is already released. Nothing was changed." ;;
    draft) die "$1 is already released as a draft: publish or delete the draft on GitHub. Nothing was changed." ;;
  esac
}

# release_publish REPO PLAN  The only writes (design 6): the annotated tag on the head
# of the default branch, its ref, then the GitHub Release. A tag left by an earlier run is kept.
release_publish() {
  local repo="$1" plan="$2" tag branch sha obj url err rerun hint created=false rels
  tag="$(printf '%s' "$plan" | jq -r .tag)"
  branch="$(printf '%s' "$plan" | jq -r .branch)"
  rerun="the same command again, with the same options: $RELEASE_CMD"
  hint="the token needs contents: write on $repo. Check: /scrum-github:doctor"
  err="$(mktemp "${TMPDIR:-/tmp}/scrum-release.XXXXXX")"
  # Read again right before writing: a release (or a draft) made since the preview stops here.
  rels="$(release_list "$repo" 2>"$err")" || { rm -f "$err"; die "cannot read the releases of $repo. Check: /scrum-github:doctor. Nothing was changed."; }
  release_stop_if_released "$tag" "$rels"
  if [ "$(printf '%s' "$plan" | jq -r .tag_exists)" != true ]; then
    if gh_get "repos/$repo/git/ref/tags/$(uri "$tag")" >/dev/null 2>"$err"; then
      rm -f "$err"; die "tag $tag already exists on GitHub but was not among the version tags read. Nothing was changed; run $rerun"
    fi
    gh_status_404 "$err" || { rm -f "$err"; die "cannot check whether tag $tag exists. Check: /scrum-github:doctor"; }
    sha="$(gh_get "repos/$repo/git/ref/heads/$(uri "$branch")" | jq -r '.object.sha // empty')" || sha=""
    [ -n "$sha" ] || { rm -f "$err"; die "cannot read the head commit of $branch"; }
    if ! obj="$(jq -nc --arg t "$tag" --arg s "$sha" '{tag: $t, message: "Release \($t)", object: $s, type: "commit"}' \
        | gh_send POST "repos/$repo/git/tags" 2>"$err" | jq -r '.sha // empty')" || [ -z "$obj" ]; then
      if gh_status_403 "$err"; then
        rm -f "$err"; die "GitHub refused to create tag $tag (403): $hint. Nothing was changed."
      fi
      rm -f "$err"; die "could not create tag $tag. Nothing was changed."
    fi
    if ! jq -nc --arg r "refs/tags/$tag" --arg s "$obj" '{ref: $r, sha: $s}' | gh_send POST "repos/$repo/git/refs" >/dev/null 2>"$err"; then
      local why=""
      if gh_status_403 "$err"; then why=" (403: $hint)"; fi
      rm -f "$err"
      die "could not create the ref of tag $tag$why. GitHub keeps the tag object it made, but no ref points to it, so there is no tag $tag yet (the object is harmless). Nothing changed on $branch. Run $rerun"
    fi
    created=true
    say "Created tag $tag on $branch (${sha:0:7})."
  fi
  if ! url="$(printf '%s' "$plan" | jq -c '{tag_name: .tag, name: .tag, body: .notes, draft: .draft}' \
      | gh_send POST "repos/$repo/releases" 2>"$err" | jq -r '.html_url // empty')"; then
    local why=""
    if gh_status_403 "$err"; then why=" (403: $hint)"; fi
    rm -f "$err"
    die "tag $tag exists on GitHub, but its release was not created$why. Run $rerun: it creates only the release and leaves the tag as it is."
  fi
  rm -f "$err"
  if [ "$(printf '%s' "$plan" | jq -r .draft)" = true ]; then
    say "Created the draft release $tag: $url"
  else
    say "Published release $tag: $url"
  fi
  if [ "${RELEASE_JSON_OUT:-0}" = 1 ]; then
    printf '%s' "$plan" | jq -c --arg u "$url" --argjson c "$created" '. + {published: {tag: .tag, url: $u, draft: .draft, tag_created: $c}}'
  fi
}


# ---------- presets with a working branch (spec release-pr, design 7 and 8) ----------

RELEASE_NOTES_START='<!-- scrum-release-notes -->'
RELEASE_NOTES_END='<!-- /scrum-release-notes -->'
RELEASE_UNTASKED_LIMIT=100   # merged pull requests into the working branch read for "Other" (one call)

# release_start_branch  The branch a release starts from: staging in environments, else the
# working branch (release_source_branch in scrum.jq).
release_start_branch() {
  jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum"; release_source_branch($cfg)'
}

# path_uri PATH  A path inside the repository for a URL: each segment encoded, the slashes kept.
path_uri() { jq -rn --arg s "$1" '$s | split("/") | map(@uri) | join("/")'; }

# location_issues REPO  The open issues with a location label ("on: <branch>" of each lower
# long-lived branch), one list. Fails when GitHub cannot be read.
location_issues() {
  local repo="$1" label list all='[]'
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    list="$(gh_get_all "repos/$repo/issues?state=open&labels=$(uri "$label")&per_page=100")" || return 1
    all="$(jq -nc --argjson a "$all" --argjson b "$list" '$a + $b | unique_by(.number)')"
  done <<LABELS
$(jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum"; location_labels($cfg)[]')
LABELS
  printf '%s' "$all"
}

# release_untasked_prs REPO PREV_TAG START_SHA  [{number, title}] of the merged pull requests into
# the working branch that link no task and whose merge commit is in PREV_TAG...START_SHA (spec
# release-pr "Pull requests without a task"). The commits come from one compare (GitHub lists up
# to 250), or, before the first release, from the latest 100 commits of START_SHA; the pull
# requests are the RELEASE_UNTASKED_LIMIT closed ones into the working branch updated last (one
# call), not one call per commit. Release, promotion and back-merge pull requests are left out.
release_untasked_prs() {
  local repo="$1" prev="$2" sha="$3" working commits prs
  working="$(branch_role working)"
  if [ -n "$prev" ]; then
    commits="$(gh_get "repos/$repo/compare/$(uri "$prev")...$(uri "$sha")" | jq -c '[.commits[]?.sha]')" || return 1
  else
    commits="$(gh_get "repos/$repo/commits?sha=$(uri "$sha")&per_page=100" | jq -c '[.[]?.sha]')" || return 1
  fi
  prs="$(gh_get "repos/$repo/pulls?state=closed&base=$(uri "$working")&sort=updated&direction=desc&per_page=$RELEASE_UNTASKED_LIMIT")" || return 1
  printf '%s' "$prs" | jq -c -L "$JQ_LIB" --argjson c "$commits" --argjson cfg "$CONFIG_JSON" --arg r "$repo" 'include "scrum";
    [.[]? | select(.merged_at != null and (.merge_commit_sha as $s | $c | index($s)) != null)
     | select(((.body // "") | closing_refs($r) | length) == 0)
     | select(pr_kind($cfg; .head.ref; .base.ref) == "task")
     | {number, title}] | unique_by(.number)'
}

# release_contained_plan REPO REF SHA PREV VERSION [EXTRA_ISSUES]  The release plan
# (release-plan.jq) of the In review tasks that SHA contains, plus the untasked pull requests;
# EXTRA_ISSUES (a JSON list) are tasks taken as they are (those a hotfix closes). Prints the plan
# with .contents (branch_contents) and ._issues (the issues read).
release_contained_plan() {
  local repo="$1" ref="$2" sha="$3" prev="$4" version="$5" extra="${6:-[]}" issues contents contained other prevname
  issues="$(location_issues "$repo")" || die "cannot read the tasks In review of $repo. Check: /scrum-github:doctor"
  contents="$(branch_contents "$repo" "$sha" "$issues")"
  contained="$(printf '%s' "$contents" | jq -c --argjson x "$extra" '.contained + [$x[].number] | unique')"
  issues="$(jq -nc --argjson a "$issues" --argjson b "$extra" '$a + $b | unique_by(.number)')"
  prevname="$(printf '%s' "$prev" | jq -r '.name // empty')"
  if ! other="$(release_untasked_prs "$repo" "$prevname" "$sha" 2>/dev/null)"; then
    warn "cannot read the merged pull requests of $ref: those that link no task are not listed under Other"
    other='[]'
  fi
  jqlib release-plan -n --argjson cfg "$CONFIG_JSON" --argjson prev "$prev" --argjson issues "$issues" \
    --argjson since null --argjson until null --arg version "$version" --argjson contained "$contained" --argjson other "$other" \
    | jq -c --argjson c "$contents" --argjson i "$issues" '. + {contents: $c, _issues: $i}'
}

# release_notes_of REPO PLAN [NOTES_FILE]  Adds prs, parent_title and notes to a contained plan.
release_notes_of() {
  local repo="$1" plan="$2" notes_file="${3:-}" prs parents nums notes
  prs="$(printf '%s' "$plan" | jq -c '.contents.prs // {} | map_values(map(.number))')"
  nums="$(printf '%s' "$plan" | jq -r --argjson max "$RELEASE_PARENT_LIMIT" '[.tasks[] | select(.kind == "feature") | .parent | numbers] | unique | .[:$max][]')"
  # shellcheck disable=SC2086  # one number per word
  parents="$(release_parents "$repo" "$(printf '%s' "$plan" | jq -c '._issues // []')" $nums)"
  if [ -n "$notes_file" ]; then
    notes="$(cat "$notes_file")"
  else
    notes="$(jqlib release-notes -r -n --argjson plan "$plan" --argjson prs "$prs" --argjson parents "$parents" \
      --argjson strings "$(strings_json)" --arg repo "$repo")"
  fi
  printf '%s' "$plan" | jq -c --argjson prs "$prs" --argjson parents "$parents" --arg notes "$notes" '
    .tasks |= map(. + {prs: $prs[.number | tostring], parent_title: (if .parent == null then null else $parents[.parent | tostring] end)})
    | . + {notes: $notes} | del(._issues)'
}

# release_pr_main REPO RELEASE_BRANCH PREV VERSION JSON YES FROM NOTES_FILE  scrum release with a
# working branch: the preview, and with --yes the release branch and its pull request.
release_pr_main() {
  local repo="$1" branch="$2" prev="$3" version="$4" json="$5" yes="$6" from="$7" notes_file="$8"
  local open ref sha plan unknown
  open="$(open_prs_matching "$repo" release/ "$branch")" || die "cannot read the open pull requests of $repo. Check: /scrum-github:doctor"
  if [ "$(printf '%s' "$open" | jq length)" -gt 0 ]; then
    die "a release pull request is already open: $(printf '%s' "$open" | jq -r '.[0] | "#\(.number) \(.title) (\(.head) into \(.base)): \(.html_url)"'). Merge or close it first. Nothing was changed."
  fi
  if [ -n "$from" ]; then
    ref="$from"
    sha="$(gh_get "repos/$repo/commits/$(uri "$from")" 2>/dev/null | jq -r '.sha // empty')" || sha=""
    [ -n "$sha" ] || die "cannot find $from on GitHub (a branch, tag or commit pushed to $repo). Nothing was changed."
  else
    ref="$(release_start_branch)"
    sha="$(branch_sha "$repo" "$ref" 2>/dev/null)" || sha=""
    [ -n "$sha" ] || die "cannot read the head of $ref on GitHub. Does the branch exist? /scrum-github:protect creates it. Nothing was changed."
  fi

  plan="$(release_contained_plan "$repo" "$ref" "$sha" "$prev" "$version")"
  [ "$(printf '%s' "$plan" | jq -r '.error // empty')" = "" ] || die "$(printf '%s' "$plan" | jq -r .error). Nothing was changed."
  plan="$(printf '%s' "$plan" | jq -c '.tag_exists = false')"
  release_stop_if_released "$(printf '%s' "$plan" | jq -r .tag)" "$RELEASES_JSON"
  unknown="$(printf '%s' "$plan" | jq -r '.contents.unknown | map("#\(.)") | join(", ")')"
  [ -z "$unknown" ] || warn "cannot tell whether $ref contains $unknown (their pull requests or a comparison could not be read): left out of this release"
  if [ "$(printf '%s' "$plan" | jq -r .contents.truncated)" = true ]; then
    warn "only $(printf '%s' "$plan" | jq -r .contents.limit) of the $(printf '%s' "$plan" | jq -r .contents.total) tasks In review were checked: the list is incomplete"
  fi

  if [ "$(printf '%s' "$plan" | jq -r .nothing)" = true ]; then
    if [ "$json" = 1 ]; then printf '%s' "$plan" | jq -c '. + {mode: "pull_request"} | del(._issues)'; return 0; fi
    info "Nothing to release: no task In review is on $ref and no pull request without a task was merged$(printf '%s' "$prev" | jq -r 'if . == null then "" else " since \(.name)" end'). Nothing was created."
    return 0
  fi

  plan="$(release_notes_of "$repo" "$plan" "$notes_file")"
  plan="$(printf '%s' "$plan" | jq -c --arg branch "$branch" --arg ref "$ref" --arg sha "$sha" --argjson cfg "$CONFIG_JSON" '
    . + {branch: $branch, draft: false, mode: "pull_request", start: {ref: $ref, sha: $sha},
         release_branch: "release/\(.tag)", unknown: .contents.unknown,
         files: ([$cfg.release.version_files[]?.path] + (if $cfg.release.changelog then [$cfg.release.changelog] else [] end))}')"

  if [ "$json" = 1 ]; then
    [ "$yes" = 1 ] || printf '%s\n' "$plan"
  else
    printf '%s' "$plan" | jq -r '
      def nums: map("#\(.)") | join(", ");
      (if .previous == null then "Previous version: none (no version tag on \(.branch) yet)"
       else "Previous version: \(.previous.tag)\(if .previous.date then " (\(.previous.date[0:10]))" else "" end)" end),
      "New version: \(.tag): " + (
        if .bump == "first" then "the first release (release.first_version)"
        elif .bump == "major" then "major, breaking change in \(.reasons.breaking | nums)"
        elif .bump == "minor" then "minor, new in \(.reasons.features | nums) (not bugs)"
        elif .bump == "patch" then (if (.tasks | length) == 0 then "patch, only pull requests without a task" else "patch, only bug fixes" end)
        else "given (suggested: \(.suggested))" end),
      "Release pull request: \(.release_branch) from \(.start.ref) (\(.start.sha[0:7])) into \(.branch)",
      (if (.files | length) > 0 then "Committed on it: \(.files | join(", "))" else empty end),
      "Tasks (\(.tasks | length)):",
      (.tasks[] | "  #\(.number)  \(.kind)  \(.title)"
        + (if .prs == null then "  (pull requests not read)" elif (.prs | length) > 0 then "  PR \(.prs | nums)" else "" end)),
      (if (.other | length) > 0 then "Pull requests without a task (\(.other | length)):", (.other[] | "  #\(.number)  \(.title)") else empty end),
      "", "Release notes:", "", .notes'
  fi

  if [ "$yes" != 1 ]; then
    [ "$json" = 1 ] || { info ""; info "Nothing changed. To open the release pull request of $(printf '%s' "$plan" | jq -r .tag), run again with $(printf '%s' "$plan" | jq -r .version) and --yes."; }
    return 0
  fi
  release_open_pr "$repo" "$plan"
}

# version_file_change PATH PATTERN PREV VERSION B64  {path, status: changed | current | missing,
# content} of one entry of release.version_files, whose text is B64 (base64).
version_file_change() {
  local path="$1" pattern="$2" prev="$3" version="$4" b64="$5" res
  if [ -z "$pattern" ]; then
    res="$(jqlib version-files -n --arg step json --arg version "$version" --arg b64 "$b64")"
    if [ "$(printf '%s' "$res" | jq -r .status)" = changed ]; then
      printf '%s' "$res" | jq --indent 2 .object | jq -Rsc --arg p "$path" '{path: $p, status: "changed", content: .}'
      return 0
    fi
  else
    res="$(jqlib version-files -n --arg step pattern --arg pattern "$pattern" --arg prev "$prev" --arg version "$version" --arg b64 "$b64")"
  fi
  printf '%s' "$res" | jq -c --arg p "$path" '{path: $p, status, content}'
}

# release_file_source MODE SOURCE PATH  Prints the text of PATH in base64 (no newlines): MODE
# remote reads it through the contents API (SOURCE OWNER/NAME@SHA), MODE local from a working tree
# (SOURCE its directory). Returns 4 when the file does not exist, 1 when it cannot be read.
release_file_source() {
  local mode="$1" src="$2" path="$3" raw err
  if [ "$mode" = local ]; then
    [ -f "$src/$path" ] || return 4
    base64 < "$src/$path" | tr -d '\n'
    return 0
  fi
  err="$(mktemp "${TMPDIR:-/tmp}/scrum-release.XXXXXX")"
  if ! raw="$(gh_get "repos/${src%@*}/contents/$(path_uri "$path")?ref=${src##*@}" 2>"$err")"; then
    if gh_status_404 "$err"; then rm -f "$err"; return 4; fi
    rm -f "$err"; return 1
  fi
  rm -f "$err"
  printf '%s' "$raw" | jq -r '.content // ""' | tr -d '\n'
}

# release_file_changes MODE SOURCE PREV VERSION TAG NOTES  The new text of every configured version
# file and of the changelog (MODE and SOURCE as release_file_source): [{path, content}] of those
# that change. Dies, naming the file, when a version file is missing or has no version to replace,
# before anything is written.
release_file_changes() {
  local mode="$1" src="$2" prev="$3" version="$4" tag="$5" notes="$6" out='[]' f path pattern res cl args rc where=""
  [ "$mode" = local ] || where=" at ${src##*@}"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    path="$(printf '%s' "$f" | jq -r .path)"
    pattern="$(printf '%s' "$f" | jq -r '.pattern // ""')"
    rc=0; args="$(release_file_source "$mode" "$src" "$path")" || rc=$?
    case "$rc" in
      0) ;;
      4) die "release.version_files: $path does not exist$where. Nothing was changed." ;;
      *) die "cannot read $path$where. Check: /scrum-github:doctor. Nothing was changed." ;;
    esac
    res="$(version_file_change "$path" "$pattern" "$prev" "$version" "$args")"
    case "$(printf '%s' "$res" | jq -r .status)" in
      changed) out="$(printf '%s' "$out" | jq -c --argjson r "$res" '. + [$r | {path, content}]')" ;;
      current) ;;
      *) if [ -n "$pattern" ]; then
           die "release.version_files: $path has no version to replace (nothing matches \"$pattern\" with ${prev:-a version X.Y.Z})$where. Fix the file or the pattern in .github/scrum.yml. Nothing was changed."
         fi
         die "release.version_files: $path has no version to replace (no top-level \"version\" in the JSON)$where. Nothing was changed." ;;
    esac
  done <<FILES
$(config_get '.release.version_files // [] | .[] | tojson')
FILES
  cl="$(config_get '.release.changelog // ""')"
  if [ -n "$cl" ]; then
    rc=0; args="$(release_file_source "$mode" "$src" "$cl")" || rc=$?
    case "$rc" in
      0) ;;
      4) args="" ;;   # a new changelog
      *) die "cannot read $cl$where. Nothing was changed." ;;
    esac
    res="$(jqlib version-files -n --arg step changelog --arg tag "$tag" --arg date "$(today)" --arg notes "$notes" --arg b64 "$args")"
    if [ "$(printf '%s' "$res" | jq -r .status)" = changed ]; then
      out="$(printf '%s' "$out" | jq -c --argjson r "$res" --arg p "$cl" '. + [{path: $p, content: $r.content}]')"
    fi
  fi
  printf '%s' "$out"
}

# release_open_pr REPO PLAN  The writes of --yes with a working branch, in order: the version files
# checked (nothing is created when one has no version), branch release/<tag> at the start commit,
# one commit with the version files and the changelog (none when neither is configured), then the
# pull request into the release branch. Never the tag or the GitHub Release (release finish does
# that). A branch left by an earlier run is reused as it is.
release_open_pr() {
  local repo="$1" plan="$2" tag version branch rbranch sha prev changes open head base_tree tree="" commit="" body pr err
  tag="$(printf '%s' "$plan" | jq -r .tag)"
  version="$(printf '%s' "$plan" | jq -r .version)"
  branch="$(printf '%s' "$plan" | jq -r .branch)"
  rbranch="$(printf '%s' "$plan" | jq -r .release_branch)"
  sha="$(printf '%s' "$plan" | jq -r .start.sha)"
  prev="$(printf '%s' "$plan" | jq -r '.previous.version // ""')"

  changes="$(release_file_changes remote "$repo@$sha" "$prev" "$version" "$tag" "$(printf '%s' "$plan" | jq -r .notes)")"
  # Read again right before writing: a release pull request opened since the preview stops here.
  open="$(open_prs_matching "$repo" release/ "$branch")" || die "cannot read the open pull requests of $repo. Nothing was changed."
  if [ "$(printf '%s' "$open" | jq length)" -gt 0 ]; then
    die "a release pull request is already open: $(printf '%s' "$open" | jq -r '.[0] | "#\(.number): \(.html_url)"'). Nothing was changed."
  fi

  err="$(mktemp "${TMPDIR:-/tmp}/scrum-release.XXXXXX")"
  if branch_exists "$repo" "$rbranch"; then
    head="$(branch_sha "$repo" "$rbranch")" || head=""
    say "Branch $rbranch already exists (${head:0:7}, from an earlier run): kept as it is."
  else
    if ! jq -nc --arg r "refs/heads/$rbranch" --arg s "$sha" '{ref: $r, sha: $s}' | gh_send POST "repos/$repo/git/refs" >/dev/null 2>"$err"; then
      local why=""
      if gh_status_403 "$err"; then why=" (403: the token needs contents: write on $repo. Check: /scrum-github:doctor)"; fi
      rm -f "$err"; die "could not create branch $rbranch$why. Nothing was changed."
    fi
    head="$sha"
    say "Created branch $rbranch at ${sha:0:7} ($(printf '%s' "$plan" | jq -r .start.ref))."
  fi

  if [ "$changes" != '[]' ] && [ "$head" = "$sha" ]; then
    base_tree="$(gh_get "repos/$repo/git/commits/$sha" 2>"$err" | jq -r '.tree.sha // empty')" || base_tree=""
    if [ -n "$base_tree" ]; then
      tree="$(printf '%s' "$changes" | jq -c --arg b "$base_tree" '{base_tree: $b, tree: map({path, mode: "100644", type: "blob", content})}' \
        | gh_send POST "repos/$repo/git/trees" 2>"$err" | jq -r '.sha // empty')" || tree=""
    fi
    if [ -n "$tree" ]; then
      commit="$(jq -nc --arg m "Release $tag" --arg t "$tree" --arg p "$sha" '{message: $m, tree: $t, parents: [$p]}' \
        | gh_send POST "repos/$repo/git/commits" 2>"$err" | jq -r '.sha // empty')" || commit=""
    fi
    if [ -z "$commit" ] || ! jq -nc --arg s "$commit" '{sha: $s, force: false}' \
        | gh_send PATCH "repos/$repo/git/refs/heads/$(uri "$rbranch")" >/dev/null 2>"$err"; then
      rm -f "$err"; die "could not commit the version files on $rbranch, which exists without them. Delete the branch on GitHub and run the same command again."
    fi
    say "Committed $(printf '%s' "$changes" | jq -r 'map(.path) | join(", ")') on $rbranch (${commit:0:7})."
  fi

  body="$(printf '%s' "$plan" | jq -r --arg s "$RELEASE_NOTES_START" --arg e "$RELEASE_NOTES_END" '
    "Merging this pull request publishes \(.tag): the release workflow (scrum-release.yml) tags the merge commit, creates the GitHub Release with the notes below, sets the tasks Done and opens the back-merge pull requests.\n\n\($s)\n\(.notes)\n\($e)"')"
  if ! pr="$(jq -nc --arg t "Release $tag" --arg h "$rbranch" --arg b "$branch" --arg body "$body" '{title: $t, head: $h, base: $b, body: $body}' \
      | gh_send POST "repos/$repo/pulls" 2>"$err")"; then
    rm -f "$err"; die "branch $rbranch exists, but its pull request was not opened. Run the same command again: it reuses the branch."
  fi
  rm -f "$err"
  say "Opened the release pull request #$(printf '%s' "$pr" | jq -r .number): $(printf '%s' "$pr" | jq -r '.html_url // ""')"
  say "Merging it into $branch publishes $tag (tag, GitHub Release, tasks Done, back-merge)."
  if [ "${RELEASE_JSON_OUT:-0}" = 1 ]; then
    printf '%s' "$plan" | jq -c --argjson p "$pr" --argjson f "$changes" '. + {pull_request: {number: $p.number, url: $p.html_url}, committed: [$f[].path]}'
  fi
}

# ---------- scrum release finish (spec release-pr "Publishing on merge", design 7, 8) ----------

# release_finish_publish REPO TAG SHA NOTES  The annotated tag on SHA and the GitHub Release. Each
# is checked first: a tag with a release is "already published" and nothing is changed; a tag
# left without its release by an earlier run gets only the release.
release_finish_publish() {
  local repo="$1" tag="$2" sha="$3" notes="$4" rels state obj url err
  err="$(mktemp "${TMPDIR:-/tmp}/scrum-release.XXXXXX")"
  rels="$(release_list "$repo" 2>"$err")" || { rm -f "$err"; die "cannot read the releases of $repo"; }
  state="$(release_of_tag "$rels" "$tag")"
  if gh_get "repos/$repo/git/ref/tags/$(uri "$tag")" >/dev/null 2>"$err"; then
    if [ -n "$state" ]; then
      rm -f "$err"; info "$tag is already published (its tag and GitHub Release exist): left as they are."; return 0
    fi
    info "Tag $tag already exists (from an earlier run): creating only its GitHub Release."
  else
    gh_status_404 "$err" || { rm -f "$err"; die "cannot check whether tag $tag exists"; }
    if ! obj="$(jq -nc --arg t "$tag" --arg s "$sha" '{tag: $t, message: "Release \($t)", object: $s, type: "commit"}' \
        | gh_send POST "repos/$repo/git/tags" 2>"$err" | jq -r '.sha // empty')" || [ -z "$obj" ]; then
      rm -f "$err"; die "could not create tag $tag (the workflow needs permissions: contents: write)"
    fi
    if ! jq -nc --arg r "refs/tags/$tag" --arg s "$obj" '{ref: $r, sha: $s}' | gh_send POST "repos/$repo/git/refs" >/dev/null 2>"$err"; then
      rm -f "$err"; die "could not create the ref of tag $tag. Re-run the workflow: it creates what is missing."
    fi
    info "Created tag $tag on the merge commit ${sha:0:7}."
  fi
  if [ -n "$state" ]; then
    rm -f "$err"; info "$tag already has a GitHub Release ($state): left as it is."; return 0
  fi
  if ! url="$(jq -nc --arg t "$tag" --arg b "$notes" '{tag_name: $t, name: $t, body: $b, draft: false}' \
      | gh_send POST "repos/$repo/releases" 2>"$err" | jq -r '.html_url // empty')"; then
    rm -f "$err"; die "tag $tag exists, but its GitHub Release was not created. Re-run the workflow: it creates only the release."
  fi
  rm -f "$err"
  info "Published release $tag: $url"
}

# release_finish_done REPO N  Task #N: Done, no location label, closed as completed. Changes only
# what is not so yet.
release_finish_done() {
  local repo="$1" n="$2" issue res changed=0
  if ! issue="$(gh_get "repos/$repo/issues/$n" 2>/dev/null)" || [ -z "$issue" ]; then warn "cannot read #$n; skipped"; return 0; fi
  if [ "$(printf '%s' "$issue" | jq 'has("pull_request")')" = true ]; then return 0; fi
  res="$(printf '%s' "$issue" | jq -c -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum";
    label_names as $old
    | (.labels = (labels_with_status($cfg; "done") | map({name: .}))) | labels_with_location($cfg; null) as $new
    | {labels: $new, changed: (($new | sort) != ($old | sort))}')"
  if [ "$(printf '%s' "$res" | jq -r .changed)" = true ]; then
    printf '%s' "$res" | jq -c '{labels}' | gh_send PUT "repos/$repo/issues/$n/labels" >/dev/null || { warn "could not set the labels of #$n"; return 0; }
    changed=1
  fi
  if [ "$(printf '%s' "$issue" | jq -r .state)" = open ]; then
    printf '{"state":"closed","state_reason":"completed"}' | gh_send PATCH "repos/$repo/issues/$n" >/dev/null || { warn "could not close #$n"; return 0; }
    changed=1
  fi
  if [ "$changed" = 1 ]; then
    info "#$n: $(config_get .statuses.done), closed as completed."
    project_touch "$repo" "$n"
  else
    info "#$n: already $(config_get .statuses.done)."
  fi
}

# release_back_merge REPO TAG  For each lower long-lived branch (the highest first) that does not
# contain the head of the release branch: a pull request from the release branch into it, unless
# one is open (design 8).
release_back_merge() {
  local repo="$1" tag="$2" rel head b st open title body pr
  rel="$(branch_role release)"
  head="$(branch_sha "$repo" "$rel" 2>/dev/null)" || head=""
  [ -n "$head" ] || { warn "cannot read the head of $rel: no back-merge pull request opened"; return 0; }
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    if ! st="$(ref_contains "$repo" "$head" "$b")"; then warn "cannot compare $b with $rel: no back-merge into $b"; continue; fi
    case "$st" in ahead|identical) info "$b already contains $rel: no back-merge needed."; continue ;; esac
    if ! open="$(open_prs "$repo" "$rel" "$b")"; then warn "cannot read the open pull requests into $b: no back-merge into $b"; continue; fi
    if [ "$(printf '%s' "$open" | jq length)" -gt 0 ]; then
      info "A back-merge into $b is already open: $(printf '%s' "$open" | jq -r '.[0] | "#\(.number) \(.html_url)"')"
      continue
    fi
    title="$(jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --arg b "$b" 'include "scrum"; back_merge_title($cfg; $b)')"
    body="Brings $rel${tag:+ ($tag)} back into $b, so that $b holds everything released and the next release starts from it.

Merge it with a **merge commit**, not squash or rebase: a squash breaks the history between the branches and the next release would conflict.

This pull request was opened by the release workflow, and GitHub does not start other workflows for it, so its required checks have not run yet: close and reopen it to run them."
    if pr="$(jq -nc --arg t "$title" --arg h "$rel" --arg b "$b" --arg body "$body" '{title: $t, head: $h, base: $b, body: $body}' \
        | gh_send POST "repos/$repo/pulls" 2>/dev/null)"; then
      info "Opened the back-merge #$(printf '%s' "$pr" | jq -r .number) into $b: $(printf '%s' "$pr" | jq -r '.html_url // ""')"
    else
      warn "could not open the back-merge pull request from $rel into $b: open it by hand and merge it with a merge commit"
    fi
  done <<BRANCHES
$(jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum"; branching($cfg).lower | reverse[]')
BRANCHES
}

# scrum release finish [--pr N]: after a release (release/*) or hotfix (hotfix/*) pull request is
# merged into the release branch. Reads the pull_request event ($GITHUB_EVENT_PATH) or, with
# --pr N, that pull request. Every step checks first, so running it again changes nothing.
cmd_release_finish() {
  local num="" pr ev repo head base kind sha body tag="" notes nums n plan prev=null vtags given extra='[]' links issue
  while [ $# -gt 0 ]; do
    case "$1" in
      --pr) num="${2:-}"; num="${num#\#}"; shift
        case "$num" in ""|*[!0-9]*) die "--pr needs a pull request number" ;; esac ;;
      *) die "unknown option for release finish: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  repo="$(repo_slug)"
  if [ -n "$num" ]; then
    pr="$(gh_get "repos/$repo/pulls/$num")" || die "cannot read pull request #$num"
  else
    ev="${GITHUB_EVENT_PATH:-}"
    [ -n "$ev" ] && [ -f "$ev" ] || die "GITHUB_EVENT_PATH is not set: this runs in the release workflow. Outside it, name the pull request: scrum release finish --pr N"
    pr="$(jq -c '.pull_request // empty' "$ev")"
    [ -n "$pr" ] || die "the event has no pull request"
  fi
  num="$(printf '%s' "$pr" | jq -r .number)"
  if [ "$(printf '%s' "$pr" | jq -r '.merged == true or .merged_at != null')" != true ]; then
    info "Pull request #$num was closed without merging: nothing to publish, task statuses unchanged."
    return 0
  fi
  head="$(printf '%s' "$pr" | jq -r .head.ref)"
  base="$(printf '%s' "$pr" | jq -r .base.ref)"
  kind="$(jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --arg h "$head" --arg b "$base" 'include "scrum"; pr_kind($cfg; $h; $b)')"
  case "$kind" in
    release|hotfix) ;;
    *) info "Pull request #$num ($head into $base) is not a release or hotfix pull request into $(branch_role release): nothing to do."; return 0 ;;
  esac
  sha="$(printf '%s' "$pr" | jq -r '.merge_commit_sha // empty')"
  [ -n "$sha" ] || die "pull request #$num has no merge commit"
  body="$(printf '%s' "$pr" | jq -r '.body // ""')"
  if [ "$kind" = release ]; then
    tag="${head#release/}"
  else
    tag="$(printf '%s' "$pr" | jq -r '[(.body // "") | capture("<!--\\s*scrum-release-tag:\\s*(?<t>[^\\s>]+)\\s*-->")] | .[0].t // empty')"
    # The tasks a hotfix closes are part of it even when they are not In review on a branch.
    links="$(jqlib links -n --arg body "$body" --arg repo "$repo" | jq -r '.issues[]')"
    for n in $links; do
      issue="$(gh_get "repos/$repo/issues/$n" 2>/dev/null)" || continue
      extra="$(printf '%s' "$extra" | jq -c --argjson i "$issue" '. + [$i]')"
    done
  fi
  if [ -n "$tag" ]; then
    given="$(jq -nc -L "$JQ_LIB" --arg v "$tag" --arg p "$(config_get '.release.tag_prefix')" 'include "scrum"; $v | semver_of($p)')"
    if [ "$given" != null ] && vtags="$(release_version_tags "$repo" 2>/dev/null)"; then
      prev="$(release_latest_tag "$repo" "$(branch_role release)" "$vtags" "$given" 2>/dev/null)" || prev=null
    fi
  fi
  # The tasks: In review with a location label and contained in the merge commit (spec "Publishing
  # on merge"), and for a hotfix those it closes.
  plan="$(release_contained_plan "$repo" "#$num" "$sha" "$prev" "" "$extra")"
  nums="$(printf '%s' "$plan" | jq -r '.tasks[].number')"

  # 1. Tag and GitHub Release, with the notes between the markers of the pull request body
  #    (regenerated from the contained tasks when the markers are gone).
  if [ -n "$tag" ]; then
    notes="$(printf '%s' "$pr" | jq -r --arg s "$RELEASE_NOTES_START" --arg e "$RELEASE_NOTES_END" '(.body // "") as $b
      | ($b | index($s)) as $i | ($b | index($e)) as $j
      | if $i != null and $j != null and $j > $i then $b[($i + ($s | length)):$j] | sub("^\\s+"; "") | sub("\\s+$"; "") else "" end')"
    if [ -z "$notes" ]; then
      notes="$(release_notes_of "$repo" "$(printf '%s' "$plan" | jq -c --arg t "$tag" '.tag = $t')" | jq -r .notes)"
    fi
    release_finish_publish "$repo" "$tag" "$sha" "$notes"
  else
    warn "hotfix #$num has no \"<!-- scrum-release-tag: vX.Y.Z -->\" line in its description, so no tag and no GitHub Release were created (scrum hotfix prepare --json gives that line). Add it, then run: scrum release finish --pr $num"
  fi
  # 2. Tasks Done and closed.
  for n in $nums; do release_finish_done "$repo" "$n"; done
  [ -n "$nums" ] || info "No task to set Done."
  # 3. Back-merge pull requests.
  release_back_merge "$repo" "$tag"
}
