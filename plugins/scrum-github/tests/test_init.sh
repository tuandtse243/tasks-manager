# spec: repo-bootstrap

label_plan() { # label_plan CONFIG_JSON EXISTING_JSON
  jqt label-plan -n --argjson cfg "$1" --argjson existing "$2"
}
defaults() { cat "$PLUGIN_DIR/runtime/share/defaults.json"; }

test_label_plan_first_run_keeps_bug() {
  local plan
  plan="$(label_plan "$(defaults)" "$(cat "$FIXTURES/labels-github-default.json")")"
  assert_json_eq '["status: New","status: In progress","status: Done","points: 0","points: 1","points: 3","points: 7","type: feature","type: epic","scrum: meta","no-task","ai-ready"]' \
    "$(printf '%s' "$plan" | jq -c '[.create[].name]')"
  assert_eq '[]' "$(printf '%s' "$plan" | jq -c '.update')"
  assert_eq '["bug"]' "$(printf '%s' "$plan" | jq -c '.unchanged')"
}

test_label_plan_second_run_changes_nothing() {
  local plan
  plan="$(label_plan "$(defaults)" "$(cat "$FIXTURES/labels-after-init.json")")"
  assert_eq '[]' "$(printf '%s' "$plan" | jq -c '.create')"
  assert_eq '[]' "$(printf '%s' "$plan" | jq -c '.update')"
}

test_label_plan_has_epic() {
  local plan
  plan="$(label_plan "$(defaults)" "[]")"
  assert_json_eq '{"name":"type: epic","color":"5319e7","description":"Large requirement split into features"}' \
    "$(printf '%s' "$plan" | jq -c '.create[] | select(.name == "type: epic")')"
}

# delta scrum-config "Nhãn epic: Repo cài bản cũ"
test_label_plan_old_install_creates_only_epic() {
  local old plan
  old="$(jq 'map(select(.name != "type: epic"))' "$FIXTURES/labels-after-init.json")"
  plan="$(label_plan "$(defaults)" "$old")"
  assert_eq '["type: epic"]' "$(printf '%s' "$plan" | jq -c '[.create[].name]')"
  assert_eq '[]' "$(printf '%s' "$plan" | jq -c '.update')"
  assert_contains "$(printf '%s' "$plan" | jq -c '.unchanged')" '"type: feature"'
}

test_label_plan_restores_hand_edited_color() {
  local existing plan
  existing="$(jq 'map(if .name == "status: Done" then .color = "000000" else . end)' "$FIXTURES/labels-after-init.json")"
  plan="$(label_plan "$(defaults)" "$existing")"
  assert_json_eq '[{"current":"status: Done","name":"status: Done","color":"0e8a16","description":"Task finished"}]' \
    "$(printf '%s' "$plan" | jq -c '.update')"
}

test_label_plan_reports_obsolete_points() {
  local cfg plan
  cfg="$(defaults | jq '.points.scale = [0,1,3]')"
  plan="$(label_plan "$cfg" "$(cat "$FIXTURES/labels-after-init.json")")"
  assert_eq '["points: 7"]' "$(printf '%s' "$plan" | jq -c '.obsolete')"
  assert_eq '[]' "$(printf '%s' "$plan" | jq -c '.create')"
}

test_label_plan_color_override() {
  local cfg plan
  cfg="$(defaults | jq '.colors = {"bug": "#FF0000", "status: New": "123456"}')"
  plan="$(label_plan "$cfg" "$(cat "$FIXTURES/labels-after-init.json")")"
  assert_json_eq '["bug","status: New"]' "$(printf '%s' "$plan" | jq -c '[.update[].name] | sort')"
  assert_eq 'ff0000' "$(printf '%s' "$plan" | jq -r '.update[] | select(.name == "bug") | .color')"
}

# ---------- scrum init with a fake gh ----------

init_env() {
  setup_fake_gh
  setup_repo
  route 'api --paginate repos/acme/blog/labels*' "labels.json"
  cp "$FIXTURES/labels-github-default.json" "$FAKE_GH_DIR/labels.json"
}

test_init_creates_config_labels_and_files() {
  init_env
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  [ -f "$SCRUM_REPO_DIR/.github/scrum.yml" ] || _fail "config not created"
  assert_eq "$(cat "$PLUGIN_DIR/templates/scrum.yml")" "$(cat "$SCRUM_REPO_DIR/.github/scrum.yml")"
  # 12 labels, plus "status: In review" and "on: develop" of preset standard (the template's)
  assert_eq "14" "$(gh_writes | grep -c 'POST repos/acme/blog/labels')" "14 labels created"
  for f in ISSUE_TEMPLATE/task.yml pull_request_template.md workflows/scrum-status-sync.yml workflows/scrum-pr-link-check.yml workflows/scrum-daily-digest.yml scrum/bin/scrum scrum/lib/jq/scrum.jq scrum/share/defaults.json scrum/GENERATED.md; do
    [ -f "$SCRUM_REPO_DIR/.github/$f" ] || _fail "missing .github/$f"
  done
  [ -x "$SCRUM_REPO_DIR/.github/scrum/bin/scrum" ] || _fail "vendored scrum not executable"
  assert_contains "$OUT" "git add .github"
}

test_init_dry_run_writes_nothing() {
  init_env
  run_scrum init --dry-run
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "would create   status: New"
  assert_contains "$OUT" "would create  .github/pull_request_template.md"
  assert_eq "" "$(gh_writes)" "no GitHub writes"
  [ ! -e "$SCRUM_REPO_DIR/.github/scrum.yml" ] || _fail "config written in dry run"
  [ ! -e "$SCRUM_REPO_DIR/.github/scrum" ] || _fail "runtime written in dry run"
}

test_init_keeps_existing_config() {
  init_env
  printf 'points:\n  scale: [1, 2, 3, 5, 8]\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_eq 'points:
  scale: [1, 2, 3, 5, 8]' "$(cat "$SCRUM_REPO_DIR/.github/scrum.yml")"
  assert_contains "$(gh_calls)" '"name":"points: 5"'
  assert_contains "$(cat "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml")" '- "8"'
}

test_init_second_run_makes_no_writes() {
  init_env
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  cp "$FIXTURES/labels-after-init-standard.json" "$FAKE_GH_DIR/labels.json"
  : > "$FAKE_GH_LOG"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(gh_writes)" "no GitHub writes on second run"
  assert_not_contains "$OUT" "created"
  assert_contains "$OUT" "unchanged     .github/workflows/scrum-status-sync.yml"
}

test_init_keeps_edited_file_until_forced() {
  init_env
  mkdir -p "$SCRUM_REPO_DIR/.github"
  printf 'Our own template\n' > "$SCRUM_REPO_DIR/.github/pull_request_template.md"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "Our own template" "$(cat "$SCRUM_REPO_DIR/.github/pull_request_template.md")"
  assert_contains "$OUT" "conflict      .github/pull_request_template.md"
  assert_contains "$OUT" "--force-file .github/pull_request_template.md"
  run_scrum init --force-file .github/pull_request_template.md
  assert_contains "$(cat "$SCRUM_REPO_DIR/.github/pull_request_template.md")" "Closes #"
}

test_issue_form_follows_point_scale() {
  init_env
  printf 'points:\n  scale: [0, 1, 3, 7]\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  local form; form="$(cat "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml")"
  assert_contains "$form" 'labels: ["status: New"]'
  assert_eq '["0","1","3","7"]' "$(yq -o=json '.body[] | select(.id == "points") | .attributes.options' "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml" | jq -c .)"
  printf 'points:\n  scale: [1, 2, 3, 5, 8]\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init --force-file .github/ISSUE_TEMPLATE/task.yml
  assert_eq '["1","2","3","5","8"]' "$(yq -o=json '.body[] | select(.id == "points") | .attributes.options' "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml" | jq -c .)"
}

test_digest_cron_comes_from_config() {
  init_env
  printf 'digest:\n  cron: "30 2 * * 1-5"\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_eq '30 2 * * 1-5' "$(yq '.on.schedule[0].cron' "$SCRUM_REPO_DIR/.github/workflows/scrum-daily-digest.yml")"
}

test_workflows_never_check_out_pr_code() {
  local wf perms
  for wf in "$PLUGIN_DIR"/templates/github/workflows/*.yml; do
    assert_not_contains "$(cat "$wf")" "github.event.pull_request.head" "$(basename "$wf") checks out PR code"
    # Only optional secrets: the project token, and the digest webhook in the digest workflow
    # (spec pr-task-linking: Quyền tối thiểu cho workflow).
    assert_eq "" "$(grep -o 'secrets\.[A-Za-z_]*' "$wf" | grep -v '^secrets\.SCRUM_PROJECT_TOKEN$' \
      | { if [ "$(basename "$wf")" = scrum-daily-digest.yml ]; then grep -v '^secrets\.SCRUM_DIGEST_WEBHOOK$'; else cat; fi; } || true)" \
      "$(basename "$wf") uses another secret"
    perms="$(yq -o=json '.permissions' "$wf" | jq -c -S .)"
    case "$(basename "$wf")" in
      scrum-project-sync.yml) assert_eq '{"contents":"read","issues":"write"}' "$perms" "$(basename "$wf") permissions" ;;
      *) assert_eq '{"contents":"read","issues":"write","pull-requests":"read"}' "$perms" "$(basename "$wf") permissions" ;;
    esac
  done
  assert_not_contains "$(cat "$PLUGIN_DIR/templates/github/workflows/scrum-pr-link-check.yml")" "secrets." "the PR check needs no secret"
}

test_init_second_run_does_not_ask_to_commit() {
  init_env
  git init -q "$SCRUM_REPO_DIR"
  run_scrum init
  git -C "$SCRUM_REPO_DIR" add -A && git -C "$SCRUM_REPO_DIR" -c user.email=t@example.com -c user.name=t commit -qm init
  cp "$FIXTURES/labels-after-init.json" "$FAKE_GH_DIR/labels.json"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_not_contains "$OUT" "git add .github"
}

# ---------- project board (spec: project-board-sync, Workflow đồng bộ Project) ----------

test_init_project_off_skips_project_workflow() {
  init_env
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  [ ! -f "$SCRUM_REPO_DIR/.github/workflows/scrum-project-sync.yml" ] || _fail "project workflow installed while the project is off"
  assert_contains "$(cat "$SCRUM_REPO_DIR/.github/workflows/scrum-status-sync.yml")" 'SCRUM_PROJECT_TOKEN: ${{ secrets.SCRUM_PROJECT_TOKEN }}'
  assert_not_contains "$OUT" "scrum project init"
}

test_init_project_on_installs_workflow_with_cron() {
  init_env
  printf 'project:\n  enabled: true\n  owner: acme\n  number: 2\n  poll_cron: "*/20 1-11 * * 1-5"\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  local wf="$SCRUM_REPO_DIR/.github/workflows/scrum-project-sync.yml"
  [ -f "$wf" ] || _fail "project workflow not installed"
  assert_contains "$(cat "$wf")" 'cron: "*/20 1-11 * * 1-5"'
  assert_contains "$(cat "$wf")" 'SCRUM_PROJECT_TOKEN: ${{ secrets.SCRUM_PROJECT_TOKEN }}'
  assert_contains "$(cat "$wf")" 'group: scrum-project-sync'
  assert_contains "$OUT" "scrum project init"
  assert_contains "$OUT" "add the repository secret SCRUM_PROJECT_TOKEN"
}

test_init_project_on_with_secret_does_not_ask_for_it() {
  init_env
  printf 'project:\n  enabled: true\n  owner: acme\n  number: 2\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  cp "$FIXTURES/actions-secrets.json" "$FAKE_GH_DIR/secrets.json"
  route 'api repos/acme/blog/actions/secrets' "secrets.json"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "the secret SCRUM_PROJECT_TOKEN is set"
  assert_not_contains "$OUT" "add the repository secret"
}

test_init_old_status_sync_is_a_conflict() {
  init_env
  run_scrum init
  local wf="$SCRUM_REPO_DIR/.github/workflows/scrum-status-sync.yml"
  # the file as version 0.1.0 installed it
  grep -v 'SCRUM_PROJECT_TOKEN\|Optional: moves the card' "$wf" > "$wf.old"; mv "$wf.old" "$wf"
  run_scrum init
  assert_contains "$OUT" "conflict      .github/workflows/scrum-status-sync.yml"
  run_scrum init --force-file .github/workflows/scrum-status-sync.yml
  assert_contains "$OUT" "overwritten   .github/workflows/scrum-status-sync.yml"
  assert_contains "$(cat "$wf")" "SCRUM_PROJECT_TOKEN"
}

test_init_copies_no_vendored_skill() {
  init_env
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "" "$(find "$SCRUM_REPO_DIR" -path '*pocock*')" "vendored skills stay in the plugin"
  assert_eq "" "$(find "$SCRUM_REPO_DIR" -name 'project-board.sh')" "the wizard stays in the plugin"
}

test_pr_template_has_four_sections() {
  init_env
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  local body; body="$(cat "$SCRUM_REPO_DIR/.github/pull_request_template.md")"
  assert_eq "## Summary
## Evidence
## Merge Danger
## Task" "$(printf '%s\n' "$body" | grep -E '^## ')"
  assert_contains "$body" "Closes #"
  assert_contains "$body" '"no-task" label'
  assert_not_contains "$body" "{{"
}

test_version_matches_plugin_json() {
  run_scrum --version
  assert_eq "0.12.0" "$OUT"
  assert_eq "$(jq -r .version "$PLUGIN_DIR/.claude-plugin/plugin.json")" "$OUT"
}

# ---------- record of generated files (delta repo-bootstrap "Cài template vào repo") ----------

points_options() { yq -o=json '.body[] | select(.id == "points") | .attributes.options' "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml" | jq -c .; }

test_init_records_generated_files() {
  init_env
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  local rec="$SCRUM_REPO_DIR/.github/scrum/files.json"
  [ -f "$rec" ] || _fail "no files.json"
  assert_eq "$(git hash-object "$SCRUM_REPO_DIR/.github/pull_request_template.md")" \
    "$(jq -r '.files[".github/pull_request_template.md"]' "$rec")"
  assert_eq "5" "$(jq '.files | length' "$rec")"
}

test_init_updates_issue_form_after_scale_change() {
  init_env
  run_scrum init
  printf 'points:\n  scale: [1, 2, 3, 5, 8]\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "updated       .github/ISSUE_TEMPLATE/task.yml"
  assert_eq '["1","2","3","5","8"]' "$(points_options)"
  assert_not_contains "$OUT" "conflict"
}

test_init_updates_digest_after_cron_change() {
  init_env
  run_scrum init
  printf 'digest:\n  cron: "30 2 * * 1-5"\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_contains "$OUT" "updated       .github/workflows/scrum-daily-digest.yml"
  assert_contains "$(cat "$SCRUM_REPO_DIR/.github/workflows/scrum-daily-digest.yml")" 'cron: "30 2 * * 1-5"'
}

test_init_dry_run_reports_update_and_writes_nothing() {
  init_env
  run_scrum init
  local form; form="$(cat "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml")"
  local rec; rec="$(cat "$SCRUM_REPO_DIR/.github/scrum/files.json")"
  printf 'points:\n  scale: [1, 2, 3, 5, 8]\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init --dry-run
  assert_contains "$OUT" "would update  .github/ISSUE_TEMPLATE/task.yml"
  assert_eq "$form" "$(cat "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml")"
  assert_eq "$rec" "$(cat "$SCRUM_REPO_DIR/.github/scrum/files.json")"
}

test_init_keeps_hand_edited_file_after_scale_change() {
  init_env
  run_scrum init
  printf '# our form\n' >> "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml"
  local form; form="$(cat "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml")"
  printf 'points:\n  scale: [1, 2, 3, 5, 8]\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_contains "$OUT" "conflict      .github/ISSUE_TEMPLATE/task.yml"
  assert_eq "$form" "$(cat "$SCRUM_REPO_DIR/.github/ISSUE_TEMPLATE/task.yml")"
}

test_init_without_record_treats_difference_as_conflict() {
  init_env
  run_scrum init
  rm "$SCRUM_REPO_DIR/.github/scrum/files.json"   # installed by a version that kept no record
  printf 'points:\n  scale: [1, 2, 3, 5, 8]\n' > "$SCRUM_REPO_DIR/.github/scrum.yml"
  run_scrum init
  assert_contains "$OUT" "conflict      .github/ISSUE_TEMPLATE/task.yml"
  assert_eq '["0","1","3","7"]' "$(points_options)"
  [ -f "$SCRUM_REPO_DIR/.github/scrum/files.json" ] || _fail "record written for the files that matched"
}

test_init_updates_automatically_after_forced_overwrite() {
  init_env
  run_scrum init
  local pr="$SCRUM_REPO_DIR/.github/pull_request_template.md" rec="$SCRUM_REPO_DIR/.github/scrum/files.json"
  printf 'Our own template\n' > "$pr"
  run_scrum init --force-file .github/pull_request_template.md
  assert_contains "$OUT" "overwritten   .github/pull_request_template.md"
  assert_eq "$(git hash-object "$pr")" "$(jq -r '.files[".github/pull_request_template.md"]' "$rec")" "recorded after overwrite"
}

# delta repo-bootstrap "Nâng plugin, file chưa sửa": the recorded copy is an older template.
test_init_updates_unedited_file_from_older_version() {
  init_env
  run_scrum init
  local pr="$SCRUM_REPO_DIR/.github/pull_request_template.md" rec="$SCRUM_REPO_DIR/.github/scrum/files.json"
  printf 'Template of an older version\n' > "$pr"
  jq --arg h "$(git hash-object "$pr")" '.files[".github/pull_request_template.md"] = $h' "$rec" > "$T/rec"
  mv "$T/rec" "$rec"
  run_scrum init
  assert_contains "$OUT" "updated       .github/pull_request_template.md"
  assert_contains "$(cat "$pr")" "Closes #"
}

# delta repo-bootstrap "Secret webhook cho workflow digest"
test_digest_workflow_passes_the_webhook_secret() {
  init_env
  run_scrum init
  assert_contains "$(cat "$SCRUM_REPO_DIR/.github/workflows/scrum-daily-digest.yml")" 'SCRUM_DIGEST_WEBHOOK: ${{ secrets.SCRUM_DIGEST_WEBHOOK }}'
}

# delta repo-bootstrap "Label In review": the status workflow hears converted_to_draft.
test_status_workflow_hears_converted_to_draft() {
  assert_contains "$(yq -o=json '.on.pull_request_target.types' "$PLUGIN_DIR/templates/github/workflows/scrum-status-sync.yml" | jq -c .)" '"converted_to_draft"'
}

test_label_plan_in_review_on_creates_the_label() {
  local plan
  plan="$(label_plan "$(defaults | jq '.statuses.in_review = "In review"')" "$(cat "$FIXTURES/labels-after-init.json")")"
  assert_json_eq '[{"name":"status: In review","color":"1d76db","description":"Task waiting for review"}]' \
    "$(printf '%s' "$plan" | jq -c '.create')"
}

test_label_plan_in_review_turned_off_is_obsolete() {
  local plan existing
  existing="$(jq '. + [{"name":"status: In review","color":"1d76db","description":"Task waiting for review"}]' "$FIXTURES/labels-after-init.json")"
  plan="$(label_plan "$(defaults)" "$existing")"
  assert_eq '["status: In review"]' "$(printf '%s' "$plan" | jq -c '.obsolete')"
  assert_eq '[]' "$(printf '%s' "$plan" | jq -c '.create')"
}

# delta scrum-config "Nhãn ai-ready: Mặc định"
test_label_plan_creates_ai_ready() {
  local plan old
  old="$(jq 'map(select(.name != "ai-ready"))' "$FIXTURES/labels-after-init.json")"
  plan="$(label_plan "$(defaults)" "$old")"
  assert_eq '["ai-ready"]' "$(printf '%s' "$plan" | jq -c '[.create[].name]')"
  plan="$(label_plan "$(defaults | jq '.labels.ai_ready = "agent: ready"')" "[]")"
  assert_contains "$(printf '%s' "$plan" | jq -c '[.create[].name]')" '"agent: ready"'
}

# spec branching-presets: one location label per long-lived branch below the release branch.
test_label_plan_location_labels_by_preset() {
  local cfg
  cfg="$(defaults | jq '.statuses.in_review = "In review" | .branching.preset = "standard"')"
  assert_json_eq '[{"name":"on: develop","color":"c5def5","description":"Task merged into develop, not released yet"}]' \
    "$(label_plan "$cfg" "[]" | jq -c '[.create[] | select(.name | startswith("on: "))]')"
  cfg="$(defaults | jq '.statuses.in_review = "In review" | .branching.preset = "environments"')"
  assert_json_eq '["on: develop","on: staging"]' "$(label_plan "$cfg" "[]" | jq -c '[.create[].name | select(startswith("on: "))]')"
  assert_json_eq '[]' "$(label_plan "$(defaults)" "[]" | jq -c '[.create[].name | select(startswith("on: "))]')" "trunk has no location label"
}

test_label_plan_reports_obsolete_location_label() {
  local cfg
  cfg="$(defaults | jq '.statuses.in_review = "In review" | .branching.preset = "standard" | .branching.develop = "dev"')"
  assert_json_eq '["on: develop"]' "$(label_plan "$cfg" '[{"name":"on: develop","color":"c5def5","description":""}]' | jq -c .obsolete)"
}

test_init_new_setup_writes_preset_standard() {
  init_env
  run_scrum init
  assert_status 0 "$STATUS" "$ERR"
  assert_eq "standard" "$(yq '.branching.preset' "$SCRUM_REPO_DIR/.github/scrum.yml")"
  assert_contains "$(gh_calls)" '"name":"on: develop"'
}
