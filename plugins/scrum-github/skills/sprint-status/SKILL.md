---
name: sprint-status
description: Show Scrum sprint progress from GitHub - tasks and story points per person and status (New, In progress, Done), percent of points done, unestimated tasks and days left. Use when the user asks how the sprint is going, who is working on what, or what is left.
---

# Sprint status

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.
Run it from the root of the target repository. It only reads from GitHub.

1. Run `scrum status [SPRINT]` (no name = current sprint).
   Add `--json` if you need the numbers for further analysis.
2. Show the table as it is, then add a short reading: what is done, who has the most open work,
   whether the remaining points fit the days left, unestimated tasks to estimate.
3. Answer the user's actual question (for example "what is David doing?") from the table.

For a chart, use `/scrum-github:sprint-report`.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
