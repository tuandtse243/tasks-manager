# The one next step (spec: next-step-guidance), first true condition wins.
# -n --argjson init BOOL --argjson pushed BOOL --argjson sprint MILESTONE_OR_NULL
#    --argjson issues ISSUES_OF_THE_SPRINT --arg me LOGIN --arg today YYYY-MM-DD --argjson cfg CONFIG
#    --argjson backlog_count N (tasks in the backlog; only needed when the sprint has no task)
#    [--argjson run_open {id}|null]  an unfinished /scrum-github:run in this working tree
#    [--argjson ai_blocked {"N": [open blocking numbers]|null}]  blockers of my ai-ready tasks
#    [--argjson release {sprint, tag, since, issues}|null]  the most recently closed sprint, the
#        latest version tag on the default branch (null: none yet) and its commit date, and the
#        issues of that sprint; null or left out when not read (then there is no release step)
# Output: {step, message, command, issues: [numbers]}
include "scrum";
($ARGS.named.run_open // null) as $run_open
| ($ARGS.named.ai_blocked // {}) as $ai_blocked
| ($ARGS.named.release // null) as $release
| 
def step($id; $message; $command; $issues): {step: $id, message: $message, command: $command, issues: $issues};
def refs: map("#\(.number) \"\(.title)\"") | join(", ");
# Done tasks of the last closed sprint that are in no version yet (spec next-step-guidance
# "Suggest a release"): closed after the latest version tag.
def unreleased:
  if $release == null then []
  else [$release.issues | release_tasks($cfg; $release.since; null)[] | .number] | sort end;
def release_step:
  unreleased as $u
  | if ($u | length) == 0 then empty
    else step("release"; "\($release.sprint) is closed and \($u | length) of its Done task\(if ($u | length) == 1 then " is" else "s are" end) in no version yet\(if $release.tag == null then "" else " (latest: \($release.tag))" end). Publish a version with the tag and release notes.";
              "/scrum-github:release"; $u) end;

if $init | not then
  step("init"; "Scrum on GitHub is not set up in this repository yet."; "/scrum-github:init"; [])
elif $pushed | not then
  step("push"; "The workflows are not on the default branch on GitHub yet, so statuses will not change on their own. Commit and push .github/ (directly or through a pull request).";
       "git add .github && git commit -m \"Set up Scrum on GitHub\" && git push"; [])
elif $sprint == null then
  first(release_step, step("sprint-new"; "There is no open sprint."; "/scrum-github:sprint-new"; []))
else
  ($sprint | sprint_info) as $s
  | if $s.end != null and $today > $s.end then
      step("sprint-close"; "\($s.title) ended on \($s.end). Close it to record its velocity and carry over unfinished tasks.";
           "/scrum-github:sprint-close"; [])
    else
      ($issues | report_tasks($cfg) | sort_by(.number)) as $t
      | [$t[] | select(._role == "in_progress" and (._who | index($me)))] as $mine
      | [$t[] | select(._role != "done" and ._pts == null)] as $unestimated
      | [$t[] | select(._role == "in_progress" and (._who | length) == 0)] as $orphans
      | [$t[] | select(._role == "new")] as $new
      | ([$new[] | select(._who | index($me))] + [$new[] | select((._who | length) == 0)]) as $pickable
      # ai-ready tasks that nothing open blocks (a task whose blockers were not read counts as free)
      | [$new[] | select(._who | index($me)) | select(has_label_ci($cfg.labels.ai_ready))
         | select((($ai_blocked[.number | tostring] // []) | length) == 0)] as $ai_ready
      | if ($t | length) == 0 and $backlog_count > 0 then
          step("fill"; "\($s.title) has no tasks yet, and \($backlog_count) task\(if $backlog_count == 1 then " waits" else "s wait" end) in the backlog. Choose what fits its capacity.";
               "/scrum-github:sprint-fill"; [])
        elif $run_open != null then
          step("run-resume"; "Your run \($run_open.id) of AI agents is not finished. Continue it (or close it) before starting other work.";
               "/scrum-github:run"; [])
        elif ($mine | length) > 0 then
          step("continue"; "You are working on \($mine | refs). When it is done, open its pull request.";
               "/scrum-github:task-pr"; [$mine[].number])
        elif (unreleased | length) > 0 then
          release_step
        elif ($unestimated | length) > 0 then
          step("estimate"; "\($unestimated | refs) \(if ($unestimated | length) == 1 then "has" else "have" end) no points. Estimate with one of \($cfg.points.scale | map(tostring) | join(", ")).";
               "gh issue edit \($unestimated[0].number) --add-label \"\($cfg.points.label_prefix)N\""; [$unestimated[].number])
        elif ($orphans | length) > 0 then
          step("assign"; "\($orphans | refs) \(if ($orphans | length) == 1 then "is" else "are" end) In progress but assigned to nobody.";
               "gh issue edit \($orphans[0].number) --add-assignee LOGIN"; [$orphans[].number])
        elif ($ai_ready | length) > 0 then
          step("run"; "\($ai_ready | refs) \(if ($ai_ready | length) == 1 then "is" else "are" end) yours and labelled \($cfg.labels.ai_ready): AI agents can work \(if ($ai_ready | length) == 1 then "it" else "them in parallel" end), each in its own worktree, and open one pull request for your review.";
               "/scrum-github:run"; [$ai_ready[].number])
        elif ($pickable | length) > 0 then
          ($pickable[0]) as $p
          | step("start"; "Pick up #\($p.number) \"\($p.title)\"\(if ($p._who | index($me)) then " (assigned to you)" else "" end).";
                 "/scrum-github:task-start \($p.number)"; [$p.number])
        else
          days_left($cfg; $s; $today) as $d
          | step("done"; "No task left to pick up in \($s.title)\(if $d == null then "" else " (\($d) day\(if $d == 1 then "" else "s" end) left)" end).";
                 "/scrum-github:sprint-status"; [])
        end
    end
end
