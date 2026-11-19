---
name: sprint-close
description: Close a Scrum sprint on GitHub - show velocity, done tasks and unfinished tasks, then after confirmation record the velocity, move unfinished tasks to the next sprint and close the milestone. Use for sprint review or end-of-sprint wrap-up.
---

# Close a sprint

The script is `${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum`; run it with `bash` from the root of the
target repository.

1. **Plan.** Run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" sprint close [SPRINT]`
   (no sprint name = the current sprint). This changes nothing. Show the user the velocity,
   the done tasks, the tasks that will be carried over and the next sprint.
2. **Confirm.** Ask the user to confirm. If the next sprint does not exist yet, say that it will be
   created with the dates shown and ask for that too.
3. **Apply.** Only after a yes, run `scrum sprint close [SPRINT] --yes`, adding `--create-next`
   when the user agreed to create the next sprint.
4. Report: velocity recorded, tasks moved, milestone closed. Suggest `/scrum-github:sprint-report`
   for the final burndown, generated before closing if the user wants it.

Never pass `--yes` without the user's confirmation in this conversation.
`gh` cannot read its keychain token inside the Claude Code sandbox; run outside it if needed.
