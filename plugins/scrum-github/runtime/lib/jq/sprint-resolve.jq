# -n --argjson ms MILESTONES --argjson cfg CONFIG --arg title TITLE --arg today DATE
# Prints the milestone named $title (case-insensitive), or the current sprint when $title is empty, or null.
include "scrum";
if $title != "" then
  ([$ms[] | select((.title | ascii_downcase) == ($title | ascii_downcase))] | .[0])
else
  ($ms | current_sprint($today))
end
