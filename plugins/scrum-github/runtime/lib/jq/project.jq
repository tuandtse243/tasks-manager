# Pure functions for the GitHub Projects (v2) board sync. Load with: include "project";
include "scrum";

def roles: ["new", "in_progress", "done"];
def is_role: . as $r | roles | index($r) != null;

# Built-in project workflows that change Status on their own. They would move cards without
# updating the "Synced status" field, so the next sync would copy their change onto the label.
def conflicting_workflows:
  ["Item added to project", "Item closed", "Item reopened", "Pull request linked to issue", "Pull request merged"];

# Board option name -> role, or null.
def option_role($cfg; $name):
  [$cfg.project.status_options | to_entries[] | select(.value == $name) | .key] | .[0];

# ---------- project metadata ----------
# Input: response of share/graphql/project.graphql.
# Output: {found, id, title, url, status_field, options {role: id}, synced_field, points_field,
#          missing_options, missing_fields, wrong_types, conflicts}
def project_meta($cfg):
  (.data.repositoryOwner.projectV2 // null) as $p
  | if $p == null then {found: false}
    else
      ($cfg.project) as $c
      | [$p.fields.nodes[]? | select(.id != null)] as $fields
      | def field($name): [$fields[] | select(.name == $name)] | .[0];
      field($c.status_field) as $sf
      | field($c.synced_field) as $yf
      | (if $c.points_field == null then null else field($c.points_field) end) as $pf
      | {found: true, id: $p.id, title: $p.title, url: $p.url,
         status_field: (if $sf then $sf.id else null end),
         options: (if $sf then
                     reduce roles[] as $r ({}; . + {($r): ([$sf.options[]? | select(.name == $c.status_options[$r]) | .id] | .[0])})
                   else {} end),
         synced_field: (if $yf and $yf.dataType == "TEXT" then $yf.id else null end),
         points_field: (if $pf and $pf.dataType == "NUMBER" then $pf.id else null end),
         missing_options: (if $sf then [roles[] as $r | $c.status_options[$r] as $o
                                          | select(([$sf.options[]?.name] | index($o)) == null) | $o]
                           else [] end),
         missing_fields: ([
           (if $yf == null then {name: $c.synced_field, type: "TEXT"} else empty end),
           (if $c.points_field != null and $pf == null then {name: $c.points_field, type: "NUMBER"} else empty end)]),
         wrong_types: ([
           (if $sf and $sf.dataType != "SINGLE_SELECT" then "\($c.status_field) must be a single select field" else empty end),
           (if $yf and $yf.dataType != "TEXT" then "\($c.synced_field) must be a text field" else empty end),
           (if $pf and $pf.dataType != "NUMBER" then "\($c.points_field) must be a number field" else empty end)]),
         conflicts: [$p.workflows.nodes[]? | select(.enabled == true) | .name
                     | select(. as $n | conflicting_workflows | index($n) != null)]}
    end;

# ---------- items ----------
# One raw item (items.graphql / issue-item.graphql shape, with .content = the issue)
# -> the issue in the REST shape the rest of the plugin understands, plus board fields.
def normalize_item:
  .content as $i
  | {item_id: .id,
     node_id: $i.id,
     number: $i.number,
     repo: $i.repository.nameWithOwner,
     state: ($i.state | ascii_downcase),
     state_reason: (($i.stateReason // null) | if . == null then null else ascii_downcase end
                    | if . == "reopened" then null else . end),
     labels: [$i.labels.nodes[]? | {name}],
     milestone: $i.milestone,
     board: (.status.name // null),
     synced: (.synced.text // null),
     points: (.points.number // null)};

# Input: raw items. Keeps the issues of $repo; drops pull requests, drafts and redacted items.
def project_items($repo):
  [.[] | select(.type == "ISSUE" and .content != null and .content.number != null)
   | select((.content.repository.nameWithOwner | ascii_downcase) == ($repo | ascii_downcase))
   | normalize_item];

# ---------- sync plan ----------
def status_name($cfg; $role): $cfg.statuses[$role];

# Plan for one normalized item. Output: {ops: [...], warnings: [...]}
# L = status from the label (or closed state), B = board column, S = "Synced status".
def plan_item($cfg; $meta):
  . as $it
  | ($it | task_role($cfg)) as $L
  | ($it.board) as $board
  | (if $board == null then null else option_role($cfg; $board) end) as $B
  | ($it.synced | if . != null and is_role then . else null end) as $S
  | "#\($it.number)" as $n
  | ( if ($it | is_task($cfg)) | not then {ops: [], warnings: []}
      elif $L == "dropped" then {ops: [], warnings: []}
      elif $board != null and $B == null then
        {ops: [], warnings: ["\($n) is in the board column \"\($board)\", which is not one of \($cfg.project.status_options | [.new, .in_progress, .done] | map("\"\(.)\"") | join(", ")); its status was left as it is"]}
      else
        ($B // $S) as $Beff
        | (if $S == null then $L
           elif $Beff == $S then $L
           elif $L == $S then $Beff
           else $L end) as $R
        | ($S != null and $Beff != $S and $L != $S and $L != $Beff) as $conflict
        | {warnings: [],
           ops: [
             (if $L != $R then
                {op: "set_labels", number: $it.number, labels: ($it | labels_with_status($cfg; $R)),
                 msg: "\($n): status set to \(status_name($cfg; $R)) (moved on the board)"},
                (if $R == "done" and $it.state == "open" then
                   {op: "close", number: $it.number, msg: "\($n): closed as completed (moved to \($cfg.project.status_options.done) on the board)"}
                 elif $R != "done" and $it.state == "closed" then
                   {op: "reopen", number: $it.number, msg: "\($n): reopened (moved out of \($cfg.project.status_options.done) on the board)"}
                 else empty end)
              else empty end),
             (if $conflict then
                {op: "comment", number: $it.number,
                 body: "The board moved this task to \"\($cfg.project.status_options[$Beff])\" while its status changed to \"\(status_name($cfg; $L))\" (by a pull request or a command). The status wins, so the card is back in \"\($cfg.project.status_options[$L])\".",
                 msg: "\($n): moved on the board and changed elsewhere at the same time; kept \(status_name($cfg; $L))"}
              else empty end),
             (if $B != $R then
                {op: "set_status", number: $it.number, item_id: $it.item_id, option_id: $meta.options[$R],
                 msg: "\($n): card moved to \($cfg.project.status_options[$R])"}
              else empty end),
             (if $S != $R then
                {op: "set_synced", number: $it.number, item_id: $it.item_id, text: $R}
              else empty end)
           ]}
      end ) as $status
  | ( if ($it | is_task($cfg)) | not then []
      elif $meta.points_field == null then []
      else
        ($it | task_points($cfg)) as $P
        | if $P == $it.points then []
          elif $P == null then [{op: "clear_points", number: $it.number, item_id: $it.item_id, msg: "#\($it.number): points cleared on the board"}]
          else [{op: "set_points", number: $it.number, item_id: $it.item_id, value: $P, msg: "#\($it.number): points set to \($P) on the board"}] end
      end ) as $points
  | {ops: ($status.ops + $points), warnings: $status.warnings};

# Input: normalized items. Output: {ops, warnings, changed: [numbers], unchanged: count}
# Counts cover tasks only (features, meta issues and tasks closed as not planned are left alone).
def sync_plan($cfg; $meta):
  [.[] | {number, task: (is_task($cfg) and (is_not_planned | not)), plan: plan_item($cfg; $meta)}] as $plans
  | {ops: [$plans[].plan.ops[]],
     warnings: [$plans[].plan.warnings[]],
     changed: [$plans[] | select((.plan.ops | length) > 0) | .number],
     unchanged: ([$plans[] | select(.task and (.plan.ops | length) == 0)] | length)};

# ---------- mutations ----------
# Board ops -> GraphQL mutation documents, at most $size mutations each (aliases m0, m1, ...).
def board_mutations($meta; $size):
  [.[] | select(.op == "set_status" or .op == "set_synced" or .op == "set_points" or .op == "clear_points")] as $ops
  | [range(0; $ops | length; $size) as $i | $ops[$i:($i + $size)]
     | to_entries
     | map(.key as $k | .value as $o
           | "projectId: \($meta.id | tojson), itemId: \($o.item_id | tojson)" as $base
           | if $o.op == "set_status" then
               "m\($k): updateProjectV2ItemFieldValue(input: {\($base), fieldId: \($meta.status_field | tojson), value: {singleSelectOptionId: \($o.option_id | tojson)}}) { clientMutationId }"
             elif $o.op == "set_synced" then
               "m\($k): updateProjectV2ItemFieldValue(input: {\($base), fieldId: \($meta.synced_field | tojson), value: {text: \($o.text | tojson)}}) { clientMutationId }"
             elif $o.op == "set_points" then
               "m\($k): updateProjectV2ItemFieldValue(input: {\($base), fieldId: \($meta.points_field | tojson), value: {number: \($o.value | tojson)}}) { clientMutationId }"
             else
               "m\($k): clearProjectV2ItemFieldValue(input: {\($base), fieldId: \($meta.points_field | tojson)}) { clientMutationId }"
             end)
     | "mutation {\n  " + join("\n  ") + "\n}"];
