# shellcheck shell=bash
# scrum release: publish a version from the Done tasks (spec release). release-plan.jq picks the
# tasks and the version, release-notes.jq writes the notes; this file reads GitHub and, only
# with --yes, creates the tag and the GitHub Release. Also used by next (release_latest_tag).

RELEASE_TAG_CHECKS=20        # version tags checked for being on the default branch, newest first
RELEASE_TIMELINE_LIMIT=100   # tasks whose closing pull requests are read (one call each)
RELEASE_PARENT_LIMIT=50      # parent features whose title is read (one call each)

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

# release_tag_on_branch REPO TAG BRANCH  {status, date} of the tag against the branch: status
# "ahead" or "identical" means the tag is on the branch; date is the tag's commit date.
release_tag_on_branch() {
  gh_get "repos/$1/compare/$2...$3" | jq -c '{status, date: .base_commit.commit.committer.date}'
}

# release_latest_tag REPO BRANCH VTAGS [BELOW]  The highest version tag on the branch, lower than
# the version BELOW ([X, Y, Z]) when given: {name, version, date}, or null when there is none.
release_latest_tag() {
  local repo="$1" branch="$2" vtags="$3" below="${4:-null}" name cmp
  for name in $(printf '%s' "$vtags" | jq -r --argjson b "$below" --argjson max "$RELEASE_TAG_CHECKS" \
      '[.[] | select($b == null or .version < $b)] | .[:$max][] | .name'); do
    cmp="$(release_tag_on_branch "$repo" "$name" "$branch" 2>/dev/null)" || continue
    case "$(printf '%s' "$cmp" | jq -r .status)" in
      ahead|identical)
        printf '%s' "$vtags" | jq -c --arg n "$name" --argjson c "$cmp" '[.[] | select(.name == $n) | . + {date: $c.date}] | .[0]'
        return 0 ;;
    esac
  done
  printf 'null'
}

# release_prs REPO NUMBERS...  {"N": [merged pull requests that closed it] | null (not read)}.
release_prs() {
  local repo="$1" n list map='{}'
  shift
  for n in "$@"; do
    if list="$(gh_get_all "repos/$repo/issues/$n/timeline?per_page=100" 2>/dev/null)"; then
      list="$(printf '%s' "$list" | jq -c -L "$JQ_LIB" --arg r "$repo" --argjson n "$n" 'include "scrum"; timeline_prs($r; $n)' 2>/dev/null)" || list=null
    else
      list=null
    fi
    map="$(printf '%s' "$map" | jq -c --arg k "$n" --argjson v "$list" '.[$k] = $v')"
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

# gh_status_404 FILE  True when the gh error in FILE is a 404.
gh_status_404() { grep -q '404' "$1"; }

cmd_release() {
  local version="" since_tag="" sprints='[]' draft=false notes_file="" json=0 yes=0
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
  require_tools
  load_config
  local repo branch vtags prefix given existing="" prev since=null until=null err
  repo="$(repo_slug)"
  prefix="$(config_get '.release.tag_prefix')"
  err="$(mktemp "${TMPDIR:-/tmp}/scrum-release.XXXXXX")"
  branch="$(release_default_branch "$repo")" || die "cannot read the default branch of $repo. Check: /scrum-github:doctor"
  vtags="$(release_version_tags "$repo")" || die "cannot read the tags of $repo. Check: /scrum-github:doctor"

  # A version whose tag already exists: released (stop) or left by a run that failed after
  # creating the tag (create only the release, design 6).
  given="$(jq -nc -L "$JQ_LIB" --arg v "$version" --arg p "$prefix" 'include "scrum"; $v | semver_of($p)')"
  if [ "$given" != null ]; then
    existing="$(printf '%s' "$vtags" | jq -r --argjson g "$given" '[.[] | select(.version == $g) | .name] | .[0] // empty')"
  fi
  if [ -n "$existing" ]; then
    local rel
    if rel="$(gh_get "repos/$repo/releases/tags/$existing" 2>"$err")"; then
      rm -f "$err"
      die "$existing is already released: $(printf '%s' "$rel" | jq -r '.html_url // ""'). Nothing was changed."
    fi
    gh_status_404 "$err" || { rm -f "$err"; die "cannot read the release of $existing. Check: /scrum-github:doctor"; }
    until="$(gh_get "repos/$repo/commits/$existing" | jq -c '.commit.committer.date // null')" \
      || { rm -f "$err"; die "cannot read the commit of tag $existing"; }
  fi
  rm -f "$err"

  if [ -n "$since_tag" ]; then
    local cmp
    prev="$(printf '%s' "$vtags" | jq -c --arg n "$since_tag" '[.[] | select(.name == $n)] | .[0]')"
    [ "$prev" != null ] || die "no version tag named $since_tag in $repo (version tags look like ${prefix}1.2.3)"
    cmp="$(release_tag_on_branch "$repo" "$since_tag" "$branch")" || die "cannot compare $since_tag with $branch"
    prev="$(printf '%s' "$prev" | jq -c --argjson c "$cmp" '. + {date: $c.date}')"
  elif [ -n "$existing" ]; then
    prev="$(release_latest_tag "$repo" "$branch" "$vtags" "$given")"
  else
    prev="$(release_latest_tag "$repo" "$branch" "$vtags")"
  fi

  # The tasks: those of the named sprints, or those closed since the previous tag (design 2).
  local issues ms s q
  if [ "$sprints" != '[]' ]; then
    ms="$(fetch_milestones "$repo")"
    issues='[]'
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      q="$(resolve_sprint "$ms" "$s")"
      issues="$(jq -nc --argjson a "$issues" --argjson b "$(fetch_milestone_issues "$repo" "$(printf '%s' "$q" | jq -r .number)")" '$a + $b')"
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
    printf '%s\n' "$plan"
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
    [ "$json" = 1 ] || { info ""; info "Nothing changed. To publish $(printf '%s' "$plan" | jq -r .tag), run again with --yes."; }
    return 0
  fi
  release_publish "$repo" "$plan"
}

# release_publish REPO PLAN  The only writes (design 6): the annotated tag on the head
# of the default branch, its ref, then the GitHub Release. A tag left by an earlier run is kept.
release_publish() {
  local repo="$1" plan="$2" tag branch sha obj url err rerun
  tag="$(printf '%s' "$plan" | jq -r .tag)"
  branch="$(printf '%s' "$plan" | jq -r .branch)"
  rerun="the same command again (for example: scrum release $(printf '%s' "$plan" | jq -r .version) --yes)"
  err="$(mktemp "${TMPDIR:-/tmp}/scrum-release.XXXXXX")"
  if [ "$(printf '%s' "$plan" | jq -r .tag_exists)" != true ]; then
    if gh_get "repos/$repo/git/ref/tags/$tag" >/dev/null 2>"$err"; then
      rm -f "$err"; die "tag $tag appeared on GitHub meanwhile. Nothing was changed; run $rerun"
    fi
    gh_status_404 "$err" || { rm -f "$err"; die "cannot check whether tag $tag exists. Check: /scrum-github:doctor"; }
    sha="$(gh_get "repos/$repo/git/ref/heads/$branch" | jq -r '.object.sha // empty')" || sha=""
    [ -n "$sha" ] || { rm -f "$err"; die "cannot read the head commit of $branch"; }
    if ! obj="$(jq -nc --arg t "$tag" --arg s "$sha" '{tag: $t, message: "Release \($t)", object: $s, type: "commit"}' \
        | gh_send POST "repos/$repo/git/tags" 2>"$err" | jq -r '.sha // empty')" || [ -z "$obj" ]; then
      if grep -q '403' "$err"; then
        rm -f "$err"; die "GitHub refused to create tag $tag (403): the token needs contents: write on $repo. Check: /scrum-github:doctor. Nothing was changed."
      fi
      rm -f "$err"; die "could not create tag $tag. Nothing was changed."
    fi
    if ! jq -nc --arg r "refs/tags/$tag" --arg s "$obj" '{ref: $r, sha: $s}' | gh_send POST "repos/$repo/git/refs" >/dev/null 2>"$err"; then
      rm -f "$err"; die "could not create the ref of tag $tag. Nothing was changed on $branch; run $rerun"
    fi
    info "Created tag $tag on $branch (${sha:0:7})."
  fi
  if ! url="$(printf '%s' "$plan" | jq -c '{tag_name: .tag, name: .tag, body: .notes, draft: .draft}' \
      | gh_send POST "repos/$repo/releases" 2>"$err" | jq -r '.html_url // empty')"; then
    rm -f "$err"
    die "tag $tag exists on GitHub, but its release was not created. Run $rerun: it creates only the release and leaves the tag as it is."
  fi
  rm -f "$err"
  if [ "$(printf '%s' "$plan" | jq -r .draft)" = true ]; then
    info "Created the draft release $tag: $url"
  else
    info "Published release $tag: $url"
  fi
}
