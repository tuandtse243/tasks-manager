# The team and each member's load in the open sprint (spec: team "Nguồn danh sách team", "Xem team").
# -n --argjson cfg CONFIG --argjson assignees [users or logins]|null (read only when cfg.team is empty)
#    --argjson sprint MILESTONE|null (the open sprint) --argjson issues [issues of that sprint]
# Output: {source, sprint: {number, title}|null,
#          members: [{login, areas, capacity, load: {tasks, points, done_points}|null}]}
include "scrum";

team_list($cfg; $assignees) as $team
| ($issues | report_tasks($cfg)) as $tasks
| { source: $team.source,
    sprint: (if $sprint == null then null else {number: $sprint.number, title: $sprint.title} end),
    members: [$team.members[] | . + {load: (if $sprint == null then null else member_load(.login; $tasks) end)}] }
