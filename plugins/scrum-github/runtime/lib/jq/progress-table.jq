# Input: output of progress.jq. --argjson cfg CONFIG --argjson strings STRINGS (one language)
# Output: a text table; with time estimates in the sprint, two more columns (work and review
# minutes left) and a line with the tasks not done that have no time estimate. With a working
# branch, the tasks In review follow, each in code review or on a branch.
include "scrum";
def cell: tr($strings; "cell"; {count: .count, pts: trn($strings; "pts"; .points; {})});
def pad($n): tostring | . + ([range(0; ($n - length) | if . < 0 then 0 else . end)] | map(" ") | join(""));
def who: if . == "Unassigned" then tr($strings; "unassigned") else . end;
. as $p
| roles($cfg) as $roles
# With time estimates: work and review minutes left (tasks not done), per person and in all.
| ($p.total | has("time")) as $timed
| def times: if $timed then [(.time.work_minutes | fmt_duration), (.time.review_minutes | fmt_duration)] else [] end;
  ([[tr($strings; "assignee")] + [$roles[] as $r | $cfg.statuses[$r]] + [tr($strings; "total")]
     + (if $timed then [tr($strings; "work_left"), tr($strings; "review_left")] else [] end)]
   + [$p.rows[] | . as $row | [(.assignee | who)] + [$roles[] as $r | $row[$r] | cell] + [(.total | cell)] + ($row | times)]
   + [[tr($strings; "total")] + [$roles[] as $r | $p.total[$r] | cell] + [($p.total.total | cell)] + ($p.total | times)]) as $tbl
| ($tbl[0] | length) as $ncol
| [range(0; $ncol) as $c | [$tbl[][$c] | length] | max] as $w
| tr($strings; "sprint_line"; {title: $p.sprint.title, start: $p.sprint.start, end: $p.sprint.end,
     left: (if $p.days_left == null then "" else trn($strings; "days_left_suffix"; $p.days_left; {}) end)}),
  "",
  ($tbl | to_entries[] | .value as $row | [range(0; $ncol) as $c | $row[$c] | pad($w[$c] + 2)] | join("") | sub("[ ]+$"; "")),
  "",
  (if $p.pct_done == null then tr($strings; "done_line_na"; {unest: $p.unestimated})
   else tr($strings; "done_line"; {pct: $p.pct_done, done: $p.total.done.points, total: $p.total.total.points, unest: $p.unestimated}) end),
  (if $timed then tr($strings; "time_missing_line"; {n: $p.time_missing}) else empty end),
  # With a working branch: where each task In review is (input `review`, absent in trunk).
  (if (($p.review // []) | length) > 0 then
     "", "\($cfg.statuses.in_review):",
     ($p.review[] | "  #\(.number) \(.title): \(location_text($strings; .location))")
   else empty end)
