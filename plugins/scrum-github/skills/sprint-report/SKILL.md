---
name: sprint-report
description: Generate a self-contained HTML Scrum sprint report from GitHub with a burndown chart (actual vs ideal), a per-person table and the velocity of recent sprints. Use when the user wants a burndown, sprint report, velocity chart or something to share at sprint review.
---

# Sprint report

The script is `${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum`; run it with `bash` from the root of the
target repository. It only reads from GitHub and writes one local HTML file.

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" report [SPRINT] [--out FILE]`
   (default file: `scrum-reports/<sprint>.html` in the current directory).
2. Give the user the full path of the file. It works offline and can be attached or shared as is.
3. Summarize what the burndown shows: on track, behind or ahead of the ideal line, and the trend
   of velocity if earlier sprints exist.

Limits to mention when relevant: points come from each task's current label, and tasks added
during the sprint are counted from the first day.
`gh` cannot read its keychain token inside the Claude Code sandbox; run outside it if needed.
