# Input: output of progress.jq. Output: a text table.
def cell: "\(.count) (\(.points) pt\(if .points == 1 then "" else "s" end))";
def pad($n): tostring | . + ([range(0; ($n - length) | if . < 0 then 0 else . end)] | map(" ") | join(""));
. as $p
| ([["Assignee", "New", "In progress", "Done", "Total"]]
   + [$p.rows[] | [.assignee, (.new | cell), (.in_progress | cell), (.done | cell), (.total | cell)]]
   + [["Total", ($p.total.new | cell), ($p.total.in_progress | cell), ($p.total.done | cell), ($p.total.total | cell)]]) as $tbl
| [range(0; 5) as $c | [$tbl[][$c] | length] | max] as $w
| "\($p.sprint.title)  (\($p.sprint.start) to \($p.sprint.end)\(if $p.days_left == null then "" else ", \($p.days_left) day\(if $p.days_left == 1 then "" else "s" end) left" end))",
  "",
  ($tbl | to_entries[] | .value as $row | [range(0; 5) as $c | $row[$c] | pad($w[$c] + 2)] | join("") | sub("[ ]+$"; "")),
  "",
  "Done: \(if $p.pct_done == null then "n/a (no points estimated)" else "\($p.pct_done)% of points (\($p.total.done.points) of \($p.total.total.points))" end). Unestimated tasks: \($p.unestimated)."
