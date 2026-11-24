# scrum promote and scrum hotfix (spec branch-promotion)

issues() { jq -sc . ; }
# open_issue NUMBER LABELS_CSV [TITLE] [STATE]
open_issue() {
  jq -nc --argjson n "$1" --arg l "${2:-}" --arg t "${3:-Task $1}" --arg s "${4:-open}" '{number: $n, title: $t, state: $s, body: "",
    labels: ($l | split(",") | map(select(. != "")) | map({name: .})), assignees: []}'
}
config_of() { printf 'version: 1\nbranching:\n  preset: %s\nstatuses:\n  in_review: In review\n' "$1"; }
write_paths() { gh_writes | sed 's/.*-X \([A-Z]*\) \([^ ]*\).*/\1 \2/' | paste -sd '|' -; }
stdin_of() { grep "^STDIN $1" "$FAKE_GH_LOG" | sed 's/^STDIN //'; }

# ---------- promote (spec "Promote the working branch to staging") ----------

# promote_env: environments; #12 and #13 In review on develop (merges aaa111, bbb222), neither on
# staging; develop (dev999) is ahead of staging.
promote_env() {
  setup_fake_gh
  setup_repo "$(config_of "${1:-environments}")"
  route 'auth status*' "auth.txt"
  cp "$FIXTURES/gh-auth-status.txt" "$FAKE_GH_DIR/auth.txt"
  route_json 'api --paginate repos/acme/blog/pulls?state=open&per_page=100&head=acme%3Adevelop&base=staging' '[]'
  route_json 'api repos/acme/blog/git/ref/heads/develop' '{"object":{"sha":"dev999"}}'
  route_json 'api repos/acme/blog/compare/dev999...staging' '{"status":"behind"}'
  route_json 'api --paginate repos/acme/blog/issues?state=open&labels=on%3A%20develop&per_page=100' \
    "$( { open_issue 12 'status: In review,on: develop'; open_issue 13 'status: In review,on: develop'; } | issues)"
  route_json 'api --paginate repos/acme/blog/issues?state=open&labels=on%3A%20staging&per_page=100' \
    "$(open_issue 11 'status: In review,on: staging' | issues)"
  route_json 'api --paginate repos/acme/blog/issues/12/timeline*' \
    '[{"event":"cross-referenced","source":{"issue":{"number":40,"body":"Closes #12","pull_request":{"merged_at":"2026-11-15T09:00:00Z"}}}}]'
  route_json 'api --paginate repos/acme/blog/issues/13/timeline*' \
    '[{"event":"cross-referenced","source":{"issue":{"number":41,"body":"Closes #13","pull_request":{"merged_at":"2026-11-16T09:00:00Z"}}}}]'
  route_json 'api repos/acme/blog/pulls/40' '{"number":40,"merge_commit_sha":"aaa111"}'
  route_json 'api repos/acme/blog/pulls/41' '{"number":41,"merge_commit_sha":"bbb222"}'
  route_json 'api repos/acme/blog/compare/aaa111...staging' '{"status":"behind"}'
  route_json 'api repos/acme/blog/compare/bbb222...staging' '{"status":"diverged"}'
  route_json 'api -X POST repos/acme/blog/pulls *' '{"number":60,"html_url":"https://github.com/acme/blog/pull/60"}'
}

# spec "Preview".
test_promote_preview_lists_the_tasks() {
  promote_env
  run_scrum promote
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#12  Task 12"
  assert_contains "$OUT" "#13  Task 13"
  assert_not_contains "$OUT" "Task 11"
  assert_not_contains "$(gh_calls)" "issues/11/timeline" "only the tasks on develop are checked"
  assert_eq "" "$(gh_writes)"
}

test_promote_json() {
  promote_env
  run_scrum promote --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "develop staging [12,13] false" "$(printf '%s' "$OUT" | jq -r '"\(.working) \(.staging) \([.tasks[].number] | tojson) \(.nothing)"')"
}

# spec "Open the promotion".
test_promote_yes_opens_the_pull_request() {
  promote_env
  run_scrum promote --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "POST repos/acme/blog/pulls" "$(write_paths)"
  assert_eq "Promote develop to staging develop staging" "$(stdin_of '{"title"' | jq -r '"\(.title) \(.head) \(.base)"')"
  assert_contains "$(stdin_of '{"title"' | jq -r .body)" $'<!-- scrum-promotion -->\n- #12 Task 12\n- #13 Task 13\n<!-- /scrum-promotion -->'
  assert_contains "$OUT" "Opened the promotion #60"
}

# spec "Nothing to promote".
test_promote_nothing_when_staging_contains_develop() {
  promote_env
  route_first 'api repos/acme/blog/compare/dev999...staging' 'same.json'
  printf '{"status":"identical"}' > "$FAKE_GH_DIR/same.json"
  run_scrum promote --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Nothing to promote"
  assert_eq "" "$(gh_writes)"
}

# spec "Promotion already open".
test_promote_already_open_names_it() {
  promote_env
  route_first 'api --paginate repos/acme/blog/pulls?state=open&per_page=100&head=acme%3Adevelop&base=staging' 'open.json'
  printf '[{"number":59,"title":"Promote develop to staging","html_url":"https://github.com/acme/blog/pull/59","head":{"ref":"develop"},"base":{"ref":"staging"}}]' > "$FAKE_GH_DIR/open.json"
  run_scrum promote --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "#59 Promote develop to staging: https://github.com/acme/blog/pull/59"
  assert_eq "" "$(gh_writes)"
}

# spec "Standard preset".
test_promote_in_standard_points_to_release() {
  promote_env standard
  run_scrum promote
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "no staging branch"
  assert_contains "$ERR" "/scrum-github:release"
  assert_eq "" "$(gh_writes)"
}

# ---------- hotfix (spec "Start a hotfix") ----------

# hotfix_env [PRESET]  A clone of origin (main with one commit); #31 "Payment fails" open, unassigned.
hotfix_env() {
  setup_fake_gh
  git init -q -b main "$T/origin-src"
  git -C "$T/origin-src" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m first
  git clone -q --bare "$T/origin-src" "$T/origin.git"
  git clone -q "$T/origin.git" "$T/repo"
  export SCRUM_REPO_DIR="$T/repo"
  mkdir -p "$SCRUM_REPO_DIR/.github"
  config_of "${1:-standard}" > "$SCRUM_REPO_DIR/.github/scrum.yml"
  # main moves on origin after the clone: the hotfix starts from the remote head.
  git -C "$T/origin-src" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m second
  git -C "$T/origin-src" push -q "$T/origin.git" main
  route 'auth status*' "auth.txt"
  cp "$FIXTURES/gh-auth-status.txt" "$FAKE_GH_DIR/auth.txt"
  route_json 'api repos/acme/blog/issues/31' "$(open_issue 31 'bug' 'Payment fails')"
  route_json 'api user' '{"login":"alice"}'
  route_json 'api -X POST repos/acme/blog/issues/31/assignees *' '{}'
  route_json 'api -X PUT repos/acme/blog/issues/31/labels *' '[]'
}

test_hotfix_start() {
  hotfix_env
  run_scrum hotfix 31
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "hotfix/31-payment-fails" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)"
  assert_eq "$(git -C "$T/origin-src" rev-parse HEAD)" "$(git -C "$SCRUM_REPO_DIR" rev-parse HEAD)" "created from origin/main, not the stale local main"
  assert_eq '{"assignees":["alice"]}' "$(stdin_of '{"assignees"')"
  assert_contains "$(stdin_of '{"labels"')" '"status: In progress"'
  assert_contains "$OUT" "Created branch hotfix/31-payment-fails from origin/main."
}

# spec "Closed issue": refused, nothing changed.
test_hotfix_refuses_a_closed_issue() {
  hotfix_env
  route_first 'api repos/acme/blog/issues/31' 'closed.json'
  open_issue 31 bug 'Payment fails' closed > "$FAKE_GH_DIR/closed.json"
  run_scrum hotfix 31
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "#31 is closed"
  assert_eq "main" "$(git -C "$SCRUM_REPO_DIR" rev-parse --abbrev-ref HEAD)"
  assert_eq "" "$(gh_writes)"
}

test_hotfix_in_trunk_points_to_task_start() {
  hotfix_env trunk
  run_scrum hotfix 31
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "task start already branches from main"
  assert_eq "" "$(gh_writes)"
}

# ---------- hotfix prepare (spec "Hotfix release") ----------

# prepare_env: on hotfix/31-payment-fails; v1.4.0 on main; package.json at 1.4.0 and a changelog.
prepare_env() {
  hotfix_env
  printf 'version: 1\nbranching:\n  preset: standard\nstatuses:\n  in_review: In review\nrelease:\n  version_files:\n    - path: package.json\n  changelog: CHANGELOG.md\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  printf '{\n  "name": "blog",\n  "version": "1.4.0"\n}\n' > "$SCRUM_REPO_DIR/package.json"
  printf '# Changelog\n' > "$SCRUM_REPO_DIR/CHANGELOG.md"
  git -C "$SCRUM_REPO_DIR" checkout -q -b hotfix/31-payment-fails
  git -C "$SCRUM_REPO_DIR" add -A
  git -C "$SCRUM_REPO_DIR" -c user.email=t@example.com -c user.name=t commit -q -m files
  export SCRUM_TODAY=2026-11-24
  route_json 'api --paginate repos/acme/blog/tags*' '[{"name":"v1.4.0"},{"name":"v1.3.0"}]'
  route_json 'api repos/acme/blog/compare/v1.4.0...main' '{"status":"identical","base_commit":{"commit":{"committer":{"date":"2026-11-20T08:00:00Z"}}}}'
  route 'api repos/acme/blog/git/ref/tags/*' '!404'
  route_json 'api --paginate repos/acme/blog/releases*' '[]'
}

# spec "Pull request of a hotfix branch": the version and the marker for the description.
test_hotfix_prepare_json() {
  prepare_env
  run_scrum hotfix prepare --json
  assert_status 0 "$STATUS" "$ERR"
  assert_eq 'v1.4.1 1.4.1 v1.4.0 31 <!-- scrum-release-tag: v1.4.1 -->' \
    "$(printf '%s' "$OUT" | jq -r '"\(.tag) \(.version) \(.previous) \(.task) \(.marker)"')"
  assert_eq "" "$(gh_writes)"
  assert_eq "files" "$(git -C "$SCRUM_REPO_DIR" log -1 --format=%s)" "nothing committed without --yes"
}

# spec "Hotfix release": the version files and changelog on the hotfix branch, one local commit.
test_hotfix_prepare_yes_commits_the_version() {
  prepare_env
  run_scrum hotfix prepare --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "1.4.1" "$(jq -r .version "$SCRUM_REPO_DIR/package.json")"
  assert_contains "$(cat "$SCRUM_REPO_DIR/CHANGELOG.md")" $'# Changelog\n\n## v1.4.1 (2026-11-24)\n\n### Bug fixes\n\n- Payment fails (#31)'
  assert_eq "Release v1.4.1" "$(git -C "$SCRUM_REPO_DIR" log -1 --format=%s)"
  assert_eq "" "$(git -C "$SCRUM_REPO_DIR" status --porcelain)"
  assert_contains "$OUT" "<!-- scrum-release-tag: v1.4.1 -->"
  assert_eq "" "$(gh_writes)"
  assert_eq "" "$(git -C "$T/origin.git" branch --list 'hotfix/*')" "never pushed"
  # Running it again finds the files already at 1.4.1 and commits nothing.
  run_scrum hotfix prepare --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "2" "$(git -C "$SCRUM_REPO_DIR" log --format=%s main..HEAD | wc -l | tr -d ' ')"
}

test_hotfix_prepare_needs_a_hotfix_branch() {
  prepare_env
  git -C "$SCRUM_REPO_DIR" checkout -q -b feat/12-login
  run_scrum hotfix prepare
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "not a hotfix branch"
}
