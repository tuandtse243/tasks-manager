---
name: sprint-status
description: Show Scrum sprint progress from GitHub - tasks and story points per person and status (New, In progress, Done), percent of points done, unestimated tasks, days left, and the minutes of work and review left per person when tasks have time estimates. Use when the user asks how the sprint is going, who is working on what, or what is left.
---

# Sprint status

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository. It only reads from GitHub.

1. Run `scrum status [SPRINT]` (no name = current sprint).
   Add `--json` if you need the numbers for further analysis.
2. Show the table as it is, then add a short reading: what is done, who has the most open work,
   whether the remaining points fit the days left, unestimated tasks to estimate.
   When tasks of the sprint have time estimates, the table has two more columns, "Work left" and
   "Review left" (minutes of the tasks not done), and a line with the tasks not done that have no
   time estimate. When AI does the work, review time is usually the bottleneck: say who has the
   most review left. Without any time estimate the table has no time columns.
3. Answer the user's actual question (for example "what is David doing?") from the table.

For a chart, use `/scrum-github:sprint-report`.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
