# shellcheck shell=bash
# scrum release: publish a version from the Done tasks (spec release). release-plan.jq picks the
# tasks and the version, release-notes.jq writes the notes; this file reads GitHub and, only
# with --yes, creates the tag and the GitHub Release. Also used by next (release_latest_tag).

RELEASE_TAG_CHECKS=20        # version tags checked for being on the default branch, newest first
RELEASE_TIMELINE_LIMIT=100   # tasks whose closing pull requests are read (one call each)
RELEASE_PARENT_LIMIT=50      # parent features whose title is read (one call each)
RELEASES_JSON=""             # every release of the repository (drafts too); read on demand when empty

# uri TEXT  TEXT encoded for one segment of a URL path (a tag "release/1.2.0" -> release%2F1.2.0).
uri() { jq -rn --arg s "$1" '$s | @uri'; }

# gh_status_404 FILE / gh_status_403 FILE  True when the gh error in FILE is that HTTP status.
gh_status_404() { grep -q 'HTTP 404' "$1"; }
gh_status_403() { grep -q 'HTTP 403' "$1"; }

# release_default_branch REPO  The default branch of the repository.
release_default_branch() {
  local b
  b="$(gh_get "repos/$1" | jq -r '.default_branch // empty')" || return 1
  [ -n "$b" ] || return 1
  printf '%s' "$b"
}

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
  local version="" since_tag="" sprints='[]' draft=false notes_file="" json=0 yes=0 a
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
  branch="$(release_default_branch "$repo")" || die "cannot read the default branch of $repo. Check: /scrum-github:doctor"
  vtags="$(release_version_tags "$repo")" || die "cannot read the tags of $repo. Check: /scrum-github:doctor"
  RELEASES_JSON="$(release_list "$repo")" || die "cannot read the releases of $repo. Check: /scrum-github:doctor"

  # A version whose tag already exists: released (stop) or left by a run that failed after
  # creating the tag (create only the release, design 6).
  given="$(jq -nc -L "$JQ_LIB" --arg v "$version" --arg p "$prefix" 'include "scrum"; $v | semver_of($p)')"
  if [ "$given" != null ]; then
    existing="$(printf '%s' "$vtags" | jq -r --argjson g "$given" '[.[] | select(.version == $g) | .name] | .[0] // empty')"
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

# scrum release finish: after a release or hotfix pull request is merged into the release branch
# (spec release-pr "Publishing on merge", "Back-merge after the release branch changes").
cmd_release_finish() { die "scrum release finish is not implemented yet"; }
