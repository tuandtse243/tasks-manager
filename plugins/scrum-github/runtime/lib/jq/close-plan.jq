# -n --argjson ms MILESTONES --argjson cfg CONFIG --argjson sprint MILESTONE --argjson issues ISSUES --arg today DATE
# Plan for closing a sprint: velocity, done tasks, tasks to carry over, the next sprint, new description.
include "scrum";
($sprint | sprint_info) as $s
| [$issues[] | select(is_task($cfg))] as $tasks
| [$tasks[] | select(is_completed)] as $done
| ([$done[] | task_points($cfg) // 0] | add // 0) as $velocity
| ($ms | map(sprint_info)) as $all
| ([$all[] | select(.state == "open" and .number != $s.number and .start != null and .start > ($s.start // ""))]
   | sort_by(.start) | .[0]) as $next
| ((($s.end // $today) | add_days(1))) as $nstart
| { sprint: {number: $s.number, title: $s.title, start: $s.start, end: $s.end},
    already_closed: ($s.state == "closed"),
    velocity: $velocity,
    done: [$done[] | {number, title, points: task_points($cfg)}],
    unestimated_done: [$done[] | select(task_points($cfg) == null) | .number],
    dropped: [$tasks[] | select(is_not_planned) | .number],
    carry: [$tasks[] | select(.state == "open") | {number, title, points: task_points($cfg), status: task_role($cfg)}],
    next: (if $next then {exists: true, number: $next.number, title: $next.title}
           else {exists: false,
                 title: sprint_title($cfg.sprint.name_pattern; ($ms | max_sprint_number($cfg)) + 1),
                 start: $nstart,
                 end: ($nstart | add_days($cfg.sprint.length_days - 1))} end),
    description: (
      ($s.description
       | gsub("\n*\\*\\*Velocity:\\*\\*[^\n]*"; "")
       | gsub("\n*<!-- scrum:velocity=[0-9]+ -->"; ""))
      + "\n\n**Velocity:** \($velocity) points\n<!-- scrum:velocity=\($velocity) -->") }
