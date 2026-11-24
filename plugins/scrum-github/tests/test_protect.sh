# scrum protect (spec repo-governance: protection preview, branches, rules, tags, merge settings)

MAIN_SHA="abc1234def5678abc1234def5678abc1234def56"

# protect_env PRESET [extra yaml]  A repository with main only, no rulesets, GitHub's default
# merge settings (every method on, head branches kept).
protect_env() {
  setup_fake_gh
  local yaml="branching:
  preset: $1"
  [ "$1" = trunk ] || yaml="$yaml
statuses:
  in_review: In review"
  setup_repo "$yaml${2:+
$2}"
  route 'api repos/acme/blog/branches/main' "branch.json"
  route 'api repos/acme/blog/branches/*' '!404'
  route_json 'api repos/acme/blog/git/ref/heads/main' "{\"ref\":\"refs/heads/main\",\"object\":{\"sha\":\"$MAIN_SHA\"}}"
  printf '{"name":"main"}' > "$FAKE_GH_DIR/branch.json"
  printf '[]' > "$FAKE_GH_DIR/rulesets.json"
  route 'api --paginate repos/acme/blog/rulesets*' "rulesets.json"
  printf '{"full_name":"acme/blog","default_branch":"main","allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":true,"delete_branch_on_merge":false,"allow_auto_merge":false}' > "$FAKE_GH_DIR/repo.json"
  route 'api repos/acme/blog' "repo.json"
}

plan_json() { run_scrum protect --json; assert_status 0 "$STATUS" "$ERR"; printf '%s' "$OUT"; }
ruleset_body() { # ruleset_body KEY  The body of one ruleset of the plan in $OUT.
  printf '%s' "$OUT" | jq -c --arg k "$1" '.rulesets[] | select(.key == $k) | .body'
}
sent_after() { # sent_after 'METHOD PATH'  The JSON sent with the first write to PATH.
  grep -A1 -F -- "-X $1 --input -" "$FAKE_GH_LOG" | sed -n 's/^STDIN //p' | head -1
}

# Make the repository match the plan in $1 (rulesets with ids, settings as desired).
protect_matching() {
  local plan="$1" i=0 id key list='[]'
  for key in $(printf '%s' "$plan" | jq -r '.rulesets[].key'); do
    i=$((i + 1)); id=$((100 + i))
    printf '%s' "$plan" | jq --arg k "$key" --argjson id "$id" \
      '.rulesets[] | select(.key == $k) | .body + {id: $id, source: "acme/blog", source_type: "Repository", bypass_actors: []}' \
      > "$FAKE_GH_DIR/ruleset-$id.json"
    route "api repos/acme/blog/rulesets/$id" "ruleset-$id.json"
    list="$(printf '%s' "$list" | jq -c --argjson id "$id" --arg n "$(jq -r .name "$FAKE_GH_DIR/ruleset-$id.json")" '. + [{id: $id, name: $n}]')"
  done
  printf '%s' "$list" > "$FAKE_GH_DIR/rulesets.json"
  printf '%s' "$plan" | jq '{full_name: "acme/blog", default_branch: "main"} + .settings.desired' > "$FAKE_GH_DIR/repo.json"
}

# ---------- Protection preview and confirmation ----------

test_protect_preview_lists_everything_and_writes_nothing() {
  protect_env standard
  run_scrum protect
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "create  develop (from main at abc1234)"
  assert_contains "$OUT" "ok      main"
  assert_contains "$OUT" "create  scrum: working on develop: pull request required, 1 approval, checks pr-check, merge methods merge commit, squash, no force push, no deletion"
  assert_contains "$OUT" "create  scrum: release on main: pull request required, 1 approval, checks pr-check, merge methods merge commit, no force push"
  assert_contains "$OUT" "create  scrum: tags: tags v*: no update, no deletion"
  assert_contains "$OUT" "allow_rebase_merge: true -> false"
  assert_contains "$OUT" "delete_branch_on_merge: false -> true"
  assert_contains "$OUT" "allow_auto_merge: false -> true"
  assert_contains "$OUT" "To apply, run again with --yes."
  assert_eq "" "$(gh_writes)" "no GitHub writes without --yes"
}

test_protect_json_is_the_plan() {
  protect_env standard
  plan_json >/dev/null
  assert_eq '["working","release","tags"]' "$(printf '%s' "$OUT" | jq -c '[.rulesets[].key]')"
  assert_eq '[{"name":"main","action":"none"},{"name":"develop","action":"create"}]' \
    "$(printf '%s' "$OUT" | jq -c '[.branches[] | {name, action}]')"
  assert_eq "standard" "$(printf '%s' "$OUT" | jq -r .preset)"
  assert_eq "5" "$(printf '%s' "$OUT" | jq -r .changes)"
  assert_eq "" "$(gh_writes)"
}

test_protect_already_protected() {
  protect_env standard
  plan_json >/dev/null
  local plan="$OUT"
  protect_matching "$plan"
  printf '{"name":"develop"}' > "$FAKE_GH_DIR/develop.json"
  route_first 'api repos/acme/blog/branches/develop' "develop.json"
  run_scrum protect
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "Nothing to change: the repository already matches preset standard."
  assert_not_contains "$OUT" "create  "
  assert_not_contains "$OUT" "update  "
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)" "nothing written when nothing differs"
}

test_protect_changed_ruleset_is_updated() {
  protect_env standard
  plan_json >/dev/null
  protect_matching "$OUT"
  # Someone changed the number of approvals on main by hand.
  jq '(.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count) = 2' \
    "$FAKE_GH_DIR/ruleset-102.json" > "$T/r.json" && mv "$T/r.json" "$FAKE_GH_DIR/ruleset-102.json"
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$(gh_writes)" "api -X PUT repos/acme/blog/rulesets/102 --input -"
  assert_eq "1" "$(sent_after 'PUT repos/acme/blog/rulesets/102' | jq '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count')"
  assert_not_contains "$(gh_writes)" "rulesets/101"
}

# ---------- Long-lived branches exist ----------

test_protect_creates_develop_at_main() {
  protect_env standard
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR$OUT"
  assert_eq "{\"ref\":\"refs/heads/develop\",\"sha\":\"$MAIN_SHA\"}" "$(sent_after 'POST repos/acme/blog/git/refs')"
  assert_not_contains "$(gh_writes)" "git/refs/heads/main" "main is never moved"
  assert_not_contains "$(gh_writes)" "DELETE"
  assert_contains "$OUT" "done    develop"
}

test_protect_environments_creates_develop_and_staging() {
  protect_env environments
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR$OUT"
  assert_eq "2" "$(grep -c -- '-X POST repos/acme/blog/git/refs' "$FAKE_GH_LOG")"
  assert_contains "$(gh_calls)" '{"ref":"refs/heads/staging","sha":"'"$MAIN_SHA"'"}'
  assert_contains "$(gh_calls)" '{"ref":"refs/heads/develop","sha":"'"$MAIN_SHA"'"}'
}

test_protect_missing_release_branch_is_reported() {
  protect_env standard
  route_first 'api repos/acme/blog/branches/main' '!404'
  run_scrum protect --yes
  assert_status 1 "$STATUS"
  assert_contains "$OUT" "the release branch main does not exist"
  assert_not_contains "$(gh_writes)" "git/refs"
}

# ---------- Branch rules ----------

test_protect_main_in_standard() {
  protect_env standard
  plan_json >/dev/null
  local main; main="$(ruleset_body release)"
  assert_eq '"scrum: release"' "$(printf '%s' "$main" | jq -c .name)"
  assert_eq '["refs/heads/main"]' "$(printf '%s' "$main" | jq -c .conditions.ref_name.include)"
  assert_eq '["deletion","non_fast_forward","pull_request","required_status_checks"]' "$(printf '%s' "$main" | jq -c '[.rules[].type] | sort')"
  assert_eq '["merge"]' "$(printf '%s' "$main" | jq -c '.rules[] | select(.type == "pull_request") | .parameters.allowed_merge_methods')"
  assert_eq '[{"context":"pr-check"}]' "$(printf '%s' "$main" | jq -c '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks')"
  assert_eq '["merge","squash"]' "$(ruleset_body working | jq -c '.rules[] | select(.type == "pull_request") | .parameters.allowed_merge_methods')"
  assert_eq '["refs/heads/develop"]' "$(ruleset_body working | jq -c .conditions.ref_name.include)"
}

test_protect_environments_staging_merge_commit_only() {
  protect_env environments
  plan_json >/dev/null
  assert_eq '["working","staging","release","tags"]' "$(printf '%s' "$OUT" | jq -c '[.rulesets[].key]')"
  assert_eq '["merge"]' "$(ruleset_body staging | jq -c '.rules[] | select(.type == "pull_request") | .parameters.allowed_merge_methods')"
  assert_eq '["refs/heads/staging"]' "$(ruleset_body staging | jq -c .conditions.ref_name.include)"
}

test_protect_applies_rulesets_with_yes() {
  protect_env standard
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR$OUT"
  assert_eq "3" "$(grep -c -- '-X POST repos/acme/blog/rulesets --input -' "$FAKE_GH_LOG")"
  assert_contains "$(gh_calls)" '"name":"scrum: working"'
  assert_contains "$(gh_calls)" '"name":"scrum: release"'
}

test_protect_solo_project() {
  protect_env standard "governance:
  approvals: 0"
  plan_json >/dev/null
  assert_eq "0" "$(ruleset_body release | jq '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count')"
  assert_eq "0" "$(ruleset_body working | jq '.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count')"
  run_scrum protect
  assert_contains "$OUT" "pull request required, no approval"
}

test_protect_required_checks_from_config() {
  protect_env standard "governance:
  required_checks: [test, lint]"
  plan_json >/dev/null
  assert_eq '["lint","pr-check","test"]' "$(ruleset_body release | jq -c '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | sort')"
}

# ---------- Version tags are protected ----------

test_protect_tag_rule() {
  protect_env standard
  plan_json >/dev/null
  local tags; tags="$(ruleset_body tags)"
  assert_eq '"tag"' "$(printf '%s' "$tags" | jq -c .target)"
  assert_eq '["refs/tags/v*"]' "$(printf '%s' "$tags" | jq -c .conditions.ref_name.include)"
  assert_eq '["deletion","update"]' "$(printf '%s' "$tags" | jq -c '[.rules[].type] | sort')"
}

test_protect_tag_rule_follows_prefix() {
  protect_env standard "release:
  tag_prefix: rel-"
  plan_json >/dev/null
  assert_eq '["refs/tags/rel-*"]' "$(ruleset_body tags | jq -c .conditions.ref_name.include)"
}

# ---------- Repository merge settings ----------

test_protect_trunk_settings() {
  protect_env trunk
  run_scrum protect --yes
  assert_status 0 "$STATUS" "$ERR$OUT"
  assert_eq '{"allow_auto_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false,"allow_squash_merge":true,"delete_branch_on_merge":true}' \
    "$(sent_after 'PATCH repos/acme/blog' | jq -c -S .)"
  assert_not_contains "$(gh_writes)" "git/refs" "trunk creates no branch"
  assert_not_contains "$(gh_calls)" '"name":"scrum: working"'
  assert_contains "$(gh_calls)" '"allowed_merge_methods":["squash"]'
}

test_protect_standard_settings_allow_squash_and_merge() {
  protect_env standard
  plan_json >/dev/null
  assert_eq '{"allow_auto_merge":true,"allow_merge_commit":true,"allow_rebase_merge":false,"allow_squash_merge":true,"delete_branch_on_merge":true}' \
    "$(printf '%s' "$OUT" | jq -c -S .settings.desired)"
}

# ---------- Protection that cannot be applied is reported ----------

test_protect_rulesets_refused_on_free_plan() {
  protect_env standard
  route_first 'api -X POST repos/acme/blog/rulesets*' '!403'
  run_scrum protect --yes
  assert_status 1 "$STATUS"
  assert_contains "$OUT" "FAILED  scrum: release"
  assert_contains "$OUT" "rules are not available for this repository on its plan"
  assert_contains "$(gh_writes)" "api -X PATCH repos/acme/blog --input -" "the merge settings are still applied"
  assert_contains "$OUT" "3 items failed; the others were applied."
  assert_eq "failed" "$(run_scrum protect --yes --json; printf '%s' "$OUT" | jq -r '[.results[] | select(.item == "ruleset:tags")][0].status')"
}

test_protect_rulesets_unreadable_is_noted() {
  protect_env standard
  route_first 'api --paginate repos/acme/blog/rulesets*' '!403'
  run_scrum protect
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "the rules could not be read: GitHub refused (HTTP 403)"
}

test_protect_settings_refused() {
  protect_env standard
  route_first 'api -X PATCH repos/acme/blog*' '!403'
  run_scrum protect --yes
  assert_status 1 "$STATUS"
  assert_contains "$OUT" "the token has no admin rights on the repository"
  assert_eq "3" "$(grep -c -- '-X POST repos/acme/blog/rulesets --input -' "$FAKE_GH_LOG")"
}

test_protect_obsolete_ruleset_is_listed_not_deleted() {
  protect_env trunk
  printf '[{"id":7,"name":"scrum: working"}]' > "$FAKE_GH_DIR/rulesets.json"
  route_json 'api repos/acme/blog/rulesets/7' '{"id":7,"name":"scrum: working","target":"branch","enforcement":"active","rules":[]}'
  run_scrum protect
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "obsolete scrum: working (not in preset trunk; not deleted)"
}

test_protect_unknown_option() {
  protect_env standard
  run_scrum protect --force
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "unknown option for protect"
}
