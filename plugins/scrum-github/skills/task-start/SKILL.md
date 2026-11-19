---
name: task-start
description: Start working on a Scrum task - assign it to me if unassigned, set its status to In progress and create or check out its branch (feat/<number>-<slug>). Use when the user says they start, pick up or work on issue/task #N.
---

# Start a task

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.
Run it from the root of the target repository (it creates a local branch there).

1. Get the issue number from the user's request.
2. Run `scrum task start N`.
3. Report the branch, the status change and any note (for example the task is assigned to someone
   else). Say that `/scrum-github:task-pr` writes the pull request description when the work
   is ready, and that a description written by hand needs `Closes #N`: the PR check fails
   without it, and merging the PR moves the task to Done.

If git refuses to switch branches because of uncommitted changes, tell the user; nothing was
changed on GitHub in that case.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
