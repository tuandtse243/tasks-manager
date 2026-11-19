---
name: sprint-status
description: Show Scrum sprint progress from GitHub - tasks and story points per person and status (New, In progress, Done), percent of points done, unestimated tasks and days left. Use when the user asks how the sprint is going, who is working on what, or what is left.
---

# Sprint status

The script is `${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum`; run it with `bash` from the root of the
target repository. It only reads from GitHub.

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" status [SPRINT]` (no name = current sprint).
   Add `--json` if you need the numbers for further analysis.
2. Show the table as it is, then add a short reading: what is done, who has the most open work,
   whether the remaining points fit the days left, unestimated tasks to estimate.
3. Answer the user's actual question (for example "what is David doing?") from the table.

For a chart, use `/scrum-github:sprint-report`.
`gh` cannot read its keychain token inside the Claude Code sandbox; run outside it if needed.
