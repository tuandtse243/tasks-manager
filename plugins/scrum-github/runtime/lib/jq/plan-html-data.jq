# Data of plan.html (design 8; spec work-plan "Bản xem HTML"). Pure: same input, same output.
# Input: a valid plan in version 2 form.
# --argjson cfg CONFIG --argjson insights (plan-insights.jq) --argjson diff (plan-diff.jq)
# --argjson actions [plan-actions] | null (offline or not computed) --argjson action_errors [texts]
# --argjson strings (strings.json, one language) --arg now ISO --arg path (the plan folder, for the header)
# [--argjson done true]  the actions were just carried out by plan apply (the page says "created")
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
        fit: ($fit[.id] // null),
        estimate: (.estimate | clean_estimate) } ] as $tasks
# Time (spec work-plan "Thời gian trong bản xem", "Dòng thời gian trong plan.html"): minutes only;
# plan-html.jq turns them into the to-scale timeline. null when no task has an estimate.
| ($cfg.planning.merge_minutes // 5) as $merge
| ( if all($tasks[]; .estimate == null) then null
    else ($tasks | eta_by_waves($merge)) as $eta
      | ($tasks | estimate_totals) as $sum
      | ($eta.waves | reduce .[] as $w ({at: 0, list: []}; .list += [$w + {start: .at}] | .at += $w.work + $merge) | .list) as $wl
      | ([$wl[] | {key: (.wave | tostring), value: .start}] | from_entries) as $start
      | { merge: $merge,
          work: $eta.work_minutes, review: $eta.review_minutes, total: ($eta.work_minutes + $eta.review_minutes),
          sum_work: $sum.work_minutes, sum_review: $sum.review_minutes,
          estimated: $sum.estimated, missing: $sum.missing,
          missing_ids: [$tasks[] | select(.estimate == null) | .id],
          humans: any($tasks[]; .estimate.by == "human"),
          waves: $wl,
          # Only tasks with a work time get a bar; a review-only task adds to the review bar alone.
          rows: [$tasks | to_entries | sort_by(.value.wave, .key)[] | .value | select(.estimate.work_minutes != null)
                 | {id, title, wave, start: $start[.wave | tostring], work: (.estimate.work_minutes // 0),
                    review: (.estimate.review_minutes // 0), by: .estimate.by}] }
    end ) as $time
| [$tasks[] | select(.sprint.kind == "open")] as $into
| [$tasks[] | select(.sprint.kind == "backlog")] as $backlog
| ($actions // []) as $acts
| def count($op): [$acts[] | select(.op == $op)] | length;
  ($ARGS.named.done // false) as $done
| ([$acts[] | select(.op == "create_task") | .ref]) as $created
# The tasks the actions are about: the new ones, or after apply the ones it created.
| [$tasks[] | if $done then (.id as $i | select($created | index($i))) else select(.issue == null) end] as $new
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
    time: $time,
    diff: {first: $diff.first, revision: $diff.revision, previous: (if $diff.first then null else $diff.revision - (if ($diff.added + $diff.removed + $diff.changed | length) > 0 then 1 else 0 end) end),
           added: $diff.added, removed: $diff.removed, changed: $diff.changed},
    load: { online: $insights.online, sprint: $insights.sprint, capacity: $insights.capacity,
            planned: $insights.planned, adding: $insights.adding, after: $insights.after, over_sprint: $insights.over_sprint,
            team_source: ($insights.team.source // null), people: ($insights.load // []),
            fit: $insights.fit,
            unreadable: ($insights.unreadable // false),
            into_tasks: [$into[] | select(.issue == null) | {id, points, feature_index}],
            backlog_tasks: [$backlog[] | select(.issue == null) | {id, points, reason: (.fit.reason // null)}] },
    review: ($plan.review // []),
    actions: (if $actions == null then null
              else { errors: $action_errors, done: $done,
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
