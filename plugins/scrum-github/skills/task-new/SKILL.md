---
name: task-new
description: Create a Scrum task as a GitHub issue in the current (or a named) sprint, or in the backlog when no sprint is open or the user asks for it, with status New, story points, assignees and an optional bug label. Use when the user wants to add a task, ticket, story or bug to the sprint or the backlog.
---

# Create a task

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository.

1. Take from the user's request: title (required), description, points, assignees (GitHub logins),
   sprint name or "backlog", and whether it is a bug. Do not invent points or assignees the user did not give.
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
   `scrum task new --title "..." [--body "..."] [--points N] [--assignee LOGIN]... [--sprint "Sprint N" | --backlog] [--bug]`
   Without `--sprint` the task goes into the open sprint, or into the backlog (no milestone) when
   no sprint is open. Pass `--backlog` when the user wants it in the backlog although a sprint is
   open. `--sprint` and `--backlog` together are refused.
3. Report the issue number, the link, and where the task went: the sprint named in the output
   ("in Sprint 5") or the backlog ("in the backlog"). When it went to the backlog because no
   sprint is open, say so and mention `/scrum-github:sprint-new`. If the script rejects the
   points, show the allowed values. If it warns that a login is not in the team, tell the user
   (the task was still created and assigned).

For several tasks from one feature, `/scrum-github:plan` is a better fit.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
