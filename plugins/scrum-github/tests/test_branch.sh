# spec: branch-collaboration (scrum sync, branches, cleanup). Temporary git repositories: a bare
# "origin" in $T/remote.git, the user's clone in $SCRUM_REPO_DIR, a teammate's clone in $T/other.

STANDARD='version: 1
branching: {preset: standard}
statuses: {in_review: In review}'

# git_repos [CONFIG]  origin with main and develop, the user's clone, a teammate's clone.
git_repos() {
  setup_fake_gh
  setup_repo "${1:-$STANDARD}"
  export SCRUM_TODAY=2026-11-24
  export GIT_AUTHOR_NAME=tuan GIT_AUTHOR_EMAIL=tuan@example.com GIT_COMMITTER_NAME=tuan GIT_COMMITTER_EMAIL=tuan@example.com
  git init -q --bare -b main "$T/remote.git"
  git init -q -b main "$SCRUM_REPO_DIR"
  git -C "$SCRUM_REPO_DIR" config commit.gpgsign false
  mkdir -p "$SCRUM_REPO_DIR/src"
  printf 'timeout = 10\n' > "$SCRUM_REPO_DIR/src/auth.ts"
  git -C "$SCRUM_REPO_DIR" add -A
  git -C "$SCRUM_REPO_DIR" commit -q -m init
  git -C "$SCRUM_REPO_DIR" branch develop
  git -C "$SCRUM_REPO_DIR" remote add origin "$T/remote.git"
  git -C "$SCRUM_REPO_DIR" push -q origin main develop 2>/dev/null
  git -C "$SCRUM_REPO_DIR" fetch -q origin
  git clone -q "$T/remote.git" "$T/other" 2>/dev/null
  git -C "$T/other" config commit.gpgsign false
}

# teammate BRANCH AUTHOR SUBJECT [FILE TEXT]  A commit by AUTHOR on BRANCH of origin.
teammate() {
  git -C "$T/other" fetch -q origin
  git -C "$T/other" checkout -q -B "$1" "origin/$1" 2>/dev/null || git -C "$T/other" checkout -q -b "$1"
  if [ $# -ge 5 ]; then
    mkdir -p "$(dirname "$T/other/$4")"; printf '%s\n' "$5" > "$T/other/$4"; git -C "$T/other" add -A
  fi
  GIT_AUTHOR_NAME="$2" git -C "$T/other" commit -q --allow-empty -m "$3"
  git -C "$T/other" push -q origin "$1" 2>/dev/null
}

on_task_branch() { git -C "$SCRUM_REPO_DIR" checkout -q -b "${1:-feat/12-login}" "origin/${2:-develop}"; }
head_of() { git -C "$SCRUM_REPO_DIR" rev-parse "$1"; }

# ---------- sync ----------

# "Sync a task branch: Behind the working branch"
test_sync_behind_the_working_branch() {
  git_repos
  on_task_branch
  git -C "$SCRUM_REPO_DIR" commit -q --allow-empty -m "my work"
  teammate develop ruby "one"; teammate develop ruby "two"; teammate develop ruby "three"
  run_scrum sync
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Merged origin/develop into feat/12-login: 3 commits brought in."
  git -C "$SCRUM_REPO_DIR" merge-base --is-ancestor origin/develop HEAD || _fail "origin/develop is not merged"
  assert_eq "feat/12-login" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)"
  assert_eq "" "$(gh_calls)" "sync does not call GitHub"
}

# "Sync a task branch: Up to date"
test_sync_up_to_date() {
  git_repos
  on_task_branch
  git -C "$SCRUM_REPO_DIR" commit -q --allow-empty -m "my work"
  local before; before="$(head_of HEAD)"
  run_scrum sync
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "feat/12-login is up to date with origin/develop"
  assert_eq "$before" "$(head_of HEAD)"
}

# "Sync a task branch: Uncommitted changes"
test_sync_refuses_uncommitted_changes() {
  git_repos
  on_task_branch
  teammate develop ruby "one"
  printf 'changed\n' > "$SCRUM_REPO_DIR/src/auth.ts"
  local before; before="$(head_of HEAD)"
  run_scrum sync
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "uncommitted changes. Commit or stash them first"
  assert_eq "$before" "$(head_of HEAD)"
}

# "Sync a task branch: On a long-lived branch"
test_sync_refuses_a_long_lived_branch() {
  git_repos
  git -C "$SCRUM_REPO_DIR" checkout -q develop
  run_scrum sync
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "develop is a long-lived branch; scrum sync works on task branches"
  git -C "$SCRUM_REPO_DIR" checkout -q main
  run_scrum sync
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "main is a long-lived branch"
}

# A hotfix branch is synced with the release branch, not the working branch.
test_sync_hotfix_with_the_release_branch() {
  git_repos
  on_task_branch hotfix/31-payment-fails main
  teammate main ruby "fix on main"
  teammate develop ruby "feature on develop"
  run_scrum sync
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Merged origin/main into hotfix/31-payment-fails: 1 commit brought in."
  git -C "$SCRUM_REPO_DIR" merge-base --is-ancestor origin/main HEAD || _fail "origin/main is not merged"
  git -C "$SCRUM_REPO_DIR" fetch -q origin
  ! git -C "$SCRUM_REPO_DIR" merge-base --is-ancestor origin/develop HEAD || _fail "develop was merged into a hotfix"
}

# "Sync reports conflicts: Conflict"
test_sync_conflict_is_listed_and_left_in_progress() {
  git_repos
  on_task_branch
  printf 'timeout = 30\n' > "$SCRUM_REPO_DIR/src/auth.ts"
  git -C "$SCRUM_REPO_DIR" commit -q -am "my timeout"
  teammate develop ruby "feat: session timeout" src/auth.ts 'timeout = 60'
  run_scrum sync
  assert_status 1 "$STATUS"
  assert_contains "$OUT" 'src/auth.ts  (ruby: "feat: session timeout")'
  assert_contains "$OUT" "git merge --continue"
  assert_contains "$OUT" "git merge --abort"
  assert_contains "$ERR" "has conflicts"
  git -C "$SCRUM_REPO_DIR" rev-parse -q --verify MERGE_HEAD >/dev/null || _fail "the merge is not left in progress"
  assert_eq "src/auth.ts" "$(git -C "$SCRUM_REPO_DIR" diff --name-only --diff-filter=U)" "nothing resolved"
}

test_sync_in_trunk_uses_main() {
  git_repos 'version: 1'
  on_task_branch feat/3-x main
  teammate main ruby "on main"
  run_scrum sync
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Merged origin/main into feat/3-x: 1 commit brought in."
}

# ---------- branches ----------

branches_env() {
  git_repos "$@"
  # feat/9-export: last commit eight working days before 2026-11-24, by david; feat/10-fresh: yesterday.
  GIT_COMMITTER_DATE="2026-11-12T10:00:00" GIT_AUTHOR_DATE="2026-11-12T10:00:00" teammate feat/9-export david "export"
  GIT_COMMITTER_DATE="2026-11-23T10:00:00" GIT_AUTHOR_DATE="2026-11-23T10:00:00" teammate feat/10-fresh ruby "fresh"
  route_json 'api --paginate repos/acme/blog/issues?state=open&labels=*' '[
    {"number":12,"state":"open","title":"Login","labels":[{"name":"status: In review"},{"name":"on: develop"}]},
    {"number":13,"state":"open","title":"Signup","labels":[{"name":"status: In review"},{"name":"on: develop"}]},
    {"number":15,"state":"open","title":"Review","labels":[{"name":"status: In review"}]}]'
  route_json 'api --paginate repos/acme/blog/issues/12/timeline*' '[{"event":"cross-referenced","source":{"issue":{"number":40,"body":"Closes #12","pull_request":{"merged_at":"2026-11-20T10:00:00Z"},"repository":{"full_name":"acme/blog"}}}}]'
  route_json 'api --paginate repos/acme/blog/issues/13/timeline*' '[{"event":"cross-referenced","source":{"issue":{"number":41,"body":"Closes #13","pull_request":{"merged_at":"2026-11-21T10:00:00Z"},"repository":{"full_name":"acme/blog"}}}}]'
  route_json 'api repos/acme/blog/pulls/40' '{"number":40,"merge_commit_sha":"aaa111"}'
  route_json 'api repos/acme/blog/pulls/41' '{"number":41,"merge_commit_sha":"bbb222"}'
  route_json 'api repos/acme/blog/compare/aaa111...main' '{"status":"behind"}'
  route_json 'api repos/acme/blog/compare/bbb222...main' '{"status":"diverged"}'
  route_json 'api repos/acme/blog/compare/main...develop' '{"ahead_by":2}'
  route_json 'api repos/acme/blog/compare/develop...main' '{"ahead_by":0}'
  route_json 'api --paginate repos/acme/blog/pulls?state=open&per_page=100&head=acme%3Amain&base=develop' '[]'
  route_json 'api --paginate repos/acme/blog/pulls?state=open&per_page=100&base=main' \
    '[{"number":60,"title":"Release v1.4.0","html_url":"u60","head":{"ref":"release/v1.4.0"},"base":{"ref":"main"}}]'
}

# "Branch overview: Waiting on develop"
test_branches_waiting_on_develop() {
  branches_env
  run_scrum branches
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "develop → main: 2 commits and 2 tasks on develop that main lacks
  #12 Login
  #13 Signup"
  assert_not_contains "$OUT" "#15"
  assert_contains "$OUT" "  develop has every commit of main."
  assert_contains "$OUT" "  #60 release/v1.4.0 → main  Release v1.4.0"
  assert_eq "" "$(gh_writes)" "read-only"
}

# "Branch overview: Drift" (none open, then one open)
test_branches_drift_and_back_merge() {
  branches_env
  route_first 'api repos/acme/blog/compare/develop...main' "$(printf '{"ahead_by":1}' > "$FAKE_GH_DIR/drift.json"; echo drift.json)"
  run_scrum branches
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "develop lacks 1 commit of main. Back-merge: none open"
  printf '[{"number":50,"title":"Back-merge main into develop","html_url":"u50","head":{"ref":"main"},"base":{"ref":"develop"}}]' > "$FAKE_GH_DIR/bm.json"
  route_first 'api --paginate repos/acme/blog/pulls?state=open&per_page=100&head=acme%3Amain&base=develop' bm.json
  run_scrum branches
  assert_contains "$OUT" "develop lacks 1 commit of main. Back-merge: #50 u50"
  assert_contains "$OUT" "Open back-merge pull requests
  #50 main → develop  Back-merge main into develop"
}

# "Branch overview: Stale branch"
test_branches_stale_branch() {
  branches_env
  run_scrum branches
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Stale task branches (no commit for 5 working days)
  feat/9-export  8 working days, last commit 2026-11-12 by david"
  assert_not_contains "$OUT" "feat/10-fresh"
  assert_not_contains "$OUT" "  develop  " "long-lived branches are never stale"
}

test_branches_json() {
  branches_env
  run_scrum branches --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq '[12,13]' "$(printf '%s' "$OUT" | jq -c '[.pairs[0].tasks[].number]')"
  assert_eq 'develop main 2' "$(printf '%s' "$OUT" | jq -r '.pairs[0] | "\(.lower) \(.upper) \(.commits)"')"
  assert_eq '0 []' "$(printf '%s' "$OUT" | jq -c '.drift[0] | .missing_commits, .back_merge' | tr '\n' ' ' | sed 's/ $//')"
  assert_eq '[60]' "$(printf '%s' "$OUT" | jq -c '[.pull_requests.release[].number]')"
  assert_json_eq '[{"branch":"feat/9-export","last_commit":"2026-11-12","author":"david","working_days":8}]' "$(printf '%s' "$OUT" | jq -c .stale)"
}

# "Branch overview: Trunk"
test_branches_trunk() {
  branches_env 'version: 1'
  route_json 'api --paginate repos/acme/blog/pulls?state=open&per_page=100' \
    '[{"number":7,"title":"Add export","html_url":"u7","head":{"ref":"feat/9-export"},"base":{"ref":"main"}}]'
  run_scrum branches
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Open pull requests
  #7 feat/9-export → main  Add export"
  assert_contains "$OUT" "feat/9-export  8 working days"
  assert_not_contains "$OUT" "Drift"
  assert_not_contains "$OUT" "→ main: "
  assert_not_contains "$(gh_calls)" "compare"
  assert_not_contains "$(gh_calls)" "issues?"
}

# ---------- cleanup ----------

cleanup_env() {
  git_repos
  local d="$SCRUM_REPO_DIR"
  # feat/7-signup: squash-merged through #70 (its tip is the pull request's head), local and origin
  git -C "$d" checkout -q -b feat/7-signup main
  git -C "$d" commit -q --allow-empty -m "signup"
  git -C "$d" push -q origin feat/7-signup 2>/dev/null
  SHA7="$(head_of feat/7-signup)"
  # feat/6-old: merged into develop with a merge commit (contained), local only
  git -C "$d" checkout -q -b feat/6-old develop
  git -C "$d" commit -q --allow-empty -m "old"
  git -C "$d" checkout -q develop
  git -C "$d" merge -q --no-ff --no-edit feat/6-old
  git -C "$d" push -q origin develop 2>/dev/null
  # feat/8-profile: contained in develop, but its pull request is open
  git -C "$d" branch feat/8-profile develop
  git -C "$d" push -q origin feat/8-profile 2>/dev/null
  # feat/9-wip: work that is merged nowhere
  git -C "$d" checkout -q -b feat/9-wip develop
  git -C "$d" commit -q --allow-empty -m "wip"
  git -C "$d" push -q origin feat/9-wip 2>/dev/null
  git -C "$d" checkout -q main
  git -C "$d" fetch -q origin
  route_json 'api --paginate repos/acme/blog/pulls?state=closed*' "[
    {\"number\":70,\"merged_at\":\"2026-11-20T10:00:00Z\",\"head\":{\"ref\":\"feat/7-signup\",\"sha\":\"$SHA7\"}},
    {\"number\":71,\"merged_at\":null,\"head\":{\"ref\":\"feat/9-wip\",\"sha\":\"$(head_of feat/9-wip)\"}}]"
  route_json 'api --paginate repos/acme/blog/pulls?state=open*' \
    '[{"number":80,"title":"Profile","html_url":"u80","head":{"ref":"feat/8-profile"},"base":{"ref":"develop"}}]'
}

remote_branches() { git --git-dir="$T/remote.git" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ' | sed 's/ $//'; }
local_branches() { git -C "$SCRUM_REPO_DIR" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ' | sed 's/ $//'; }

# "Clean up merged branches: Preview" and "Branch with an open pull request"
test_cleanup_preview_deletes_nothing() {
  cleanup_env
  local before_l before_r
  before_l="$(local_branches)"; before_r="$(remote_branches)"
  run_scrum cleanup
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "feat/7-signup  local and origin  pull request #70 merged"
  assert_contains "$OUT" "feat/6-old  local  contained in develop"
  assert_not_contains "$OUT" "feat/8-profile"
  assert_not_contains "$OUT" "feat/9-wip"
  assert_not_contains "$OUT" "  main "
  assert_not_contains "$OUT" "  develop "
  assert_contains "$OUT" "Nothing was deleted. To delete them: scrum cleanup --yes"
  assert_eq "$before_l" "$(local_branches)"
  assert_eq "$before_r" "$(remote_branches)"
  assert_eq "" "$(gh_writes)"
}

test_cleanup_json() {
  cleanup_env
  run_scrum cleanup --json
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '[{"branch":"feat/6-old","local":true,"remote":false,"reason":"contained","into":"develop","pr":null},
    {"branch":"feat/7-signup","local":true,"remote":true,"reason":"merged","into":null,"pr":70}]' "$OUT"
}

# "Clean up merged branches: Delete"
test_cleanup_yes_deletes_locally_and_on_origin() {
  cleanup_env
  run_scrum cleanup --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Deleted the local branch feat/7-signup."
  assert_contains "$OUT" "Deleted feat/7-signup on origin."
  assert_eq "develop feat/8-profile feat/9-wip main" "$(local_branches)"
  assert_eq "develop feat/8-profile feat/9-wip main" "$(remote_branches)"
}

# The current branch is never listed.
test_cleanup_skips_the_current_branch() {
  cleanup_env
  git -C "$SCRUM_REPO_DIR" checkout -q feat/6-old
  run_scrum cleanup --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq '["feat/7-signup"]' "$(printf '%s' "$OUT" | jq -c '[.[].branch]')"
}

# A branch with commits after its merged pull request is not listed.
test_cleanup_skips_work_after_the_merge() {
  cleanup_env
  git -C "$SCRUM_REPO_DIR" checkout -q feat/7-signup
  git -C "$SCRUM_REPO_DIR" commit -q --allow-empty -m "more"
  git -C "$SCRUM_REPO_DIR" checkout -q main
  run_scrum cleanup --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq '[{"branch":"feat/7-signup","local":false,"remote":true}]' \
    "$(printf '%s' "$OUT" | jq -c '[.[] | select(.branch == "feat/7-signup") | {branch, local, remote}]')"
}
