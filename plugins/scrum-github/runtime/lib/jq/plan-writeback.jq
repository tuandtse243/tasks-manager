# Input: a plan (version 1 or 2). --arg ref ("epic", or a feature or task id) --argjson issue NUMBER.
# Output: the plan in version 2 form with that item's "issue" set. Everything else is unchanged.
include "plan";
normalize
| if $ref == "epic" then .epic.issue = $issue
  else
    .features |= map(
      if .id == $ref then .issue = $issue
      else .tasks |= map(if .id == $ref then .issue = $issue else . end) end)
  end
