---
name: backlog
description: Show the Scrum backlog on GitHub - open tasks with no sprint (milestone), with points, assignees, parent feature and which open tasks block them, plus totals and how many are not estimated. Read-only. Use when the user asks what is in the backlog, what is left to plan, or what could go into the next sprint.
---

# Backlog

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository. It only reads from GitHub.

1. Run `scrum backlog` (add `--json` if you need the data for further analysis).
2. Show the list as it is, then a short reading: how many points wait, which tasks are not
   estimated yet, which are blocked and by what.
3. Answer the user's actual question from the list. To put tasks into a sprint, suggest
   `/scrum-github:sprint-fill`; to estimate, assign or drop a task, `/scrum-github:task`.

"blocked-by not checked" means the task is past the first 50 of the backlog, whose blockers are
the only ones read, or GitHub did not return them; it does not mean the task is free.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
