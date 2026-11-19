# Input: response of share/graphql/project.graphql. --argjson cfg CONFIG
# Output: normalized project metadata (see project_meta in project.jq).
include "project";
project_meta($cfg)
