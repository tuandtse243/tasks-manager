# Scenario tests (black box, from the specs) for stream A: repo-governance and the
# allowed-source-branch check of branching-presets. Change: branching-and-release-flow.

# shellcheck source=fixtures/scenarios/helpers.sh
. "$FIXTURES/scenarios/helpers.sh"

all_out() { printf '%s\n%s' "$OUT" "$ERR"; }

# ---------- scrum protect ----------

# protect_env CONFIG  A repository with main only, no rulesets, GitHub's default merge settings.
protect_env() {
  sc_gh
  setup_repo "$1"
  route_json 'api repos/acme/blog' '{"full_name":"acme/blog","default_branch":"main","private":false,
    "allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":true,
    "delete_branch_on_merge":false,"allow_auto_merge":false}'
  route_branch_head main abc1234main
  route 'api repos/acme/blog/git/ref/heads/develop' '!404'
  route 'api repos/acme/blog/git/ref/heads/staging' '!404'
  route 'api repos/acme/blog/branches/develop' '!404'
  route 'api repos/acme/blog/branches/staging' '!404'
  # writes (ahead of the read globs below)
  route_json 'api -X POST repos/acme/blog/git/refs --input -' '{"ref":"refs/heads/develop","object":{"sha":"abc1234main"}}'
  route_json 'api -X POST repos/acme/blog/rulesets --input -' '{"id":901}'
  route_json 'api -X PATCH repos/acme/blog --input -' '{"full_name":"acme/blog"}'
  # assumes: rulesets are listed with repos/{r}/rulesets (paginated or not) and branch rules with
  # repos/{r}/rules/branches/{b}
  route_json 'api --paginate repos/acme/blog/rulesets*' '[]'
  route_json 'api repos/acme/blog/rulesets*' '[]'
  route_json 'api --paginate repos/acme/blog/rules/branches/*' '[]'
  route_json 'api repos/acme/blog/rules/branches/*' '[]'
}

# The ruleset bodies sent with POST (or PUT, for an update).
rulesets_sent() { { stdin_of '-X POST repos/acme/blog/rulesets'; stdin_of '-X PUT repos/acme/blog/rulesets/'; } | jq -s -c .; }
# ruleset_for REF  The ruleset sent whose conditions include REF (refs/heads/main, refs/tags/v*).
ruleset_for() { rulesets_sent | jq -c --arg r "$1" '[.[] | select((.conditions.ref_name.include // []) | index($r))] | .[0]'; }

# spec repo-governance: Preview
test_protect_preview_changes_nothing() {
  protect_env "$CFG_STANDARD"
  run_scrum protect
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "develop" "the missing develop branch is planned"
  assert_contains "$OUT" "main" "the rule for main is planned"
  assert_eq "" "$(gh_writes)" "nothing on GitHub changes"
}

# spec repo-governance: Preview (--json prints the same plan as data)
test_protect_json_is_data() {
  protect_env "$CFG_STANDARD"
  run_scrum protect --json
  assert_status 0 "$STATUS" "$ERR"
  printf '%s' "$OUT" | jq -e . >/dev/null || _fail "--json did not print JSON: $OUT"
  assert_contains "$OUT" "develop"
  assert_eq "" "$(gh_writes)"
}

# spec repo-governance: Standard without develop
test_protect_creates_develop_at_main_head() {
  protect_env "$CFG_STANDARD"
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq '{"ref":"refs/heads/develop","sha":"abc1234main"}' \
    "$(stdin_of '-X POST repos/acme/blog/git/refs' | jq -c '{ref, sha}' | head -1)"
  assert_not_contains "$(gh_writes)" "DELETE" "no branch is deleted"
  assert_not_contains "$(gh_calls)" "git/refs/heads/main" "main is not moved"
}

# spec repo-governance: Main in standard
test_protect_rule_for_main_in_standard() {
  protect_env "branching: {preset: standard}
statuses: {in_review: In review}
governance: {required_checks: [ci/test]}"
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR"
  local r types
  r="$(ruleset_for refs/heads/main)"
  [ "$r" != null ] || _fail "no ruleset for refs/heads/main was sent: $(rulesets_sent)"
  types="$(printf '%s' "$r" | jq -c '[.rules[].type] | sort')"
  assert_contains "$types" '"pull_request"'
  assert_contains "$types" '"required_status_checks"'
  assert_contains "$types" '"non_fast_forward"' "force pushes are rejected"
  assert_contains "$types" '"deletion"' "deletion is rejected"
  assert_eq '["merge"]' "$(printf '%s' "$r" | jq -c '.rules[] | select(.type == "pull_request") | .parameters.allowed_merge_methods')" \
    "main allows only merge commits"
  assert_contains "$(printf '%s' "$r" | jq -c '.rules[] | select(.type == "required_status_checks")')" '"ci/test"'
  # the working branch allows squash and merge commits
  assert_eq '["merge","squash"]' "$(ruleset_for refs/heads/develop | jq -c '.rules[] | select(.type == "pull_request") | .parameters.allowed_merge_methods | sort')"
}

# spec repo-governance: Solo project
test_protect_solo_requires_pr_without_approval() {
  protect_env "branching: {preset: standard}
statuses: {in_review: In review}
governance: {approvals: 0}"
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR"
  local pr
  pr="$(ruleset_for refs/heads/main | jq -c '.rules[] | select(.type == "pull_request")')"
  [ -n "$pr" ] || _fail "a pull request is still required"
  assert_eq "0" "$(printf '%s' "$pr" | jq -r '.parameters.required_approving_review_count')"
}

# spec repo-governance: Moving a tag (the tag rule blocks update and deletion, not creation)
test_protect_tag_rule() {
  protect_env "$CFG_STANDARD"
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR"
  local r types
  r="$(ruleset_for 'refs/tags/v*')"
  [ "$r" != null ] || _fail "no ruleset for refs/tags/v*: $(rulesets_sent)"
  assert_eq tag "$(printf '%s' "$r" | jq -r .target)"
  types="$(printf '%s' "$r" | jq -c '[.rules[].type]')"
  assert_contains "$types" '"update"'
  assert_contains "$types" '"deletion"'
  assert_not_contains "$types" '"creation"' "the release workflow must still create tags"
}

# spec repo-governance: Trunk (merge settings)
test_protect_trunk_merge_settings() {
  protect_env 'version: 1'
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR"
  local s
  s="$(stdin_of '-X PATCH repos/acme/blog --input' | jq -s -c 'add')"
  assert_json_eq '{"allow_squash_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false,"delete_branch_on_merge":true,"allow_auto_merge":true}' \
    "$(printf '%s' "$s" | jq -c '{allow_squash_merge, allow_merge_commit, allow_rebase_merge, delete_branch_on_merge, allow_auto_merge}')"
  assert_not_contains "$(gh_calls)" 'refs/heads/develop' "trunk has no develop"
}

# spec repo-governance: Private repository on a free plan
test_protect_403_reported_settings_applied_non_zero() {
  protect_env "$CFG_STANDARD"
  route_first 'api -X POST repos/acme/blog/rulesets --input -' '!403'
  run_scrum protect --yes
  [ "$STATUS" -ne 0 ] || _fail "protect must exit non-zero when a ruleset is refused"
  assert_contains "$(all_out | tr '[:upper:]' '[:lower:]')" "plan" "says rules are not available on the plan"
  assert_contains "$(gh_calls)" 'api -X PATCH repos/acme/blog --input -' "the merge settings are still applied"
}

# spec repo-governance: Already protected
# The state left by a first `protect --yes` is served back; a second preview finds nothing to do.
test_protect_already_protected() {
  protect_env "$CFG_STANDARD"
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR"
  local sets settings repo
  sets="$(rulesets_sent | jq -c '[to_entries[] | .value + {id: (900 + .key), source_type: "Repository", source: "acme/blog"}]')"
  settings="$(stdin_of '-X PATCH repos/acme/blog --input' | jq -s -c 'add // {}')"
  repo="$(jq -nc --argjson s "$settings" '{full_name: "acme/blog", default_branch: "main", private: false,
    allow_squash_merge: true, allow_merge_commit: true, allow_rebase_merge: true,
    delete_branch_on_merge: false, allow_auto_merge: false} + $s')"
  : > "$FAKE_GH_LOG"
  route_first 'api repos/acme/blog' "$(printf '%s' "$repo" > "$FAKE_GH_DIR/repo2.json"; echo repo2.json)"
  route_branch_head develop abc1234main
  route_first 'api repos/acme/blog/branches/develop' "$(printf '{"name":"develop","commit":{"sha":"abc1234main"}}' > "$FAKE_GH_DIR/dev.json"; echo dev.json)"
  route_first 'api repos/acme/blog/git/ref/heads/develop' "$(printf '{"object":{"sha":"abc1234main"}}' > "$FAKE_GH_DIR/devref.json"; echo devref.json)"
  printf '%s' "$sets" > "$FAKE_GH_DIR/sets.json"
  route_first 'api --paginate repos/acme/blog/rulesets*' sets.json
  local i id
  for i in $(printf '%s' "$sets" | jq -r 'keys[]'); do
    id="$(printf '%s' "$sets" | jq -r ".[$i].id")"
    printf '%s' "$sets" | jq -c ".[$i]" > "$FAKE_GH_DIR/set$id.json"
    route_first "api repos/acme/blog/rulesets/$id*" "set$id.json"
  done
  route_first 'api repos/acme/blog/rulesets' sets.json
  route_first 'api repos/acme/blog/rulesets[?]*' sets.json
  for b in main develop; do
    printf '%s' "$sets" | jq -c --arg r "refs/heads/$b" '[.[] | select((.conditions.ref_name.include // []) | index($r)) | .id as $id | .rules[] | . + {ruleset_id: $id, ruleset_source_type: "Repository", ruleset_source: "acme/blog"}]' > "$FAKE_GH_DIR/rules-$b.json"
    route_first "api --paginate repos/acme/blog/rules/branches/$b*" "rules-$b.json"
    route_first "api repos/acme/blog/rules/branches/$b*" "rules-$b.json"
  done
  run_scrum protect
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(all_out | tr '[:upper:]' '[:lower:]')" "nothing to change"
  assert_eq "" "$(gh_writes)"
}

# ---------- pull request checks (scrum pr-check) ----------

# check_pr CONFIG TITLE HEAD BASE [BODY]  Runs scrum pr-check for that pull request.
check_pr() {
  setup_fake_gh
  setup_repo "$1"
  export GITHUB_EVENT_NAME=pull_request_target GITHUB_EVENT_PATH="$T/event.json"
  jq -n --arg t "$2" --arg h "$3" --arg b "$4" --arg body "${5:-Closes #12}" \
    '{action: "opened", pull_request: {number: 20, title: $t, body: $body, labels: [], draft: false,
      head: {ref: $h}, base: {ref: $b}}}' > "$GITHUB_EVENT_PATH"
  run_scrum pr-check
}

# spec repo-governance: Valid title
test_pr_check_valid_title() {
  check_pr "$CFG_STANDARD" 'feat(auth): log in with email' feat/12-login develop
  assert_status 0 "$STATUS" "$(all_out)"
}

# spec repo-governance: Valid title (each type, scope and "!")
test_pr_check_valid_title_variants() {
  local t
  for t in 'fix: crash on save' 'docs: readme' 'chore(deps)!: drop node 16' 'refactor: x' 'test: y' 'ci: z' 'perf: a' 'build: b' 'revert: c'; do
    check_pr "$CFG_STANDARD" "$t" feat/12-login develop
    assert_status 0 "$STATUS" "title \"$t\": $(all_out)"
  done
}

# spec repo-governance: Invalid title
test_pr_check_invalid_title() {
  check_pr "$CFG_STANDARD" 'Login page' feat/12-login develop
  [ "$STATUS" -ne 0 ] || _fail "the check must fail for \"Login page\""
  assert_contains "$(all_out)" "feat" "shows an example of a valid title"
}

# spec repo-governance: Release pull request
test_pr_check_release_pr_exempt() {
  check_pr "$CFG_STANDARD" 'Release v1.4.0' release/v1.4.0 main $'<!-- scrum-release-notes -->\n## Features\n- Login (#12)\n<!-- scrum-release-notes -->'
  assert_status 0 "$STATUS" "$(all_out)"
}

# spec repo-governance: release, back-merge and promotion pull requests are exempt
test_pr_check_back_merge_and_promotion_exempt() {
  check_pr "$CFG_STANDARD" 'Back-merge main into develop' main develop 'Brings v1.4.0 back.'
  assert_status 0 "$STATUS" "back-merge: $(all_out)"
  check_pr "$CFG_ENVIRONMENTS" 'Promote develop to staging' develop staging '- #12'
  assert_status 0 "$STATUS" "promotion: $(all_out)"
}

# spec branching-presets: Task branch into main
test_pr_check_task_branch_into_main_fails() {
  check_pr "$CFG_STANDARD" 'feat: login' feat/12-login main
  [ "$STATUS" -ne 0 ] || _fail "a task branch may not target main"
  assert_contains "$(all_out)" "develop" "says the branch must target develop"
}

# spec branching-presets: Release branch into main
test_pr_check_release_branch_into_main_passes() {
  check_pr "$CFG_STANDARD" 'Release v1.4.0' release/v1.4.0 main 'notes'
  assert_status 0 "$STATUS" "$(all_out)"
}

# spec branching-presets: Back-merge into develop
test_pr_check_back_merge_into_develop_passes() {
  check_pr "$CFG_STANDARD" 'Back-merge main into develop' main develop 'notes'
  assert_status 0 "$STATUS" "$(all_out)"
}

# spec branching-presets: Trunk
test_pr_check_trunk_any_source() {
  check_pr 'version: 1' 'feat: login' feat/12-login main
  assert_status 0 "$STATUS" "$(all_out)"
}

# ---------- governance files from scrum init ----------

init_env() {
  setup_fake_gh
  setup_repo
  route 'api --paginate repos/acme/blog/labels*' "labels.json"
  cp "$FIXTURES/labels-github-default.json" "$FAKE_GH_DIR/labels.json"
}

# find_file NAME  The path of an installed file (root, .github/ or docs/), or nothing.
find_file() {
  local d
  for d in "$SCRUM_REPO_DIR" "$SCRUM_REPO_DIR/.github" "$SCRUM_REPO_DIR/docs"; do
    [ -f "$d/$1" ] && { printf '%s' "$d/$1"; return 0; }
  done
  return 0
}

# spec repo-governance: Fresh project
test_init_installs_governance_files() {
  init_env
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  local f
  for f in CODEOWNERS CONTRIBUTING.md SECURITY.md; do
    [ -n "$(find_file "$f")" ] || _fail "$f was not installed"
  done
  [ -f "$SCRUM_REPO_DIR/.github/dependabot.yml" ] || _fail ".github/dependabot.yml was not installed"
  local dep
  dep="$(yq -o=json '.' "$SCRUM_REPO_DIR/.github/dependabot.yml")"
  assert_eq "weekly" "$(printf '%s' "$dep" | jq -r '.updates[] | select(."package-ecosystem" == "github-actions") | .schedule.interval')" \
    "GitHub Actions are updated weekly"
  assert_eq "true" "$(printf '%s' "$dep" | jq '[.updates[] | select(."package-ecosystem" == "github-actions") | .groups // {} | length] | .[0] >= 1')" \
    "in one grouped pull request"
  # CONTRIBUTING.md describes the branches, the title rule and the release path
  local c
  c="$(cat "$(find_file CONTRIBUTING.md)")"
  assert_contains "$c" "develop"
  assert_contains "$c" "main"
  assert_contains "$c" "feat"
  assert_contains "$(printf '%s' "$c" | tr '[:upper:]' '[:lower:]')" "release"
}

# spec repo-governance: Existing CONTRIBUTING
test_init_keeps_existing_contributing() {
  init_env
  printf '# Our own rules\n' > "$SCRUM_REPO_DIR/CONTRIBUTING.md"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "# Our own rules" "$(cat "$SCRUM_REPO_DIR/CONTRIBUTING.md")" "the file is left unchanged"
  [ ! -f "$SCRUM_REPO_DIR/.github/CONTRIBUTING.md" ] || _fail "a second CONTRIBUTING.md was written to .github/"
  local line
  line="$(all_out | grep 'CONTRIBUTING' || true)"
  [ -n "$line" ] || _fail "init does not mention CONTRIBUTING.md: $(all_out)"
  printf '%s' "$line" | grep -qiE 'skip|kept|keep|exist|unchanged|left' || _fail "init does not say it was skipped: $line"
}

# spec repo-governance: Checkout action (every installed workflow pins actions by SHA)
test_init_workflows_pin_actions_by_sha() {
  init_env
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  local f bad="" n=0
  for f in "$SCRUM_REPO_DIR"/.github/workflows/*.yml; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      n=$((n + 1))
      printf '%s\n' "$line" | grep -qE 'uses:[[:space:]]*\./' && continue
      printf '%s\n' "$line" | grep -qE 'uses:[[:space:]]*[^@[:space:]]+@[0-9a-f]{40}([[:space:]]|$)' || bad="$bad"$'\n'"${f##*/}: $line"
    done <<EOF
$(grep -E '^[[:space:]-]*uses:' "$f")
EOF
  done
  [ "$n" -gt 0 ] || _fail "no uses: line found in the installed workflows"
  [ -z "$bad" ] || _fail "actions not pinned by a 40-character SHA:$bad"
  grep -qE 'uses:[[:space:]]*actions/checkout@[0-9a-f]{40}[[:space:]]*#' "$SCRUM_REPO_DIR"/.github/workflows/*.yml \
    || _fail "the checkout action has no version comment"
}

# spec branching-presets: Daily digest in standard
test_init_digest_checks_out_develop_in_standard() {
  init_env
  printf '%s\n' "$CFG_STANDARD" > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  grep -qE '^[[:space:]]*ref:[[:space:]]*["'"'"']?develop["'"'"']?[[:space:]]*$' "$SCRUM_REPO_DIR/.github/workflows/scrum-daily-digest.yml" \
    || _fail "the digest workflow does not check out develop: $(cat "$SCRUM_REPO_DIR/.github/workflows/scrum-daily-digest.yml")"
}

# spec branching-presets: Daily digest in trunk
test_init_digest_checks_out_main_in_trunk() {
  init_env
  printf 'version: 1\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  local wf
  wf="$(cat "$SCRUM_REPO_DIR/.github/workflows/scrum-daily-digest.yml")"
  assert_not_contains "$wf" "develop"
  # Without a branching block the ref is empty: the default branch, which is main here (older
  # installs whose default branch has another name keep working). An explicit trunk writes main.
  if printf '%s\n' "$wf" | grep -qE '^[[:space:]]*ref:'; then
    printf '%s\n' "$wf" | grep -qE '^[[:space:]]*ref:[[:space:]]*(""|["'"'"']?main["'"'"']?)[[:space:]]*$' || _fail "the digest checks out another branch than main"
  fi
  printf 'branching:\n  preset: trunk\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(cat "$SCRUM_REPO_DIR/.github/workflows/scrum-daily-digest.yml")" 'ref: "main"'
}

# ---------- doctor ----------

# doctor_env  An installed repo (preset standard from the template) where every governance check
# passes: main is the default branch, develop exists and contains main, both have rules, the
# governance files are there.
doctor_env() {
  sc_gh
  setup_repo
  git init -q "$SCRUM_REPO_DIR"
  route 'api --paginate repos/acme/blog/labels*' "labels.json"
  route 'api repos/acme/blog/contents/.github/workflows' "workflows.json"
  route 'api repos/acme/blog/actions/secrets' "secrets.json"
  cp "$FIXTURES/labels-github-default.json" "$FAKE_GH_DIR/labels.json"
  cp "$FIXTURES/remote-workflows.json" "$FAKE_GH_DIR/workflows.json"
  cp "$FIXTURES/actions-secrets.json" "$FAKE_GH_DIR/secrets.json"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  cp "$FIXTURES/labels-after-init-standard.json" "$FAKE_GH_DIR/labels.json"
  route_json 'api repos/acme/blog' '{"full_name":"acme/blog","default_branch":"main","private":false,
    "allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":false,"delete_branch_on_merge":true,"allow_auto_merge":true}'
  route_branch_head main aaa000main
  route_branch_head develop bbb000dev
  # develop contains main (and is ahead of it)
  route_json 'api repos/acme/blog/compare/main...develop' '{"status":"ahead","ahead_by":3,"behind_by":0}'
  route_json 'api repos/acme/blog/compare/develop...main' '{"status":"behind","ahead_by":0,"behind_by":3}'
  route_json 'api repos/acme/blog/compare/aaa000main...develop' '{"status":"ahead","ahead_by":3,"behind_by":0}'
  route_json 'api repos/acme/blog/compare/bbb000dev...main' '{"status":"behind","ahead_by":0,"behind_by":3}'
  route_json 'api repos/acme/blog/compare/*...*' '{"status":"ahead","ahead_by":3,"behind_by":0}'
  # assumes: branch rules are read with repos/{r}/rules/branches/{b}
  route_json 'api --paginate repos/acme/blog/rules/branches/*' '[{"type":"pull_request","ruleset_id":901},{"type":"deletion","ruleset_id":901}]'
  route_json 'api repos/acme/blog/rules/branches/*' '[{"type":"pull_request","ruleset_id":901},{"type":"deletion","ruleset_id":901}]'
  route_json 'api --paginate repos/acme/blog/rulesets*' '[{"id":901,"name":"scrum: main","target":"branch"},{"id":902,"name":"scrum: develop","target":"branch"},{"id":903,"name":"scrum: tags","target":"tag"}]'
  route_json 'api repos/acme/blog/rulesets*' '[{"id":901,"name":"scrum: main","target":"branch"},{"id":902,"name":"scrum: develop","target":"branch"},{"id":903,"name":"scrum: tags","target":"tag"}]'
  route_open_prs '[]'
  : > "$FAKE_GH_LOG"
}

# doctor_has STATUS REGEX  True when doctor --json has a check with STATUS whose message or fix
# matches REGEX (case-insensitive).
doctor_has() {
  printf '%s' "$OUT" | jq -e --arg s "$1" --arg r "$2" \
    '[.checks[] | select(.status == $s) | select(((.message // "") + " " + (.fix // "")) | test($r; "i"))] | length > 0' >/dev/null
}

# spec repo-governance: diagnostics baseline (no governance problem reported when all is in place)
test_doctor_governance_baseline_has_no_branch_problem() {
  doctor_env
  run_scrum doctor --json
  printf '%s' "$OUT" | jq -e . >/dev/null || _fail "doctor --json is not JSON: $OUT $ERR"
  if doctor_has error 'default branch' || doctor_has warn 'back-merge|protect'; then
    _fail "governance problems reported on a healthy repo: $(printf '%s' "$OUT" | jq -c '[.checks[] | select(.status != "ok")]')"
  fi
}

# spec repo-governance: Default branch is develop
test_doctor_default_branch_develop_is_error() {
  doctor_env
  route_first 'api repos/acme/blog' "$(printf '{"full_name":"acme/blog","default_branch":"develop"}' > "$FAKE_GH_DIR/repo-dev.json"; echo repo-dev.json)"
  run_scrum doctor --json
  assert_status 1 "$STATUS" "an error makes doctor exit 1"
  doctor_has error 'main' || _fail "no error telling to set the default branch to main: $(printf '%s' "$OUT" | jq -c '[.checks[] | select(.status == "error")]')"
  doctor_has error 'default' || _fail "the error does not name the default branch"
}

# spec repo-governance: Main is ahead of develop
test_doctor_main_ahead_of_develop_warns() {
  doctor_env
  route_first 'api repos/acme/blog/compare/*...*' "$(printf '{"status":"diverged","ahead_by":1,"behind_by":2}' > "$FAKE_GH_DIR/div.json"; echo div.json)"
  route_first 'api repos/acme/blog/compare/main...develop' div.json
  route_first 'api repos/acme/blog/compare/aaa000main...develop' div.json
  route_first 'api repos/acme/blog/compare/develop...main' "$(printf '{"status":"diverged","ahead_by":1,"behind_by":2}' > "$FAKE_GH_DIR/div2.json"; echo div2.json)"
  route_first 'api repos/acme/blog/compare/bbb000dev...main' div2.json
  run_scrum doctor --json
  doctor_has warn 'back-merge|back merge' || _fail "no warning suggesting the back-merge: $(printf '%s' "$OUT" | jq -c '[.checks[] | select(.status != "ok")]')"
}

# spec repo-governance: Unprotected main
test_doctor_unprotected_main_warns() {
  doctor_env
  route_first 'api --paginate repos/acme/blog/rules/branches/main*' "$(printf '[]' > "$FAKE_GH_DIR/norules.json"; echo norules.json)"
  route_first 'api repos/acme/blog/rules/branches/main*' norules.json
  route_first 'api --paginate repos/acme/blog/rulesets*' norules.json
  route_first 'api repos/acme/blog/rulesets*' norules.json
  run_scrum doctor --json
  doctor_has warn '/scrum-github:protect' || _fail "no warning suggesting /scrum-github:protect: $(printf '%s' "$OUT" | jq -c '[.checks[] | select(.status != "ok")]')"
}
