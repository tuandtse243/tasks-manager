# Filling a sprint from the backlog (spec: sprint-lifecycle "Sức chứa của sprint", "Đưa task từ
# backlog vào sprint"). -n --argjson ms MILESTONES --argjson sprint MILESTONE --argjson issues
# SPRINT_ISSUES --argjson backlog BACKLOG (backlog.jq) --argjson add [NUMBERS] --argjson capacity N|null
# --argjson cfg CONFIG
# Output: {sprint, velocity: {average, sprints}, capacity, capacity_source, planned, free,
#          adding: {tasks, points}, after, errors, warnings}
include "scrum";

($ms | recent_velocity_sprints) as $recent
| (if ($recent | length) > 0 then ([$recent[].velocity] | add / length | floor) else null end) as $avg
| (if $capacity != null then $capacity else $avg end) as $cap
| ($issues | report_tasks($cfg)) as $in
| ([$in[]._pts // 0] | add // 0) as $planned
| ([$in[] | select(._role != "done") | .number]) as $open_in_sprint
| ($backlog.tasks | map({key: (.number | tostring), value: .}) | from_entries) as $bl
| [$add[] | select($bl[tostring] == null)] as $unknown
| [$add[] | $bl[tostring] | select(. != null)] as $adding
| ([$adding[].points // 0] | add // 0) as $add_pts
| { sprint: ($sprint | sprint_info | {number, title, start, end}),
    velocity: {average: $avg, sprints: [$recent[] | {title, velocity}]},
    capacity: $cap,
    capacity_source: (if $capacity != null then "option" elif $avg != null then "velocity" else null end),
    planned: $planned,
    free: (if $cap == null then null else $cap - $planned end),
    adding: {tasks: $adding, points: $add_pts},
    after: ($planned + $add_pts),
    errors: [$unknown[] | "#\(.) is not an open task in the backlog (it may be closed, already in a sprint, a feature or epic, or not exist)"],
    warnings: [
      (if $cap != null and ($add | length) > 0 and ($planned + $add_pts) > $cap
       then "over capacity by \($planned + $add_pts - $cap) point\(if $planned + $add_pts - $cap == 1 then "" else "s" end) (capacity \($cap), planned \($planned), adding \($add_pts))"
       else empty end),
      ($adding[] | select(.points == null) | "#\(.number) has no points; estimate it with: scrum task estimate \(.number) POINTS"),
      ($adding[] | . as $t
       | if .blocked_by == null then "#\(.number): its blockers were not checked"
         else (.blocked_by - $add - $open_in_sprint) as $out
         | if ($out | length) > 0 then "#\(.number) is blocked by \($out | map("#\(.)") | join(", ")), not in \($sprint.title)" else empty end
         end) ] }
