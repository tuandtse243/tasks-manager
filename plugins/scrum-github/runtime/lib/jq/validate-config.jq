# Input: merged configuration. Output: array of error messages (empty when valid).

def is_int: type == "number" and . == floor;
def nonempty_string: type == "string" and length > 0;

. as $c
| [
    # points.scale
    (if ($c.points.scale | type) != "array" or ($c.points.scale | length) == 0
       then "points.scale: must be a non-empty list of whole numbers"
     else
       ($c.points.scale[] | select((is_int and . >= 0) | not)
        | "points.scale: values must be non-negative whole numbers (got \(tojson))"),
       (if ($c.points.scale | length) != ($c.points.scale | unique | length)
          then "points.scale: values must not repeat" else empty end)
     end),
    (if ($c.points.label_prefix | nonempty_string) then empty
     else "points.label_prefix: must be a non-empty text" end),

    # sprint
    (if ($c.sprint.length_days | is_int) and $c.sprint.length_days > 0 then empty
     else "sprint.length_days: must be a whole number greater than 0 (got \($c.sprint.length_days | tojson))" end),
    (if ($c.sprint.name_pattern | type) == "string" and ($c.sprint.name_pattern | contains("{n}")) then empty
     else "sprint.name_pattern: must contain {n}, for example \"Sprint {n}\"" end),

    # statuses
    (["new", "in_progress", "done"][] as $k
     | if ($c.statuses[$k] | nonempty_string) then empty
       else "statuses.\($k): must be a non-empty text" end),
    (if ([$c.statuses.new, $c.statuses.in_progress, $c.statuses.done] | map(ascii_downcase? // .) | unique | length) < 3
       then "statuses: new, in_progress and done must be different" else empty end),
    (if ($c.statuses.label_prefix | type) == "string" then empty
     else "statuses.label_prefix: must be text" end),

    # labels
    (["bug", "feature", "epic", "meta", "no_task"][] as $k
     | if ($c.labels[$k] | nonempty_string) then empty
       else "labels.\($k): must be a non-empty text" end),
    (if ($c.labels.epic | nonempty_string)
        and ([$c.labels.feature, $c.labels.meta, $c.labels.no_task] | map(ascii_downcase? // .)
             | index($c.labels.epic | ascii_downcase)) != null
       then "labels.epic: must differ from labels.feature, labels.meta and labels.no_task (got \($c.labels.epic | tojson))"
       else empty end),

    # planning
    (if ($c.planning | type) != "object" then "planning: must be a mapping"
     else
       ($c.planning) as $pl
       | (["dir", "context_file"][] as $k
          | if ($pl[$k] | nonempty_string) | not then "planning.\($k): must be a non-empty path inside the repo"
            elif ($pl[$k] | startswith("/")) then "planning.\($k): must be relative to the repo root (got \($pl[$k] | tojson))"
            elif ($pl[$k] | split("/") | any(.[]; . == "..")) then "planning.\($k): must stay inside the repo, \"..\" is not allowed (got \($pl[$k] | tojson))"
            else empty end),
         (if $pl.hours_per_point == null or (($pl.hours_per_point | type) == "number" and $pl.hours_per_point > 0) then empty
          else "planning.hours_per_point: must be a number greater than 0, or null (got \($pl.hours_per_point | tojson))" end),
         (if ($pl.context_stale_commits | is_int) and $pl.context_stale_commits > 0 then empty
          else "planning.context_stale_commits: must be a whole number greater than 0 (got \($pl.context_stale_commits | tojson))" end)
     end),

    # misc
    (if ($c.timezone | nonempty_string) then empty else "timezone: must be a time zone name such as UTC or Asia/Ho_Chi_Minh" end),
    (if ($c.branch.pattern | type) == "string" and ($c.branch.pattern | contains("{number}")) then empty
     else "branch.pattern: must contain {number}" end),
    (if ($c.digest.enabled | type) == "boolean" then empty else "digest.enabled: must be true or false" end),
    (if ($c.digest.cron | type) == "string" and ($c.digest.cron | split(" ") | map(select(. != "")) | length) == 5 then empty
     else "digest.cron: must be a 5-field cron expression" end),
    (if ($c.colors | type) == "object" then
       ($c.colors | to_entries[] | select((.value | type) != "string" or (.value | test("^#?[0-9a-fA-F]{6}$") | not))
        | "colors.\(.key): must be a 6-digit hex color such as 0e8a16")
     else "colors: must be a mapping of label name to color" end),

    # project (board sync): checked only when turned on
    (if ($c.project | type) != "object" then "project: must be a mapping"
     elif ($c.project.enabled | type) != "boolean" then "project.enabled: must be true or false"
     elif $c.project.enabled | not then empty
     else
       ($c.project) as $p
       | (if ($p.owner | nonempty_string) then empty
          else "project.owner: must be the user or organization that owns the project" end),
         (if ($p.number | is_int) and $p.number > 0 then empty
          else "project.number: must be the project number from its URL, a whole number greater than 0" end),
         (["status_field", "synced_field"][] as $k
          | if ($p[$k] | nonempty_string) then empty else "project.\($k): must be a non-empty text" end),
         (if $p.points_field == null or ($p.points_field | nonempty_string) then empty
          else "project.points_field: must be a field name, or null to turn it off" end),
         (if ($p.status_options | type) != "object" then "project.status_options: must be a mapping"
          else
            (["new", "in_progress", "done"][] as $k
             | if ($p.status_options[$k] | nonempty_string) then empty
               else "project.status_options.\($k): must be a non-empty text" end),
            (if ([$p.status_options.new, $p.status_options.in_progress, $p.status_options.done] | unique | length) < 3
               then "project.status_options: new, in_progress and done must be different options" else empty end)
          end),
         (if ($p.poll_cron | type) == "string" and ($p.poll_cron | split(" ") | map(select(. != "")) | length) == 5 then empty
          else "project.poll_cron: must be a 5-field cron expression" end)
     end)
  ]
