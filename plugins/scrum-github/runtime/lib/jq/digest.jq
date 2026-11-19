# -n --argjson cfg CONFIG --argjson sprint MILESTONE --argjson issues ISSUES --argjson comments COMMENTS
#    --arg today DATE --argjson off SECONDS
# Output: {body} for the digest comment.
include "scrum";
def pts: "\(.) pt\(if . == 1 then "" else "s" end)";
def who: if (._who | length) == 0 then "unassigned" else (._who | map("@" + .) | join(", ")) end;
($sprint | sprint_info) as $s
| progress($cfg; $sprint; $issues; $today) as $p
| ($issues | report_tasks($cfg)) as $t
| ([$comments[] | select((.body // "") | contains("<!-- scrum:digest -->")) | .created_at] | sort | .[-1]) as $last
| (if $last then ($last | fromdateiso8601) else (($s.start | date_epoch) - $off) end) as $since
| [$t[] | select(is_completed and ((.closed_at | fromdateiso8601) > $since))] as $done_since
| [$t[] | select(._role == "in_progress")] as $doing
| [$t[] | select(._role == "new")] as $todo
| ($p.total.total.points - $p.total.done.points) as $remaining
| { body: ([
      "<!-- scrum:digest -->",
      "## \($s.title) digest, \($today)",
      "",
      "**Remaining:** \($remaining) of \($p.total.total.points) points. "
        + (if $p.days_left == null then "" elif $p.days_left == 0 then "The sprint has ended (\($s.end))."
           else "\($p.days_left) day\(if $p.days_left == 1 then "" else "s" end) left (ends \($s.end))." end),
      "",
      "### Done since \(if $last then "the last digest" else "the start of the sprint" end)",
      (if ($done_since | length) == 0 then "- Nothing closed."
       else ($done_since | sort_by(.closed_at)[] | "- #\(.number) \(.title) (\(._pts // 0 | pts)), \(who)") end),
      "",
      "### In progress",
      (if ($doing | length) == 0 then "- Nothing in progress."
       else ($doing | sort_by(._who[0] // "~")[] | "- \(who): #\(.number) \(.title) (\(._pts // 0 | pts))") end),
      "",
      "### Not started",
      "- \($todo | length) task\(if ($todo | length) == 1 then "" else "s" end), \([$todo[]._pts // 0] | add // 0 | pts)"
    ] | join("\n")) }
