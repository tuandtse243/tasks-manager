# shellcheck shell=bash
# Shared helpers for tests/test_scenarios_*.sh (black-box tests written from the spec scenarios
# of openspec/changes/archive/2026-11-24-branching-and-release-flow, now merged into
# openspec/specs). Sourced by each scenario test file.
#
# GitHub reads use the REST endpoints a straightforward implementation calls; where the
# endpoint is a guess, the route carries a comment "# assumes: ...".

# shellcheck disable=SC2034  # used by the test files that source this one
CFG_TRUNK='statuses: {in_review: In review}'
# shellcheck disable=SC2034
CFG_STANDARD='branching: {preset: standard}
statuses: {in_review: In review}'
# shellcheck disable=SC2034
CFG_ENVIRONMENTS='branching: {preset: environments}
statuses: {in_review: In review}'

# sc_gh  fake gh with a valid login, alice as the current user and acme/blog as the repo.
sc_gh() {
  setup_fake_gh
  route 'auth status*' "auth.txt"
  cp "$FIXTURES/gh-auth-status.txt" "$FAKE_GH_DIR/auth.txt"
  route_json 'api user' '{"login":"alice"}'
  route_json 'repo view acme/blog*' 'main'
  route_json 'repo view*' 'acme/blog'
}

# sc_gh_bodies  Wraps the fake gh so that the text of --body-file and --body is logged as
# "BODY <text>" (pull requests may be opened with gh pr create).
sc_gh_bodies() {
  cat > "$T/gh-body" <<'GH'
#!/usr/bin/env bash
prev=""
for a in "$@"; do
  if [ "$prev" = "--body-file" ] && [ -f "$a" ]; then printf 'BODY %s\n' "$(tr '\n' ' ' < "$a")" >> "$FAKE_GH_LOG"; fi
  if [ "$prev" = "--body" ] || [ "$prev" = "-b" ]; then printf 'BODY %s\n' "$(printf '%s' "$a" | tr '\n' ' ')" >> "$FAKE_GH_LOG"; fi
  prev="$a"
done
exec "$TESTS_DIR/fake-gh" "$@"
GH
  chmod +x "$T/gh-body"
  export SCRUM_GH="$T/gh-body"
}

# stdin_of TEXT  The JSON bodies sent by the calls whose log line contains TEXT, one per line.
stdin_of() {
  awk -v p="$1" '/^STDIN / { if (want) print substr($0, 7); want = 0; next }
                 { want = (index($0, p) > 0) }' "$FAKE_GH_LOG"
}

# pr_opened HEAD BASE  What was sent to open a pull request from HEAD into BASE, as text (the
# REST body as JSON, or the gh pr create line with its BODY); nothing when none was opened.
pr_opened() {
  local h="$1" b="$2"
  stdin_of '-X POST repos/acme/blog/pulls --input' \
    | jq -c --arg h "$h" --arg b "$b" 'select(((.head // "") | split(":") | last) == $h and .base == $b)' 2>/dev/null
  awk -v h="$h" -v b="$b" '
    /^BODY / { body = $0; next }
    /^pr create / { line = $0 " ";
      if (index(line, " --head " h " ") && index(line, " --base " b " ")) print line " " body
      body = "" }' "$FAKE_GH_LOG"
}

# any_pr_opened  True when any pull request was opened.
any_pr_opened() { grep -qE -- '-X POST repos/acme/blog/pulls( |$)|^pr create ' "$FAKE_GH_LOG"; }

# issue_json N STATUS [LOCATION_BRANCH] [EXTRA_LABELS_CSV] [STATE]  An issue of acme/blog.
issue_json() {
  jq -nc --argjson n "$1" --arg s "$2" --arg loc "${3:-}" --arg x "${4:-}" --arg st "${5:-open}" '{
    number: $n, title: "Task \($n)", state: $st,
    state_reason: (if $st == "closed" then "completed" else null end),
    body: "Do task \($n)", updated_at: "2026-11-24T08:00:00Z", created_at: "2026-11-10T08:00:00Z",
    closed_at: (if $st == "closed" then "2026-11-20T10:00:00Z" else null end),
    milestone: {number: 3, title: "Sprint 3"},
    assignees: [{login: "alice"}],
    labels: ([{name: "status: \($s)"}, {name: "points: 3"}]
             + (if $loc == "" then [] else [{name: "on: \($loc)"}] end)
             + ($x | split(",") | map(select(. != "")) | map({name: .}))) }'
}

# _sc_hold / _sc_release  Routes added between the two go ahead of every earlier route (so a
# later call of route_issues or route_open_prs replaces the answers of an earlier one).
_sc_hold() { mv "$FAKE_GH_DIR/routes" "$FAKE_GH_DIR/routes.held"; : > "$FAKE_GH_DIR/routes"; }
_sc_release() { cat "$FAKE_GH_DIR/routes.held" >> "$FAKE_GH_DIR/routes"; rm -f "$FAKE_GH_DIR/routes.held"; }

# route_issues JSON_ARRAY  Open and listed issues: the issue list endpoints (any filter) and
# each issue by number. A later call replaces the answers of an earlier one.
route_issues() {
  local n
  _sc_hold
  printf '%s' "$1" > "$FAKE_GH_DIR/sc-issues.json"
  # assumes: the open tasks are read from repos/{r}/issues?... (any query string)
  route 'api --paginate repos/acme/blog/issues[?]*' sc-issues.json
  route 'api repos/acme/blog/issues[?]*' sc-issues.json
  for n in $(printf '%s' "$1" | jq -r '.[].number'); do
    printf '%s' "$1" | jq -c --argjson n "$n" '.[] | select(.number == $n)' > "$FAKE_GH_DIR/sc-issue-$n.json"
    route "api repos/acme/blog/issues/$n" "sc-issue-$n.json"
  done
  _sc_release
}

# route_task_pr TASK PR SHA [BASE] [MERGED_AT] [LABELED_AT]  Task TASK was closed by the merged
# pull request PR whose merge commit is SHA (timeline cross-reference and the pull request).
# With LABELED_AT, the timeline (and the events) also hold the "labeled" event of its location
# label "on: develop" at that time.
route_task_pr() {
  local task="$1" pr="$2" sha="$3" base="${4:-develop}" at="${5:-2026-11-18T10:00:00Z}" lab="${6:-}" tl
  tl="$(jq -nc --argjson t "$task" --argjson p "$pr" --arg at "$at" --arg lab "$lab" --arg base "$base" '
    [{event: "cross-referenced", created_at: $at,
      source: {issue: {number: $p, title: "feat: task \($t)", body: "Closes #\($t)",
                       pull_request: {merged_at: $at}, repository: {full_name: "acme/blog"}}}}]
    + (if $lab == "" then [] else [{event: "labeled", created_at: $lab, label: {name: "on: \($base)"}}] end)')"
  route_json "api --paginate repos/acme/blog/issues/$task/timeline*" "$tl"
  route_json "api --paginate repos/acme/blog/issues/$task/events*" "$tl"
  route_json "api repos/acme/blog/pulls/$pr" "$(jq -nc --argjson t "$task" --argjson p "$pr" --arg s "$sha" --arg at "$at" --arg base "$base" '
    {number: $p, title: "feat: task \($t)", body: "Closes #\($t)", state: "closed", merged: true, merged_at: $at,
     merge_commit_sha: $s, head: {ref: "feat/\($t)-task"}, base: {ref: $base},
     html_url: "https://github.com/acme/blog/pull/\($p)"}')"
}

# route_contains SHA REF STATUS  The compare answer for "does REF contain SHA" (ahead or
# identical: yes; behind or diverged: no). REF may be a glob such as '*'.
route_contains() {
  route_json "api repos/acme/blog/compare/$1...$2" "$(jq -nc --arg s "$3" '{status: $s,
    ahead_by: (if $s == "ahead" then 1 else 0 end), behind_by: (if $s == "behind" or $s == "diverged" then 1 else 0 end),
    commits: [], base_commit: {commit: {committer: {date: "2026-11-01T08:00:00Z"}}}}')"
}

# route_open_prs JSON_ARRAY  The open pull requests, each {number, title, head, base, body?},
# answered for the queries of branching.sh (open_prs: state=open&per_page=100 with head=acme%3AH
# and/or base=B) and for an unfiltered list. A later call replaces the answers of an earlier one.
route_open_prs() {
  local full combos kind h b q sel f
  _sc_hold
  full="$(printf '%s' "$1" | jq -c '[.[] | {number, title, state: "open", draft: false, body: (.body // ""),
    html_url: "https://github.com/acme/blog/pull/\(.number)", head: {ref: .head}, base: {ref: .base},
    user: {login: "alice"}, updated_at: "2026-11-24T08:00:00Z", merged_at: null}]')"
  printf '%s' "$full" > "$FAKE_GH_DIR/sc-open-prs.json"
  # head and base together, head only, base only (exact queries of open_prs)
  combos="$(printf '%s' "$full" | jq -r '
      ([.[] | [.head.ref, .base.ref]] | unique[] | "pair\t\(.[0])\t\(.[1])"),
      ([.[] | .head.ref] | unique[] | "head\t\(.)\t"),
      ([.[] | .base.ref] | unique[] | "base\t\t\(.)")')"
  while IFS="$(printf '\t')" read -r kind h b; do
    [ -n "$kind" ] || continue
    case "$kind" in
      pair) q="head=$(jq -rn --arg s "acme:$h" '$s|@uri')&base=$(jq -rn --arg s "$b" '$s|@uri')"
            sel="select(.head.ref == \"$h\" and .base.ref == \"$b\")" ;;
      head) q="head=$(jq -rn --arg s "acme:$h" '$s|@uri')"; sel="select(.head.ref == \"$h\")" ;;
      base) q="base=$(jq -rn --arg s "$b" '$s|@uri')"; sel="select(.base.ref == \"$b\")" ;;
    esac
    f="sc-prs-$(printf '%s' "$q" | tr -c 'A-Za-z0-9' '_').json"
    printf '%s' "$full" | jq -c "[.[] | $sel]" > "$FAKE_GH_DIR/$f"
    route "api --paginate repos/acme/blog/pulls[?]state=open&per_page=100&$q" "$f"
    route "api repos/acme/blog/pulls[?]state=open&per_page=100&$q" "$f"
  done <<EOF
$combos
EOF
  # any other filtered query of open pull requests: none
  printf '[]' > "$FAKE_GH_DIR/sc-prs-none.json"
  route 'api --paginate repos/acme/blog/pulls[?]state=open&per_page=100&*' sc-prs-none.json
  route 'api repos/acme/blog/pulls[?]state=open&per_page=100&*' sc-prs-none.json
  # assumes: an unfiltered list of open pull requests is repos/{r}/pulls?state=open...
  route 'api --paginate repos/acme/blog/pulls[?]state=open*' sc-open-prs.json
  route 'api repos/acme/blog/pulls[?]state=open*' sc-open-prs.json
  route 'api --paginate repos/acme/blog/pulls[?]per_page=*' sc-open-prs.json
  route 'api --paginate repos/acme/blog/pulls' sc-open-prs.json
  _sc_release
}

# route_branch_head BRANCH SHA  The head commit of a branch on GitHub (git/ref and branches).
route_branch_head() { # a later call for the same branch wins (its routes go first)
  local enc f
  enc="$(jq -rn --arg s "$1" '$s|@uri')"
  f="head-$(printf '%s' "$1" | tr '/' '_')-$2.json"
  printf '{"ref":"refs/heads/%s","object":{"sha":"%s","type":"commit"}}' "$1" "$2" > "$FAKE_GH_DIR/$f"
  printf '{"name":"%s","commit":{"sha":"%s"},"protected":false}' "$1" "$2" > "$FAKE_GH_DIR/b$f"
  route_first "api repos/acme/blog/git/ref/heads/$enc" "$f"
  route_first "api repos/acme/blog/git/ref/heads/$1" "$f"
  route_first "api repos/acme/blog/branches/$enc" "b$f"
  route_first "api repos/acme/blog/branches/$1" "b$f"
}

# ---------- local git ----------

# Identity and settings for every git call of the test and of the command under test.
sc_git_env() {
  export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@example.com
  export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@example.com
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=3
  export GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false
  export GIT_CONFIG_KEY_1=init.defaultBranch GIT_CONFIG_VALUE_1=main
  export GIT_CONFIG_KEY_2=pull.rebase GIT_CONFIG_VALUE_2=false
}

# git_project CONFIG_YAML  A bare origin ($T/origin.git) with main and develop at the same
# commit (holding .github/scrum.yml and src/auth.ts), a helper clone $T/seed used to push
# other people's work, and the user's clone $T/repo (SCRUM_REPO_DIR) on develop.
git_project() {
  sc_git_env
  git init -q --bare -b main "$T/origin.git"
  git init -q -b main "$T/seed"
  mkdir -p "$T/seed/.github" "$T/seed/src"
  printf '%s\n' "$1" > "$T/seed/.github/scrum.yml"
  printf 'export const timeout = 30;\n' > "$T/seed/src/auth.ts"
  printf 'blog\n' > "$T/seed/README.md"
  git -C "$T/seed" add -A
  git -C "$T/seed" commit -q -m "chore: init"
  git -C "$T/seed" remote add origin "$T/origin.git"
  git -C "$T/seed" push -q origin main 2>/dev/null
  git -C "$T/seed" push -q origin main:develop 2>/dev/null
  git clone -q "$T/origin.git" "$T/repo" 2>/dev/null
  git -C "$T/repo" checkout -q -b develop origin/develop
  export SCRUM_REPO_DIR="$T/repo"
}

# seed_commits BRANCH N [FILE] [MESSAGE]  N commits pushed to origin/BRANCH by someone else.
seed_commits() {
  local b="$1" n="$2" f="${3:-notes.txt}" m="${4:-chore: work}" i=1
  git -C "$T/seed" fetch -q origin
  git -C "$T/seed" checkout -q -B "$b" "origin/$b"
  while [ "$i" -le "$n" ]; do
    printf '%s %s\n' "$m" "$i" >> "$T/seed/$f"
    git -C "$T/seed" add -A
    git -C "$T/seed" commit -q -m "$m $i"
    i=$((i + 1))
  done
  git -C "$T/seed" push -q origin "$b" 2>/dev/null
}
