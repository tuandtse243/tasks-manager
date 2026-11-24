# -n --arg body TEXT --arg repo owner/name
# Output: {issues: [numbers linked with a closing keyword], solve: [numbers written as "Solve #n"]}
# HTML comments are ignored, like GitHub does. References to other repositories are ignored.
include "scrum";
($body | gsub("<!--[\\s\\S]*?-->"; "")) as $b
| { issues: ($body | closing_refs($repo)),
    solve: ([ $b | capture("(?<![A-Za-z0-9_])solve[sd]?:?\\s+#(?<num>[0-9]+)(?![0-9])"; "gi") | .num | tonumber ] | unique) }
