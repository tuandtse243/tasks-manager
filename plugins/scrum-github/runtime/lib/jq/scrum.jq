# Shared jq functions. Load with: jq -L lib/jq 'include "scrum"; ...'
# All functions are pure: they only read their input and arguments.

# ---------- dates (YYYY-MM-DD strings, UTC arithmetic) ----------
def date_epoch: strptime("%Y-%m-%d") | mktime;
def epoch_date: strftime("%Y-%m-%d");
def add_days($n): (date_epoch + ($n * 86400)) | epoch_date;
# Whole days from $a to $b (b - a).
def days_between($a; $b): ((($b | date_epoch) - ($a | date_epoch)) / 86400) | floor;
# ISO timestamp -> local date for a UTC offset in seconds.
def local_date($off): (fromdateiso8601 + $off) | epoch_date;
def is_date: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$");
# ISO weekday of a date: 1 = Monday ... 7 = Sunday.
def weekday: date_epoch | strftime("%u") | tonumber;
def is_working_day($cfg): weekday as $w | ($cfg.sprint.working_days // [1, 2, 3, 4, 5]) | index($w) != null;
# Working days from $a to $b, both included (0 when $b is before $a).
def working_days_between($cfg; $a; $b):
  if $b < $a then 0 else [range(0; days_between($a; $b) + 1) | . as $i | $a | add_days($i) | select(is_working_day($cfg))] | length end;

# ---------- text ----------
# Lowercase ASCII words joined by "-", at most 40 characters. Non-ASCII letters are dropped,
# so callers with non-English titles should pass their own slug.
def slug_text:
  ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "") | .[0:40] | gsub("-+$"; "");
def slug: slug_text | if . == "" then "task" else . end;
def is_slug: type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$");

# ---------- text in the configured language (share/strings.json) ----------
# $s is the table of one language. {name} in the text is replaced by $args.name; a missing key
# prints the key itself, so a gap is visible rather than silent.
def tr($s; $key; $args):
  reduce ($args | to_entries[]) as $e (($s[$key] // $key); gsub("\\{" + $e.key + "\\}"; $e.value | tostring));
def tr($s; $key): tr($s; $key; {});
# Picks "<key>_one" for 1 when the language has it (English plural), else "<key>"; {n} is $n.
def trn($s; $key; $n; $args):
  tr($s; (if $n == 1 and $s[$key + "_one"] != null then $key + "_one" else $key end); $args + {n: $n});

# ---------- labels and tasks ----------
def label_names: [.labels[]? | if type == "object" then .name else . end];
def has_label($n): label_names | any(.[]; . == $n);
def status_label($cfg; $role): $cfg.statuses.label_prefix + $cfg.statuses[$role];
def status_labels($cfg): [status_label($cfg; "new"), status_label($cfg; "in_progress"), status_label($cfg; "done")];
def points_label($cfg; $p): "\($cfg.points.label_prefix)\($p)";

# Body of a task issue: text, acceptance criteria, subtasks (checkboxes), and "Part of #parent".
def task_issue_body($task; $parent):
  [ ($task.body // "" | select(. != "")),
    (if (($task.acceptance // []) | length) > 0
       then "### Acceptance criteria\n\n" + ($task.acceptance | map("- [ ] \(.)") | join("\n")) else empty end),
    (if (($task.subtasks // []) | length) > 0
       then "### Subtasks\n\n" + ($task.subtasks | map("- [ ] \(.)") | join("\n")) else empty end),
    (if ($parent // "" | tostring) != "" then "Part of #\($parent)" else empty end)
  ] | join("\n\n");

# Text between <!-- scrum:NAME --> and <!-- /scrum:NAME --> markers (fallbacks written by plan apply).
def scrum_block_re($name): "\n*<!-- scrum:\($name) -->[\\s\\S]*?<!-- /scrum:\($name) -->";
def scrum_blocks: [match("<!-- scrum:(?<n>[a-z-]+) -->[\\s\\S]*?<!-- /scrum:\\k<n> -->"; "g").string] // [];
def strip_scrum_blocks: gsub("\n*<!-- scrum:(?<n>[a-z-]+) -->[\\s\\S]*?<!-- /scrum:[a-z-]+ -->"; "");
# Replace the block NAME in a body (append it when missing). Empty $content removes it.
def set_scrum_block($name; $content):
  (. // "") as $b
  | ($b | gsub(scrum_block_re($name); "")) as $rest
  | if $content == "" then $rest
    else ($rest | if . == "" then "" else . + "\n\n" end)
         + "<!-- scrum:\($name) -->\n\($content)\n<!-- /scrum:\($name) -->" end;

def is_pr: has("pull_request");
# Features, epics and meta issues are not tasks: they never count in points, velocity or status sync.
def is_task($cfg):
  (is_pr | not) and (has_label($cfg.labels.feature) | not) and (has_label($cfg.labels.meta) | not)
  and (($cfg.labels.epic // null) as $e | $e == null or (has_label($e) | not));
def is_completed: .state == "closed" and ((.state_reason // "completed") == "completed");
def is_not_planned: .state == "closed" and .state_reason == "not_planned";

def task_points($cfg):
  [label_names[] | select(startswith($cfg.points.label_prefix))
   | ltrimstr($cfg.points.label_prefix) | tonumber?] | .[0];

# new | in_progress | done | dropped
def task_role($cfg):
  if is_completed then "done"
  elif is_not_planned then "dropped"
  elif has_label(status_label($cfg; "done")) then "done"
  elif has_label(status_label($cfg; "in_progress")) then "in_progress"
  else "new" end;

def assignee_logins: [.assignees[]?.login];

# Label set after moving an issue to $role: every status label removed, the target added.
def labels_with_status($cfg; $role):
  label_names as $cur
  | ($cfg.statuses.label_prefix) as $p
  | [$cur[] | select(. as $n | (status_labels($cfg) | any(.[]; . == $n)) or ($p != "" and ($n | startswith($p))) | not)]
    + [status_label($cfg; $role)];

# ---------- sprints (milestones) ----------
def sprint_info:
  (.description // "") as $d
  | ([$d | capture("scrum:start=(?<s>[0-9]{4}-[0-9]{2}-[0-9]{2})[ ]+end=(?<e>[0-9]{4}-[0-9]{2}-[0-9]{2})")] | .[0]) as $m
  | ([$d | capture("scrum:velocity=(?<v>[0-9]+)")] | .[0].v) as $v
  | { number, title, state, description: $d,
      start: ($m.s // ((.created_at // "") | if length >= 10 then .[0:10] else null end)),
      end: ($m.e // (if .due_on then .due_on[0:10] else null end)),
      velocity: (if $v then ($v | tonumber) else null end) };

# Sprint number from a title, given the pattern ("Sprint {n}"). Empty when it does not match.
def pattern_number($pattern):
  ($pattern | split("{n}")) as $p
  | if startswith($p[0]) and endswith($p[1]) and (length > (($p[0] | length) + ($p[1] | length)))
    then (.[($p[0] | length):(length - ($p[1] | length))] | tonumber? // empty)
    else empty end;

def sprint_title($pattern; $n): $pattern | gsub("\\{n\\}"; "\($n)");

def max_sprint_number($cfg): [.[] | .title | pattern_number($cfg.sprint.name_pattern)] | max // 0;

# Input: milestones. The open sprint whose dates contain $today, else the open one ending first.
# Input: milestones. The (up to) three most recently closed sprints that recorded a velocity,
# oldest first, as sprint_info objects with closed_at.
def recent_velocity_sprints:
  [.[]? | select(.state == "closed") | . as $m | sprint_info + {closed_at: $m.closed_at}
   | select(.velocity != null)] | sort_by(.closed_at // .end // "") | .[-3:];

def current_sprint($today):
  [.[] | select(.state == "open")] as $open
  | ([$open[] | . as $ms | sprint_info | select(.start != null and .end != null and .start <= $today and $today <= .end) | $ms]
     | sort_by(sprint_info.start) | .[0])
    // ($open | sort_by(sprint_info.end // "9999-12-31") | .[0]);

# Working days left, today included (spec sprint-reporting "Tóm tắt tiến độ sprint").
def days_left($cfg; $s; $today):
  if $s.end == null then null
  elif $today > $s.end then 0
  else working_days_between($cfg; (if $today < $s.start then $s.start else $today end); $s.end) end;

# Ideal remaining at the end of day $d: falls only across working days, from $total to 0.
def ideal_at($cfg; $s; $total; $d):
  working_days_between($cfg; $s.start; $s.end) as $w
  | if $w <= 1 then (if $d >= $s.end then 0 else $total end)
    else working_days_between($cfg; $s.start; ($d | add_days(-1))) as $k
    | (($total * (1 - ([$k, $w - 1] | min) / ($w - 1))) * 100 | round) / 100 end;

# ---------- progress ----------
def bucket: {count: length, points: ([.[]._pts // 0] | add // 0)};

# Tasks of a sprint that count in reports (no PRs, features, meta, not-planned), annotated.
def report_tasks($cfg):
  [.[] | select(is_task($cfg)) | select(is_not_planned | not)
   | . + {_role: task_role($cfg), _pts: task_points($cfg), _who: assignee_logins}];

def progress($cfg; $sprint; $issues; $today):
  ($sprint | sprint_info) as $s
  | ($issues | report_tasks($cfg)) as $t
  | def row($xs): {
        new: ([$xs[] | select(._role == "new")] | bucket),
        in_progress: ([$xs[] | select(._role == "in_progress")] | bucket),
        done: ([$xs[] | select(._role == "done")] | bucket),
        total: ($xs | bucket) };
  ([$t[]._who[]] | unique) as $people
  | ( ($people | map(. as $p | {assignee: $p} + row([$t[] | select(._who | any(.[]; . == $p))])))
      + (if any($t[]; (._who | length) == 0) then [{assignee: "Unassigned"} + row([$t[] | select((._who | length) == 0)])] else [] end)
    ) as $rows
  | row($t) as $total
  | { sprint: {number: $s.number, title: $s.title, start: $s.start, end: $s.end, state: $s.state},
      rows: $rows,
      total: $total,
      pct_done: (if $total.total.points > 0 then ($total.done.points * 100 / $total.total.points | round) else null end),
      unestimated: ([$t[] | select(._pts == null)] | length),
      days_left: days_left($cfg; $s; $today) };

# ---------- burndown ----------
def burndown($cfg; $sprint; $issues; $today; $off):
  ($sprint | sprint_info) as $s
  | ($issues | report_tasks($cfg)) as $t
  | ([$t[]._pts // 0] | add // 0) as $total
  | (days_between($s.start; $s.end) + 1) as $n
  | { start: $s.start, end: $s.end, total: $total,
      days: [range(0; $n) | . as $i | ($s.start | add_days($i)) as $d
        | { date: $d,
            ideal: ideal_at($cfg; $s; $total; $d),
            remaining: (if $d > $today then null
                        else $total - ([$t[] | select(is_completed and ((.closed_at | local_date($off)) <= $d)) | ._pts // 0] | add // 0)
                        end) }] };

# ---------- project board (GitHub Projects v2) ----------
# Kept in this file, not in a project.jq that includes it: jq 1.8.2 aborts at compile time
# on include chains (jqlang/jq#3636), so every library must be included straight from a program.

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
