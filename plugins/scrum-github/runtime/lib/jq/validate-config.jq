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
    (if $c.statuses.in_review == null or ($c.statuses.in_review | nonempty_string) then empty
     else "statuses.in_review: must be a non-empty text, or left out to turn it off" end),
    ([$c.statuses.new, $c.statuses.in_progress, $c.statuses.done] + (if $c.statuses.in_review == null then [] else [$c.statuses.in_review] end)) as $names
    | (if ($names | map(ascii_downcase? // .) | unique | length) < ($names | length)
       then "statuses: new, in_progress\(if $c.statuses.in_review == null then "" else ", in_review" end) and done must be different" else empty end),
    (if ($c.statuses.label_prefix | type) == "string" then empty
     else "statuses.label_prefix: must be text" end),

    # labels
    (["bug", "feature", "epic", "meta", "no_task", "ai_ready"][] as $k
     | if ($c.labels[$k] | nonempty_string) then empty
       else "labels.\($k): must be a non-empty text" end),
    (if ($c.labels.epic | nonempty_string)
        and ([$c.labels.feature, $c.labels.meta, $c.labels.no_task] | map(ascii_downcase? // .)
             | index($c.labels.epic | ascii_downcase)) != null
       then "labels.epic: must differ from labels.feature, labels.meta and labels.no_task (got \($c.labels.epic | tojson))"
       else empty end),
    # labels.ai_ready marks a task ready for /scrum-github:run; it must not be a label that makes
    # an issue a non-task or lets a pull request skip the link check (spec scrum-config "Nhãn ai-ready")
    (if ($c.labels.ai_ready | nonempty_string)
        and ([$c.labels.feature, $c.labels.epic, $c.labels.meta, $c.labels.no_task] | map(ascii_downcase? // .)
             | index($c.labels.ai_ready | ascii_downcase)) != null
       then "labels.ai_ready: must differ from labels.feature, labels.epic, labels.meta and labels.no_task (got \($c.labels.ai_ready | tojson))"
       else empty end),

    # run (spec scrum-config "Cấu hình chạy task bằng agent")
    (if ($c.run | type) != "object" then "run: must be a mapping"
     else
       (if ($c.run.test_command | type) == "string" then empty
        else "run.test_command: must be a command (text), or empty to let the agent find how to test (got \($c.run.test_command | tojson))" end),
       (if ($c.run.max_parallel | is_int) and $c.run.max_parallel > 0 then empty
        else "run.max_parallel: must be a whole number greater than 0 (got \($c.run.max_parallel | tojson))" end),
       (if ($c.run.branch_pattern | nonempty_string) then empty
        else "run.branch_pattern: must be a non-empty branch name pattern, such as \"run/{sprint}-{login}\" (got \($c.run.branch_pattern | tojson))" end)
     end),

    # release (spec scrum-config "Release configuration")
    (if ($c.release | type) != "object" then "release: must be a mapping"
     else
       (if ($c.release.tag_prefix | type) == "string" and ($c.release.tag_prefix | test("^[A-Za-z0-9._/-]*$")) then empty
        else "release.tag_prefix: must be text without spaces, such as \"v\", or \"\" for none (got \($c.release.tag_prefix | tojson))" end),
       (if ($c.release.breaking_label | nonempty_string) then empty
        else "release.breaking_label: must be a non-empty label name (got \($c.release.breaking_label | tojson))" end),
       (if ($c.release.first_version | type) == "string" and ($c.release.first_version | test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")) then empty
        else "release.first_version: must be a version X.Y.Z, such as \"0.1.0\" (got \($c.release.first_version | tojson))" end),
       # spec scrum-config "Release files"
       (if ($c.release.version_files // [] | type) != "array"
          then "release.version_files: must be a list of files, each with a path and an optional pattern containing {version}"
        else
          ($c.release.version_files // [] | to_entries[] | .key as $i | .value as $f
           | if ($f | type) != "object" or ($f.path | nonempty_string | not)
               then "release.version_files[\($i)].path: is required (the file whose version the release updates)"
             elif ($f.path | startswith("/")) or ($f.path | split("/") | any(.[]; . == ".."))
               then "release.version_files[\($i)].path: must be a path inside the repo, relative to its root (got \($f.path | tojson))"
             elif $f.pattern != null and (($f.pattern | type) != "string" or ($f.pattern | contains("{version}") | not))
               then "release.version_files[\($i)].pattern: needs {version} where the version goes, for example \"version = \\\"{version}\\\"\" (got \($f.pattern | tojson))"
             elif $f.pattern == null and ($f.path | endswith(".json") | not)
               then "release.version_files[\($i)].pattern: is required for a file that is not JSON (\($f.path)); it needs {version}"
             else empty end)
        end),
       (if $c.release.changelog == null then empty
        elif ($c.release.changelog | nonempty_string) and ($c.release.changelog | startswith("/") | not)
             and ($c.release.changelog | split("/") | any(.[]; . == "..") | not) then empty
        else "release.changelog: must be a path inside the repo, such as CHANGELOG.md, or null (got \($c.release.changelog | tojson))" end)
     end),

    # branching (spec branching-presets, scrum-config "Branching block")
    (if $c.branching == null then empty
     elif ($c.branching | type) != "object" then "branching: must be a mapping"
     else
       ($c.branching) as $b
       | ($b.preset // "trunk") as $p
       | (if ["trunk", "standard", "environments"] | index($p) then empty
          else "branching.preset: must be trunk, standard or environments (got \($b.preset | tojson))" end),
         (["main", "develop", "staging"][] as $k
          | if ($b[$k] | nonempty_string) and ($b[$k] | test("^[A-Za-z0-9._][A-Za-z0-9._/-]*$")) then empty
            else "branching.\($k): must be a branch name (got \($b[$k] | tojson))" end),
         (if ($b.location_prefix | nonempty_string) then empty
          else "branching.location_prefix: must be a non-empty text, such as \"on: \" (got \($b.location_prefix | tojson))" end),
         (if ($b.stale_days | is_int) and $b.stale_days > 0 then empty
          else "branching.stale_days: must be a whole number greater than 0 (got \($b.stale_days | tojson))" end),
         ({trunk: ["main"], standard: ["main", "develop"], environments: ["main", "develop", "staging"]}[$p] // []) as $keys
         | ([$keys[] as $k | {k: $k, v: $b[$k]}] | group_by(.v) | map(select(length > 1))[]
            | "branching.\(map(.k) | join(" and branching.")): must be different branches (all are \(.[0].v | tojson))"),
         (if $p != "trunk" and (($c.statuses.in_review | type) != "string" or ($c.statuses.in_review | length) == 0)
          then "statuses.in_review: must be set with branching.preset \($p), because a task waits In review between its merge and the release (for example in_review: In review)"
          else empty end)
     end),

    # governance (spec scrum-config "Governance block")
    (if $c.governance == null then empty
     elif ($c.governance | type) != "object" then "governance: must be a mapping"
     else
       (if ($c.governance.approvals | is_int) and $c.governance.approvals >= 0 and $c.governance.approvals <= 6 then empty
        else "governance.approvals: must be a whole number from 0 to 6 (got \($c.governance.approvals | tojson))" end),
       (["required_checks", "codeowners"][] as $k
        | if ($c.governance[$k] | type) == "array" and all($c.governance[$k][]; nonempty_string) then empty
          else "governance.\($k): must be a list of non-empty texts (got \($c.governance[$k] | tojson))" end)
     end),

    # deploy (spec scrum-config "Deploy block", deploy-templates "Platform selection")
    (if $c.deploy == null then empty
     elif ($c.deploy | type) != "object" then "deploy: must be a mapping"
     elif ["none", "vercel", "cloudflare", "docker"] | index($c.deploy.platform // "none") then empty
     else "deploy.platform: must be none, vercel, cloudflare or docker (got \($c.deploy.platform | tojson))" end),

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
          else "planning.context_stale_commits: must be a whole number greater than 0 (got \($pl.context_stale_commits | tojson))" end),
         (if ($pl.merge_minutes | is_int) and $pl.merge_minutes >= 0 then empty
          else "planning.merge_minutes: must be a whole number of minutes, 0 or more (got \($pl.merge_minutes | tojson))" end)
     end),

    # misc
    (if ($c.timezone | nonempty_string) then empty else "timezone: must be a time zone name such as UTC or Asia/Ho_Chi_Minh" end),
    (if ($c.branch.pattern | type) == "string" and ($c.branch.pattern | contains("{number}")) then empty
     else "branch.pattern: must contain {number}" end),
    (if ($c.digest.enabled | type) == "boolean" then empty else "digest.enabled: must be true or false" end),
    (if $c.digest.webhook_format == "slack" or $c.digest.webhook_format == "telegram" then empty
     else "digest.webhook_format: must be slack or telegram (got \($c.digest.webhook_format | tojson))" end),

    # language
    (if $c.language == "en" or $c.language == "vi" then empty
     else "language: must be en or vi (got \($c.language | tojson))" end),

    # attention
    (["stale_days", "behind_percent", "review_days"][] as $k
     | if ($c.attention[$k] | is_int) and $c.attention[$k] >= 0 then empty
       else "attention.\($k): must be a whole number, 0 or more (got \($c.attention[$k] | tojson))" end),
    (if ($c.attention.promote_days | is_int) and $c.attention.promote_days > 0 then empty
     else "attention.promote_days: must be a whole number greater than 0 (got \($c.attention.promote_days | tojson))" end),

    # sprint.working_days
    (if ($c.sprint.working_days | type) != "array" or ($c.sprint.working_days | length) == 0
       then "sprint.working_days: must be a non-empty list of weekdays, 1 (Monday) to 7 (Sunday)"
     elif any($c.sprint.working_days[]; (is_int and . >= 1 and . <= 7) | not)
       then "sprint.working_days: values must be 1 (Monday) to 7 (Sunday) (got \($c.sprint.working_days | tojson))"
     elif ($c.sprint.working_days | length) != ($c.sprint.working_days | unique | length)
       then "sprint.working_days: values must not repeat"
     else empty end),
    (if ($c.digest.cron | type) == "string" and ($c.digest.cron | split(" ") | map(select(. != "")) | length) == 5 then empty
     else "digest.cron: must be a 5-field cron expression" end),
    (if ($c.colors | type) == "object" then
       ($c.colors | to_entries[] | select((.value | type) != "string" or (.value | test("^#?[0-9a-fA-F]{6}$") | not))
        | "colors.\(.key): must be a 6-digit hex color such as 0e8a16")
     else "colors: must be a mapping of label name to color" end),

    # team (members, their areas and capacity); logins are compared without case
    (if ($c.team | type) != "array" then "team: must be a list of members, each with a login"
     else
       ($c.team | to_entries[] | .key as $i | .value as $m
        | if ($m | type) != "object" then "team[\($i)]: must be a mapping with a login"
          else
            (if ($m.login | nonempty_string) | not then "team[\($i)].login: is required"
             elif ($m.login | test("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$") | not)
               then "team[\($i)].login: \($m.login | tojson) is not a GitHub login (letters, digits and dashes)"
             else empty end),
            (if $m.areas == null then empty
             elif ($m.areas | type) == "array" and all($m.areas[]; nonempty_string) then empty
             else "team[\($i)].areas: must be a list of non-empty texts (\($m.login // "?"))" end),
            (if $m.capacity == null then empty
             elif ($m.capacity | type) == "number" and $m.capacity > 0 then empty
             else "team[\($i)].capacity: must be a number of points greater than 0 (\($m.login // "?"): got \($m.capacity | tojson))" end),
            (if $m.review_hours == null then empty
             elif ($m.review_hours | type) == "number" and $m.review_hours > 0 then empty
             else "team[\($i)].review_hours: must be a number of hours greater than 0 (\($m.login // "?"): got \($m.review_hours | tojson))" end)
          end),
       ([$c.team[] | objects | .login | strings | ascii_downcase] | group_by(.) | map(select(length > 1) | .[0])[]
        | "team: the login \(tojson) is listed more than once (logins are not case-sensitive)")
     end),

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
            ([$p.status_options.new, $p.status_options.in_progress, $p.status_options.done]
             + (if $c.statuses.in_review == null then [] else [$p.status_options.in_review] end)) as $opts
            | (if $c.statuses.in_review != null and ($p.status_options.in_review | nonempty_string | not)
               then "project.status_options.in_review: must be a non-empty text when statuses.in_review is set" else empty end),
              (if ($opts | unique | length) < ($opts | length)
               then "project.status_options: the options of the statuses in use must be different" else empty end)
          end),
         (if ($p.poll_cron | type) == "string" and ($p.poll_cron | split(" ") | map(select(. != "")) | length) == 5 then empty
          else "project.poll_cron: must be a 5-field cron expression" end)
     end)
  ]
