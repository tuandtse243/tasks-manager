# -n --argjson cfg CONFIG --argjson task {title, body, acceptance, subtasks, points, assignees, bug}
#    --argjson milestone NUMBER|null [--arg parent NUMBER]
# Output: {error} or the JSON body for POST /repos/{owner}/{repo}/issues.
# A null milestone (backlog) sends no "milestone" key.
include "scrum";
($task.points) as $p
| if (($task.title // "") | gsub("^\\s+|\\s+$"; "")) == "" then {error: "a task needs a title"}
  elif $p != null and (($cfg.points.scale | any(.[]; . == $p)) | not) then
    {error: "\($p) is not an allowed point value. Allowed: \($cfg.points.scale | map(tostring) | join(", "))"}
  else
    { title: $task.title,
      body: task_issue_body($task; $ARGS.named.parent),
      labels: ([status_label($cfg; "new")]
               + (if $p != null then [points_label($cfg; $p)] else [] end)
               + (if $task.bug == true then [$cfg.labels.bug] else [] end)),
      assignees: ($task.assignees // []) }
    + (if $milestone == null then {} else {milestone: $milestone} end)
  end
