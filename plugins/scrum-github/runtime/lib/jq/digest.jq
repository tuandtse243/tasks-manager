# -n --argjson cfg CONFIG --argjson sprint MILESTONE --argjson issues ISSUES --argjson comments COMMENTS
#    --arg today DATE --argjson off SECONDS --argjson strings STRINGS (one language)
#    --argjson attention [lines of "Needs attention"; [] for none]
# Output: {body} for the digest comment.
include "scrum";
def pts: trn($strings; "pts"; .; {});
def who: if (._who | length) == 0 then tr($strings; "digest_unassigned") else (._who | map("@" + .) | join(", ")) end;
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
      "## " + tr($strings; "digest_title"; {title: $s.title, today: $today}),
      "",
      tr($strings; "digest_remaining"; {rem: $remaining, total: $p.total.total.points}) + " "
        + (if $p.days_left == null then "" elif $p.days_left == 0 then tr($strings; "digest_ended"; {end: $s.end})
           else trn($strings; "digest_left"; $p.days_left; {end: $s.end}) end),
      "",
      (if ($attention | length) > 0 then ("### " + tr($strings; "attention_title"), ($attention[] | "- " + .), "") else empty end),
      "### " + tr($strings; if $last then "digest_done_since_last" else "digest_done_since_start" end),
      (if ($done_since | length) == 0 then "- " + tr($strings; "digest_nothing_closed")
       else ($done_since | sort_by(.closed_at)[] | "- #\(.number) \(.title) (\(._pts // 0 | pts)), \(who)") end),
      "",
      "### " + tr($strings; "digest_in_progress"),
      (if ($doing | length) == 0 then "- " + tr($strings; "digest_nothing_in_progress")
       else ($doing | sort_by(._who[0] // "~")[] | "- \(who): #\(.number) \(.title) (\(._pts // 0 | pts))") end),
      "",
      "### " + tr($strings; "digest_not_started"),
      "- " + trn($strings; "digest_not_started_line"; ($todo | length); {pts: ([$todo[]._pts // 0] | add // 0 | pts)})
    ] | join("\n")) }
