# Changes since the last generated view of the same plan folder (design 9; spec work-plan
# "Thay đổi so với lần xem trước"). Pure.
# Input: a plan in version 2 form. --argjson prev SNAPSHOT|null (.plan-snapshot.json of the last view)
# Output: {revision, first, added: [{id, title}], removed: [{id, title}],
#          changed: [{id, title, fields: [{field, from, to}]}], snapshot}
# first: no earlier view (no changes are listed). The revision goes up by one only when something
# changed. Issue numbers are not compared, so recording them (plan apply) is not a change.
include "plan";

. as $plan
| { revision: null,
    tasks: [plan_tasks[] | { id, title,
                             points: (.points // null),
                             depends_on: (deps | unique),
                             assignees: ([(.assignees // [])[] | ltrimstr("@")] | sort),
                             sprint: (task_sprint($plan) | if . == "" then null else . end) }] } as $now
| if $prev == null or ($prev.tasks | type) != "array" then
    { revision: 1, first: true, added: [], removed: [], changed: [], snapshot: ($now | .revision = 1) }
  else
    ([$prev.tasks[] | {key: .id, value: .}] | from_entries) as $old
    | ([$now.tasks[] | {key: .id, value: .}] | from_entries) as $new
    | [$now.tasks[] | select($old[.id] == null) | {id, title}] as $added
    | [$prev.tasks[] | select($new[.id] == null) | {id, title}] as $removed
    | [$now.tasks[] | . as $t | $old[$t.id] as $o | select($o != null)
       | [ ("title", "points", "depends_on", "assignees", "sprint") as $f
           | select(($o[$f] // null) != ($t[$f] // null))
           | {field: $f, from: ($o[$f] // null), to: ($t[$f] // null)} ] as $fields
       | select(($fields | length) > 0)
       | {id: $t.id, title: $t.title, fields: $fields}] as $changed
    | (($prev.revision // 1) + (if ($added + $removed + $changed | length) > 0 then 1 else 0 end)) as $rev
    | { revision: $rev, first: false, added: $added, removed: $removed, changed: $changed,
        snapshot: ($now | .revision = $rev) }
  end
