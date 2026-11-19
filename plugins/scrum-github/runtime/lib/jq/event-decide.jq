# -n --argjson cfg CONFIG --arg kind pr_open|pr_merged|issue_closed|issue_reopened|issue_opened --argjson issue ISSUE
# Output: {skip: reason or null, labels: new label list or null, close: bool}
include "scrum";
def keep($why): {skip: $why, labels: null, close: false};
def move($role; $close):
  ($issue | labels_with_status($cfg; $role)) as $new
  | if (($new | sort) == ($issue | label_names | sort)) and ($close | not) then keep("already \($role)")
    else {skip: null, labels: (if ($new | sort) == ($issue | label_names | sort) then null else $new end), close: $close} end;
if ($issue | is_pr) then keep("is a pull request")
elif ($issue | is_task($cfg) | not) then keep("feature or meta issue")
elif $kind == "pr_open" then
  if $issue.state != "open" then keep("issue is closed")
  elif ($issue | task_role($cfg)) != "new" then keep("already \($issue | task_role($cfg))")
  else move("in_progress"; false) end
elif $kind == "pr_merged" then move("done"; $issue.state == "open")
elif $kind == "issue_closed" then
  if ($issue | is_completed) then move("done"; false) else keep("closed as not planned") end
elif $kind == "issue_reopened" then
  # The board sync sets "New" before reopening a card dragged out of Done: keep it.
  if ($issue | has_label(status_label($cfg; "new"))) and ($issue | has_label(status_label($cfg; "done")) | not)
  then keep("already new") else move("in_progress"; false) end
elif $kind == "issue_opened" then
  # Issue form: "### Points\n\n7" -> points label, when the issue has none yet.
  ([($issue.body // "") | capture("###[ ]*Points[ ]*\\r?\\n+[ ]*(?<p>[0-9]+)[ ]*(\\r?\\n|$)")] | .[0].p
   | if . == null then null else (tonumber? // null) end) as $p
  | if $p == null then keep("no points in the issue form")
    elif ($issue | task_points($cfg)) != null then keep("already has points")
    elif ($cfg.points.scale | any(.[]; . == $p) | not) then keep("points \($p) not in the scale")
    else {skip: null, labels: (($issue | label_names) + [points_label($cfg; $p)]), close: false} end
else keep("unknown event kind \($kind)") end
