# -n --argjson ms MILESTONES --argjson cfg CONFIG --argjson args {title,start,length,goal} --arg today DATE
# Output: {error} or {title, start, end, due_on, description, warnings}
include "scrum";
($ms | map(sprint_info)) as $all
| ($args.length // $cfg.sprint.length_days) as $len
| ($args.start // $today) as $start
| if ($start | is_date | not) then {error: "start date must look like YYYY-MM-DD (got \"\($start)\")"}
  elif ($len | type) != "number" or $len < 1 or $len != ($len | floor) then {error: "sprint length must be a whole number of days, at least 1"}
  else
    ($start | add_days($len - 1)) as $end
    | ($args.title // sprint_title($cfg.sprint.name_pattern; ($ms | max_sprint_number($cfg)) + 1)) as $title
    | if any($all[]; (.title | ascii_downcase) == ($title | ascii_downcase)) then
        {error: "a sprint named \"\($title)\" already exists"}
      else
        { title: $title, start: $start, end: $end,
          due_on: "\($end)T12:00:00Z",
          description: (
            (if ($args.goal // "") != "" then "**Goal:** \($args.goal)\n\n" else "" end)
            + "**Dates:** \($start) to \($end)\n\n<!-- scrum:start=\($start) end=\($end) -->"),
          warnings: [$all[] | select(.state == "open" and .start != null and .end != null and .start <= $end and .end >= $start)
                     | "dates overlap with open sprint \"\(.title)\" (\(.start) to \(.end))"] }
      end
  end
