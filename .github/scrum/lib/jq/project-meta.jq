# Input: response of share/graphql/project.graphql. --argjson cfg CONFIG
# Output: normalized project metadata (see project_meta in scrum.jq).
include "scrum";
project_meta($cfg)
