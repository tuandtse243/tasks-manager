# Input: an issue. --argjson cfg CONFIG --arg role new|in_progress|done
# Output: {labels: [...], changed: bool}
include "scrum";
labels_with_status($cfg; $role) as $new
| {labels: $new, changed: (($new | sort) != (label_names | sort))}
