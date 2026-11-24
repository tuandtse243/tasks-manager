# -n --argjson cfg CONFIG --argjson issue ISSUE --argjson draft BOOL
#    --arg kind pr_open|pr_draft|pr_closed|pr_merged|pr_promoted|issue_closed|issue_reopened|issue_opened
#    --arg base BRANCH --arg head BRANCH (of the pull request; "" when unknown)
# pr_open: opened, reopened, edited or ready for review ($draft tells which); pr_draft: converted
# to draft; pr_closed: closed without merging. Without statuses.in_review, pr_open moves New to
# In progress whatever $draft says, and pr_draft and pr_closed change nothing (as before).
# pr_merged follows the merge table of design 4: in trunk Done and close; with a working branch
# (standard, environments) a merge into the working branch keeps the task open and In review with
# that branch's location label, a hotfix merged into the release branch sets Done and closes, and
# release (handled by `scrum release finish`), promotion, back-merge and any other merge change
# nothing. pr_promoted: the task is contained in a promotion merged into $base (staging): its
# location label becomes that of $base. A Done task never moves back.
# Output: {skip: reason or null, labels: new label list or null, close: bool}
include "scrum";
($ARGS.named.draft // false) as $draft
| ($ARGS.named.base // "") as $base
| ($ARGS.named.head // "") as $head
| def keep($why): {skip: $why, labels: null, close: false};
# move($role; $close; $loc): status $role and, when $loc is not false, the location label of the
# branch $loc (null: no location label).
def move($role; $close; $loc):
  ($issue | labels_with_status($cfg; $role)
   | if $loc == false then . else {labels: .} | labels_with_location($cfg; $loc) end) as $new
  | if (($new | sort) == ($issue | label_names | sort)) and ($close | not) then keep("already \($role)")
    else {skip: null, labels: (if ($new | sort) == ($issue | label_names | sort) then null else $new end), close: $close} end;
def move($role; $close): move($role; $close; false);
# A merged pull request when the preset has a working branch.
def merged_with_branches:
  ($issue | task_role($cfg)) as $role
  | pr_kind($cfg; $head; $base) as $pk
  | if $role == "done" then keep("already done")
    elif $pk == "hotfix" then move("done"; $issue.state == "open"; null)
    elif $pk == "release" then keep("released by scrum release finish")
    elif $pk == "promotion" then keep("promotion: handled for the tasks it contains")
    elif $pk == "back_merge" then keep("back-merge")
    elif $issue.state != "open" then keep("issue is closed")
    elif $base != "" and $base == working_branch($cfg) then
      move(if review_on($cfg) then "in_review" else $role end; false; $base)
    else keep("merged into \(if $base == "" then "an unknown branch" else $base end), not the working branch") end;
if ($issue | is_pr) then keep("is a pull request")
elif ($issue | is_task($cfg) | not) then keep("feature or meta issue")
elif ($kind == "pr_open" or $kind == "pr_draft" or $kind == "pr_closed") and $issue.state != "open" then keep("issue is closed")
elif (review_on($cfg) | not) and ($kind == "pr_open" or $kind == "pr_draft" or $kind == "pr_closed") then
  if $kind == "pr_open" then
    if ($issue | task_role($cfg)) != "new" then keep("already \($issue | task_role($cfg))")
    else move("in_progress"; false) end
  else keep("no In review status") end
# A task already merged into a long-lived branch (location label) is waiting for the release:
# another pull request moving to draft or closing does not move it back.
elif ($kind == "pr_open" or $kind == "pr_draft" or $kind == "pr_closed") and ($issue | task_location($cfg)) != null
     and ($issue | task_role($cfg)) == "in_review" then keep("already on \($issue | task_location($cfg))")
elif $kind == "pr_open" and ($draft | not) then
  if ["new", "in_progress"] | index($issue | task_role($cfg)) then move("in_review"; false)
  else keep("already \($issue | task_role($cfg))") end
elif $kind == "pr_open" or $kind == "pr_draft" then
  if ["new", "in_review"] | index($issue | task_role($cfg)) then move("in_progress"; false)
  else keep("already \($issue | task_role($cfg))") end
elif $kind == "pr_closed" then
  if ($issue | task_role($cfg)) == "in_review" then move("in_progress"; false)
  else keep("not in review") end
elif $kind == "pr_merged" and has_working_branch($cfg) then merged_with_branches
elif $kind == "pr_merged" then move("done"; $issue.state == "open")
elif $kind == "pr_promoted" then
  if (has_working_branch($cfg) | not) then keep("no working branch")
  elif $issue.state != "open" or ($issue | task_role($cfg)) != "in_review" then keep("not in review")
  elif ($issue | task_location($cfg)) == null then keep("not on a branch")
  elif $base == "" then keep("no base branch")
  else move("in_review"; false; $base) end
elif $kind == "issue_closed" then
  if ($issue | is_completed) then move("done"; false; if has_working_branch($cfg) then null else false end) else keep("closed as not planned") end
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
