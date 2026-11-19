---
name: sprint-new
description: Create the next Scrum sprint as a GitHub milestone with start and end dates and a goal. Use when the user wants to start, create or plan a new sprint.
---

# Create a sprint

The script is `${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum`; run it with `bash` from the root of the
target repository.

1. Collect from the user's request, without asking for what they did not mention:
   - `--start YYYY-MM-DD` (default: today in the configured time zone)
   - `--length DAYS` (default: `sprint.length_days` from `.github/scrum.yml`)
   - `--title "Sprint N"` (default: next number from the name pattern)
   - `--goal "..."` (optional sprint goal)
   Convert relative dates ("next Monday") to absolute dates.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" sprint new [options]`.
3. Report the created sprint, its dates and link. Pass on any warning (for example dates that
   overlap an open sprint).
4. Suggest the next step: add tasks with `/scrum-github:task-new` or break a feature down with
   `/scrum-github:plan`.

If the script says the repository has no configuration, run `/scrum-github:scrum-init` first.
`gh` cannot read its keychain token inside the Claude Code sandbox; run outside it if needed.
