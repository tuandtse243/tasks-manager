# spec: branching-presets (Branch roles, Allowed source branches) and design 5 (which tasks a
# branch contains).

LIBJQ="$PLUGIN_DIR/runtime/lib/jq"
defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }
cfg_of() { # cfg_of PRESET [jq filter]  The defaults with that preset (and In review on).
  defaults | jq --arg p "$1" '.branching.preset = $p | .statuses.in_review = "In review"' | jq "${2:-.}"
}
jqs() { # jqs CONFIG EXPR  Evaluate EXPR (with include "scrum") against $cfg.
  jq -nc -L "$LIBJQ" --argjson cfg "$1" "include \"scrum\"; $2"
}

# ---------- Branch roles ----------

test_roles_standard() {
  local cfg
  cfg="$(cfg_of standard)"
  assert_eq '"develop"' "$(jqs "$cfg" 'working_branch($cfg)')"
  assert_eq '"main"' "$(jqs "$cfg" 'release_branch($cfg)')"
  assert_eq '["develop"]' "$(jqs "$cfg" 'branching($cfg).lower')"
  assert_eq 'true' "$(jqs "$cfg" 'has_working_branch($cfg)')"
}

test_roles_trunk() {
  local cfg
  cfg="$(defaults)"
  assert_eq '"main"' "$(jqs "$cfg" 'working_branch($cfg)')"
  assert_eq '"main"' "$(jqs "$cfg" 'release_branch($cfg)')"
  assert_eq '[]' "$(jqs "$cfg" 'location_labels($cfg)')"
  assert_eq 'false' "$(jqs "$cfg" 'has_working_branch($cfg)')"
}

test_roles_renamed_working_branch() {
  assert_eq '"dev"' "$(jqs "$(cfg_of standard '.branching.develop = "dev"')" 'working_branch($cfg)')"
}

test_roles_environments() {
  local cfg
  cfg="$(cfg_of environments)"
  assert_json_eq '{"working":"develop","staging":"staging","release":"main","chain":["develop","staging","main"],"lower":["develop","staging"]}' \
    "$(jqs "$cfg" 'branching($cfg) | {working, staging, release, chain, lower}')"
  assert_eq '"staging"' "$(jqs "$cfg" 'release_source_branch($cfg)')"
  assert_eq '"develop"' "$(jqs "$(cfg_of standard)" 'release_source_branch($cfg)')"
}

test_branch_role_in_shell() {
  setup_repo 'branching: {preset: environments}
statuses: {in_review: In review}'
  local out
  out="$(SCRUM_ROOT="$PLUGIN_DIR/runtime" "$BASH" -c '. "$SCRUM_ROOT/lib/common.sh"; load_config
    printf "%s|%s|%s|%s\n" "$(branch_role working)" "$(branch_role release)" "$(branch_role staging)" "$(branch_role lower | tr "\n" ,)"
    has_working_branch && echo yes')"
  assert_eq "develop|main|staging|develop,staging,
yes" "$out"
}

# ---------- Allowed source branches ----------

test_allowed_task_branch_into_main() {
  assert_json_eq '{"allowed":false,"base_kind":"release","accepts":["release/*","hotfix/*"],"target":"develop"}' \
    "$(jqs "$(cfg_of standard)" 'allowed_source($cfg; "feat/12-login"; "main")')"
}

test_allowed_release_branch_into_main() {
  assert_eq 'true' "$(jqs "$(cfg_of standard)" 'allowed_source($cfg; "release/v1.4.0"; "main").allowed')"
  assert_eq 'true' "$(jqs "$(cfg_of standard)" 'allowed_source($cfg; "hotfix/31-payment-fails"; "main").allowed')"
}

test_allowed_back_merge_into_develop() {
  assert_eq 'true' "$(jqs "$(cfg_of standard)" 'allowed_source($cfg; "main"; "develop").allowed')"
}

test_allowed_trunk() {
  assert_eq 'true' "$(jqs "$(defaults)" 'allowed_source($cfg; "feat/12-login"; "main").allowed')"
}

test_allowed_staging_sources() {
  local cfg
  cfg="$(cfg_of environments)"
  assert_eq 'true' "$(jqs "$cfg" 'allowed_source($cfg; "develop"; "staging").allowed')"
  assert_eq 'true' "$(jqs "$cfg" 'allowed_source($cfg; "main"; "staging").allowed')"
  assert_eq 'false' "$(jqs "$cfg" 'allowed_source($cfg; "feat/1-x"; "staging").allowed')"
  assert_eq 'false' "$(jqs "$cfg" 'allowed_source($cfg; "staging"; "develop").allowed')"
  assert_eq 'true' "$(jqs "$cfg" 'allowed_source($cfg; "feat/1-x"; "develop").allowed')"
  assert_eq 'true' "$(jqs "$cfg" 'allowed_source($cfg; "feat/1-x"; "feat/2-y").allowed')"
}

test_pr_kinds() {
  local cfg
  cfg="$(cfg_of environments)"
  assert_eq '["release","hotfix","promotion","back_merge","back_merge","task","task"]' "$(jqs "$cfg" '[
    pr_kind($cfg; "release/v1.4.0"; "main"), pr_kind($cfg; "hotfix/3-x"; "main"),
    pr_kind($cfg; "develop"; "staging"), pr_kind($cfg; "main"; "develop"), pr_kind($cfg; "main"; "staging"),
    pr_kind($cfg; "feat/1-x"; "develop"), pr_kind($cfg; "feat/1-x"; "main")]')"
  assert_eq 'true' "$(jqs "$cfg" 'pr_exempt($cfg; "main"; "develop")')"
  assert_eq '"task"' "$(jqs "$(defaults)" 'pr_kind($cfg; "release/v1"; "main")')" "trunk has no release pull request"
}

# ---------- location labels ----------

test_location_helpers() {
  local cfg issue
  cfg="$(cfg_of environments)"
  issue='{"number":1,"state":"open","labels":[{"name":"status: In review"},{"name":"on: develop"},{"name":"bug"}]}'
  assert_eq '"develop"' "$(jq -nc -L "$LIBJQ" --argjson cfg "$cfg" --argjson i "$issue" 'include "scrum"; $i | task_location($cfg)')"
  assert_eq '["status: In review","bug","on: staging"]' \
    "$(jq -nc -L "$LIBJQ" --argjson cfg "$cfg" --argjson i "$issue" 'include "scrum"; $i | labels_with_location($cfg; "staging")')"
  assert_eq '["status: In review","bug"]' \
    "$(jq -nc -L "$LIBJQ" --argjson cfg "$cfg" --argjson i "$issue" 'include "scrum"; $i | labels_with_location($cfg; null)')"
  assert_eq '"develop"' "$(jq -nc -L "$LIBJQ" --argjson cfg "$cfg" --argjson i "$issue" 'include "scrum"; $i | review_location($cfg)')"
  assert_eq '"code_review"' "$(jq -nc -L "$LIBJQ" --argjson cfg "$cfg" 'include "scrum"; {labels: [{name: "status: In review"}]} | review_location($cfg)')"
  assert_eq 'null' "$(jq -nc -L "$LIBJQ" --argjson cfg "$(defaults | jq '.statuses.in_review = "In review"')" --argjson i "$issue" 'include "scrum"; $i | task_location($cfg)')" "trunk ignores location labels"
}

test_deploy_environments_by_preset() {
  assert_eq '{"develop":"staging","main":"production"}' "$(jqs "$(cfg_of standard)" 'deploy_environments($cfg)')"
  assert_eq '{"develop":"development","staging":"staging","main":"production"}' "$(jqs "$(cfg_of environments)" 'deploy_environments($cfg)')"
  assert_eq '{"main":"production"}' "$(jqs "$(defaults)" 'deploy_environments($cfg)')"
}

# ---------- which tasks a branch contains (design 5) ----------

contents_env() {
  setup_fake_gh
  setup_repo 'branching: {preset: standard}
statuses: {in_review: In review}'
  cat > "$T/issues.json" <<'JSON'
[{"number":12,"state":"open","title":"Login","labels":[{"name":"status: In review"},{"name":"on: develop"}]},
 {"number":13,"state":"open","title":"Signup","labels":[{"name":"status: In review"},{"name":"on: develop"}]},
 {"number":14,"state":"open","title":"Profile","labels":[{"name":"status: In progress"}]},
 {"number":15,"state":"open","title":"Review","labels":[{"name":"status: In review"}]}]
JSON
  route_json 'api --paginate repos/acme/blog/issues/12/timeline*' '[{"event":"cross-referenced","source":{"issue":{"number":40,"body":"Closes #12","pull_request":{"merged_at":"2026-11-20T10:00:00Z"},"repository":{"full_name":"acme/blog"}}}}]'
  route_json 'api --paginate repos/acme/blog/issues/13/timeline*' '[{"event":"cross-referenced","source":{"issue":{"number":41,"body":"Fixes #13","pull_request":{"merged_at":"2026-11-21T10:00:00Z"},"repository":{"full_name":"acme/blog"}}}}]'
  route_json 'api repos/acme/blog/pulls/40' '{"number":40,"merge_commit_sha":"aaa111"}'
  route_json 'api repos/acme/blog/pulls/41' '{"number":41,"merge_commit_sha":"bbb222"}'
  route_json 'api repos/acme/blog/compare/aaa111...main' '{"status":"ahead"}'
  route_json 'api repos/acme/blog/compare/bbb222...main' '{"status":"diverged"}'
}

branch_contents_of() { # branch_contents_of REF [LIMIT]
  # shellcheck disable=SC2016  # expanded by the inner shell
  SCRUM_ROOT="$PLUGIN_DIR/runtime" REF="$1" LIM="${2:-100}" "$BASH" -c '. "$SCRUM_ROOT/lib/common.sh"; load_config
    BRANCH_CONTENTS_LIMIT="$LIM"; branch_contents acme/blog "$REF" "$(cat "$T/issues.json")"'
}

test_branch_contents_contained_and_not() {
  contents_env
  local out
  out="$(branch_contents_of main)"
  assert_eq '[12]' "$(printf '%s' "$out" | jq -c .contained)"
  assert_eq '[13]' "$(printf '%s' "$out" | jq -c .missing)"
  assert_eq '[]' "$(printf '%s' "$out" | jq -c .unknown)"
  assert_eq '[{"number":40,"sha":"aaa111"}]' "$(printf '%s' "$out" | jq -c '.prs["12"]')"
  assert_eq 'false' "$(printf '%s' "$out" | jq -c .truncated)"
  assert_eq "" "$(gh_writes)" "read-only"
}

test_branch_contents_unknown_when_unread() {
  contents_env
  route_first 'api repos/acme/blog/compare/aaa111...main' '!fail'
  assert_eq '[12]' "$(branch_contents_of main | jq -c .unknown)"
}

test_branch_contents_over_the_cap() {
  contents_env
  local out
  out="$(branch_contents_of main 1)"
  assert_eq 'true' "$(printf '%s' "$out" | jq -c .truncated)"
  assert_eq '2' "$(printf '%s' "$out" | jq -c .total)"
  assert_eq '[12]' "$(printf '%s' "$out" | jq -c .contained)"
  assert_not_contains "$(gh_calls)" "issues/13/timeline" "past the cap nothing is read"
}

test_open_prs_query() {
  setup_fake_gh
  setup_repo 'version: 1'
  route_json 'api --paginate repos/acme/blog/pulls?state=open&per_page=100&head=acme%3Amain&base=develop' \
    '[{"number":50,"title":"Back-merge main into develop","html_url":"u","head":{"ref":"main"},"base":{"ref":"develop"}}]'
  route_json 'api --paginate repos/acme/blog/pulls?state=open&per_page=100&base=main' \
    '[{"number":51,"title":"Release v1.4.0","html_url":"u","head":{"ref":"release/v1.4.0"},"base":{"ref":"main"},"body":"x"},{"number":52,"title":"t","html_url":"u","head":{"ref":"feat/1-x"},"base":{"ref":"main"}}]'
  local out
  # shellcheck disable=SC2016  # expanded by the inner shell
  out="$(SCRUM_ROOT="$PLUGIN_DIR/runtime" "$BASH" -c '. "$SCRUM_ROOT/lib/common.sh"; load_config
    open_prs acme/blog main develop | jq -c "[.[].number]"; open_prs_matching acme/blog release/ main | jq -c "[.[].number]"')"
  assert_eq '[50]
[51]' "$out"
}
