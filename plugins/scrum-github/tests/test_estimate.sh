# spec: time-estimate

ejq() { jq -L "$PLUGIN_DIR/runtime/lib/jq" "$@"; }
strings_en() { jq -c .en "$PLUGIN_DIR/runtime/share/strings.json"; }
strings_vi() { jq -c .vi "$PLUGIN_DIR/runtime/share/strings.json"; }
dur() { ejq -n --arg d "$1" 'include "scrum"; $d | parse_duration'; }

# "Định dạng thời lượng"
test_duration_formats() {
  assert_eq "90" "$(dur 90)"
  assert_eq "25" "$(dur 25m)"
  assert_eq "120" "$(dur 2h)"
  assert_eq "90" "$(dur 1h30m)"
  assert_eq "90" "$(dur 1h30)"
  assert_eq "5" "$(dur ' 5m ')"
}

test_duration_invalid_values() {
  local d
  for d in 0 0m 0h0m abc -5 1.5h h m '' 1m30h 2x; do
    assert_eq "null" "$(dur "$d")" "\"$d\" is not a duration"
  done
}

test_fmt_duration() {
  assert_eq '["25m","1h","1h30m","2h5m"]' "$(ejq -nc 'include "scrum"; [25, 60, 90, 125] | map(fmt_duration)')"
}

# "Nơi lưu ước lượng"
test_estimate_block_first_write_keeps_the_body() {
  local body
  body="$(ejq -nr --argjson s "$(strings_en)" 'include "scrum";
    "Lưu bình luận" | set_estimate({work_minutes: 25, review_minutes: 20, by: "ai"}; $s)')"
  assert_eq 'Lưu bình luận

<!-- scrum:estimate -->
AI ~25m · Review ~20m
<!-- {"work_minutes":25,"review_minutes":20,"by":"ai"} -->
<!-- /scrum:estimate -->' "$body"
  assert_json_eq '{"work_minutes":25,"review_minutes":20,"by":"ai"}' \
    "$(jq -n --arg b "$body" '{body: $b}' | ejq 'include "scrum"; issue_estimate')"
}

test_estimate_block_overwrite_leaves_one_block() {
  local body
  body="$(ejq -nr --argjson s "$(strings_en)" 'include "scrum";
    "Lưu bình luận\n\nPart of #3" | set_estimate({work_minutes: 25, review_minutes: 20}; $s)
    | . as $b | {body: $b} | issue_estimate as $old
    | $b | set_estimate($old + {review_minutes: 30}; $s)')"
  assert_eq "1" "$(printf '%s' "$body" | /usr/bin/grep -c '<!-- scrum:estimate -->')"
  case "$body" in "Lưu bình luận"*) ;; *) _fail "body must still start with its text: $body" ;; esac
  assert_contains "$body" "Part of #3"
  assert_json_eq '{"work_minutes":25,"review_minutes":30,"by":"ai"}' \
    "$(jq -n --arg b "$body" '{body: $b}' | ejq 'include "scrum"; issue_estimate')"
}

test_estimate_block_human_and_vietnamese() {
  assert_eq 'Người ~1h30m · Review ~45m' \
    "$(ejq -nr --argjson s "$(strings_vi)" 'include "scrum"; estimate_line({work_minutes: 90, review_minutes: 45, by: "human"}; $s)')"
  assert_eq 'Review ~10m' \
    "$(ejq -nr --argjson s "$(strings_en)" 'include "scrum"; estimate_line({review_minutes: 10}; $s)')"
}

test_issue_without_block_has_no_estimate() {
  assert_eq "null" "$(printf '{"body":"Just text"}' | ejq 'include "scrum"; issue_estimate')"
  assert_eq "null" "$(printf '{"body":null}' | ejq 'include "scrum"; issue_estimate')"
}

test_broken_block_reads_as_no_estimate() {
  local b
  for b in '<!-- scrum:estimate -->\nAI ~25m\n<!-- {"work_minutes":25, -->\n<!-- /scrum:estimate -->' \
           '<!-- scrum:estimate -->\nAI ~25m\n<!-- /scrum:estimate -->' \
           '<!-- scrum:estimate -->\n<!-- {"work_minutes":0,"review_minutes":"x"} -->\n<!-- /scrum:estimate -->'; do
    assert_eq "null" "$(jq -n --arg b "$b" '{body: ($b | gsub("\\\\n"; "\n"))}' | ejq 'include "scrum"; issue_estimate')"
  done
}

test_report_tasks_carry_the_estimate() {
  local cfg
  cfg="$(cat "$PLUGIN_DIR/runtime/share/defaults.json")"
  assert_eq '[{"work_minutes":20,"by":"ai"},null]' "$(jq -n '[
      {number: 1, state: "open", labels: [], body: "x\n\n<!-- scrum:estimate -->\nAI ~20m\n<!-- {\"work_minutes\":20} -->\n<!-- /scrum:estimate -->"},
      {number: 2, state: "open", labels: [], body: "y"}]' \
    | ejq -c --argjson cfg "$cfg" 'include "scrum"; report_tasks($cfg) | map(._est)')"
}

# design 4: the one function behind every "done in" estimate (spec work-plan "Ba đợt").
test_eta_by_waves_three_waves() {
  assert_json_eq '{"work_minutes":90,"review_minutes":0,"estimated":5}' "$(jq -n '[
      {wave: 1, estimate: {work_minutes: 20}}, {wave: 1, estimate: {work_minutes: 8}},
      {wave: 2, estimate: {work_minutes: 15}}, {wave: 2, estimate: {work_minutes: 35}},
      {wave: 3, estimate: {work_minutes: 20}}, {wave: 3, estimate: null}]' \
    | ejq -c 'include "scrum"; eta_by_waves(5) | {work_minutes, review_minutes, estimated}')"
}

test_eta_by_waves_skips_waves_without_estimate() {
  assert_json_eq '{"work_minutes":25,"review_minutes":15}' "$(jq -n '[
      {wave: 1, estimate: {work_minutes: 20, review_minutes: 15}}, {wave: 2, estimate: null}]' \
    | ejq -c 'include "scrum"; eta_by_waves(5) | {work_minutes, review_minutes}')"
}
