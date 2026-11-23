# Data of plan.html (design 8; spec work-plan "Bản xem HTML"). Pure: same input, same output.
# Input: a valid plan in version 2 form.
# --argjson cfg CONFIG --argjson insights (plan-insights.jq) --argjson diff (plan-diff.jq)
# --argjson actions [plan-actions] | null (offline or not computed) --argjson action_errors [texts]
# --argjson strings (strings.json, one language) --arg now ISO --arg path (the plan folder, for the header)
# Output: every number the page shows comes from here, so it matches the plan file.
include "scrum";
include "plan";

. as $plan
| plan_tasks as $all
| ($insights.sprint.title // null) as $open
| ([plan_features | to_entries[] | {key: .value.id, value: .key}] | from_entries) as $fidx
| ([plan_features[] as $f | $f.tasks[] | {key: .id, value: $f.id}] | from_entries) as $feature_of
| ([$diff.added[].id] ) as $added
| ([$diff.changed[] | {key: .id, value: [.fields[].field]}] | from_entries) as $changed
| ([($insights.fit.tasks // [])[] | {key: .id, value: .}] | from_entries) as $fit
| def sprint_of:
    task_sprint($plan) as $s
    | if $s == "" then {kind: "backlog", label: null}
      elif ($s | ascii_downcase) == "current" then {kind: (if $open == null then "current" else "open" end), label: $open}
      elif $open != null and ($s | ascii_downcase) == ($open | ascii_downcase) then {kind: "open", label: $open}
      else {kind: "named", label: $s} end;
  [ $all[] | sprint_of as $sp | .id as $id
    | { id, feature: $feature_of[.id], feature_index: ($fidx[$feature_of[.id]] // 0),
        title, body: (.body // ""), acceptance: (.acceptance // []), subtasks: (.subtasks // []),
        points: (.points // null), depends_on: (deps | unique), assignees: [(.assignees // [])[] | ltrimstr("@")],
        bug: (.bug == true), issue: (.issue // null),
        sprint: $sp, wave: ($insights.waves[.id] // 1),
        change: (if ($added | index($id)) != null then "added" elif $changed[$id] != null then "changed" else null end),
        changed_fields: ($changed[.id] // []),
        fit: ($fit[.id] // null) } ] as $tasks
| [$tasks[] | select(.sprint.kind == "open")] as $into
| [$tasks[] | select(.sprint.kind == "backlog")] as $backlog
| ($actions // []) as $acts
| def count($op): [$acts[] | select(.op == $op)] | length;
  [$tasks[] | select(.issue == null)] as $new
| { title: $plan.title,
    language: ($cfg.language // "en"),
    path: $path,
    generated_at: $now,
    strings: $strings,
    applied: (($all | length) > 0 and all($all[]; .issue != null)),
    epic: (if $plan.epic == null then null else {title: $plan.epic.title, issue: ($plan.epic.issue // null)} end),
    features: [plan_features | to_entries[] | {id: .value.id, title: .value.title, index: .key, issue: (.value.issue // null)}],
    tasks: $tasks,
    waves: ($insights.wave_list // []),
    summary: { tasks: ($tasks | length),
               points: ([$tasks[].points // 0] | add // 0),
               unestimated: ([$tasks[] | select(.points == null)] | length),
               into: ($into | length), into_points: ([$into[].points // 0] | add // 0),
               backlog: ($backlog | length),
               waves: (($insights.wave_list // []) | length) },
    diff: {first: $diff.first, revision: $diff.revision, previous: (if $diff.first then null else $diff.revision - (if ($diff.added + $diff.removed + $diff.changed | length) > 0 then 1 else 0 end) end),
           added: $diff.added, removed: $diff.removed, changed: $diff.changed},
    load: { online: $insights.online, sprint: $insights.sprint, capacity: $insights.capacity,
            planned: $insights.planned, adding: $insights.adding, after: $insights.after, over_sprint: $insights.over_sprint,
            team_source: ($insights.team.source // null), people: ($insights.load // []),
            fit: $insights.fit,
            into_tasks: [$into[] | {id, points, feature_index}],
            backlog_tasks: [$backlog[] | select(.issue == null) | {id, points, reason: (.fit.reason // null)}] },
    review: ($plan.review // []),
    actions: (if $actions == null then null
              else { errors: $action_errors,
                     epic: count("create_epic"), features: count("create_feature"), tasks: count("create_task"),
                     link_sub: count("link_sub"), link_blocked: count("link_blocked"),
                     existing: (count("skip") + count("update")),
                     into: ([$new[] | select(.sprint.kind == "open" or .sprint.kind == "named")] | length),
                     backlog: ([$new[] | select(.sprint.kind == "backlog")] | length),
                     assigned: ([$new[] | select((.assignees | length) > 0)] | length),
                     people: ([$new[].assignees[] | ascii_downcase] | unique | length),
                     lines: [$acts[].text] } end),
    assumptions: ($plan.assumptions // []),
    out_of_scope: ($plan.out_of_scope // []),
    warnings: ($insights.warnings // []) }
