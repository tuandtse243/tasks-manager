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

# ---------- text ----------
# Lowercase ASCII words joined by "-", at most 40 characters. Non-ASCII letters are dropped,
# so callers with non-English titles should pass their own slug.
def slug_text:
  ascii_downcase | gsub("[^a-z0-9]+"; "-") | gsub("^-+|-+$"; "") | .[0:40] | gsub("-+$"; "");
def slug: slug_text | if . == "" then "task" else . end;
def is_slug: type == "string" and test("^[a-z0-9]+(-[a-z0-9]+)*$");

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
def current_sprint($today):
  [.[] | select(.state == "open")] as $open
  | ([$open[] | . as $ms | sprint_info | select(.start != null and .end != null and .start <= $today and $today <= .end) | $ms]
     | sort_by(sprint_info.start) | .[0])
    // ($open | sort_by(sprint_info.end // "9999-12-31") | .[0]);

def days_left($s; $today):
  if $s.end == null then null
  elif $today > $s.end then 0
  elif $today < $s.start then days_between($s.start; $s.end) + 1
  else days_between($today; $s.end) + 1 end;

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
      days_left: days_left($s; $today) };

# ---------- burndown ----------
def burndown($cfg; $sprint; $issues; $today; $off):
  ($sprint | sprint_info) as $s
  | ($issues | report_tasks($cfg)) as $t
  | ([$t[]._pts // 0] | add // 0) as $total
  | (days_between($s.start; $s.end) + 1) as $n
  | { start: $s.start, end: $s.end, total: $total,
      days: [range(0; $n) | . as $i | ($s.start | add_days($i)) as $d
        | { date: $d,
            ideal: (if $n == 1 then 0 else (($total * (1 - ($i / ($n - 1)))) * 100 | round) / 100 end),
            remaining: (if $d > $today then null
                        else $total - ([$t[] | select(is_completed and ((.closed_at | local_date($off)) <= $d)) | ._pts // 0] | add // 0)
                        end) }] };
