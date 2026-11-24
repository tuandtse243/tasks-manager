# -n --argjson cfg CONFIG --argjson sprint MILESTONE --argjson issues ISSUES --arg today DATE --argjson off SECONDS
include "scrum";
burndown($cfg; $sprint; $issues; $today; $off)
