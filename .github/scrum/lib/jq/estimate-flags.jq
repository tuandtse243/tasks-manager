# The time flags of task new and task estimate (spec time-estimate). Pure: no network.
# -n --arg work D --arg review D --arg by ai|human ("" = not given)
#    [--argjson strings STRINGS]
# Input: the issue to change (task estimate), or nothing with -n (task new, or a check of the flags
# before the issue is read). The issue comes on stdin: a body can be too long for one argument.
#    [--argjson partial true]   (only check the flags: the issue is read later)
# Output: {error} when a flag is wrong, otherwise
#   {given: bool, estimate: the estimate after the change (null when none),
#    changed: bool, body: new issue body (only with issue, when changed), summary: "work 25m (AI), review 20m"}
# Fields not given keep the issue's value; "by" defaults to ai.
include "scrum";

. as $issue
| ($ARGS.named.strings // null) as $s
| (if $issue == null then null else $issue | issue_estimate end) as $old
| [ (if $work != "" and ($work | parse_duration) == null
       then "--work: \($work | tojson) is not a duration. Use \(duration_formats)" else empty end),
    (if $review != "" and ($review | parse_duration) == null
       then "--review: \($review | tojson) is not a duration. Use \(duration_formats)" else empty end),
    (if $by != "" and $by != "ai" and $by != "human" then "--by must be ai or human (got \($by | tojson))" else empty end)
  ] as $errors
| ($work != "" or $review != "" or $by != "") as $given
| if ($errors | length) > 0 then {error: ($errors | join("; "))}
  elif ($given | not) then {given: false, estimate: $old, changed: false}
  else
    (($old // {})
     + (if $work != "" then {work_minutes: ($work | parse_duration)} else {} end)
     + (if $review != "" then {review_minutes: ($review | parse_duration)} else {} end)
     + (if $by != "" then {by: $by} else {} end)
     | clean_estimate) as $new
    | if $new == null and $ARGS.named.partial == true then {given: true, estimate: null, changed: false}
      elif $new == null then {error: ("--by needs --work or --review" + (if $issue == null then "" else ": the task has no time estimate yet" end))}
      else
        ($new != $old) as $changed
        | {given: true, estimate: $new, changed: $changed,
           summary: ([ (if $new.work_minutes != null then "work \($new.work_minutes | fmt_duration) (\(if $new.by == "human" then "human" else "AI" end))" else empty end),
                       (if $new.review_minutes != null then "review \($new.review_minutes | fmt_duration)" else empty end) ] | join(", "))}
          + (if $issue != null and $changed then {body: ($issue.body // "" | set_estimate($new; $s))} else {} end)
      end
  end
