# -n --argjson cfg CONFIG --argjson sprint MILESTONE --argjson issues ISSUES --argjson ms MILESTONES
#    --arg today DATE --argjson off SECONDS --arg now ISO --arg repo owner/name
#    --argjson hissues ISSUES_WITH_HISTORY --argjson attention ATTENTION --argjson strings STRINGS
#    --argjson limited BOOL (history read for only part of the issues)
# Data embedded in the HTML report.
include "scrum";
($sprint | sprint_info) as $s
| { repo: $repo,
    generated_at: $now,
    today: $today,
    statuses: {new: $cfg.statuses.new, in_progress: $cfg.statuses.in_progress, done: $cfg.statuses.done},
    goal: ([($s.description // "") | capture("\\*\\*Goal:\\*\\* (?<g>[^\n]+)")] | .[0].g),
    progress: progress($cfg; $sprint; $issues; $today),
    burndown: burndown($cfg; $sprint; $hissues; $today; $off),
    attention: $attention.lines,
    strings: $strings,
    language: ($cfg.language // "en"),
    history_limited: $limited,
    velocity: ([$ms[] | sprint_info | select(.state == "closed")] | sort_by(.end // "") | .[-6:]
               | map({title, end, velocity})) }
