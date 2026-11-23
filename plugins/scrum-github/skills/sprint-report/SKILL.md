---
name: sprint-report
description: Generate a self-contained HTML Scrum sprint report from GitHub with a burndown chart (actual vs ideal), a per-person table and the velocity of recent sprints. Use when the user wants a burndown, sprint report, velocity chart or something to share at sprint review.
---

# Sprint report

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository. It only reads from GitHub and writes one local HTML file.

1. Run `scrum report [SPRINT] [--out FILE]`
   (default file: `scrum-reports/<sprint>.html` in the current directory).
2. Give the user the full path of the file. It works offline and can be attached or shared as is.
3. Summarize what the burndown shows: on track, behind or ahead of the ideal line, and the trend
   of velocity if earlier sprints exist.

Limits to mention when relevant: points come from each task's current label, and tasks added
during the sprint are counted from the first day.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
