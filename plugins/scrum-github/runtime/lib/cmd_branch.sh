# shellcheck shell=bash
# Daily branch commands (spec branch-collaboration, design 11): sync, branches, cleanup.
# Local git plus read-only GitHub calls; only cleanup --yes deletes anything.

# branch_git_dir  The target repository's working tree, or dies when it is not a git repository.
branch_git_dir() {
  local dir
  dir="$(repo_dir)"
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || die "$dir is not a git repository"
  printf '%s' "$dir"
}

# ---------- sync ----------

# scrum sync  Merge origin/<working> (origin/<release> on hotfix/* and release/*) into the
# current task branch. Conflicts are listed and left for the user; nothing is resolved here.
cmd_sync() {
  while [ $# -gt 0 ]; do
    case "$1" in
      *) die "usage: scrum sync (no options; run it on the task branch to update)" ;;
    esac
  done
  require_tools nogh
  load_config
  local dir cur kind base n files f line err
  dir="$(branch_git_dir)"
  cur="$(git -C "$dir" symbolic-ref --short -q HEAD)" || die "HEAD is not on a branch; check out your task branch first"
  kind="$(branch_kind_of "$cur")"
  case "$kind" in
    release|staging|working)
      die "$cur is a long-lived branch; scrum sync works on task branches (check out yours first)" ;;
    hotfix|release_pr) base="$(branch_role release)" ;;
    *) base="$(branch_role working)" ;;
  esac
  if git -C "$dir" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    die "a merge is already in progress on $cur. Finish it (git merge --continue) or abort it (git merge --abort) first"
  fi
  [ -z "$(git -C "$dir" status --porcelain --untracked-files=no)" ] \
    || die "$cur has uncommitted changes. Commit or stash them first, then run scrum sync again"

  git -C "$dir" fetch -q origin "$base" 2>/dev/null \
    && git -C "$dir" rev-parse --verify -q "refs/remotes/origin/$base" >/dev/null \
    || die "cannot fetch $base from origin; nothing was changed. Check your network and that origin has $base"

  n="$(git -C "$dir" rev-list --count "HEAD..refs/remotes/origin/$base")"
  if [ "$n" = 0 ]; then
    info "$cur is up to date with origin/$base; nothing to merge."
    return 0
  fi
  err="$(mktemp "${TMPDIR:-/tmp}/scrum-git.XXXXXX")"
  if git -C "$dir" merge -q --no-edit "refs/remotes/origin/$base" >/dev/null 2>"$err"; then
    rm -f "$err"
    if [ "$n" = 1 ]; then info "Merged origin/$base into $cur: 1 commit brought in."
    else info "Merged origin/$base into $cur: $n commits brought in."; fi
    return 0
  fi
  files="$(git -C "$dir" diff --name-only --diff-filter=U)"
  if [ -z "$files" ]; then
    f="$(tr '\n' ' ' < "$err")"; rm -f "$err"
    die "git could not merge origin/$base into $cur: $f"
  fi
  rm -f "$err"
  info "Merging origin/$base into $cur conflicts in these files (last change on $base):"
  printf '%s\n' "$files" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    line="$(git -C "$dir" log -1 --format='%an%x09%s' "refs/remotes/origin/$base" -- "$f" 2>/dev/null)"
    if [ -n "$line" ]; then
      printf '  %s  (%s: "%s")\n' "$f" "${line%%	*}" "${line#*	}"
    else
      printf '  %s\n' "$f"
    fi
  done
  info "The merge is left in progress; nothing was resolved. Fix each file, then: git add <files> && git merge --continue"
  info "To give up and go back to where you were: git merge --abort"
  die "the merge of origin/$base into $cur has conflicts"
}

# json_or_null CMD...  The JSON CMD prints, or null when it fails or prints nothing.
json_or_null() {
  local o
  if o="$("$@" 2>/dev/null)" && [ -n "$o" ] && printf '%s' "$o" | jq -e . >/dev/null 2>&1; then printf '%s' "$o"
  else printf 'null'; fi
}

# ---------- branches ----------

# compare_ahead REPO BASE HEAD  How many commits HEAD has that BASE lacks (compare ahead_by);
# "null" when GitHub does not say.
compare_ahead() {
  local n
  n="$(gh_get "repos/$1/compare/$(branch_uri "$2")...$(branch_uri "$3")" 2>/dev/null | jq -r '.ahead_by // empty' 2>/dev/null)" || n=""
  case "$n" in ""|*[!0-9]*) printf 'null' ;; *) printf '%s' "$n" ;; esac
}

# remote_branch_refs DIR  [{branch, date, author}] of every branch of origin (from the last fetch).
remote_branch_refs() {
  git -C "$1" for-each-ref --format='%(refname)%09%(committerdate:short)%09%(authorname)' refs/remotes/origin \
    | jq -R -s -c '[split("\n")[] | select(. != "") | split("\t")
        | {branch: (.[0] | ltrimstr("refs/remotes/origin/")), date: .[1], author: (.[2] // "")}
        | select(.branch != "HEAD")]'
}

# scrum branches [--json]  (spec branch-collaboration "Branch overview"; read-only)
cmd_branches() {
  local json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      *) die "unknown option for branches: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  local repo dir b release preset chain i lower upper locs issues label res contained tasks commits behind bm
  local pairs='[]' drift='[]' prs pro stale overview
  repo="$(repo_slug)"
  dir="$(branch_git_dir)"
  b="$(jq -nc -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" 'include "scrum"; branching($cfg)')"
  preset="$(printf '%s' "$b" | jq -r .preset)"
  release="$(printf '%s' "$b" | jq -r .release)"
  git -C "$dir" fetch -q --prune origin 2>/dev/null || warn "cannot fetch from origin; stale branches are as of your last fetch"

  if [ "$preset" = trunk ]; then
    prs="$(open_prs "$repo" "" "" | jq -c '{open: .}')" || die "cannot read the open pull requests of $repo"
  else
    label="$(config_get '.statuses.label_prefix + .statuses.in_review')"
    issues="$(gh_get_all "repos/$repo/issues?state=open&labels=$(branch_uri "$label")&per_page=100" \
      | jq -c '[.[] | select(has("pull_request") | not)]')" || die "cannot read the tasks of $repo"
    chain="$(printf '%s' "$b" | jq -c .chain)"
    i=0
    while [ "$i" -lt "$(( $(printf '%s' "$chain" | jq length) - 1 ))" ]; do
      lower="$(printf '%s' "$chain" | jq -r --argjson i "$i" '.[$i]')"
      upper="$(printf '%s' "$chain" | jq -r --argjson i "$i" '.[$i + 1]')"
      locs="$(printf '%s' "$chain" | jq -c --argjson i "$i" '.[0:$i + 1]')"
      commits="$(compare_ahead "$repo" "$upper" "$lower")"
      # The tasks at the lower branch (or below) that the upper one lacks; above the lowest pair
      # they must also be on the lower branch.
      res="$(branch_contents "$repo" "$upper" "$issues" "$locs")"
      tasks="$(printf '%s' "$res" | jq -c '.missing')"
      if [ "$i" -gt 0 ] && [ "$tasks" != '[]' ]; then
        contained="$(branch_contents "$repo" "$lower" "$issues" "$locs" | jq -c '.contained')"
        tasks="$(jq -nc --argjson t "$tasks" --argjson c "$contained" '[$t[] | select(. as $n | $c | index($n))]')"
      fi
      pairs="$(jq -nc --argjson p "$pairs" --arg l "$lower" --arg u "$upper" --argjson c "$commits" \
        --argjson t "$tasks" --argjson r "$res" --argjson is "$issues" \
        '$p + [{lower: $l, upper: $u, commits: $c,
                tasks: [$t[] as $n | {number: $n, title: ([$is[] | select(.number == $n) | .title][0] // "")}],
                unknown: $r.unknown, truncated: $r.truncated}]')"
      i=$((i + 1))
    done
    for lower in $(printf '%s' "$b" | jq -r '.lower[]'); do
      behind="$(compare_ahead "$repo" "$lower" "$release")"
      bm="$(json_or_null open_prs "$repo" "$release" "$lower")"
      drift="$(jq -nc --argjson d "$drift" --arg l "$lower" --argjson n "$behind" --argjson bm "$bm" \
        '$d + [{branch: $l, missing_commits: $n, back_merge: $bm}]')"
    done
    pro='[]'
    if [ "$(printf '%s' "$b" | jq -r '.staging // ""')" != "" ]; then
      pro="$(json_or_null open_prs "$repo" "$(printf '%s' "$b" | jq -r .working)" "$(printf '%s' "$b" | jq -r .staging)")"
    fi
    prs="$(jq -nc --argjson d "$drift" --argjson pro "$pro" \
      --argjson rel "$(json_or_null open_prs_matching "$repo" release/ "$release")" \
      --argjson hot "$(json_or_null open_prs_matching "$repo" hotfix/ "$release")" \
      '{promotion: $pro, release: (if $rel == null or $hot == null then null else $rel + $hot end),
        back_merge: ([$d[].back_merge | select(. != null)] | add // [])}')"
  fi

  stale="$(remote_branch_refs "$dir" | jqlib branches-overview --arg step stale --argjson cfg "$CONFIG_JSON" --arg today "$(today)")"
  overview="$(jq -nc --argjson b "$b" --argjson pairs "$pairs" --argjson drift "$drift" --argjson prs "$prs" \
    --argjson stale "$stale" --argjson days "$(config_get '.branching.stale_days // 5')" \
    '{preset: $b.preset, working: $b.working, release: $b.release, chain: $b.chain,
      pairs: $pairs, drift: $drift, pull_requests: $prs, stale_days: $days, stale: $stale}')"
  if [ "$json" = 1 ]; then printf '%s\n' "$overview"; return 0; fi
  printf '%s' "$overview" | jqlib branches-overview -r --arg step text
}

# ---------- cleanup ----------

# cleanup_plan REPO DIR  The branches to delete, as cleanup in branches-overview.jq prints them.
cleanup_plan() {
  local repo="$1" dir="$2" x cur head merged open locals remotes cl='{}' cr='{}' long
  cur="$(git -C "$dir" symbolic-ref --short -q HEAD || true)"
  head="$(git -C "$dir" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  long="$(branch_role chain | jq -R -s -c --arg h "${head#origin/}" 'split("\n") | map(select(. != "")) + (if $h == "" then [] else [$h] end)')"
  merged="$(gh_get_all "repos/$repo/pulls?state=closed&per_page=100" \
    | jq -c '[.[] | select(.merged_at != null) | {head: .head.ref, sha: .head.sha, number}]')" \
    || die "cannot read the merged pull requests of $repo"
  open="$(open_prs "$repo" "" "" | jq -c '[.[].head]')" || die "cannot read the open pull requests of $repo"
  locals="$(git -C "$dir" for-each-ref --format='%(refname:short)%09%(objectname)' refs/heads \
    | jq -R -s -c '[split("\n")[] | select(. != "") | split("\t") | {name: .[0], sha: .[1]}]')"
  remotes="$(git -C "$dir" for-each-ref --format='%(refname)%09%(objectname)' refs/remotes/origin \
    | jq -R -s -c '[split("\n")[] | select(. != "") | split("\t") | {name: (.[0] | ltrimstr("refs/remotes/origin/")), sha: .[1]}
        | select(.name != "HEAD")]')"
  for x in $(printf '%s' "$long" | jq -r '.[]'); do
    git -C "$dir" rev-parse --verify -q "refs/remotes/origin/$x" >/dev/null || continue
    cl="$(git -C "$dir" for-each-ref --merged "refs/remotes/origin/$x" --format='%(refname:short)' refs/heads \
      | jq -R -s -c --argjson m "$cl" --arg x "$x" '$m + {($x): (split("\n") | map(select(. != "")))}')"
    cr="$(git -C "$dir" for-each-ref --merged "refs/remotes/origin/$x" --format='%(refname)' refs/remotes/origin \
      | jq -R -s -c --argjson m "$cr" --arg x "$x" '$m + {($x): (split("\n") | map(select(. != "") | ltrimstr("refs/remotes/origin/")))}')"
  done
  jq -nc --argjson locals "$locals" --argjson remotes "$remotes" --argjson cl "$cl" --argjson cr "$cr" \
      --argjson merged "$merged" --argjson open "$open" --argjson long "$long" --arg current "$cur" \
      '{locals: $locals, remotes: $remotes, contained_local: $cl, contained_remote: $cr,
        merged: $merged, open_heads: $open, long_lived: $long, current: $current}' \
    | jqlib branches-overview --arg step cleanup
}

# scrum cleanup [--json] [--yes]  (spec branch-collaboration "Clean up merged branches")
cmd_cleanup() {
  local json=0 yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --yes) yes=1 ;;
      *) die "unknown option for cleanup: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  local repo dir plan count name loc rem failed=0 result='[]' ok_l ok_r
  repo="$(repo_slug)"
  dir="$(branch_git_dir)"
  git -C "$dir" fetch -q --prune origin 2>/dev/null || warn "cannot fetch from origin; remote branches are as of your last fetch"
  plan="$(cleanup_plan "$repo" "$dir")"
  count="$(printf '%s' "$plan" | jq length)"
  if [ "$yes" = 0 ]; then
    if [ "$json" = 1 ]; then printf '%s\n' "$plan"; return 0; fi
    if [ "$count" = 0 ]; then info "No merged branch to delete."; return 0; fi
    printf '%s' "$plan" | jqlib branches-overview -r --arg step cleanup_text
    info "Nothing was deleted. To delete them: scrum cleanup --yes"
    return 0
  fi
  if [ "$count" = 0 ]; then
    if [ "$json" = 1 ]; then printf '[]\n'; else info "No merged branch to delete."; fi
    return 0
  fi
  while IFS="$(printf '\t')" read -r name loc rem; do
    [ -n "$name" ] || continue
    ok_l=null; ok_r=null
    # Every listed branch is merged (its pull request's head is its tip) or contained in a
    # long-lived branch, which is checked above; -D because a squash merge is not an ancestor.
    if [ "$loc" = true ]; then
      if git -C "$dir" branch -q -D "$name" >/dev/null 2>&1; then ok_l=true; info "Deleted the local branch $name."
      else ok_l=false; failed=1; warn "could not delete the local branch $name"; fi
    fi
    if [ "$rem" = true ]; then
      if git -C "$dir" push -q origin --delete "$name" >/dev/null 2>&1; then ok_r=true; info "Deleted $name on origin."
      else ok_r=false; failed=1; warn "could not delete $name on origin"; fi
    fi
    result="$(jq -nc --argjson r "$result" --arg n "$name" --argjson l "$ok_l" --argjson o "$ok_r" \
      '$r + [{branch: $n, local_deleted: $l, remote_deleted: $o}]')"
  done <<EOF
$(printf '%s' "$plan" | jq -r '.[] | [.branch, .local, .remote] | @tsv')
EOF
  [ "$json" = 0 ] || jq -nc --argjson p "$plan" --argjson r "$result" '[$p[] as $b | $b + ([$r[] | select(.branch == $b.branch)][0] // {} | del(.branch))]'
  [ "$failed" = 0 ] || die "some branches could not be deleted (see the warnings above)"
}
