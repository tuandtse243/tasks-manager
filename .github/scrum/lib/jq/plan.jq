# Plan helpers (design 2-4). Load with: include "plan";
# Every function is pure. Later steps only see the version 2 form produced by normalize.

# Version 1 (no "version": one "feature" and a flat "tasks" list) -> version 2.
# An empty sprint keeps the old meaning: the current sprint. Version 2 passes through unchanged.
def normalize:
  if type == "object" and (has("version") | not) then
    . as $p
    | { version: 2,
        title: ($p.feature.title // $p.title // null),
        sprint: (if (($p.sprint // "") | tostring) == "" then "current" else $p.sprint end),
        epic: null,
        features: [ { id: "F1",
                      title: ($p.feature.title // null),
                      body: ($p.feature.body // ""),
                      issue: ($p.feature.issue // null),
                      tasks: [ ($p.tasks // []) | to_entries[]
                               | .value + {id: (.value.id // "T\(.key + 1)"), issue: (.value.issue // null)} ] } ],
        assumptions: ($p.assumptions // []),
        out_of_scope: ($p.out_of_scope // []) }
  else . end;

def plan_features: [(.features // [])[]? | select(type == "object")];
def plan_tasks: [plan_features[] | (.tasks // [])[]? | select(type == "object")];
def task_ids: [plan_tasks[] | .id | select(type == "string")];
def deps: [(.depends_on // [])[]? | select(type == "string")];

# Input: list of tasks. Output: {id: [ids it depends on]}; a repeated id gets the union.
def dep_graph: group_by(.id) | map({key: .[0].id, value: ([.[] | deps[]] | unique)}) | from_entries;

# Input: list of tasks. Kahn's algorithm: [ordered ids, ids left over (cycles and what hangs on them)].
# Dependencies on unknown ids or on the task itself are ignored here (reported by validation).
def topo_split:
  (map(.id) | unique) as $ids
  | (dep_graph | map_values(map(select(. as $d | $ids | index($d))))) as $g
  # Each step takes the first task, in plan order, whose dependencies are all done, so the
  # order stays as close to the plan as the dependencies allow.
  | def step($done; $left):
      ([$left[] | select(. as $t | ($g[$t] // []) | map(select(. != $t)) | all(.[]; . as $d | $done | index($d))) ] | .[0]) as $next
      | if $next == null then [$done, $left]
        else step($done + [$next]; [$left[] | select(. != $next)]) end;
    step([]; [.[].id] | reduce .[] as $i ([]; if index($i) then . else . + [$i] end));

def topo_order: topo_split[0];

# Ids that lie on a cycle: of the leftovers, repeatedly drop ids no other leftover depends on.
def cycle_ids:
  . as $tasks
  | topo_split[1] as $left
  | ($tasks | dep_graph) as $g
  | def prune($s):
      [$s[] | select(. as $t | any($s[]; . != $t and (($g[.] // []) | index($t))) or (($g[$t] // []) | index($t)))] as $n
      | if ($n | length) == ($s | length) then $s else prune($n) end;
    prune($left);

# Sprint of one task: its own when the key is present (null = backlog), else the plan's.
# "" means backlog.
def task_sprint($plan): (if has("sprint") then .sprint else $plan.sprint end) // "" | tostring;

# ---------- waves, load and capacity (design 6; spec work-plan "Đợt theo phụ thuộc") ----------

# Input: a plan. {task id: wave}: wave 1 has no dependency inside the plan, each later wave
# depends only on earlier ones (1 + the latest wave it depends on). The plan has no cycle.
def plan_waves:
  plan_tasks as $ts
  | ($ts | dep_graph) as $g
  | reduce ($ts | topo_order)[] as $id ({}; . as $w | .[$id] = 1 + ([0] + [($g[$id] // [])[] | $w[.] // 0] | max));

# Does a task of $plan go into the open sprint titled $title (null: no open sprint)?
def in_open_sprint($plan; $title):
  task_sprint($plan) as $s
  | $title != null and (($s | ascii_downcase) == "current" or ($s | ascii_downcase) == ($title | ascii_downcase));

def plan_login_key: ltrimstr("@") | ascii_downcase;

# Input: a plan. Load of each person in the open sprint (spec work-plan "Tải và capacity khi
# kiểm tra plan"): the points they have in it now ($sprint_tasks: report_tasks of the sprint's
# issues) plus the points of the plan's new tasks assigned to them in it, against their capacity.
# $members: [{login, capacity}] (the team); people of either side who are not in it are added
# with in_team false. $title: the open sprint's title, or null.
# Output: [{login, capacity, in_team, current, adding, total, over, tasks: [ids]}]
def plan_load($members; $sprint_tasks; $title):
  . as $plan
  | [plan_tasks[] | select(.issue == null and in_open_sprint($plan; $title))] as $new
  | ([$members[].login] + [$sprint_tasks[]._who[]] + [$new[] | (.assignees // [])[]]
     | map(ltrimstr("@")) | reduce .[] as $l ([]; if any(.[]; plan_login_key == ($l | plan_login_key)) then . else . + [$l] end)) as $people
  | [$people[] as $p | ($p | plan_login_key) as $k
     | ([$members[] | select((.login | plan_login_key) == $k)] | .[0]) as $m
     | ([$sprint_tasks[] | select(any(._who[]; plan_login_key == $k)) | ._pts // 0] | add // 0) as $cur
     | [$new[] | select(any((.assignees // [])[]; plan_login_key == $k))] as $mine
     | ([$mine[].points // 0] | add // 0) as $add
     | { login: ($m.login // $p), capacity: ($m.capacity // null), in_team: ($m != null),
         current: $cur, adding: $add, total: ($cur + $add),
         over: ($m.capacity != null and ($cur + $add) > $m.capacity),
         tasks: [$mine[].id] } ];

# Input: a plan. What fits in the open sprint (design 6): the plan's new tasks that are not
# named for another sprint, by wave then plan order, adding points to $planned (already in the sprint).
# A task that would pass $capacity, or that depends on a task left for the backlog, should stay
# in the backlog. A task the plan names for this very sprint ("sprint": "Sprint 2", not "current"
# or empty) is the user's choice: it always fits, counts first and is never suggested out
# (plan-insights warns about it instead). Unknown capacity (null) leaves every task in. No open sprint ($title null):
# every task stays in the backlog. Suggestions only: the plan is not changed.
# Output: {capacity, planned, into, after, tasks: [{id, points, wave, fit: "sprint"|"backlog", reason}]}
# reason: null | "over_capacity" | "depends_on_backlog" | "no_sprint"
def plan_fit($capacity; $planned; $title):
  . as $plan
  | plan_waves as $w
  | [plan_tasks | to_entries[] | .key as $i | .value | select(.issue == null)
     | select(task_sprint($plan) as $s | $s == "" or ($s | ascii_downcase) == "current"
              or ($title != null and ($s | ascii_downcase) == ($title | ascii_downcase)))
     | {id, points: (.points // null), deps: deps, wave: $w[.id], order: $i,
        explicit: (task_sprint($plan) as $s | $s != "" and ($s | ascii_downcase) != "current")}]
  | sort_by(.wave, .order) | map(del(.order))
  | reduce .[] as $t ({sum: ($planned + ([.[] | select(.explicit) | .points // 0] | add // 0)), out: [], tasks: []};
      . as $st
      | if $t.explicit then .tasks += [$t + {fit: "sprint", reason: null}] else
      (if $title == null then "no_sprint"
       elif any($t.deps[]; . as $d | $st.out | index($d) != null) then "depends_on_backlog"
       elif $capacity != null and ($st.sum + ($t.points // 0)) > $capacity then "over_capacity"
       else null end) as $why
      | if $why == null then .sum += ($t.points // 0) | .tasks += [$t + {fit: "sprint", reason: null}]
        else .out += [$t.id] | .tasks += [$t + {fit: "backlog", reason: $why}] end end)
  | { capacity: $capacity, planned: $planned, into: (.sum - $planned), after: .sum,
      tasks: [.tasks[] | del(.deps, .explicit)] };
