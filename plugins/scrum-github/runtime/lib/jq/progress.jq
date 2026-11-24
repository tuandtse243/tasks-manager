# -n --argjson cfg CONFIG --argjson sprint MILESTONE --argjson issues ISSUES --arg today DATE
# With a working branch (standard, environments) the output also has `review`: the tasks In review
# and where they are (review_locations); in trunk it is as before.
include "scrum";
progress($cfg; $sprint; $issues; $today)
+ (if has_working_branch($cfg) then {review: ($issues | review_locations($cfg))} else {} end)
