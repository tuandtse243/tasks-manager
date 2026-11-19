# Input: output of progress.jq. --argjson cfg CONFIG --argjson strings STRINGS (one language)
# Output: a text table.
include "scrum";
def cell: tr($strings; "cell"; {count: .count, pts: trn($strings; "pts"; .points; {})});
def pad($n): tostring | . + ([range(0; ($n - length) | if . < 0 then 0 else . end)] | map(" ") | join(""));
def who: if . == "Unassigned" then tr($strings; "unassigned") else . end;
. as $p
| roles($cfg) as $roles
| ([[tr($strings; "assignee")] + [$roles[] as $r | $cfg.statuses[$r]] + [tr($strings; "total")]]
   + [$p.rows[] | . as $row | [(.assignee | who)] + [$roles[] as $r | $row[$r] | cell] + [(.total | cell)]]
   + [[tr($strings; "total")] + [$roles[] as $r | $p.total[$r] | cell] + [($p.total.total | cell)]]) as $tbl
| ($tbl[0] | length) as $ncol
| [range(0; $ncol) as $c | [$tbl[][$c] | length] | max] as $w
| tr($strings; "sprint_line"; {title: $p.sprint.title, start: $p.sprint.start, end: $p.sprint.end,
     left: (if $p.days_left == null then "" else trn($strings; "days_left_suffix"; $p.days_left; {}) end)}),
  "",
  ($tbl | to_entries[] | .value as $row | [range(0; $ncol) as $c | $row[$c] | pad($w[$c] + 2)] | join("") | sub("[ ]+$"; "")),
  "",
  (if $p.pct_done == null then tr($strings; "done_line_na"; {unest: $p.unestimated})
   else tr($strings; "done_line"; {pct: $p.pct_done, done: $p.total.done.points, total: $p.total.total.points, unest: $p.unestimated}) end)
