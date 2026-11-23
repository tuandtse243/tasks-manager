---
name: sprint-new
description: Create the next Scrum sprint as a GitHub milestone with start and end dates and a goal. Use when the user wants to start, create or plan a new sprint.
---

# Create a sprint

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository.

1. Collect from the user's request, without asking for what they did not mention:
   - `--start YYYY-MM-DD` (default: today in the configured time zone)
   - `--length DAYS` (default: `sprint.length_days` from `.github/scrum.yml`)
   - `--title "Sprint N"` (default: next number from the name pattern)
   - `--goal "..."` (optional sprint goal)
   Convert relative dates ("next Monday") to absolute dates.
2. Run `scrum sprint new [options]`.
3. Report the created sprint, its dates and link. Pass on any warning (for example dates that
   overlap an open sprint).
4. Suggest the next step: if the script says the backlog has tasks waiting, choose them for this
   sprint with `/scrum-github:sprint-fill`; otherwise add tasks with `/scrum-github:task-new` or
   break a feature down with `/scrum-github:plan`.

If the script says the repository has no configuration, run `/scrum-github:init` first.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
