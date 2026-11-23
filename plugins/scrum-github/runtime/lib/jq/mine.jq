# One person's work (spec my-work, design 5). Pure: no network.
# -n --argjson cfg CONFIG --arg login LOGIN
#    --argjson issues [open issues assigned to LOGIN, any milestone; PRs and features are dropped here]
#    --argjson ms [milestones] --argjson sprint MILESTONE|null (the open sprint)
#    --argjson blocked {"N": [open blocking numbers] | null (not read)}; numbers missing = not checked
#    --argjson prs [search items of pull requests waiting for LOGIN's review] | null (not read)
# Output: {login, sprint: {number, title}|null, total: {tasks, points},
#          groups: [{key: in_progress|in_review|current|sprint|backlog, title, sprint, tasks: [task]}],
#          next: {number, title, action: "continue"|"start"}|null, order: [numbers],
#          reviews: [{number, title, author, url}]|null,
#          time: {tasks, estimated, missing, missing_numbers, work_minutes, review_minutes, waves}|null}
# task: {number, title, points, status, role, sprint, blocked_by: [numbers]|null, estimate|null}
# time (spec my-work "Thời gian trong việc của một người"): the open tasks in the open sprint;
# work by waves of the blocking graph between them, like the plan view; null without them.
include "scrum";

([$ms[]? | {key: (.number | tostring), value: sprint_info}] | from_entries) as $msinfo
| ($sprint.number // null) as $cur
| [ $issues[] | select(.state == "open" and is_task($cfg))
    | task_role($cfg) as $role
    | { number, title,
        points: task_points($cfg),
        role: $role,
        status: ($cfg.statuses[$role] // $role),
        milestone: (.milestone.number // null),
        sprint: (.milestone.title // null),
        due: (if .milestone == null then null
              else ($msinfo[.milestone.number | tostring].end // (.milestone.due_on // "" | .[0:10]) | if . == "" then null else . end) end),
        blocked_by: ((.number | tostring) as $k | if $blocked | has($k) then $blocked[$k] else null end),
        estimate: issue_estimate } ]
| sort_by(.number) as $tasks

# groups, in the order of the spec
| [$tasks[] | select(.role == "in_progress")] as $prog
| [$tasks[] | select(.role == "in_review")] as $rev
| [$tasks[] | select(.role != "in_progress" and .role != "in_review")] as $rest
| [$rest[] | select($cur != null and .milestone == $cur and .role == "new")] as $current
# open tasks of the open sprint labelled Done are listed under that sprint with the other sprints
| [$rest[] | select(.milestone != null and (.milestone != $cur or .role != "new"))] as $others
| [$rest[] | select(.milestone == null)] as $backlog
| ($others | group_by(.milestone) | sort_by(.[0].due // "9999-12-31", .[0].sprint)) as $by_sprint
| def clean: map(del(.milestone, .due));
  [ (if ($prog | length) > 0 then {key: "in_progress", title: $cfg.statuses.in_progress, sprint: null, tasks: ($prog | clean)} else empty end),
    (if ($rev | length) > 0 then {key: "in_review", title: $cfg.statuses.in_review, sprint: null, tasks: ($rev | clean)} else empty end),
    (if ($current | length) > 0 then {key: "current", title: "\($cfg.statuses.new) in \($sprint.title)", sprint: $sprint.title, tasks: ($current | clean)} else empty end),
    ($by_sprint[] | {key: "sprint", title: .[0].sprint, sprint: .[0].sprint, tasks: clean}),
    (if ($backlog | length) > 0 then {key: "backlog", title: "Backlog", sprint: null, tasks: ($backlog | clean)} else empty end)
  ] as $groups

# what to do next: a task In progress, else a New task of the open sprint that no open task
# blocks, earliest wave of the blocking graph between these tasks, then lowest number
| [$current[] | select(.role == "new")] as $todo
| ([$todo[].number]) as $set
| ([$todo[] | {number,
               deps: [(.blocked_by // [])[] | select(. as $b | $set | index($b))],
               outside: any((.blocked_by // [])[]; . as $b | ($set | index($b)) == null)}]) as $items
| (reduce range(0; ($items | length) + 1) as $_
     ([$items[] | {key: (.number | tostring), value: 1}] | from_entries;
     . as $w
     | reduce $items[] as $t (.;
         .[$t.number | tostring] = 1 + ([0] + [$t.deps[] | $w[tostring]] + (if $t.outside then [1] else [] end) | max)))
  ) as $wave
| ($todo | sort_by($wave[.number | tostring], .number)) as $ordered

# time left in the open sprint: waves of the blocking graph between the open tasks there
| [$tasks[] | select($cur != null and .milestone == $cur and .role != "done")] as $left
| ([$left[].number]) as $lset
| ([$left[] | {number, deps: [(.blocked_by // [])[] | select(. as $b | $lset | index($b))]}]) as $litems
| (reduce range(0; ($litems | length) + 1) as $_
     ([$litems[] | {key: (.number | tostring), value: 1}] | from_entries;
     . as $w
     | reduce $litems[] as $t (.; .[$t.number | tostring] = 1 + ([0] + [$t.deps[] | $w[tostring]] | max)))
  ) as $lwave
| ( if ($left | length) == 0 then null
    else ([$left[] | {wave: $lwave[.number | tostring], estimate}] | eta_by_waves($cfg.planning.merge_minutes // 5)) as $eta
      | { tasks: ($left | length), estimated: $eta.estimated,
          missing: (($left | length) - $eta.estimated),
          missing_numbers: [$left[] | select(.estimate == null) | .number],
          work_minutes: $eta.work_minutes, review_minutes: $eta.review_minutes,
          waves: ($eta.waves | length) }
    end ) as $time
| ( if ($prog | length) > 0 then ($prog[0] | {number, title, action: "continue"})
    else ([$ordered[] | select(.blocked_by == [])] | .[0] | if . == null then null else {number, title, action: "start"} end)
    end ) as $next
| { login: $login,
    sprint: (if $sprint == null then null else {number: $sprint.number, title: $sprint.title} end),
    total: {tasks: ($tasks | length), points: ([$tasks[].points // 0] | add // 0)},
    groups: $groups,
    next: $next,
    order: [$ordered[].number],
    reviews: (if $prs == null then null
              else [$prs[] | {number, title, author: (.user.login // null), url: (.html_url // null)}] | sort_by(.number) end),
    time: $time }
