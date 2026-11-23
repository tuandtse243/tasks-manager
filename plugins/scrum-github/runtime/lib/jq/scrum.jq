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

# ---------- pull request links ----------
# Input: a pull request body. Issue numbers it closes in $repo (close/fix/resolve keywords).
# HTML comments are ignored, like GitHub does. References to other repositories are ignored.
def closing_refs($repo):
  gsub("<!--[\\s\\S]*?-->"; "") as $b
  | ($repo | ascii_downcase) as $r
  | [ $b | capture("(?<![A-Za-z0-9_])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\\s+(?:(?<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+))?#(?<num>[0-9]+)(?![0-9])"; "gi")
      | select(.repo == null or (.repo | ascii_downcase) == $r) | .num | tonumber ] | unique;

# ---------- labels and tasks ----------
def label_names: [.labels[]? | if type == "object" then .name else . end];
def has_label($n): label_names | any(.[]; . == $n);
def status_label($cfg; $role): $cfg.statuses.label_prefix + $cfg.statuses[$role];
# The optional fourth status (statuses.in_review); off when it is not a non-empty text.
def review_on($cfg): ($cfg.statuses.in_review | type) == "string" and ($cfg.statuses.in_review | length) > 0;
# The statuses in use, in order. Every list of statuses comes from here.
def roles($cfg): ["new", "in_progress"] + (if review_on($cfg) then ["in_review"] else [] end) + ["done"];
def status_labels($cfg): [roles($cfg)[] as $r | status_label($cfg; $r)];
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

# ---------- time estimates (spec time-estimate) ----------
# A duration from the command line: 90, 25m, 2h, 1h30m -> whole minutes (> 0), or null.
# After "h" the minutes need their "m" (1h30 is refused). At most 10000 hours, so a long string of
# digits is refused rather than stored as a float.
def max_duration_minutes: 600000;
def parse_duration:
  (if type == "number" then (if . == floor then . else null end)
   elif type != "string" then null
   else ([gsub("^\\s+|\\s+$"; "") | capture("^(?:(?<h>[0-9]{1,7})h(?:(?<hm>[0-9]{1,7})m)?|(?<m>[0-9]{1,9})m?)$")] | .[0]) as $c
     | if $c == null then null
       else (($c.h // "0") | tonumber) * 60 + (($c.hm // $c.m // "0") | tonumber) end
   end)
  | if . == null or . <= 0 or . > max_duration_minutes then null else . end;
def duration_formats: "minutes (90), minutes with m (25m), hours (2h) or both (1h30m)";
# Minutes -> 25m, 2h, 1h30m.
def fmt_duration:
  (. / 60 | floor) as $h | (. - $h * 60) as $m
  | if $h == 0 then "\($m)m" elif $m == 0 then "\($h)h" else "\($h)h\($m)m" end;
def is_minutes: type == "number" and . == floor and . > 0 and . <= max_duration_minutes;

# An estimate with only its valid fields: {work_minutes?, review_minutes?, by}; null when it has
# neither time. "by" is "ai" unless it says "human".
def clean_estimate:
  if type != "object" then null
  else {work_minutes: (.work_minutes | if is_minutes then . else null end),
        review_minutes: (.review_minutes | if is_minutes then . else null end),
        by: (if .by == "human" then "human" else "ai" end)}
    | if .work_minutes == null and .review_minutes == null then null
      else with_entries(select(.value != null)) end
  end;

# Input: an issue. Its estimate from the "estimate" block of its body; null when the block is
# missing or its data cannot be read (design 1: a broken block never stops a command).
def issue_estimate:
  ((.body // "") | if type == "string" then . else "" end) as $b
  # The block that is actually closed: no other start marker between its markers, so a start
  # marker left without its end (edited by hand) never swallows a later block.
  | ([$b | match("<!-- scrum:estimate -->(?:(?!<!-- scrum:estimate -->)[\\s\\S])*?<!-- /scrum:estimate -->").string] | .[0]) as $blk
  | (if $blk == null then null else [$blk | capture("<!-- (?<j>\\{[^\\n]*\\}) -->")] | .[0].j end) as $j
  | if $j == null then null else (try ($j | fromjson) catch null) | clean_estimate end;

# The line people read: "AI ~25m · Review ~20m" ($s: strings of the configured language).
def estimate_line($e; $s):
  [ (if $e.work_minutes != null
       then tr($s; "est_work"; {by: tr($s; "est_by_\($e.by // "ai")"), d: ($e.work_minutes | fmt_duration)}) else empty end),
    (if $e.review_minutes != null then tr($s; "est_review"; {d: ($e.review_minutes | fmt_duration)}) else empty end)
  ] | join(" · ");
# Input: an object with "estimate". "  [AI 20m, review 15m]" for one line of a CLI list, or "".
def estimate_brief:
  (.estimate | clean_estimate) as $e
  | if $e == null then ""
    else "  [" + ([ (if $e.work_minutes != null then "\(if $e.by == "human" then "human" else "AI" end) \($e.work_minutes | fmt_duration)" else empty end),
                    (if $e.review_minutes != null then "review \($e.review_minutes | fmt_duration)" else empty end) ] | join(", ")) + "]" end;
# Content of the "estimate" block: the line, then the data in an HTML comment (hidden on GitHub).
def estimate_block($e; $s):
  ($e | clean_estimate) as $c
  | if $c == null then ""
    else estimate_line($c; $s) + "\n<!-- " + ($c | {work_minutes, review_minutes, by} | with_entries(select(.value != null)) | tojson) + " -->" end;
# Input: a body. The body with its "estimate" block replaced by $e (removed when $e is null).
# Leftovers of a block broken by hand go too: a start marker without its end (with the rest of
# its paragraph) and an end marker without its start, so exactly one clean block remains.
def set_estimate($e; $s):
  (. // "") | gsub(scrum_block_re("estimate"); "")
  | gsub("\n*<!-- scrum:estimate -->(?:(?!\n\n)[\\s\\S])*"; "")
  | gsub("\n*<!-- /scrum:estimate -->"; "")
  | set_scrum_block("estimate"; estimate_block($e; $s));

# Done time of tasks worked in waves (design 4): for each wave with at least one task that has a
# work time, the longest work time plus $merge; review is the sum of the review times (a task
# with only a review time adds no wave and no merge).
# Input: [{wave, estimate}]; tasks without a wave or an estimate are left out.
def eta_by_waves($merge):
  [.[] | select(.wave != null) | . as $t | (.estimate | clean_estimate) as $e | select($e != null) | {wave: $t.wave, e: $e}] as $xs
  | ([$xs[] | select(.e.work_minutes != null)] | group_by(.wave) | map({wave: .[0].wave, work: ([.[].e.work_minutes] | max)})) as $waves
  | {work_minutes: ([$waves[] | .work + $merge] | add // 0),
     review_minutes: ([$xs[].e.review_minutes // 0] | add // 0),
     waves: [$waves[] | {wave, work}],
     estimated: ($xs | length)};

# Waves of a blocking graph. Input: [{number, deps: [numbers of the same list]}].
# Output: {"N": wave}, 1 for a task that depends on none of the list. Rounds are capped at the
# list's length, so a cycle ends with large waves instead of looping.
def wave_map:
  . as $items
  | reduce range(0; ($items | length) + 1) as $_
      ([$items[] | {key: (.number | tostring), value: 1}] | from_entries;
       . as $w
       | reduce $items[] as $t (.; .[$t.number | tostring] = 1 + ([0] + [$t.deps[] | $w[tostring] // 0] | max)));

# Sums of the estimates of a list of tasks ({estimate} each): work, review and how many have none.
def estimate_totals:
  [.[] | .estimate | clean_estimate] as $es
  | {work_minutes: ([$es[] | select(. != null) | .work_minutes // 0] | add // 0),
     review_minutes: ([$es[] | select(. != null) | .review_minutes // 0] | add // 0),
     estimated: ([$es[] | select(. != null)] | length),
     missing: ([$es[] | select(. == null)] | length)};

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

# new | in_progress | in_review (when on) | done | dropped
def task_role($cfg):
  if is_completed then "done"
  elif is_not_planned then "dropped"
  elif has_label(status_label($cfg; "done")) then "done"
  elif review_on($cfg) and has_label(status_label($cfg; "in_review")) then "in_review"
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
   | . + {_role: task_role($cfg), _pts: task_points($cfg), _who: assignee_logins, _est: issue_estimate}];

# Time left of tasks not done (spec sprint-reporting "Thời gian còn lại trong bảng tiến độ").
def time_left: [.[] | select(._role != "done") | ._est | select(. != null)]
  | {work_minutes: ([.[].work_minutes // 0] | add // 0), review_minutes: ([.[].review_minutes // 0] | add // 0)};

def progress($cfg; $sprint; $issues; $today):
  ($sprint | sprint_info) as $s
  | ($issues | report_tasks($cfg)) as $t
  # Time columns only when a task of the sprint has an estimate; otherwise the output is as before.
  | any($t[]; ._est != null) as $timed
  | def row($xs): {
        new: ([$xs[] | select(._role == "new")] | bucket),
        in_progress: ([$xs[] | select(._role == "in_progress")] | bucket) }
      + (if review_on($cfg) then {in_review: ([$xs[] | select(._role == "in_review")] | bucket)} else {} end)
      + { done: ([$xs[] | select(._role == "done")] | bucket),
          total: ($xs | bucket) }
      + (if $timed then {time: ($xs | time_left)} else {} end);
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
      days_left: days_left($cfg; $s; $today) }
    + (if $timed then {time_missing: ([$t[] | select(._role != "done" and ._est == null)] | length)} else {} end);

# ---------- team (spec team) ----------
# GitHub logins are not case-sensitive; a leading "@" is not part of the login.
def login_key: ltrimstr("@") | ascii_downcase;
def same_login($a; $b): ($a | login_key) == ($b | login_key);

# The team: from cfg.team when it has a member, else the repo's assignable users ($assignees:
# GitHub's list of users or of logins; null when it was not read).
# Output: {source: "config"|"github", members: [{login, areas, capacity}]}
def team_list($cfg; $assignees):
  if (($cfg.team // []) | length) > 0 then
    {source: "config",
     members: [$cfg.team[] | {login: (.login | ltrimstr("@")), areas: (.areas // []), capacity: (.capacity // null)}]}
  else
    {source: "github",
     members: [($assignees // [])[] | (if type == "object" then .login else . end) | select(type == "string")
               | {login: ltrimstr("@"), areas: [], capacity: null}]}
  end;

# Logins of $logins that are not in cfg.team, in their order, each once; [] when team is empty.
def unknown_logins($cfg; $logins):
  if (($cfg.team // []) | length) == 0 then []
  else ([$cfg.team[].login | login_key]) as $known
    | reduce ($logins[] | ltrimstr("@") | select(. != "")) as $l ([];
        if ($known | index($l | ascii_downcase)) != null or any(.[]; same_login(.; $l)) then . else . + [$l] end)
  end;

# Load of one login among annotated sprint tasks (report_tasks): open tasks and the points of all
# its tasks in the sprint (done ones still used capacity).
def member_load($login; $tasks):
  [$tasks[] | select(any(._who[]; same_login(.; $login)))] as $mine
  | {tasks: ([$mine[] | select(._role != "done")] | length),
     points: ([$mine[]._pts // 0] | add // 0),
     done_points: ([$mine[] | select(._role == "done") | ._pts // 0] | add // 0)};

# ---------- burndown ----------
# Issues may carry `_events` (GitHub issue events, oldest first). The state of an issue at the
# end of day $d is rebuilt by undoing, from its current state, the events after $d: labeled X
# removes X, unlabeled X adds it back, milestoned into the sprint means it was not in yet,
# demilestoned from the sprint means it still was, closed/reopened flip the state. Without
# events an issue is in the sprint from the first day and closes at its closed_at.
# `_in_now: false` marks an issue that is not in the sprint any more (it may have left it).

# day_state($cfg; $title; $d; $off) on one issue -> {in, pts, done}
def day_state($cfg; $title; $d; $off):
  . as $i
  | ([$i._events // [] | .[] | select((.created_at | local_date($off)) > $d)] | reverse) as $after
  | ([$i._events // [] | .[] | select(.event == "closed" or .event == "reopened")] | length > 0) as $tracked
  | reduce $after[] as $e (
      { labels: [$i.labels[]? | if type == "object" then .name else . end],
        in: (if $i | has("_in_now") then $i._in_now else true end),   # not `//`: false is a value
        closed: ($i.state == "closed") };
      if $e.event == "labeled" then .labels -= [$e.label.name]
      elif $e.event == "unlabeled" then .labels += [$e.label.name]
      elif $e.event == "milestoned" and $e.milestone.title == $title then .in = false
      elif $e.event == "demilestoned" and $e.milestone.title == $title then .in = true
      elif $e.event == "closed" then .closed = false
      elif $e.event == "reopened" then .closed = true
      else . end )
  | ( [$i._events // [] | .[] | select(.event == "closed" and (.created_at | local_date($off)) <= $d)] | .[-1] ) as $last_close
  | (if $tracked then .closed
     else ($i.state == "closed" and $i.closed_at != null and (($i.closed_at | local_date($off)) <= $d)) end) as $closed
  | (($last_close.state_reason // $i.state_reason // "completed") | if . == null then "completed" else . end) as $reason
  | (if $i.created_at != null and (($i.created_at | local_date($off)) > $d) then false else .in end) as $in
  | { in: ($in and (($closed and $reason == "not_planned") | not)),
      pts: ({labels: (.labels | map({name: .}))} | task_points($cfg)),
      done: ($closed and $reason != "not_planned") };

def burndown($cfg; $sprint; $issues; $today; $off):
  ($sprint | sprint_info) as $s
  # A task closed as not planned counts nowhere, not even before it was dropped (spec
  # sprint-reporting "Phạm vi số liệu").
  | [$issues[] | select(is_task($cfg)) | select(is_not_planned | not)] as $t
  | (days_between($s.start; $s.end) + 1) as $n
  | [range(0; $n) | . as $k | $s.start | add_days($k)] as $dates
  | [$dates[] as $d | [$t[] | day_state($cfg; $s.title; $d; $off) + {number}]] as $states
  | [$states[] | [.[] | select(.in) | .pts // 0] | add // 0] as $scope
  | ($scope[0]) as $total
  | [range(1; $n) as $k | select($dates[$k] <= $today)
     | ($states[$k - 1] | map({key: (.number | tostring), value: .}) | from_entries) as $prev
     | $states[$k][] | . as $now | ($prev[.number | tostring]) as $was
     | if $now.in and ($was.in | not) then {added: ($now.pts // 0)}
       elif ($now.in | not) and $was.in then {removed: ($was.pts // 0)}
       else empty end ] as $moves
  | { start: $s.start, end: $s.end, total: $total,
      added: ([$moves[].added // 0] | add // 0),
      removed: ([$moves[].removed // 0] | add // 0),
      days: [range(0; $n) as $k | $dates[$k] as $d
        | { date: $d,
            ideal: ideal_at($cfg; $s; $total; $d),
            scope: (if $d > $today then null else $scope[$k] end),
            remaining: (if $d > $today then null
                        else [$states[$k][] | select(.in and (.done | not)) | .pts // 0] | add // 0 end) }] };

# ---------- project board (GitHub Projects v2) ----------
# Kept in this file, not in a project.jq that includes it: jq 1.8.2 aborts at compile time
# on include chains (jqlang/jq#3636), so every library must be included straight from a program.

def is_role($cfg): . as $r | roles($cfg) | index($r) != null;

# Built-in project workflows that change Status on their own. They would move cards without
# updating the "Synced status" field, so the next sync would copy their change onto the label.
def conflicting_workflows:
  ["Item added to project", "Item closed", "Item reopened", "Pull request linked to issue", "Pull request merged"];

# Board option name -> role, or null.
def option_role($cfg; $name):
  [$cfg.project.status_options | to_entries[] | select(.value == $name) | .key | select(is_role($cfg))] | .[0];

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
                     reduce roles($cfg)[] as $r ({}; . + {($r): ([$sf.options[]? | select(.name == $c.status_options[$r]) | .id] | .[0])})
                   else {} end),
         synced_field: (if $yf and $yf.dataType == "TEXT" then $yf.id else null end),
         points_field: (if $pf and $pf.dataType == "NUMBER" then $pf.id else null end),
         missing_options: (if $sf then [roles($cfg)[] as $r | $c.status_options[$r] as $o
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
  | ($it.synced | if . != null and is_role($cfg) then . else null end) as $S
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
