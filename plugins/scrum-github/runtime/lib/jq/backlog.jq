# The backlog (spec: backlog). Input: open issues without a milestone.
# --argjson cfg CONFIG --argjson blocked {"NUMBER": [open blocking numbers] | null (not checked)}
# Output: {tasks: [{number, title, points, assignees, parent, blocked_by, estimate}], total, points, unestimated}
# estimate: the time estimate of the issue (spec time-estimate), or null.
include "scrum";

[ .[] | select(.state == "open" and .milestone == null and is_task($cfg))
  | { number, title,
      points: task_points($cfg),
      assignees: assignee_logins,
      parent: ([(.body // "") | capture("Part of #(?<n>[0-9]+)")] | .[0].n | if . then tonumber else null end),
      blocked_by: ((.number | tostring) as $k | if $blocked | has($k) then $blocked[$k] else null end),
      estimate: issue_estimate } ]
| sort_by(.number)
| { tasks: .,
    total: length,
    points: ([.[].points // 0] | add // 0),
    unestimated: ([.[] | select(.points == null)] | length) }
