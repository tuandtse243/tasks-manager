---
name: sprint-close
description: Close a Scrum sprint on GitHub - show velocity, done tasks and unfinished tasks, then after confirmation record the velocity, move unfinished tasks to the next sprint and close the milestone. Use for sprint review or end-of-sprint wrap-up.
---

# Close a sprint

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository.

1. **Plan.** Run `scrum sprint close [SPRINT]`
   (no sprint name = the current sprint). This changes nothing. Show the user the velocity,
   the done tasks, the tasks that will be carried over and the next sprint.
2. **Confirm.** Ask the user to confirm. If the next sprint does not exist yet, say that it will be
   created with the dates shown and ask for that too.
3. **Apply.** Only after a yes, run `scrum sprint close [SPRINT] --yes`, adding `--create-next`
   when the user agreed to create the next sprint.
4. Report: velocity recorded, tasks moved, milestone closed. Suggest `/scrum-github:sprint-report`
   for the final burndown, generated before closing if the user wants it.
5. When the sprint had Done tasks, the command suggests `/scrum-github:release --sprint "<sprint>"`:
   offer to publish a version with them. Releasing is the user's choice; it has its own preview and
   confirmation.

Never pass `--yes` without the user's confirmation in this conversation.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
