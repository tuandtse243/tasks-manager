# Tasks to list (spec: task-management "Liệt kê task"). Input: issues.
# --argjson cfg CONFIG --arg me LOGIN_OR_EMPTY --arg status new|in_progress|in_review|done|""
# Output: [{number, title, role, status, points, assignees}] by number.
include "scrum";

[ report_tasks($cfg)[]
  | select($me == "" or (._who | index($me)))
  | select($status == "" or ._role == $status)
  | {number, title, role: ._role, status: $cfg.statuses[._role], points: ._pts, assignees: ._who} ]
| sort_by(.number)
