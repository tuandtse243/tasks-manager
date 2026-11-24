# The version to release and its tasks (spec release, design 2 and 4).
# -n --argjson cfg CONFIG
#    --argjson prev {name, version: [X, Y, Z], date} | null   the previous version tag
#    --argjson issues ISSUES        closed issues since the previous tag, or those of the sprints
#    --argjson since TIME|null      keep tasks closed after it (null with --sprint or no tag)
#    --argjson until TIME|null      keep tasks closed until it (a tag created by an earlier run)
#    --arg version VERSION          the version the user gave, or ""
#    [--argjson contained [N]]      presets with a working branch (spec release-pr "Tasks of a
#        release"): the tasks are the issues with these numbers (In review, contained in the start
#        ref), not the closed ones; $since and $until are then ignored
#    [--argjson other [{number, title}]]  merged pull requests in the release that link no task
#        (spec release-pr "Pull requests without a task"): listed under "Other", never change the
#        bump; a release with only these is a patch
# Output: {error, nothing, previous, suggested, version, tag, bump, reasons, tasks, other}
#   bump: first | major | minor | patch | given; reasons: task numbers by kind
#   tasks: [{number, title, kind: breaking | feature | bug, parent}], by number
include "scrum";
($cfg.release.tag_prefix // "") as $prefix
| ($ARGS.named.contained // null) as $contained
| ($ARGS.named.other // [] | sort_by(.number) | map({number, title})) as $other
| (if $contained == null then $issues | release_tasks($cfg; $since; $until)
   else [$issues[] | select(.number as $n | $contained | index($n)) | select(is_task($cfg))] | unique_by(.number)
   end | sort_by(.number)) as $found
| [$found[]
   | {number, title,
      kind: (if has_label_ci($cfg.release.breaking_label) then "breaking"
             elif has_label_ci($cfg.labels.bug) then "bug" else "feature" end),
      parent: parent_number}] as $tasks
| {breaking: [$tasks[] | select(.kind == "breaking") | .number],
   features: [$tasks[] | select(.kind == "feature") | .number],
   bugs: [$tasks[] | select(.kind == "bug") | .number]} as $reasons
| (if $prev == null then {bump: "first", v: ($cfg.release.first_version | semver_of(""))}
   else $prev.version as [$x, $y, $z]
   | if ($reasons.breaking | length) > 0 then {bump: "major", v: [$x + 1, 0, 0]}
     elif ($reasons.features | length) > 0 then {bump: "minor", v: [$x, $y + 1, 0]}
     else {bump: "patch", v: [$x, $y, $z + 1]} end
   end) as $s
| ($version | semver_of($prefix)) as $given
| (if $version == "" then null
   elif $given == null then "\($version) is not a version: use X.Y.Z, such as \($s.v | semver_text)"
   elif $prev != null and $given <= $prev.version then "the version must be greater than \($prev.name) (got \($version))"
   else null end) as $error
| (if $version != "" and $given != null then $given else $s.v end) as $v
| { error: $error,
    nothing: (($tasks | length) == 0 and ($other | length) == 0),
    previous: (if $prev == null then null else {tag: $prev.name, version: ($prev.version | semver_text), date: ($prev.date // null)} end),
    suggested: ($s.v | semver_text),
    version: ($v | semver_text),
    tag: ($prefix + ($v | semver_text)),
    bump: (if $version != "" then "given" else $s.bump end),
    reasons: $reasons,
    tasks: $tasks,
    other: $other }
