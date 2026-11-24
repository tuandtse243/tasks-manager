# Input: a plan in version 2 form (run plan-normalize first). --argjson cfg CONFIG.
# Output: array of every error found (empty when valid). Never stops at the first error.
include "plan";

def name_of($x): if ($x.id | type) == "string" then $x.id else "\"\($x.title // "?")\"" end;
def nonempty: type == "string" and (gsub("^\\s+|\\s+$"; "") | length) > 0;
def str_list: type == "array" and all(.[]; type == "string");
def issue_ok: . == null or (type == "number" and . == floor and . > 0);
def sprint_ok: . == null or type == "string";

. as $p
| if type != "object" then ["the plan must be a JSON object"] else
  ($cfg.points.scale | map(tostring) | join(", ")) as $allowed
  | plan_tasks as $tasks
  | [ (if $p.version != 2 then "version: must be 2 (got \($p.version | tojson))" else empty end),
      (if ($p.title | nonempty) then empty else "title is required" end),
      (if ($p.sprint | sprint_ok) then empty else "sprint: must be a sprint name, \"current\", or empty for the backlog" end),
      (if ($p.assumptions // [] | str_list) then empty else "assumptions: must be a list of texts" end),
      (if ($p.out_of_scope // [] | str_list) then empty else "out_of_scope: must be a list of texts" end),
      # review (optional, from plan-critic; plan apply ignores it)
      (if $p.review == null then empty
       elif ($p.review | type) != "array" then "review: must be a list of findings"
       else ($p.review | to_entries[] | .key as $i | .value as $r
             | if ($r | type) != "object" then "review[\($i)]: must be an object with kind, text and status"
               else (if ($r.kind | nonempty) then empty else "review[\($i)].kind is required" end),
                    (if ($r.text | nonempty) then empty else "review[\($i)].text is required" end),
                    (if $r.status == "fixed" or $r.status == "kept" then empty else "review[\($i)].status: must be fixed or kept (got \($r.status | tojson))" end)
               end)
       end),

      # epic (optional)
      (if $p.epic == null then empty
       elif ($p.epic | type) != "object" then "epic: must be an object with a title, or null"
       else (if ($p.epic.title | nonempty) then empty else "epic.title is required when there is an epic" end),
            (if ($p.epic.issue | issue_ok) then empty else "epic.issue: must be an issue number or null" end)
       end),

      # features
      (if ($p.features | type) != "array" or ($p.features | length) == 0 then "features must be a non-empty list"
       else
         ($p.features | to_entries[] | .key as $i | .value as $f
          | if ($f | type) != "object" then "features[\($i)]: must be an object"
            else
              (if ($f.id | nonempty) then empty else "feature \(name_of($f)): id is required" end),
              (if ($f.title | nonempty) then empty else "feature \(name_of($f)): title is required" end),
              (if ($f.issue | issue_ok) then empty else "feature \(name_of($f)): issue must be an issue number or null" end),
              (if ($f.tasks | type) != "array" or ($f.tasks | length) == 0 then "feature \(name_of($f)): tasks must be a non-empty list" else empty end)
            end)
       end),

      # tasks
      ($tasks[] as $t
       | (if ($t.id | nonempty) then empty else "task \(name_of($t)): id is required" end),
         (if ($t.title | nonempty) then empty else "task \(name_of($t)): title is required" end),
         (if $t.points == null or ($cfg.points.scale | any(.[]; . == $t.points)) then empty
          else "task \(name_of($t)): \($t.points | tojson) is not an allowed point value (allowed: \($allowed))" end),
         (if ($t.issue | issue_ok) then empty else "task \(name_of($t)): issue must be an issue number or null" end),
         (if ($t.sprint | sprint_ok) then empty else "task \(name_of($t)): sprint must be a sprint name, \"current\", or null" end),
         (["acceptance", "subtasks", "assignees", "depends_on"][] as $k
          | if ($t[$k] // [] | str_list) then empty else "task \(name_of($t)): \($k) must be a list of texts" end),
         (if $t.bug == null or ($t.bug | type) == "boolean" then empty else "task \(name_of($t)): bug must be true or false" end),
         (if $t.ai_ready == null or ($t.ai_ready | type) == "boolean" then empty
          else "task \(name_of($t)): ai_ready must be true or false (got \($t.ai_ready | tojson))" end),
         # estimate (optional; spec work-plan "Ước lượng thời gian trong plan")
         (if $t.estimate == null then empty
          elif ($t.estimate | type) != "object" then "task \(name_of($t)): estimate must be an object with work_minutes, review_minutes and by"
          else (["work_minutes", "review_minutes"][] as $k | $t.estimate[$k] as $v
                | if ($v | type) == "number" and $v == ($v | floor) and $v > 0 then empty
                  else "task \(name_of($t)): estimate.\($k) must be a whole number of minutes greater than 0 (got \($v | tojson))" end),
               (if $t.estimate.by == null or $t.estimate.by == "ai" or $t.estimate.by == "human" then empty
                else "task \(name_of($t)): estimate.by must be ai or human (got \($t.estimate.by | tojson))" end)
          end)),

      # ids unique across epic-less plan: features and tasks share one namespace
      ([plan_features[].id, $tasks[].id] | map(select(type == "string")) | group_by(.) | map(select(length > 1) | .[0])[]
       | "id \(. | tojson) is used more than once"),

      # dependencies
      (task_ids as $ids
       | $tasks[] as $t | ($t | deps)[] as $d
       | if $d == $t.id then "task \($t.id) depends on itself"
         elif ($ids | index($d)) == null then "task \($t.id) depends on \($d), which is not a task of this plan"
         else empty end),
      ([$tasks[] | select((.id | type) == "string")] | cycle_ids
       | if length > 0 then "dependency cycle between \(join(", "))" else empty end)
    ]
  end
