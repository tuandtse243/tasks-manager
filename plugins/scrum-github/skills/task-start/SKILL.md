---
name: task-start
description: Start working on a Scrum task - assign it to me if unassigned, set its status to In progress and create or check out its branch (feat/<number>-<slug>). Use when the user says they start, pick up or work on issue/task #N.
---

# Start a task

The script is `${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum`; run it with `bash` from the root of the
target repository (it creates a local branch there).

1. Get the issue number from the user's request.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" task start N`.
3. Report the branch, the status change and any note (for example the task is assigned to someone
   else). Remind the user to write `Closes #N` in the pull request description; the PR check
   fails without it, and merging the PR moves the task to Done.

If git refuses to switch branches because of uncommitted changes, tell the user; nothing was
changed on GitHub in that case.
`gh` cannot read its keychain token inside the Claude Code sandbox; run outside it if needed.
