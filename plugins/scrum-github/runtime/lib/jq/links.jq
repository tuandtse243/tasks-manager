# -n --arg body TEXT --arg repo owner/name
# Output: {issues: [numbers linked with a closing keyword], solve: [numbers written as "Solve #n"]}
# HTML comments are ignored, like GitHub does. References to other repositories are ignored.
($body | gsub("<!--[\\s\\S]*?-->"; "")) as $b
| ($repo | ascii_downcase) as $r
| { issues: ([ $b | capture("(?<![A-Za-z0-9_])(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\\s+(?:(?<repo>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+))?#(?<num>[0-9]+)(?![0-9])"; "gi")
                | select(.repo == null or (.repo | ascii_downcase) == $r) | .num | tonumber ] | unique),
    solve: ([ $b | capture("(?<![A-Za-z0-9_])solve[sd]?:?\\s+#(?<num>[0-9]+)(?![0-9])"; "gi") | .num | tonumber ] | unique) }
