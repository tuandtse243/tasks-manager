# -n --argjson cfg CONFIG --argjson sprint MILESTONE --argjson issues ISSUES --arg today DATE
include "scrum";
progress($cfg; $sprint; $issues; $today)
