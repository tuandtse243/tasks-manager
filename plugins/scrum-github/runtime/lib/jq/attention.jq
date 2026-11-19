# "Needs attention" (spec sprint-reporting: "Mục cần chú ý" and its four requirements).
# -n --argjson cfg CONFIG --argjson sprint MILESTONE --argjson issues ISSUES_OF_THE_SPRINT
#    --argjson blocked {"N": [open blocking numbers] | null} --argjson prs OPEN_PULL_REQUESTS
#    --arg today DATE --argjson off SECONDS --arg repo owner/name --argjson strings STRINGS
# Output: {items: [{kind, number?, text}], lines: [text]}
include "scrum";

($sprint | sprint_info) as $s
| ($issues | report_tasks($cfg) | sort_by(.number)) as $t
| [$t[] | select(._role != "done")] as $open
| ([$t[]._pts // 0] | add // 0) as $scope
| ([$t[] | select(._role == "done") | ._pts // 0] | add // 0) as $done
| ($scope - $done) as $remaining
# Latest activity per task: the issue's own update, or that of an open PR that closes it.
| ([$prs[] | .updated_at as $u | ((.body // "") | closing_refs($repo))[] | {key: tostring, value: $u}]
   | group_by(.key) | map({key: .[0].key, value: (map(.value) | max)}) | from_entries) as $pr_activity
| def ref: "#\(.number) \(.title)";
  def act: (.updated_at // null) as $u | ($pr_activity[.number | tostring] // null) as $p
    | [$u, $p] | map(select(. != null)) | max;
  [ # sprint behind the ideal line
    ( if $s.start != null and $s.end != null and $today >= $s.start and $today <= $s.end and $scope > 0 then
        ideal_at($cfg; $s; $scope; $today) as $ideal
        | ($remaining - $ideal) as $behind
        | if ($behind * 100 / $scope) > $cfg.attention.behind_percent then
            {kind: "behind", text: tr($strings; "attention_behind";
              {n: (($behind * 100 | round) / 100), rem: $remaining, ideal: $ideal})}
          else empty end
      else empty end ),
    # blocked by an open task
    ( $open[] | . as $x | ($blocked[.number | tostring] // []) as $by | select(($by | length) > 0)
      | {kind: "blocked", number, text: tr($strings; "attention_blocked"; {ref: ($x | ref), by: ($by | map("#\(.)") | join(", "))})} ),
    # In progress without activity
    ( $open[] | select(._role == "in_progress") | . as $x | act as $a | select($a != null)
      | working_days_between($cfg; ($a | local_date($off) | add_days(1)); $today) as $idle
      | select($idle >= $cfg.attention.stale_days and $idle > 0)
      | {kind: "stale", number, text: trn($strings; "attention_stale"; $idle; {ref: ($x | ref), status: $cfg.statuses.in_progress})} ),
    # In review without activity (only when the status is on)
    ( $open[] | select(._role == "in_review") | . as $x | act as $a | select($a != null)
      | working_days_between($cfg; ($a | local_date($off) | add_days(1)); $today) as $idle
      | select($idle >= ($cfg.attention.review_days // 2) and $idle > 0)
      | {kind: "review", number, text: trn($strings; "attention_review"; $idle; {ref: ($x | ref)})} ),
    # no assignee, no points
    ( $open[] | select((._who | length) == 0) | {kind: "unassigned", number, text: tr($strings; "attention_unassigned"; {ref: ref})} ),
    ( $open[] | select(._pts == null) | {kind: "unestimated", number, text: tr($strings; "attention_unestimated"; {ref: ref})} )
  ] as $items
| {items: $items, lines: [$items[].text]}
