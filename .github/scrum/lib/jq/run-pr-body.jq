# Title and description of the pull request of a run: the review pack (spec ai-run "Một PR gói
# review", "Một PR mỗi đợt"; design 7). Pure: no network.
# -n --argjson state RUN_STATE --argjson issues {"N": issue} (merged tasks; may miss some)
#    --argjson cfg CONFIG --argjson strings STRINGS --argjson wave W|null
#    --argjson after {number, wave}|null (the pull request of the wave before, to merge first)
# Output: {title, body, numbers: [merged tasks in this pull request]}
include "scrum";

def s: $strings;
# Checkbox lines of an issue body: those under an "Acceptance" heading when there is one (the
# plan writes "### Acceptance criteria"), else every checkbox but the subtasks; scrum blocks are
# left out.
def acceptance_items:
  ((.body // "") | if type == "string" then . else "" end | strip_scrum_blocks | split("\n"))
  | reduce .[] as $l ([{h: "", lines: []}];
      if ($l | test("^#{1,6}\\s")) then . + [{h: $l, lines: []}] else .[-1].lines += [$l] end)
  | (map(select(.h | test("acceptance|tiêu chí|nghiệm thu"; "i")))) as $acc
  | (if ($acc | length) > 0 then $acc else map(select(.h | test("subtask|việc con"; "i") | not)) end)
  | [.[].lines[] | capture("^\\s*[-*+]\\s+\\[[ xX]\\]\\s+(?<t>.+?)\\s*$")? | .t];
# A note of the agent: a text, a list of texts, or nothing.
def note_text:
  if . == null or . == "" or . == [] then tr(s; "run_pr_none_given")
  elif type == "array" then map("- \(tostring)") | join("\n")
  else tostring end;
def wave_ok: $wave == null or .wave == $wave;

($state.tasks | [.[]] | sort_by(.wave, .number)) as $all
| [$all[] | select(.state == "merged" and wave_ok)] as $merged
| [$all[] | select((.state == "failed" or .state == "excluded") and wave_ok)] as $out
| (if $wave == null or $wave == 1 then $state.excluded else [] end) as $left
| (if $state.sprint then $state.sprint.title else "AI run" end) as $sprint
| ([$merged[].number] | map("#\(.)") | join(", ")) as $nums
| trn(s; "run_pr_tasks"; ($merged | length); {}) as $tasks_text
| def section($t):
    ($issues[$t.number | tostring] // {}) as $i
    | (($t.estimate | clean_estimate) // ($i | issue_estimate)) as $e
    | ($i | acceptance_items) as $acc
    | ($t.notes // {}) as $n
    | [ "## #\($t.number) \($t.title)",
        "Closes #\($t.number)",
        "**\(tr(s; "run_pr_acceptance"))**",
        (if ($acc | length) == 0 then tr(s; "run_pr_no_acceptance") else $acc | map("- [ ] \(.)") | join("\n") end),
        "**\(tr(s; "run_pr_time"))**: " + tr(s; "run_pr_time_line";
            {estimate: (if $e == null then tr(s; "run_pr_no_estimate") else estimate_line($e; s) end),
             actual: (if $t.minutes == null then tr(s; "run_pr_unknown") else $t.minutes | fmt_duration end)}),
        "**\(tr(s; "run_pr_manual_test"))**",
        (($n.manual_test // $n.text) | note_text),
        "**\(tr(s; "run_pr_look_closely"))**",
        ($n.look_closely | note_text)
      ] | join("\n\n");
  ([$merged[] | .estimate | clean_estimate | select(. != null) | .work_minutes // 0] | add // 0) as $est_work
| ([$merged[] | .minutes | select(. != null)] | add // 0) as $act
| ([$merged[] | .estimate | clean_estimate | select(. != null) | .review_minutes // 0] | add // 0) as $est_review
| { title: (if $wave == null then tr(s; "run_pr_title"; {sprint: $sprint, tasks: $tasks_text, numbers: $nums})
           else tr(s; "run_pr_title_wave"; {sprint: $sprint, wave: $wave, tasks: $tasks_text, numbers: $nums}) end),
    numbers: [$merged[].number],
    body: ([ tr(s; "run_pr_intro"; {run: $state.id, branch: $state.branch}),
             (if $after != null then tr(s; "run_pr_after"; {pr: $after.number, wave: $after.wave, base: $state.base}) else empty end),
             ($merged[] | section(.)),
             (if ($out | length) + ($left | length) > 0 then
                "## \(tr(s; "run_pr_not_included"))\n\n"
                + ([ ($out[] | if .state == "failed"
                                then "- " + tr(s; "run_pr_failed"; {number: .number, title: .title, reason: (.reason // "?"), status: $cfg.statuses.new})
                                else "- " + tr(s; "run_pr_left_out"; {number: .number, title: .title, reason: (.reason // "?")}) end),
                     ($left[] | "- " + tr(s; "run_pr_left_out"; {number: .number, title: (.title // "?"), reason: .reason})) ] | join("\n"))
              else empty end),
             (if ($merged | length) == 0 then empty
              elif $est_work > 0 then tr(s; "run_pr_totals"; {estimate: ($est_work | fmt_duration), actual: ($act | fmt_duration)})
              elif $est_review > 0 then tr(s; "run_pr_totals_review"; {estimate: ($est_review | fmt_duration), actual: ($act | fmt_duration)})
              elif $act > 0 then tr(s; "run_pr_totals"; {estimate: tr(s; "run_pr_no_estimate"), actual: ($act | fmt_duration)})
              else empty end)
           ] | join("\n\n")) + "\n" }
