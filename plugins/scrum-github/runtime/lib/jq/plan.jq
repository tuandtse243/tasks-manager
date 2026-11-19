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
