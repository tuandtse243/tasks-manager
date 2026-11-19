# spec: project-context (Bản kê repo, Trạng thái tài liệu ngữ cảnh, Ghi dấu thời điểm quét)

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

git_repo() { # git_repo  An empty git repository in $T/repo; SCRUM_REPO_DIR points at it
  export SCRUM_REPO_DIR="$T/repo" SCRUM_TODAY=2026-11-19
  mkdir -p "$SCRUM_REPO_DIR"
  git -C "$SCRUM_REPO_DIR" init -q
}
commit_all() { git -C "$SCRUM_REPO_DIR" add -A && git -C "$SCRUM_REPO_DIR" commit -qm "${1:-change}"; }
put() { mkdir -p "$(dirname "$SCRUM_REPO_DIR/$1")"; printf '%s\n' "${2:-x}" > "$SCRUM_REPO_DIR/$1"; }

# ---------- inventory ----------

test_inventory_repo_with_code() {
  git_repo
  put package.json '{"name":"app","scripts":{"test":"vitest","build":"tsc"}}'
  local i; for i in $(seq 1 40); do put "src/f$i.ts"; done
  for i in $(seq 1 10); do put "tests/t$i.test.ts"; done
  put .github/workflows/ci.yml; put README.md
  commit_all
  run_scrum context inventory
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "true" "$(jq -r .has_code <<<"$OUT")"
  assert_eq '["package.json"]' "$(jq -c .manifests <<<"$OUT")"
  assert_eq "40" "$(jq -r '.top_dirs[] | select(.name == "src") | .files' <<<"$OUT")"
  assert_eq '["tests"]' "$(jq -c .test_dirs <<<"$OUT")"
  assert_eq '{"test":"vitest","build":"tsc"}' "$(jq -c .package_scripts <<<"$OUT")"
  assert_eq '[".github/workflows/ci.yml"]' "$(jq -c .ci <<<"$OUT")"
  assert_eq '{"ext":"ts","files":50}' "$(jq -c '.extensions[0]' <<<"$OUT")"
}

test_inventory_repo_without_code() {
  git_repo
  put README.md; put .github/scrum.yml 'version: 1'; put .github/workflows/scrum-status-sync.yml; put .gitignore
  commit_all
  run_scrum context inventory
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "false" "$(jq -r .has_code <<<"$OUT")"
}

test_inventory_outside_git() {
  export SCRUM_REPO_DIR="$T/plain"; mkdir -p "$SCRUM_REPO_DIR"
  run_scrum context inventory
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "git repository"
}

test_inventory_same_commit_same_result() {
  git_repo
  put src/a.go; put go.mod; put docs/guide.md; put spec/a_spec.rb
  commit_all
  run_scrum context inventory; local first="$OUT"
  run_scrum context inventory
  assert_eq "$first" "$OUT"
  assert_eq '["spec"]' "$(jq -c .test_dirs <<<"$OUT")"
  assert_eq '["docs/guide.md"]' "$(jq -c .docs <<<"$OUT")"
}

# ---------- status ----------

context_doc() { put docs/project-context.md "# Context

## Overview

Text."; }

test_status_no_document() {
  git_repo; put README.md; commit_all
  run_scrum context status
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "false" "$(jq -r .exists <<<"$OUT")"
  assert_eq "docs/project-context.md" "$(jq -r .file <<<"$OUT")"
}

test_status_fresh() {
  git_repo; context_doc; commit_all
  run_scrum context stamp >/dev/null
  run_scrum context status
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '{"exists":true,"commits_behind":0,"changed_dirs":[],"stale":false,"unknown":false}' \
    "$(jq -c '{exists, commits_behind, changed_dirs, stale, unknown}' <<<"$OUT")"
}

test_status_stale_after_80_commits_in_api() {
  git_repo; context_doc; put api/server.js 0; commit_all
  run_scrum context stamp >/dev/null
  commit_all "stamp"
  local i; for i in $(seq 1 79); do put api/server.js "$i"; commit_all; done
  run_scrum context status
  assert_status 0 "$STATUS" "$ERR"
  assert_json_eq '{"commits_behind":80,"changed_dirs":["api"],"stale":true,"unknown":false}' \
    "$(jq -c '{commits_behind, changed_dirs, stale, unknown}' <<<"$OUT")"
}

test_status_unknown_commit() {
  git_repo; put docs/project-context.md "# Context

<!-- scrum:context sha=deadbeef1234 date=2026-01-01 -->"; commit_all
  run_scrum context status
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "true" "$(jq -r .unknown <<<"$OUT")"
  assert_eq "null" "$(jq -r .commits_behind <<<"$OUT")"
}

test_status_uses_config_threshold_and_path() {
  git_repo; put .github/scrum.yml 'planning:
  context_file: CONTEXT.md
  context_stale_commits: 1'
  put CONTEXT.md "# C"; commit_all
  run_scrum context stamp >/dev/null
  put a.txt 1; commit_all; put a.txt 2; commit_all
  run_scrum context status
  assert_eq "CONTEXT.md 2 true" "$(jq -r '"\(.file) \(.commits_behind) \(.stale)"' <<<"$OUT")"
}

# ---------- stamp ----------

test_stamp_first_time() {
  git_repo; context_doc; commit_all
  run_scrum context stamp
  assert_status 0 "$STATUS" "$ERR"
  local head; head="$(git -C "$SCRUM_REPO_DIR" rev-parse --short=12 HEAD)"
  assert_eq "1" "$(grep -c 'scrum:context' "$SCRUM_REPO_DIR/docs/project-context.md")"
  assert_contains "$(cat "$SCRUM_REPO_DIR/docs/project-context.md")" "<!-- scrum:context sha=$head date=2026-11-19 -->"
}

test_stamp_replaces_old_stamp_only() {
  git_repo
  put docs/project-context.md "# Context

<!-- scrum:context sha=aaaaaaa date=2020-01-01 -->

## Overview

Text.
## Team notes

Keep me."
  commit_all
  local before; before="$(grep -v 'scrum:context' "$SCRUM_REPO_DIR/docs/project-context.md")"
  run_scrum context stamp
  run_scrum context stamp
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "1" "$(grep -c 'scrum:context' "$SCRUM_REPO_DIR/docs/project-context.md")"
  assert_not_contains "$(cat "$SCRUM_REPO_DIR/docs/project-context.md")" "aaaaaaa"
  assert_eq "$before" "$(grep -v 'scrum:context' "$SCRUM_REPO_DIR/docs/project-context.md")"
}

test_stamp_without_document_fails() {
  git_repo; put README.md; commit_all
  run_scrum context stamp
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "does not exist"
}
