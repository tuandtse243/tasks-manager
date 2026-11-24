# -n --rawfile text FILE --argjson spec SECTIONS_OF_ONE_TYPE (from share/doc-sections.json)
# Output: {ok, missing: [section names], stamp: {sha, date} | null, errors: [messages]}.
# A section is a level-2 heading "## Name" (case and surrounding spaces ignored).
include "scrum";
def norm: ascii_downcase | gsub("^\\s+|\\s+$"; "") | gsub("\\s+"; " ");
([$text | split("\n")[] | select(test("^##[ \t]+[^#]")) | sub("^##[ \t]+"; "") | sub("[ \t#]*$"; "") | norm]) as $have
| [$spec.required[] | select((norm) as $n | $have | index($n) | not)] as $missing
| ([$text | capture("<!-- scrum:context sha=(?<sha>[0-9a-f]{7,40}) date=(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2}) -->"; "g")]) as $stamps
| (if $spec.stamp then
     (if ($stamps | length) == 0 then ["no scan stamp (<!-- scrum:context sha=... date=... -->): run scrum context stamp"]
      elif ($stamps | length) > 1 then ["\($stamps | length) scan stamps; keep exactly one (scrum context stamp replaces them)"]
      else [] end)
   else [] end) as $stamp_errors
| { missing: $missing,
    stamp: (if $spec.stamp then ($stamps | .[0]) else null end),
    errors: ([$missing[] | "missing section: ## \(.)"] + $stamp_errors) }
| .ok = ((.errors | length) == 0)
