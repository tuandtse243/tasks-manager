# Scenario tests (black box, from the specs) for stream C: task-management (start from the
# working branch), branching-presets (run in standard) and branch-collaboration (sync, branches,
# cleanup). Change: branching-and-release-flow.

# shellcheck source=fixtures/scenarios/helpers.sh
. "$FIXTURES/scenarios/helpers.sh"

all_out() { printf '%s\n%s' "$OUT" "$ERR"; }
head_of() { git -C "$SCRUM_REPO_DIR" rev-parse "$1"; }
current_branch() { git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD; }

# ---------- task start (task-management) ----------

# start_env  Standard; origin/develop is two commits ahead of the local develop.
start_env() {
  git_project "$CFG_STANDARD"
  sc_gh
  export SCRUM_REPO_DIR="$T/repo"
  route_json 'api repos/acme/blog/issues/2' '{"number":2,"title":"Login","state":"open","assignees":[],"labels":[{"name":"status: New"},{"name":"points: 3"}]}'
  seed_commits develop 2 app.txt "feat: other work"
}

# spec task-management: Preset standard
test_task_start_branches_from_origin_develop() {
  start_env
  local remote_tip
  remote_tip="$(git --git-dir="$T/origin.git" rev-parse develop)"
  cd "$SCRUM_REPO_DIR" || return 1
  run_scrum task start 2
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "feat/2-login" "$(current_branch)"
  assert_eq "$remote_tip" "$(head_of feat/2-login)" "feat/2-login starts at origin/develop with its two commits"
  assert_contains "$(gh_calls)" 'STDIN {"labels":["points: 3","status: In progress"]}'
}

# spec task-management: Không lấy được remote
test_task_start_fetch_fails_uses_local_develop_and_warns() {
  start_env
  # a local commit on develop, then the remote becomes unreachable
  printf 'local\n' > "$SCRUM_REPO_DIR/local.txt"
  git -C "$SCRUM_REPO_DIR" add -A
  git -C "$SCRUM_REPO_DIR" commit -q -m "chore: local"
  git -C "$SCRUM_REPO_DIR" remote set-url origin "$T/missing.git"
  local local_tip
  local_tip="$(head_of develop)"
  cd "$SCRUM_REPO_DIR" || return 1
  run_scrum task start 2
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "feat/2-login" "$(current_branch)"
  assert_eq "$local_tip" "$(head_of feat/2-login)" "created from the local develop"
  assert_contains "$(all_out | tr '[:upper:]' '[:lower:]')" "warning" "warns that the branch may be stale"
}

# spec task-management: Bắt đầu task mới (trunk still branches from main)
test_task_start_trunk_branches_from_main() {
  git_project 'version: 1'
  sc_gh
  route_json 'api repos/acme/blog/issues/2' '{"number":2,"title":"Login","state":"open","assignees":[],"labels":[{"name":"status: New"}]}'
  seed_commits develop 1 dev.txt "feat: only on develop"
  git -C "$SCRUM_REPO_DIR" checkout -q main
  cd "$SCRUM_REPO_DIR" || return 1
  run_scrum task start 2
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "$(git --git-dir="$T/origin.git" rev-parse main)" "$(head_of feat/2-login)"
}

# ---------- run (branching-presets: Run in standard) ----------

# run_issue N  A New ai-ready task of Sprint 5 assigned to alice.
run_issue() {
  jq -nc --argjson n "$1" '{number: $n, title: "Task \($n)", state: "open",
    body: "### Acceptance criteria\n\n- [ ] Works for \($n)",
    milestone: {number: 5, title: "Sprint 5"},
    labels: [{name: "status: New"}, {name: "points: 3"}, {name: "ai-ready"}], assignees: [{login: "alice"}]}'
}

run_env() {
  git_project "$CFG_STANDARD"
  sc_gh
  sc_gh_bodies
  export SCRUM_TODAY=2026-11-23 SCRUM_NOW=2026-11-23T10:00:00Z
  route_json 'api --paginate repos/acme/blog/milestones*' '[{"number":5,"title":"Sprint 5","state":"open","description":"<!-- scrum:start=2026-11-16 end=2026-11-27 -->"}]'
  run_issue 102 > "$FAKE_GH_DIR/i102.json"
  jq -s . "$FAKE_GH_DIR/i102.json" > "$FAKE_GH_DIR/mine.json"
  route 'api --paginate repos/acme/blog/issues?assignee=alice&state=open*' mine.json
  route 'api --paginate repos/acme/blog/issues?milestone=5*' mine.json
  route 'api repos/acme/blog/issues/102' i102.json
  route_json 'api --paginate repos/acme/blog/issues/*/dependencies/blocked_by*' '[]'
  route_json 'pr create*' 'https://github.com/acme/blog/pull/200'
  seed_commits develop 2 app.txt "feat: merged by others"
}

# spec branching-presets: Run in standard
test_run_in_standard_uses_origin_develop() {
  run_env
  cd "$SCRUM_REPO_DIR" || return 1
  run_scrum run start 102
  assert_status 0 "$STATUS" "$ERR"
  local int
  int="$(current_branch)"
  assert_eq "$(git --git-dir="$T/origin.git" rev-parse develop)" "$(head_of HEAD)" "the integration branch starts at origin/develop"
  # the agent's work, merged, and the pull request
  git -C "$SCRUM_REPO_DIR" worktree add -q -b agent-102 "$T/wt102" "$int" 2>/dev/null
  printf 'from 102\n' > "$T/wt102/a.txt"
  git -C "$T/wt102" add -A
  git -C "$T/wt102" commit -q -m "#102 work"
  run_scrum run record 102 --done --branch agent-102
  assert_status 0 "$STATUS" "$ERR"
  run_scrum run merge 102
  assert_status 0 "$STATUS" "$ERR"
  run_scrum run finish
  assert_status 0 "$STATUS" "$ERR"
  [ -n "$(pr_opened "$int" develop)" ] || _fail "the run's pull request does not target develop: $(gh_calls | grep -E 'pr create|POST repos/acme/blog/pulls' || true)"
}

# ---------- sync (branch-collaboration) ----------

# sync_env  Standard; the user is on feat/12-login made from develop.
sync_env() {
  git_project "$CFG_STANDARD"
  sc_gh
  git -C "$SCRUM_REPO_DIR" checkout -q -b feat/12-login
  printf 'login\n' > "$SCRUM_REPO_DIR/login.txt"
  git -C "$SCRUM_REPO_DIR" add -A
  git -C "$SCRUM_REPO_DIR" commit -q -m "feat: login form"
  cd "$SCRUM_REPO_DIR" || return 1
}

# spec branch-collaboration: Behind the working branch
test_sync_merges_three_commits() {
  sync_env
  seed_commits develop 3 other.txt "feat: other"
  run_scrum sync
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "feat/12-login" "$(current_branch)"
  assert_eq "0" "$(git -C "$SCRUM_REPO_DIR" rev-list --count HEAD..origin/develop)" "origin/develop is merged in"
  git -C "$SCRUM_REPO_DIR" merge-base --is-ancestor "$(git --git-dir="$T/origin.git" rev-parse develop)" HEAD || _fail "the remote develop is not in the branch"
  assert_contains "$OUT" "3" "reports three commits brought in"
}

# spec branch-collaboration: Up to date
test_sync_up_to_date() {
  sync_env
  local before
  before="$(head_of HEAD)"
  run_scrum sync
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(all_out | tr '[:upper:]' '[:lower:]')" "up to date"
  assert_eq "$before" "$(head_of HEAD)" "nothing changes"
}

# spec branch-collaboration: Uncommitted changes
test_sync_refuses_uncommitted_changes() {
  sync_env
  seed_commits develop 1 other.txt "feat: other"
  printf 'edit\n' >> "$SCRUM_REPO_DIR/login.txt"
  local before
  before="$(head_of HEAD)"
  run_scrum sync
  [ "$STATUS" -ne 0 ] || _fail "sync must refuse with uncommitted changes"
  assert_contains "$(all_out | tr '[:upper:]' '[:lower:]')" "stash" "tells to commit or stash first"
  assert_eq "$before" "$(head_of HEAD)"
  [ ! -f "$SCRUM_REPO_DIR/.git/MERGE_HEAD" ] || _fail "a merge was started"
}

# spec branch-collaboration: On a long-lived branch
test_sync_refuses_on_develop() {
  sync_env
  git -C "$SCRUM_REPO_DIR" checkout -q develop
  seed_commits develop 1 other.txt "feat: other"
  local before
  before="$(head_of HEAD)"
  run_scrum sync
  [ "$STATUS" -ne 0 ] || _fail "sync must refuse on develop"
  assert_contains "$(all_out | tr '[:upper:]' '[:lower:]')" "task branch" "says it works on task branches"
  assert_eq "$before" "$(head_of HEAD)"
}

# spec branch-collaboration: Sync a task branch (a hotfix branch is synced with main)
test_sync_hotfix_branch_uses_main() {
  git_project "$CFG_STANDARD"
  sc_gh
  git -C "$SCRUM_REPO_DIR" checkout -q -b hotfix/31-payment-fails origin/main
  seed_commits main 1 fix.txt "fix: other hotfix"
  seed_commits develop 2 dev.txt "feat: not for main"
  cd "$SCRUM_REPO_DIR" || return 1
  run_scrum sync
  assert_status 0 "$STATUS" "$ERR"
  git -C "$SCRUM_REPO_DIR" merge-base --is-ancestor "$(git --git-dir="$T/origin.git" rev-parse main)" HEAD || _fail "main is not merged in"
  if git -C "$SCRUM_REPO_DIR" merge-base --is-ancestor "$(git --git-dir="$T/origin.git" rev-parse develop)" HEAD; then
    _fail "develop was merged into a hotfix branch"
  fi
}

# spec branch-collaboration: Conflict
test_sync_conflict_lists_file_author_subject() {
  sync_env
  # develop changes src/auth.ts (ruby, "feat: session timeout"); the task branch changes the same line
  git -C "$T/seed" fetch -q origin
  git -C "$T/seed" checkout -q -B develop origin/develop
  printf 'export const timeout = 60;\n' > "$T/seed/src/auth.ts"
  git -C "$T/seed" add -A
  GIT_AUTHOR_NAME=ruby GIT_AUTHOR_EMAIL=ruby@example.com git -C "$T/seed" commit -q -m "feat: session timeout"
  git -C "$T/seed" push -q origin develop 2>/dev/null
  printf 'export const timeout = 10;\n' > "$SCRUM_REPO_DIR/src/auth.ts"
  git -C "$SCRUM_REPO_DIR" add -A
  git -C "$SCRUM_REPO_DIR" commit -q -m "feat: shorter timeout"
  run_scrum sync
  local text
  text="$(all_out)"
  assert_contains "$text" "src/auth.ts"
  assert_contains "$text" "ruby"
  assert_contains "$text" "feat: session timeout"
  assert_contains "$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')" "abort" "says how to abort"
  [ -f "$SCRUM_REPO_DIR/.git/MERGE_HEAD" ] || _fail "the merge is not left in progress"
  assert_contains "$(git -C "$SCRUM_REPO_DIR" diff --name-only --diff-filter=U)" "src/auth.ts" "the conflict is not resolved by the command"
}

# ---------- branches (branch-collaboration) ----------

# branches_env CONFIG  A clone with feat/9-export (last commit by david eight working days ago,
# pushed) and feat/10-fresh (today, by ruby). Today is 2026-11-24.
branches_env() {
  git_project "$1"
  sc_gh
  export SCRUM_TODAY=2026-11-24 SCRUM_NOW=2026-11-24T08:00:00Z
  git -C "$SCRUM_REPO_DIR" checkout -q -b feat/9-export develop
  printf 'export\n' > "$SCRUM_REPO_DIR/export.txt"
  git -C "$SCRUM_REPO_DIR" add -A
  GIT_AUTHOR_NAME=david GIT_AUTHOR_EMAIL=david@example.com GIT_AUTHOR_DATE=2026-11-12T10:00:00Z GIT_COMMITTER_DATE=2026-11-12T10:00:00Z \
    git -C "$SCRUM_REPO_DIR" commit -q -m "feat: export"
  git -C "$SCRUM_REPO_DIR" push -q origin feat/9-export 2>/dev/null
  git -C "$SCRUM_REPO_DIR" checkout -q -b feat/10-fresh develop
  printf 'fresh\n' > "$SCRUM_REPO_DIR/fresh.txt"
  git -C "$SCRUM_REPO_DIR" add -A
  GIT_AUTHOR_NAME=ruby GIT_AUTHOR_EMAIL=ruby@example.com GIT_AUTHOR_DATE=2026-11-24T07:00:00Z GIT_COMMITTER_DATE=2026-11-24T07:00:00Z \
    git -C "$SCRUM_REPO_DIR" commit -q -m "feat: fresh"
  git -C "$SCRUM_REPO_DIR" push -q origin feat/10-fresh 2>/dev/null
  git -C "$SCRUM_REPO_DIR" checkout -q develop
  git -C "$SCRUM_REPO_DIR" fetch -q origin
  route_branch_head main aaa000main
  route_branch_head develop bbb000dev
  route_branch_head staging ccc000stg
  # #12 and #13 are on develop; main lacks both (and develop is two commits ahead of main)
  route_issues "[$(issue_json 12 'In review' develop),$(issue_json 13 'In review' develop)]"
  route_task_pr 12 21 aaa111
  route_task_pr 13 22 bbb222
  route_contains aaa111 '*' behind
  route_contains bbb222 '*' behind
  route_contains aaa111 develop ahead
  route_contains bbb222 develop ahead
  route_contains aaa111 bbb000dev ahead
  route_contains bbb222 bbb000dev ahead
  # assumes: branch pairs are compared as compare/<upper>...<lower> or compare/<lower>...<upper>
  route_json 'api repos/acme/blog/compare/main...develop' '{"status":"ahead","ahead_by":2,"behind_by":0,"total_commits":2,"commits":[{"sha":"aaa111"},{"sha":"bbb222"}]}'
  route_json 'api repos/acme/blog/compare/aaa000main...bbb000dev' '{"status":"ahead","ahead_by":2,"behind_by":0,"total_commits":2,"commits":[{"sha":"aaa111"},{"sha":"bbb222"}]}'
  route_json 'api repos/acme/blog/compare/develop...main' '{"status":"behind","ahead_by":0,"behind_by":2,"total_commits":0,"commits":[]}'
  route_json 'api repos/acme/blog/compare/bbb000dev...aaa000main' '{"status":"behind","ahead_by":0,"behind_by":2,"total_commits":0,"commits":[]}'
  route_json 'api repos/acme/blog/commits/aaa111/pulls*' '[{"number":21,"merged_at":"2026-11-18T10:00:00Z","merge_commit_sha":"aaa111","body":"Closes #12","title":"feat: task 12","base":{"ref":"develop"},"head":{"ref":"feat/12-task"}}]'
  route_json 'api repos/acme/blog/commits/bbb222/pulls*' '[{"number":22,"merged_at":"2026-11-18T10:00:00Z","merge_commit_sha":"bbb222","body":"Closes #13","title":"feat: task 13","base":{"ref":"develop"},"head":{"ref":"feat/13-task"}}]'
  cd "$SCRUM_REPO_DIR" || return 1
}

# spec branch-collaboration: Waiting on develop
test_branches_develop_to_main_lists_tasks() {
  branches_env "$CFG_STANDARD"
  route_open_prs '[]'
  run_scrum branches
  assert_status 0 "$STATUS" "$ERR"
  local l
  l="$(printf '%s\n' "$OUT" | grep -E 'develop.*main' | head -1)"
  [ -n "$l" ] || _fail "no develop -> main line: $OUT"
  assert_contains "$OUT" "#12"
  assert_contains "$OUT" "#13"
  assert_eq "" "$(gh_writes)" "read-only"
}

# spec branch-collaboration: Branch overview (--json prints the same as data)
test_branches_json_is_data() {
  branches_env "$CFG_STANDARD"
  route_open_prs '[]'
  run_scrum branches --json
  assert_status 0 "$STATUS" "$ERR"
  printf '%s' "$OUT" | jq -e . >/dev/null || _fail "--json is not JSON: $OUT"
  assert_contains "$OUT" "12"
  assert_contains "$OUT" "feat/9-export"
}

# drift_env  main holds a hotfix commit that develop lacks.
drift_env() {
  branches_env "$CFG_STANDARD"
  route_first 'api repos/acme/blog/compare/develop...main' "$(printf '{"status":"diverged","ahead_by":1,"behind_by":2,"total_commits":1,"commits":[{"sha":"fff999","commit":{"message":"fix: payment (#31)"}}]}' > "$FAKE_GH_DIR/d1.json"; echo d1.json)"
  route_first 'api repos/acme/blog/compare/bbb000dev...aaa000main' d1.json
  route_first 'api repos/acme/blog/compare/main...develop' "$(printf '{"status":"diverged","ahead_by":2,"behind_by":1,"total_commits":2,"commits":[{"sha":"aaa111"},{"sha":"bbb222"}]}' > "$FAKE_GH_DIR/d2.json"; echo d2.json)"
  route_first 'api repos/acme/blog/compare/aaa000main...bbb000dev' d2.json
  route_first 'api repos/acme/blog/compare/aaa000main...develop' d2.json
}

# spec branch-collaboration: Drift (with the open back-merge)
test_branches_drift_names_open_back_merge() {
  drift_env
  route_open_prs '[{"number":50,"title":"Back-merge main into develop","head":"main","base":"develop"}]'
  run_scrum branches
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#50" "names the open back-merge pull request"
}

# spec branch-collaboration: Drift (no back-merge open)
test_branches_drift_without_back_merge() {
  drift_env
  route_open_prs '[]'
  run_scrum branches
  assert_status 0 "$STATUS" "$ERR"
  printf '%s\n' "$OUT" | grep -qiE 'back-merge|back merge' || _fail "the drift is not reported: $OUT"
  printf '%s\n' "$OUT" | grep -qiE 'none|no (open )?back|not open|is open: no' || _fail "does not say that no back-merge is open: $OUT"
}

# spec branch-collaboration: Stale branch
test_branches_stale_branch_with_author() {
  branches_env "branching: {preset: standard, stale_days: 5}
statuses: {in_review: In review}"
  route_open_prs '[]'
  run_scrum branches
  assert_status 0 "$STATUS" "$ERR"
  local l
  l="$(printf '%s\n' "$OUT" | grep -F 'feat/9-export' | head -1)"
  [ -n "$l" ] || _fail "feat/9-export is not listed as stale: $OUT"
  assert_contains "$OUT" "david"
  assert_not_contains "$OUT" "feat/10-fresh" "a branch with a commit today is not stale"
}

# spec branch-collaboration: Trunk
test_branches_trunk_shows_prs_and_stale_only() {
  branches_env 'version: 1'
  route_open_prs '[{"number":21,"title":"feat: profile","head":"feat/8-profile","base":"main"}]'
  run_scrum branches
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#21" "open pull requests are shown"
  assert_contains "$OUT" "feat/9-export" "stale task branches are shown"
  assert_not_contains "$OUT" "develop" "no long-lived branch pairs in trunk"
}

# ---------- cleanup (branch-collaboration) ----------

# cleanup_env  feat/7-signup was squash-merged through PR #30 (its commit is not in develop);
# feat/8-profile has an open PR #31 and no commit of its own. The user is on develop.
cleanup_env() {
  git_project "$CFG_STANDARD"
  sc_gh
  local b
  for b in feat/7-signup feat/8-profile; do
    git -C "$SCRUM_REPO_DIR" checkout -q -b "$b" develop
  done
  git -C "$SCRUM_REPO_DIR" checkout -q feat/7-signup
  printf 'signup\n' > "$SCRUM_REPO_DIR/signup.txt"
  git -C "$SCRUM_REPO_DIR" add -A
  git -C "$SCRUM_REPO_DIR" commit -q -m "feat: signup"
  git -C "$SCRUM_REPO_DIR" push -q origin feat/7-signup feat/8-profile 2>/dev/null
  git -C "$SCRUM_REPO_DIR" checkout -q develop
  # the squash merge on develop
  seed_commits develop 1 signup.txt "feat: signup (#30)"
  git -C "$SCRUM_REPO_DIR" fetch -q origin
  local merged open
  merged='{"number":30,"title":"feat: signup","state":"closed","merged_at":"2026-11-20T10:00:00Z","merge_commit_sha":"sq30","head":{"ref":"feat/7-signup"},"base":{"ref":"develop"},"html_url":"https://github.com/acme/blog/pull/30"}'
  open='{"number":31,"title":"feat: profile","state":"open","merged_at":null,"head":{"ref":"feat/8-profile"},"base":{"ref":"develop"},"html_url":"https://github.com/acme/blog/pull/31"}'
  # assumes: pull requests are read by state (closed/all/open) or by head branch
  route_json 'api*repos/acme/blog/pulls[?]*state=open*head=*7-signup*' '[]'
  route_json 'api*repos/acme/blog/pulls[?]*head=*7-signup*' "[$merged]"
  route_json 'api*repos/acme/blog/pulls[?]*state=closed*head=*8-profile*' '[]'
  route_json 'api*repos/acme/blog/pulls[?]*head=*8-profile*' "[$open]"
  route_json 'api*repos/acme/blog/pulls[?]*state=closed*' "[$merged]"
  route_json 'api*repos/acme/blog/pulls[?]*state=all*' "[$merged,$open]"
  route_open_prs '[{"number":31,"title":"feat: profile","head":"feat/8-profile","base":"develop"}]'
  cd "$SCRUM_REPO_DIR" || return 1
}

remote_has() { git --git-dir="$T/origin.git" show-ref --verify --quiet "refs/heads/$1"; }
local_has() { git -C "$SCRUM_REPO_DIR" show-ref --verify --quiet "refs/heads/$1"; }

# spec branch-collaboration: Preview
test_cleanup_preview_lists_squash_merged_branch() {
  cleanup_env
  run_scrum cleanup
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "feat/7-signup"
  local_has feat/7-signup || _fail "the preview deleted the local branch"
  remote_has feat/7-signup || _fail "the preview deleted the remote branch"
  assert_eq "" "$(gh_writes)"
}

# spec branch-collaboration: Branch with an open pull request
test_cleanup_skips_open_pr_long_lived_and_current() {
  cleanup_env
  run_scrum cleanup
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$OUT" "feat/8-profile"
}

# spec branch-collaboration: Delete
test_cleanup_yes_deletes_locally_and_on_remote() {
  cleanup_env
  run_scrum cleanup --yes
  assert_status 0 "$STATUS" "$ERR"
  if local_has feat/7-signup; then _fail "feat/7-signup is still a local branch"; fi
  if remote_has feat/7-signup; then _fail "feat/7-signup is still on the remote"; fi
  local_has feat/8-profile || _fail "the branch with an open pull request was deleted"
  remote_has feat/8-profile || _fail "the remote branch with an open pull request was deleted"
  local_has develop || _fail "develop was deleted"
  remote_has main || _fail "main was deleted on the remote"
}
