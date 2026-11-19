---
name: task-new
description: Create a Scrum task as a GitHub issue in the current (or a named) sprint, with status New, story points, assignees and an optional bug label. Use when the user wants to add a task, ticket, story or bug to the sprint.
---

# Create a task

The script is `${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum`; run it with `bash` from the root of the
target repository.

1. Take from the user's request: title (required), description, points, assignees (GitHub logins),
   sprint name, and whether it is a bug. Do not invent points or assignees the user did not give.
   If they ask you to estimate, propose points from the scale in `.github/scrum.yml` and say why.
2. Run:
   `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" task new --title "..." [--body "..."] [--points N] [--assignee LOGIN]... [--sprint "Sprint N"] [--bug]`
3. Report the issue number and link. If the script rejects the points, show the allowed values.

For several tasks from one feature, `/scrum-github:plan` is a better fit.
`gh` cannot read its keychain token inside the Claude Code sandbox; run outside it if needed.
