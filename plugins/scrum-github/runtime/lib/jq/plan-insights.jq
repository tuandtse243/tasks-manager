# Waves, load and capacity of a plan for `plan check` and plan.html (design 6). Pure: no network.
# Input: a valid plan in version 2 form.
# --argjson cfg CONFIG --arg today DATE
# --argjson online true|false   (false: --offline, or GitHub could not be read)
# --argjson team {source, members} | null   (team_list; null offline)
# --argjson ms [milestones] | null           (null offline)
# --argjson sprint_issues [issues of the open sprint]
# [--arg reason offline|unreadable]   why it is not online (default offline)
# Output: {online, unreadable, waves: {id: n}, wave_list: [[ids]], team, sprint, velocity: {average, sprints},
#          capacity, planned, adding, after, over_sprint, load, fit, unknown_logins, warnings}
include "scrum";
include "plan";

. as $plan
| plan_waves as $waves
| ([$waves | to_entries[] | .value] | max // 0) as $nw
| [range(1; $nw + 1) as $n | [plan_tasks[] | select($waves[.id] == $n) | .id]
   | reduce .[] as $i ([]; if index($i) then . else . + [$i] end)] as $wave_list
| ([plan_tasks[] | (.assignees // [])[]] | map(ltrimstr("@")) | unique) as $assigned
| unknown_logins($cfg; $assigned) as $unknown
| ($cfg.team // [] | map(.login) | join(", ")) as $team_text
| if ($online | not) or $ms == null then
    { online: false, unreadable: (($ARGS.named.reason // "offline") == "unreadable"), waves: $waves, wave_list: $wave_list, team: null, sprint: null,
      velocity: null, capacity: null, planned: null, adding: null, after: null, over_sprint: false,
      load: null, fit: null, unknown_logins: $unknown,
      warnings: [$unknown[] | "\(.) is not in the team (\($team_text))"] }
  else
    ($ms | current_sprint($today)) as $open
    | (if $open == null then null else ($open | sprint_info | {number, title, start, end}) end) as $s
    | ($ms | recent_velocity_sprints) as $recent
    | (if ($recent | length) > 0 then ([$recent[].velocity] | add / length | floor) else null end) as $avg
    | ($sprint_issues | report_tasks($cfg)) as $tasks
    | ([$tasks[]._pts // 0] | add // 0) as $planned
    | ($s.title // null) as $title
    | [plan_tasks[] | select(.issue == null and in_open_sprint($plan; $title))] as $new
    | ([$new[].points // 0] | add // 0) as $adding
    | (if $s == null then null else plan_load(($team.members // []); $tasks; $title) end) as $load
    | (if $s == null then 0 else $planned end) as $base
    | { online: true, unreadable: false, waves: $waves, wave_list: $wave_list, team: $team, sprint: $s,
        velocity: {average: $avg, sprints: [$recent[] | {title, velocity}]},
        capacity: $avg,
        planned: (if $s == null then null else $planned end),
        adding: (if $s == null then null else $adding end),
        after: (if $s == null then null else $planned + $adding end),
        over_sprint: ($s != null and $avg != null and ($planned + $adding) > $avg),
        load: $load,
        fit: plan_fit($avg; $base; $title),
        unknown_logins: $unknown,
        warnings: [
          ($unknown[] | "\(.) is not in the team (\($team_text))"),
          (if $s == null then "there is no open sprint: the plan's tasks for the current sprint cannot go anywhere but the backlog. Create one with /scrum-github:sprint-new"
           elif $avg == null then "the capacity of \($s.title) is not known yet: no closed sprint has a velocity"
           elif ($planned + $adding) > $avg then "\($s.title) would have \($planned + $adding) / \($avg) points after apply (over capacity by \($planned + $adding - $avg))"
           else empty end),
          ($load // [] | .[] | select(.over) | "@\(.login) would have \(.total) / \(.capacity) points in \($s.title) (over capacity by \(.total - .capacity))")
        ] }
  end
