---
name: task-new
description: Create a Scrum task as a GitHub issue in the current (or a named) sprint, with status New, story points, assignees and an optional bug label. Use when the user wants to add a task, ticket, story or bug to the sprint.
---

# Create a task

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.
Run it from the root of the target repository.

1. Take from the user's request: title (required), description, points, assignees (GitHub logins),
   sprint name, and whether it is a bug. Do not invent points or assignees the user did not give.
   If they ask you to estimate, propose points from the scale in `.github/scrum.yml` and say why.
   A description the user wrote goes in as it is. If they ask you to write it, read
   `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/triage/AGENT-BRIEF.md` and apply its four principles
   with this adapter (where they differ, the adapter wins): use the principles, not the
   template or the "Agent Brief" comment; write the behaviour now and the behaviour wanted,
   then acceptance criteria as a `- [ ]` checklist, each checkable on its own, then one line
   "Out of scope: ..." when something could be mistaken for part of the task; cite types,
   functions or config shapes, not file paths or line numbers. Show the description and
   create the issue only after the user agrees with it.
2. Run:
   `scrum task new --title "..." [--body "..."] [--points N] [--assignee LOGIN]... [--sprint "Sprint N"] [--bug]`
3. Report the issue number and link. If the script rejects the points, show the allowed values.

For several tasks from one feature, `/scrum-github:plan` is a better fit.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
