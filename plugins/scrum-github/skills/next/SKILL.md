---
name: next
description: Say the one thing to do next in Scrum on GitHub - set up, push .github/, create or close a sprint, continue your task in progress, estimate or assign a task, or pick up the next New task - with the command for it. Read-only. Use when the user asks what to do next, what to work on, or how to continue after setup.
---

# What next

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.

1. From the root of the repository, run `scrum next`. It prints one step and its command, chosen
   in this order: set up → push `.github/` → create a sprint → close an overdue sprint → fill an
   empty sprint from the backlog → your task in progress → tasks without points, or In progress with nobody assigned → the next New task
   (yours first, then unassigned) → nothing left.
2. Tell the user that step in one or two sentences, in their words, with the command.
3. Offer to do it. Commands of this plugin (such as `/scrum-github:task-start 20`) run as usual,
   with their own confirmations. For `git push` or `gh issue edit`, run them only after the user
   agrees, and fill in what the printed command leaves open (`N`, `LOGIN`) with the user.

`scrum next --json` returns `{step, message, command, issues}`.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
