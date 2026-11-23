# -n --argjson cfg CONFIG --argjson task {title, body, acceptance, subtasks, points, assignees, bug, estimate}
#    --argjson milestone NUMBER|null [--arg parent NUMBER] [--argjson strings STRINGS]
# Output: {error} or the JSON body for POST /repos/{owner}/{repo}/issues.
# A null milestone (backlog) sends no "milestone" key. A task with an estimate gets the
# "estimate" block in its body (spec time-estimate); $strings gives its line's language.
include "scrum";
($task.points) as $p
| if (($task.title // "") | gsub("^\\s+|\\s+$"; "")) == "" then {error: "a task needs a title"}
  elif $p != null and (($cfg.points.scale | any(.[]; . == $p)) | not) then
    {error: "\($p) is not an allowed point value. Allowed: \($cfg.points.scale | map(tostring) | join(", "))"}
  else
    { title: $task.title,
      body: (task_issue_body($task; $ARGS.named.parent)
             | if ($task.estimate | clean_estimate) != null then set_estimate($task.estimate; $ARGS.named.strings // null) else . end),
      labels: ([status_label($cfg; "new")]
               + (if $p != null then [points_label($cfg; $p)] else [] end)
               + (if $task.bug == true then [$cfg.labels.bug] else [] end)),
      assignees: ($task.assignees // []) }
    + (if $milestone == null then {} else {milestone: $milestone} end)
  end
