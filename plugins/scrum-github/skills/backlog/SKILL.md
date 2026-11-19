---
name: backlog
description: Show the Scrum backlog on GitHub - open tasks with no sprint (milestone), with points, assignees, parent feature and which open tasks block them, plus totals and how many are not estimated. Read-only. Use when the user asks what is in the backlog, what is left to plan, or what could go into the next sprint.
---

# Backlog

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.
Run it from the root of the target repository. It only reads from GitHub.

1. Run `scrum backlog` (add `--json` if you need the data for further analysis).
2. Show the list as it is, then a short reading: how many points wait, which tasks are not
   estimated yet, which are blocked and by what.
3. Answer the user's actual question from the list. To put tasks into a sprint, suggest
   `/scrum-github:sprint-fill`; to estimate, assign or drop a task, `/scrum-github:task`.

"blocked-by not checked" means the task is past the first 50 of the backlog, whose blockers are
the only ones read, or GitHub did not return them; it does not mean the task is free.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
