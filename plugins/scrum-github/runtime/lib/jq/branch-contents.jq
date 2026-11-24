# Which tasks a branch contains (design 5). Two pure steps around the GitHub reads of
# branching.sh (branch_contents):
#
#   --arg step candidates  Input: issues. --argjson cfg CONFIG --argjson locations [branches]|null
#     The open tasks In review with a location label (of one of $locations when not null), by
#     number, at most $limit (default 100):
#     {numbers: [N...], truncated: bool, total, limit}
#
#   --arg step result  -n --argjson checks [{number, prs: [{number, sha}] | null,
#                                           statuses: [ahead|identical|behind|diverged|null]}]
#     A task is contained when it has merged pull requests and the ref contains the merge commit
#     of every one of them (compare status ahead or identical); missing when one is not
#     contained; unknown when its pull requests or a comparison could not be read.
#     {contained: [N], missing: [N], unknown: [N], prs: {"N": [{number, sha}]}}
include "scrum";
($ARGS.named.limit // 100) as $limit
| ($ARGS.named.step // "") as $step
| ($ARGS.named.locations // null) as $locations
| ($ARGS.named.checks // []) as $checks
| ($ARGS.named.cfg // {}) as $cfg
| if $step == "candidates" then
    [.[] | select(.state == "open" and is_task($cfg) and task_role($cfg) == "in_review")
     | task_location($cfg) as $l
     | select($l != null and ($locations == null or ($locations | index($l)) != null))
     | .number] | unique as $all
    | {numbers: $all[0:$limit], truncated: (($all | length) > $limit), total: ($all | length), limit: $limit}
  elif $step == "result" then
    [ $checks[]
      | { number,
          prs: (.prs // null),
          verdict: (if .prs == null or (.prs | length) == 0 then "unknown"
                    elif any(.statuses[]; . == null) then "unknown"
                    elif all(.statuses[]; . == "ahead" or . == "identical") then "contained"
                    else "missing" end) } ] as $v
    | { contained: [$v[] | select(.verdict == "contained") | .number],
        missing: [$v[] | select(.verdict == "missing") | .number],
        unknown: [$v[] | select(.verdict == "unknown") | .number],
        prs: ([$v[] | select(.prs != null) | {key: (.number | tostring), value: .prs}] | from_entries) }
  else error("unknown step \($step)") end
