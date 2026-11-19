# spec: requirement-discovery (Kiểm tra cấu trúc brief), project-context (Kiểm tra cấu trúc tài liệu ngữ cảnh)

SECTIONS="$PLUGIN_DIR/runtime/share/doc-sections.json"

doc_of() { # doc_of TYPE [skip-section...]  A document with every section of TYPE except the skipped ones
  local type="$1"; shift
  printf '# Doc\n\n'
  [ "$type" != context ] || printf '<!-- scrum:context sha=abc1234 date=2026-11-19 -->\n\n'
  jq -r --arg t "$type" '.[$t].required[]' "$SECTIONS" | while IFS= read -r s; do
    case " $* " in *" $s "*) continue ;; esac
    printf '## %s\n\nText.\n\n' "$s"
  done
}

template_headings() { grep -E '^## ' "$1" | sed 's/^## //' | sort; }
sections_of() { jq -r --arg t "$1" '.[$t].required[], .[$t].optional[]' "$SECTIONS" | sort; }

# ---------- brief ----------

test_brief_complete() {
  doc_of brief > "$T/brief.md"
  run_scrum doc check "$T/brief.md"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "every required section of a brief is present"
}

test_brief_missing_risks() {
  doc_of brief Risks > "$T/brief.md"
  run_scrum doc check "$T/brief.md"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "missing section: ## Risks"
  assert_eq "1" "$(printf '%s\n' "$ERR" | grep -c 'missing section')"
}

test_brief_optional_sections_not_required() {
  doc_of brief > "$T/brief.md"
  assert_not_contains "$(cat "$T/brief.md")" "Project fit"
  assert_not_contains "$(cat "$T/brief.md")" "Sources"
  run_scrum doc check "$T/brief.md"
  assert_status 0 "$STATUS" "$ERR"
}

test_brief_nine_required_sections() {
  assert_eq "9" "$(jq '.brief.required | length' "$SECTIONS")"
}

test_brief_template_matches_sections() {
  assert_eq "$(sections_of brief)" "$(template_headings "$PLUGIN_DIR/reference/brief-template.md")"
}

test_brief_template_passes_check() {
  run_scrum doc check "$PLUGIN_DIR/reference/brief-template.md"
  assert_status 0 "$STATUS" "$ERR"
}

test_heading_case_and_spaces_ignored() {
  doc_of brief | sed 's/^## Risks$/##   risks  /' > "$T/brief.md"
  run_scrum doc check "$T/brief.md"
  assert_status 0 "$STATUS" "$ERR"
}

test_type_from_name_or_option() {
  doc_of brief > "$T/notes.md"
  run_scrum doc check "$T/notes.md"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "--type"
  run_scrum doc check "$T/notes.md" --type brief
  assert_status 0 "$STATUS" "$ERR"
}

# ---------- project context ----------

test_context_complete() {
  doc_of context > "$T/project-context.md"
  run_scrum doc check "$T/project-context.md"
  assert_status 0 "$STATUS" "$ERR"
  assert_contains "$OUT" "scanned at abc1234 on 2026-11-19"
}

test_context_missing_data_model() {
  doc_of context "Data model" > "$T/project-context.md"
  run_scrum doc check "$T/project-context.md"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "missing section: ## Data model"
}

test_context_missing_stamp() {
  doc_of context | grep -v 'scrum:context' > "$T/project-context.md"
  run_scrum doc check "$T/project-context.md"
  assert_status 1 "$STATUS"
  assert_contains "$ERR" "no scan stamp"
}

test_context_template_matches_sections() {
  assert_eq "$(sections_of context)" "$(template_headings "$PLUGIN_DIR/reference/project-context-template.md")"
}

test_context_template_passes_check() {
  run_scrum doc check "$PLUGIN_DIR/reference/project-context-template.md"
  assert_status 0 "$STATUS" "$ERR"
}
