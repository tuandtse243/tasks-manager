# -n --argjson cfg CONFIG --argjson issue ISSUE --argjson draft BOOL
#    --arg kind pr_open|pr_draft|pr_closed|pr_merged|issue_closed|issue_reopened|issue_opened
# pr_open: opened, reopened, edited or ready for review ($draft tells which); pr_draft: converted
# to draft; pr_closed: closed without merging. Without statuses.in_review, pr_open moves New to
# In progress whatever $draft says, and pr_draft and pr_closed change nothing (as before).
# Output: {skip: reason or null, labels: new label list or null, close: bool}
include "scrum";
($ARGS.named.draft // false) as $draft
| def keep($why): {skip: $why, labels: null, close: false};
def move($role; $close):
  ($issue | labels_with_status($cfg; $role)) as $new
  | if (($new | sort) == ($issue | label_names | sort)) and ($close | not) then keep("already \($role)")
    else {skip: null, labels: (if ($new | sort) == ($issue | label_names | sort) then null else $new end), close: $close} end;
if ($issue | is_pr) then keep("is a pull request")
elif ($issue | is_task($cfg) | not) then keep("feature or meta issue")
elif ($kind == "pr_open" or $kind == "pr_draft" or $kind == "pr_closed") and $issue.state != "open" then keep("issue is closed")
elif (review_on($cfg) | not) and ($kind == "pr_open" or $kind == "pr_draft" or $kind == "pr_closed") then
  if $kind == "pr_open" then
    if ($issue | task_role($cfg)) != "new" then keep("already \($issue | task_role($cfg))")
    else move("in_progress"; false) end
  else keep("no In review status") end
elif $kind == "pr_open" and ($draft | not) then
  if ["new", "in_progress"] | index($issue | task_role($cfg)) then move("in_review"; false)
  else keep("already \($issue | task_role($cfg))") end
elif $kind == "pr_open" or $kind == "pr_draft" then
  if ["new", "in_review"] | index($issue | task_role($cfg)) then move("in_progress"; false)
  else keep("already \($issue | task_role($cfg))") end
elif $kind == "pr_closed" then
  if ($issue | task_role($cfg)) == "in_review" then move("in_progress"; false)
  else keep("not in review") end
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
