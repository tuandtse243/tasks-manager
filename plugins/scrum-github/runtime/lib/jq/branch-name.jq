# Input: an issue. --argjson cfg CONFIG. Output: branch name from branch.pattern ({number}, {slug}).
include "scrum";
(.number | tostring) as $n
| (.title | slug) as $s
| $cfg.branch.pattern | gsub("\\{number\\}"; $n) | gsub("\\{slug\\}"; $s)
