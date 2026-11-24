# The summary posted when a sprint closes (spec sprint-lifecycle "Đóng sprint").
# -n --argjson plan CLOSE_PLAN --argjson ms MILESTONES --argjson sprint MILESTONE
#    --argjson burndown BURNDOWN --argjson strings STRINGS --argjson cfg CONFIG
# Output: {body}
include "scrum";
def pts: if . == null then tr($strings; "summary_unestimated") else trn($strings; "pts"; .; {}) end;
($sprint | sprint_info) as $s
| ([($s.description // "") | capture("\\*\\*Goal:\\*\\* (?<g>[^\n]+)")] | .[0].g) as $goal
| ([$ms[] | select(.number != $s.number)] | recent_velocity_sprints) as $prev
| { body: ([
      "<!-- scrum:summary -->",
      "## " + tr($strings; "summary_title"; {title: $s.title}),
      "",
      (if $goal then tr($strings; "summary_goal"; {goal: $goal}), "" else empty end),
      tr($strings; "summary_velocity"; {v: $plan.velocity})
        + (if ($prev | length) > 0
           then " " + trn($strings; "summary_compare"; ($prev | length); {avg: (([$prev[].velocity] | add / length) * 10 | round / 10),
                  list: ($prev | map("\(.title): \(.velocity)") | join(", "))})
           else " " + tr($strings; "summary_no_compare") end),
      (if ($burndown.added // 0) > 0 or ($burndown.removed // 0) > 0
       then tr($strings; "summary_scope"; {added: $burndown.added, removed: $burndown.removed}) else empty end),
      "",
      "### " + tr($strings; "summary_done"),
      (if ($plan.done | length) == 0 then "- " + tr($strings; "summary_none")
       else ($plan.done[] | "- #\(.number) \(.title) (\(.points | pts))") end),
      "",
      "### " + tr($strings; "summary_carry"),
      (if ($plan.carry | length) == 0 then "- " + tr($strings; "summary_none")
       else ($plan.carry[] | "- #\(.number) \(.title) (\(.points | pts), \($cfg.statuses[.status] // .status))") end)
    ] | join("\n")) }
