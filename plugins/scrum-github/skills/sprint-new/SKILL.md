---
name: sprint-new
description: Create the next Scrum sprint as a GitHub milestone with start and end dates and a goal. Use when the user wants to start, create or plan a new sprint.
---

# Create a sprint

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.
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
4. Suggest the next step: add tasks with `/scrum-github:task-new` or break a feature down with
   `/scrum-github:plan`.

If the script says the repository has no configuration, run `/scrum-github:init` first.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
