# Scenario tests (black box, from the specs) for stream D: release-pr, branch-promotion and
# next-step-guidance. Change: branching-and-release-flow.

# shellcheck source=fixtures/scenarios/helpers.sh
. "$FIXTURES/scenarios/helpers.sh"

all_out() { printf '%s\n%s' "$OUT" "$ERR"; }
lower_out() { all_out | tr '[:upper:]' '[:lower:]'; }

# ---------- release pull request ----------

# rel_env CONFIG ISSUES_JSON  Previous version v1.3.0 (2026-11-01). Heads: main aaa000main,
# develop dev999, staging stg555. No release pull request is open, no tag or release v1.4.x.
rel_env() {
  sc_gh
  sc_gh_bodies
  setup_repo "$1"
  export SCRUM_TODAY=2026-11-24 SCRUM_NOW=2026-11-24T08:00:00Z
  route_json 'api repos/acme/blog' '{"full_name":"acme/blog","default_branch":"main"}'
  route_branch_head main aaa000main
  route_branch_head develop dev999
  route_branch_head staging stg555
  route_json 'api repos/acme/blog/commits/abc123' '{"sha":"abc123","commit":{"committer":{"date":"2026-11-19T10:00:00Z"}}}'
  route_json 'api --paginate repos/acme/blog/tags*' '[{"name":"v1.3.0","commit":{"sha":"tag130"}}]'
  route_json 'api repos/acme/blog/compare/v1.3.0...*' '{"status":"ahead","ahead_by":3,"behind_by":0,
    "base_commit":{"sha":"tag130","commit":{"committer":{"date":"2026-11-01T08:00:00Z"}}},
    "commits":[{"sha":"aaa111"},{"sha":"bbb222"},{"sha":"ccc333"}]}'
  route 'api repos/acme/blog/git/ref/tags/*' '!404'
  route 'api repos/acme/blog/git/refs/tags/*' '!404'
  route 'api repos/acme/blog/releases/tags/*' '!404'
  route_json 'api --paginate repos/acme/blog/releases*' '[]'
  route_json 'api repos/acme/blog/releases*' '[]'
  # writes
  route_json 'api -X POST repos/acme/blog/git/refs --input -' '{"ref":"refs/heads/release/v1.4.0","object":{"sha":"dev999"}}'
  route_json 'api -X POST repos/acme/blog/pulls --input -' '{"number":60,"html_url":"https://github.com/acme/blog/pull/60"}'
  route_json 'pr create*' 'https://github.com/acme/blog/pull/60'
  route_json 'api -X POST repos/acme/blog/git/tags --input -' '{"sha":"tagobj140"}'
  route_json 'api -X POST repos/acme/blog/releases --input -' '{"html_url":"https://github.com/acme/blog/releases/tag/v1.4.0"}'
  route_issues "$2"
  # assumes: merged pull requests of a commit are read with repos/{r}/commits/{sha}/pulls
  route_json 'api*repos/acme/blog/commits/aaa111/pulls*' '[{"number":21,"title":"feat: task 12","body":"Closes #12","merged_at":"2026-11-18T10:00:00Z","merge_commit_sha":"aaa111","base":{"ref":"develop"},"head":{"ref":"feat/12-task"},"labels":[]}]'
  route_json 'api*repos/acme/blog/commits/bbb222/pulls*' '[{"number":22,"title":"feat: task 13","body":"Closes #13","merged_at":"2026-11-20T10:00:00Z","merge_commit_sha":"bbb222","base":{"ref":"develop"},"head":{"ref":"feat/13-task"},"labels":[]}]'
  route_json 'api*repos/acme/blog/commits/*/pulls*' '[]'
  route_json 'api*repos/acme/blog/pulls[?]*state=closed*' '[]'
  route_open_prs '[]'
}

# A feature task #12 on develop, merged as aaa111 (contained in develop and in its head).
std_release_env() {
  rel_env "$CFG_STANDARD" "[$(issue_json 12 'In review' develop)]"
  route_task_pr 12 21 aaa111
  route_contains aaa111 '*' ahead
}

ref_sent() { stdin_of '-X POST repos/acme/blog/git/refs' | jq -c '{ref, sha}'; }

# spec release-pr: Standard
test_release_pr_standard() {
  std_release_env
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(ref_sent)" '{"ref":"refs/heads/release/v1.4.0","sha":"dev999"}' "release/v1.4.0 at the head of develop"
  local pr
  pr="$(pr_opened release/v1.4.0 main)"
  [ -n "$pr" ] || _fail "no pull request from release/v1.4.0 into main: $(gh_calls)"
  assert_contains "$pr" "Release v1.4.0"
  assert_contains "$pr" "#12" "the notes are the body"
  assert_not_contains "$(gh_calls)" "-X POST repos/acme/blog/git/tags" "no tag is created"
  assert_not_contains "$(gh_calls)" "-X POST repos/acme/blog/releases" "no GitHub Release is created"
  assert_not_contains "$(ref_sent)" "refs/tags/" "no tag ref is created"
}

# spec release-pr: Environments
test_release_pr_environments_starts_at_staging() {
  rel_env "$CFG_ENVIRONMENTS" "[$(issue_json 12 'In review' staging)]"
  route_task_pr 12 21 aaa111
  route_contains aaa111 '*' ahead
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(ref_sent)" '{"ref":"refs/heads/release/v1.4.0","sha":"stg555"}'
  [ -n "$(pr_opened release/v1.4.0 main)" ] || _fail "no release pull request into main"
}

# spec release-pr: Release up to a commit
test_release_pr_from_commit() {
  std_release_env
  run_scrum release 1.4.0 --from abc123 --yes
  assert_status 0 "$STATUS" "$ERR"
  local sha
  sha="$(stdin_of '-X POST repos/acme/blog/git/refs' | jq -r 'select(.ref == "refs/heads/release/v1.4.0") | .sha')"
  case "$sha" in abc123*) ;; *) _fail "release/v1.4.0 does not start at abc123 (got: $sha)" ;; esac
}

# spec release-pr: Release already open
test_release_pr_already_open_stops() {
  std_release_env
  route_first 'api --paginate repos/acme/blog/pulls[?]state=open&per_page=100&base=main' \
    "$(printf '[{"number":58,"title":"Release v1.3.5","html_url":"https://github.com/acme/blog/pull/58","head":{"ref":"release/v1.3.5"},"base":{"ref":"main"},"body":""}]' > "$FAKE_GH_DIR/open-rel.json"; echo open-rel.json)"
  route_first 'api --paginate repos/acme/blog/pulls[?]state=open*' open-rel.json
  run_scrum release 1.4.0 --yes
  assert_contains "$(all_out)" "58" "names the open release pull request"
  assert_eq "" "$(gh_writes)" "creates nothing"
}

# tasks_env  #12 merged into develop before abc123 (aaa111), #13 after it (bbb222).
tasks_env() {
  rel_env "$CFG_STANDARD" "[$(issue_json 12 'In review' develop),$(issue_json 13 'In review' develop)]"
  route_task_pr 12 21 aaa111
  route_task_pr 13 22 bbb222 develop 2026-11-20T10:00:00Z
  route_contains aaa111 '*' ahead
  route_contains bbb222 abc123 behind
  route_contains bbb222 '*' ahead
}

# spec release-pr: Task merged after the release point
test_release_tasks_before_from_only() {
  tasks_env
  run_scrum release --from abc123
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#12"
  assert_not_contains "$OUT" "#13"
  assert_eq "" "$(gh_writes)" "a preview writes nothing"
}

# spec release-pr: Environments, task not promoted
test_release_environments_lists_only_staging_tasks() {
  rel_env "$CFG_ENVIRONMENTS" "[$(issue_json 12 'In review' staging),$(issue_json 13 'In review' develop)]"
  route_task_pr 12 21 aaa111 develop
  route_task_pr 13 22 bbb222 develop 2026-11-20T10:00:00Z
  route_contains aaa111 '*' ahead
  route_contains bbb222 staging behind
  route_contains bbb222 stg555 behind
  route_contains bbb222 '*' ahead
  run_scrum release
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#12"
  assert_not_contains "$OUT" "#13"
}

# spec release-pr: Nothing to release
test_release_nothing_to_release() {
  rel_env "$CFG_STANDARD" "[$(issue_json 14 'In progress')]"
  route_first 'api repos/acme/blog/compare/v1.3.0...*' "$(printf '{"status":"identical","ahead_by":0,"behind_by":0,"base_commit":{"commit":{"committer":{"date":"2026-11-01T08:00:00Z"}}},"commits":[]}' > "$FAKE_GH_DIR/same.json"; echo same.json)"
  run_scrum release 1.4.0 --yes
  assert_contains "$(lower_out)" "nothing to release"
  assert_eq "" "$(gh_writes)" "creates nothing"
}

# spec release-pr: Dependency update (untasked pull request #40 under "Other", minor bump from #12)
test_release_untasked_pr_under_other() {
  std_release_env
  route_first 'api*repos/acme/blog/commits/ccc333/pulls*' "$(printf '[{"number":40,"title":"chore: bump actions","body":"Bumps actions/checkout","merged_at":"2026-11-21T10:00:00Z","merge_commit_sha":"ccc333","base":{"ref":"develop"},"head":{"ref":"dependabot/github_actions/x"},"labels":[{"name":"no-task"}]}]' > "$FAKE_GH_DIR/p40.json"; echo p40.json)"
  route_first 'api*repos/acme/blog/pulls[?]*state=closed*' "$(jq -c '.' "$FAKE_GH_DIR/p40.json" > "$FAKE_GH_DIR/closed40.json"; echo closed40.json)"
  route_contains ccc333 '*' ahead
  run_scrum release
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Other"
  local other
  other="$(printf '%s\n' "$OUT" | sed -n '/Other/,$p')"
  assert_contains "$other" "#40" "#40 is listed under Other"
  assert_contains "$OUT" "v1.4.0" "a minor bump from v1.3.0 (feature #12)"
  assert_not_contains "$OUT" "v1.3.1"
}

# spec release-pr: Pull requests without a task (only untasked pull requests: a patch)
test_release_only_untasked_is_patch() {
  rel_env "$CFG_STANDARD" '[]'
  route_first 'api*repos/acme/blog/commits/ccc333/pulls*' "$(printf '[{"number":40,"title":"feat: bump actions","body":"Bumps","merged_at":"2026-11-21T10:00:00Z","merge_commit_sha":"ccc333","base":{"ref":"develop"},"head":{"ref":"deps"},"labels":[{"name":"no-task"}]}]' > "$FAKE_GH_DIR/p40.json"; echo p40.json)"
  route_first 'api*repos/acme/blog/pulls[?]*state=closed*' p40.json
  route_contains ccc333 '*' ahead
  run_scrum release
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "v1.3.1" "only untasked pull requests: a patch"
}

# spec release-pr: Version file
test_release_version_file_one_commit() {
  std_release_env
  printf 'release:\n  version_files:\n    - path: package.json\n' >> "$SCRUM_REPO_DIR/.github/scrum.yml"
  local pkg
  pkg="$(printf '{\n  "name": "blog",\n  "version": "1.3.0"\n}\n' | base64 | tr -d '\n')"
  # assumes: files are read and written with the contents API
  route_json 'api repos/acme/blog/contents/package.json*' "{\"type\":\"file\",\"path\":\"package.json\",\"sha\":\"pkgsha\",\"encoding\":\"base64\",\"content\":\"$pkg\"}"
  route_json 'api -X PUT repos/acme/blog/contents/package.json --input -' '{"commit":{"sha":"vercommit"}}'
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  local puts
  puts="$(stdin_of '-X PUT repos/acme/blog/contents/')"
  assert_eq "1" "$(printf '%s\n' "$puts" | grep -c . | tr -d ' ')" "one commit"
  assert_eq "release/v1.4.0" "$(printf '%s' "$puts" | jq -r .branch)" "on the release branch"
  assert_eq "1.4.0" "$(printf '%s' "$puts" | jq -r .content | base64 -d 2>/dev/null | jq -r .version)"
  [ -n "$(pr_opened release/v1.4.0 main)" ] || _fail "the pull request is opened after the commit"
}

# spec release-pr: Version files and changelog (with neither set, no extra commit)
test_release_without_version_files_no_commit() {
  std_release_env
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$(gh_calls)" "repos/acme/blog/contents/" "no file is read or written"
  assert_not_contains "$(gh_calls)" "-X POST repos/acme/blog/git/commits"
  [ -n "$(pr_opened release/v1.4.0 main)" ] || _fail "the release pull request is opened"
}

# spec release-pr: File without a version
test_release_file_without_version_stops_before_branch() {
  std_release_env
  printf 'release:\n  version_files:\n    - path: app/version.py\n      pattern: "__version__ = \\"{version}\\""\n' >> "$SCRUM_REPO_DIR/.github/scrum.yml"
  local py
  py="$(printf 'NAME = "blog"\n' | base64 | tr -d '\n')"
  route_json 'api repos/acme/blog/contents/app/version.py*' "{\"type\":\"file\",\"path\":\"app/version.py\",\"sha\":\"pysha\",\"encoding\":\"base64\",\"content\":\"$py\"}"
  route_json 'api repos/acme/blog/contents/app%2Fversion.py*' "{\"type\":\"file\",\"path\":\"app/version.py\",\"sha\":\"pysha\",\"encoding\":\"base64\",\"content\":\"$py\"}"
  run_scrum release 1.4.0 --yes
  [ "$STATUS" -ne 0 ] || _fail "the release must stop"
  assert_contains "$(all_out)" "app/version.py" "names the file"
  assert_eq "" "$(gh_writes)" "stops before creating the branch"
}

# ---------- release finish (publishing on merge) ----------

REL_BODY=$'<!-- scrum-release-notes -->\n## Features\n\n- Task 12 (#12, PR #21)\n<!-- scrum-release-notes -->'

# finish_env CONFIG HEAD BODY [MERGED]  The pull request #60 from HEAD into main, merged as
# mrg777 (or closed without merging), as the event and through the API.
finish_env() {
  rel_env "$1" "[$(issue_json 12 'In review' develop)]"
  route_task_pr 12 21 aaa111
  route_contains aaa111 '*' ahead
  export GITHUB_EVENT_NAME=pull_request_target GITHUB_EVENT_PATH="$T/event.json"
  jq -n --arg h "$2" --arg body "$3" --argjson m "${4:-true}" '{action: "closed", number: 60,
    pull_request: {number: 60, title: (if ($h | startswith("release/")) then "Release v1.4.0" else "fix: payment fails" end),
      body: $body, state: "closed", merged: $m, merged_at: (if $m then "2026-11-24T09:00:00Z" else null end),
      merge_commit_sha: (if $m then "mrg777" else null end), draft: false, labels: [],
      head: {ref: $h}, base: {ref: "main"}, html_url: "https://github.com/acme/blog/pull/60"},
    repository: {full_name: "acme/blog"}}' > "$GITHUB_EVENT_PATH"
  route_json 'api repos/acme/blog/pulls/60' "$(jq -c .pull_request "$GITHUB_EVENT_PATH")"
  route_branch_head main mrg777
  # develop does not contain the new head of main
  route_contains mrg777 develop behind
  route_contains mrg777 staging behind
  route_contains mrg777 dev999 behind
  route_contains mrg777 stg555 behind
  route_json 'api repos/acme/blog/compare/develop...main' '{"status":"ahead","ahead_by":1,"behind_by":0}'
  route_json 'api repos/acme/blog/compare/staging...main' '{"status":"ahead","ahead_by":1,"behind_by":0}'
  route_json 'api repos/acme/blog/compare/main...develop' '{"status":"behind","ahead_by":0,"behind_by":1}'
  route_json 'api repos/acme/blog/compare/main...staging' '{"status":"behind","ahead_by":0,"behind_by":1}'
}

tag_sent() { stdin_of '-X POST repos/acme/blog/git/tags' | jq -c '{tag, object}'; }

# spec release-pr: Release merged
test_release_finish_publishes_and_closes_tasks() {
  finish_env "$CFG_STANDARD" release/v1.4.0 "$REL_BODY"
  run_scrum release finish --pr 60
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(tag_sent)" '{"tag":"v1.4.0","object":"mrg777"}' "the tag points at the merge commit"
  assert_contains "$(stdin_of '-X POST repos/acme/blog/git/refs')" '"refs/tags/v1.4.0"'
  assert_contains "$(stdin_of '-X POST repos/acme/blog/releases' | jq -r .tag_name)" "v1.4.0" "the GitHub Release exists"
  local labels
  labels="$(stdin_of '-X PUT repos/acme/blog/issues/12/labels' | tail -1)"
  assert_contains "$labels" '"status: Done"'
  assert_not_contains "$labels" '"on: develop"' "no location label"
  assert_contains "$(stdin_of '-X PATCH repos/acme/blog/issues/12 ')" '"state":"closed"' "#12 is closed"
  assert_contains "$(stdin_of '-X PATCH repos/acme/blog/issues/12 ')" '"state_reason":"completed"'
}

# spec release-pr: After a release in standard
test_release_finish_opens_back_merge_into_develop() {
  finish_env "$CFG_STANDARD" release/v1.4.0 "$REL_BODY"
  run_scrum release finish --pr 60
  assert_status 0 "$STATUS" "$ERR"
  [ -n "$(pr_opened main develop)" ] || _fail "no back-merge pull request from main into develop: $(gh_calls | grep -E 'pr create|POST repos/acme/blog/pulls' || true)"
}

# spec release-pr: Workflow runs twice
test_release_finish_rerun_changes_nothing() {
  finish_env "$CFG_STANDARD" release/v1.4.0 "$REL_BODY"
  route_issues "[$(issue_json 12 Done '' '' closed)]"
  route_first 'api repos/acme/blog/git/ref/tags/v1.4.0' "$(printf '{"ref":"refs/tags/v1.4.0","object":{"sha":"tagobj140","type":"tag"}}' > "$FAKE_GH_DIR/tagref.json"; echo tagref.json)"
  route_first 'api repos/acme/blog/git/refs/tags/v1.4.0' tagref.json
  route_first 'api repos/acme/blog/git/tags/tagobj140' "$(printf '{"tag":"v1.4.0","object":{"sha":"mrg777","type":"commit"}}' > "$FAKE_GH_DIR/tagobj.json"; echo tagobj.json)"
  route_first 'api --paginate repos/acme/blog/tags*' "$(printf '[{"name":"v1.4.0","commit":{"sha":"mrg777"}},{"name":"v1.3.0","commit":{"sha":"tag130"}}]' > "$FAKE_GH_DIR/tags2.json"; echo tags2.json)"
  printf '[{"tag_name":"v1.4.0","draft":false,"html_url":"https://github.com/acme/blog/releases/tag/v1.4.0"}]' > "$FAKE_GH_DIR/rels.json"
  route_first 'api --paginate repos/acme/blog/releases*' rels.json
  route_first 'api repos/acme/blog/releases[?]*' rels.json
  route_first 'api repos/acme/blog/releases/tags/v1.4.0' "$(printf '{"tag_name":"v1.4.0","html_url":"https://github.com/acme/blog/releases/tag/v1.4.0"}' > "$FAKE_GH_DIR/rel.json"; echo rel.json)"
  route_open_prs '[{"number":61,"title":"Back-merge main into develop","head":"main","base":"develop"}]'
  run_scrum release finish --pr 60
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(lower_out)" "already" "reports the version as already published"
  assert_eq "" "$(gh_writes)" "changes nothing"
}

# spec release-pr: Release pull request closed without merging
test_release_finish_closed_without_merge_does_nothing() {
  finish_env "$CFG_STANDARD" release/v1.4.0 "$REL_BODY" false
  run_scrum release finish --pr 60
  assert_eq "" "$(gh_writes)" "no tag, no status change"
}

# spec release-pr: Environments (hotfix merged into main: back-merges into staging and develop)
test_release_finish_hotfix_environments_back_merges_both() {
  finish_env "$CFG_ENVIRONMENTS" hotfix/31-payment-fails "$(hotfix_body)"
  hotfix_routes
  run_scrum release finish --pr 60
  assert_status 0 "$STATUS" "$ERR"
  [ -n "$(pr_opened main staging)" ] || _fail "no back-merge into staging"
  [ -n "$(pr_opened main develop)" ] || _fail "no back-merge into develop"
}

# spec release-pr: Already open
test_release_finish_back_merge_already_open() {
  finish_env "$CFG_STANDARD" release/v1.4.0 "$REL_BODY"
  route_open_prs '[{"number":61,"title":"Back-merge main into develop","head":"main","base":"develop"}]'
  run_scrum release finish --pr 60
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(pr_opened main develop)" "no second back-merge"
}

# spec release-pr: Trunk
test_release_trunk_creates_tag_and_release_no_pr() {
  rel_env "$CFG_TRUNK" '[]'
  printf '[%s]' "$(issue_json 12 Done '' '' closed)" > "$FAKE_GH_DIR/closed.json"
  route_first 'api --paginate repos/acme/blog/issues?state=closed*' closed.json
  route_task_pr 12 21 aaa111 main
  route_contains aaa111 '*' ahead
  run_scrum release 1.4.0 --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(tag_sent)" '"tag":"v1.4.0"'
  assert_contains "$(stdin_of '-X POST repos/acme/blog/releases' | jq -r .tag_name)" "v1.4.0"
  if any_pr_opened; then _fail "trunk opens no release pull request"; fi
  assert_not_contains "$(gh_calls)" "refs/heads/release/"
}

# ---------- promote (branch-promotion) ----------

# promote_env CONFIG  #12 and #13 on develop; staging lacks both and the head of develop.
promote_env() {
  rel_env "$1" "[$(issue_json 12 'In review' develop),$(issue_json 13 'In review' develop)]"
  route_task_pr 12 21 aaa111
  route_task_pr 13 22 bbb222
  route_contains aaa111 staging behind
  route_contains bbb222 staging behind
  route_contains aaa111 stg555 behind
  route_contains bbb222 stg555 behind
  route_contains aaa111 '*' ahead
  route_contains bbb222 '*' ahead
  # assumes: "staging contains develop" is compare/<develop or its sha>...staging (or the reverse)
  route_json 'api repos/acme/blog/compare/staging...develop' '{"status":"ahead","ahead_by":2,"behind_by":0}'
  route_json 'api repos/acme/blog/compare/stg555...dev999' '{"status":"ahead","ahead_by":2,"behind_by":0}'
  route_json 'api repos/acme/blog/compare/develop...staging' '{"status":"behind","ahead_by":0,"behind_by":2}'
  route_json 'api repos/acme/blog/compare/dev999...staging' '{"status":"behind","ahead_by":0,"behind_by":2}'
  route_json 'api repos/acme/blog/compare/dev999...stg555' '{"status":"behind","ahead_by":0,"behind_by":2}'
  route_first 'api -X POST repos/acme/blog/pulls --input -' "$(printf '{"number":70,"html_url":"https://github.com/acme/blog/pull/70"}' > "$FAKE_GH_DIR/p70.json"; echo p70.json)"
}

# spec branch-promotion: Preview
test_promote_preview_lists_tasks() {
  promote_env "$CFG_ENVIRONMENTS"
  run_scrum promote
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#12"
  assert_contains "$OUT" "#13"
  if any_pr_opened; then _fail "a preview opens no pull request"; fi
  assert_eq "" "$(gh_writes)"
}

# spec branch-promotion: Open the promotion
test_promote_yes_opens_pr_listing_tasks() {
  promote_env "$CFG_ENVIRONMENTS"
  run_scrum promote --yes
  assert_status 0 "$STATUS" "$ERR"
  local pr
  pr="$(pr_opened develop staging)"
  [ -n "$pr" ] || _fail "no pull request from develop into staging: $(gh_calls)"
  assert_contains "$pr" "#12"
  assert_contains "$pr" "#13"
}

# spec branch-promotion: Nothing to promote
test_promote_nothing_to_promote() {
  promote_env "$CFG_ENVIRONMENTS"
  route_issues '[]'
  printf '{"status":"identical","ahead_by":0,"behind_by":0}' > "$FAKE_GH_DIR/ident.json"
  route_first 'api repos/acme/blog/compare/staging...develop' ident.json
  route_first 'api repos/acme/blog/compare/stg555...dev999' ident.json
  route_first 'api repos/acme/blog/compare/develop...staging' ident.json
  route_first 'api repos/acme/blog/compare/dev999...staging' ident.json
  route_first 'api repos/acme/blog/compare/dev999...stg555' ident.json
  run_scrum promote --yes
  assert_contains "$(lower_out)" "nothing to promote"
  if any_pr_opened; then _fail "no pull request when there is nothing to promote"; fi
}

# spec branch-promotion: Promotion already open
test_promote_already_open() {
  promote_env "$CFG_ENVIRONMENTS"
  route_open_prs '[{"number":71,"title":"Promote develop to staging","head":"develop","base":"staging"}]'
  run_scrum promote --yes
  assert_contains "$(all_out)" "71" "names the open promotion"
  if any_pr_opened; then _fail "opens no other pull request"; fi
}

# spec branch-promotion: Standard preset
test_promote_standard_points_to_release() {
  promote_env "$CFG_STANDARD"
  run_scrum promote --yes
  assert_contains "$(all_out)" "/scrum-github:release"
  assert_eq "" "$(gh_writes)"
}

# ---------- hotfix (branch-promotion) ----------

# hotfix_env STATE  Standard; #31 "Payment fails" (bug, STATE) unassigned; origin/main is two
# commits ahead of the local main.
hotfix_env() {
  git_project "$CFG_STANDARD"
  sc_gh
  route_json 'api repos/acme/blog/issues/31' "{\"number\":31,\"title\":\"Payment fails\",\"state\":\"$1\",\"assignees\":[],\"labels\":[{\"name\":\"status: New\"},{\"name\":\"bug\"}]}"
  git -C "$SCRUM_REPO_DIR" branch -q main origin/main 2>/dev/null || true
  seed_commits main 2 hot.txt "fix: earlier hotfix"
  cd "$SCRUM_REPO_DIR" || return 1
}

# spec branch-promotion: Start
test_hotfix_start_from_origin_main() {
  hotfix_env open
  run_scrum hotfix 31
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "hotfix/31-payment-fails" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)"
  assert_eq "$(git --git-dir="$T/origin.git" rev-parse main)" "$(git -C "$SCRUM_REPO_DIR" rev-parse HEAD)" "created from origin/main"
  assert_contains "$(stdin_of '-X PUT repos/acme/blog/issues/31/labels' | tail -1)" '"status: In progress"'
  assert_contains "$(stdin_of '-X POST repos/acme/blog/issues/31/assignees')" '"alice"' "assigned to the current user"
}

# spec branch-promotion: Closed issue
test_hotfix_closed_issue_refused() {
  hotfix_env closed
  run_scrum hotfix 31
  [ "$STATUS" -ne 0 ] || _fail "a closed issue is refused"
  assert_eq "" "$(gh_writes)" "changes nothing on GitHub"
  assert_eq "develop" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)" "changes nothing in git"
  if git -C "$SCRUM_REPO_DIR" show-ref --verify --quiet refs/heads/hotfix/31-payment-fails; then _fail "a hotfix branch was created"; fi
}

# spec branch-promotion: Start a hotfix (trunk stops and points to task start)
test_hotfix_trunk_refused() {
  git_project 'version: 1'
  sc_gh
  route_json 'api repos/acme/blog/issues/31' '{"number":31,"title":"Payment fails","state":"open","assignees":[],"labels":[{"name":"bug"}]}'
  cd "$SCRUM_REPO_DIR" || return 1
  run_scrum hotfix 31
  assert_contains "$(lower_out)" "task start"
  assert_eq "" "$(gh_writes)"
}

# The body of the hotfix pull request: "Closes #31" and the version it publishes.
# assumes: the marker of the hotfix version (written by hotfix prepare) is one of these forms
hotfix_body() {
  printf '%s\n' 'Closes #31' '' 'Publishes v1.4.1.' '<!-- scrum-release: v1.4.1 -->' '<!-- scrum:version=v1.4.1 -->' \
    '<!-- scrum-release-version: v1.4.1 -->' '<!-- scrum-release-notes -->' '## Bug fixes' '' '- Payment fails (#31)' '<!-- scrum-release-notes -->'
}

# hotfix_routes  Previous version v1.4.0; #31 a bug In review closed by the hotfix PR #60.
hotfix_routes() {
  route_first 'api --paginate repos/acme/blog/tags*' "$(printf '[{"name":"v1.4.0","commit":{"sha":"tag140"}}]' > "$FAKE_GH_DIR/tags140.json"; echo tags140.json)"
  route_first 'api repos/acme/blog/compare/v1.4.0...*' "$(printf '{"status":"ahead","ahead_by":1,"behind_by":0,"base_commit":{"sha":"tag140","commit":{"committer":{"date":"2026-11-20T08:00:00Z"}}},"commits":[{"sha":"mrg777"}]}' > "$FAKE_GH_DIR/c140.json"; echo c140.json)"
  route_issues "[$(issue_json 31 'In review' '' bug)]"
  route_first 'api --paginate repos/acme/blog/issues/31/timeline*' "$(jq -nc '[{event: "cross-referenced", source: {issue: {number: 60, body: "Closes #31", pull_request: {merged_at: "2026-11-24T09:00:00Z"}, repository: {full_name: "acme/blog"}}}}]' > "$FAKE_GH_DIR/tl31.json"; echo tl31.json)"
  route_first 'api*repos/acme/blog/commits/mrg777/pulls*' "$(jq -c '[.pull_request]' "$GITHUB_EVENT_PATH" > "$FAKE_GH_DIR/p60.json"; echo p60.json)"
  route_contains mrg777 main identical
  route_contains mrg777 mrg777 identical
  route_first 'api -X POST repos/acme/blog/git/tags --input -' "$(printf '{"sha":"tagobj141"}' > "$FAKE_GH_DIR/t141.json"; echo t141.json)"
}

# spec branch-promotion: Hotfix merged
test_hotfix_merged_publishes_patch() {
  finish_env "$CFG_STANDARD" hotfix/31-payment-fails "$(hotfix_body)"
  hotfix_routes
  # the status event of the merged pull request, then the release workflow
  run_scrum event
  assert_status 0 "$STATUS" "$ERR"
  run_scrum release finish --pr 60
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(tag_sent)" '{"tag":"v1.4.1","object":"mrg777"}' "tag v1.4.1 on the merge commit"
  assert_contains "$(stdin_of '-X POST repos/acme/blog/releases' | jq -r .tag_name)" "v1.4.1"
  assert_contains "$(stdin_of '-X PUT repos/acme/blog/issues/31/labels')" '"status: Done"'
  assert_contains "$(stdin_of '-X PATCH repos/acme/blog/issues/31 ')" '"state":"closed"'
  [ -n "$(pr_opened main develop)" ] || _fail "no back-merge pull request into develop"
}

# ---------- next (next-step-guidance) ----------

NEXT_SPRINT='{"number":3,"title":"Sprint 3","state":"open","description":"<!-- scrum:start=2026-11-16 end=2026-11-27 -->","due_on":"2026-11-27T00:00:00Z"}'

# next_env CONFIG ISSUES  Set up and pushed, Sprint 3 open, every long-lived branch has a rule,
# nothing open; alice has no task in progress.
next_env() {
  sc_gh
  setup_repo "$1"
  export SCRUM_TODAY=2026-11-24
  route 'api repos/acme/blog/contents/.github/workflows' "workflows.json"
  cp "$FIXTURES/remote-workflows.json" "$FAKE_GH_DIR/workflows.json"
  route_json 'api --paginate repos/acme/blog/milestones*' "[$NEXT_SPRINT]"
  printf '%s' "$2" > "$FAKE_GH_DIR/next-issues.json"
  route 'api --paginate repos/acme/blog/issues?milestone=3*' next-issues.json
  route_issues "$2"
  route_json 'api repos/acme/blog' '{"full_name":"acme/blog","default_branch":"main"}'
  route_branch_head main aaa000main
  route_branch_head develop dev999
  route_branch_head staging stg555
  # assumes: protection is read with repos/{r}/rules/branches/{b} (or the rulesets list)
  route_json 'api --paginate repos/acme/blog/rules/branches/*' '[{"type":"pull_request","ruleset_id":901}]'
  route_json 'api repos/acme/blog/rules/branches/*' '[{"type":"pull_request","ruleset_id":901}]'
  route_json 'api --paginate repos/acme/blog/rulesets*' '[{"id":901,"name":"scrum: main","target":"branch"}]'
  route_json 'api repos/acme/blog/rulesets*' '[{"id":901,"name":"scrum: main","target":"branch"}]'
  route_json 'api --paginate repos/acme/blog/issues/*/dependencies/blocked_by*' '[]'
}

on_develop_issues() { printf '[%s,%s]' "$(issue_json 12 'In review' develop)" "$(issue_json 13 'In review' develop)"; }

# spec next-step-guidance: Unprotected repository
test_next_unprotected_suggests_protect() {
  next_env "$CFG_STANDARD" '[]'
  route_open_prs '[]'
  route_first 'api --paginate repos/acme/blog/rules/branches/*' "$(printf '[]' > "$FAKE_GH_DIR/none.json"; echo none.json)"
  route_first 'api repos/acme/blog/rules/branches/*' none.json
  route_first 'api --paginate repos/acme/blog/rulesets*' none.json
  route_first 'api repos/acme/blog/rulesets*' none.json
  run_scrum next
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "/scrum-github:protect"
  assert_eq "" "$(gh_writes)"
}

# spec next-step-guidance: Back-merge open
test_next_back_merge_open_with_link() {
  next_env "$CFG_STANDARD" "$(on_develop_issues)"
  route_task_pr 12 21 aaa111
  route_task_pr 13 22 bbb222
  route_contains aaa111 '*' ahead
  route_contains bbb222 '*' ahead
  route_open_prs '[{"number":61,"title":"Back-merge main into develop","head":"main","base":"develop"}]'
  run_scrum next
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "https://github.com/acme/blog/pull/61" "the next step is to merge it, with its link"
}

# spec next-step-guidance: Ready to release
test_next_ready_to_release_with_count() {
  next_env "$CFG_STANDARD" "$(on_develop_issues)"
  route_task_pr 12 21 aaa111
  route_task_pr 13 22 bbb222
  route_contains aaa111 '*' ahead
  route_contains bbb222 '*' ahead
  route_open_prs '[]'
  run_scrum next
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "/scrum-github:release"
  assert_contains "$OUT" "2" "with the number of tasks waiting"
}

# spec next-step-guidance: Ready to release (--json names the step)
test_next_ready_to_release_json() {
  next_env "$CFG_STANDARD" "$(on_develop_issues)"
  route_task_pr 12 21 aaa111
  route_task_pr 13 22 bbb222
  route_contains aaa111 '*' ahead
  route_contains bbb222 '*' ahead
  route_open_prs '[]'
  run_scrum next --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "/scrum-github:release" "$(printf '%s' "$OUT" | jq -r '.command' | awk '{print $1}')"
}

# spec next-step-guidance: Ready to promote
test_next_ready_to_promote() {
  next_env "$CFG_ENVIRONMENTS" "[$(issue_json 12 'In review' develop)]"
  route_task_pr 12 21 aaa111
  route_contains aaa111 staging behind
  route_contains aaa111 stg555 behind
  route_contains aaa111 '*' ahead
  route_json 'api repos/acme/blog/compare/staging...develop' '{"status":"ahead","ahead_by":1,"behind_by":0}'
  route_json 'api repos/acme/blog/compare/develop...staging' '{"status":"behind","ahead_by":0,"behind_by":1}'
  route_open_prs '[]'
  run_scrum next
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "/scrum-github:promote"
}
