---
name: task
description: List or change Scrum tasks on GitHub without editing labels by hand - list tasks (mine, by sprint, the backlog, by status), move tasks between sprints and the backlog, re-estimate points or the time estimate (work and review minutes), assign or unassign people, or drop a task as not planned. Use when the user asks to see tasks, move a task to another sprint or back to the backlog, change its points or how long it takes to do or review, assign it, or drop it.
argument-hint: "[what to do, e.g. move #12 to the backlog]"
---

# Work with tasks

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository.

Pick the command from the user's request:

| The user wants to | Command |
|---|---|
| see tasks | `scrum task list [--mine] [--sprint "Sprint N" \| --backlog] [--status new\|in_progress\|done]` |
| move tasks | `scrum task move N[,N…] --sprint "Sprint N"` or `--backlog` |
| change points or time | `scrum task estimate N [POINTS] [--work D] [--review D] [--by ai\|human]` (points must be in the point scale; durations are `90`, `25m`, `2h` or `1h30m`; at least one of them) |
| assign / unassign | `scrum task assign N LOGIN… [--unassign]` |
| drop a task | `scrum task drop N [--reason "…"]` (closed as not planned: counts nowhere) |

1. `list` only reads: run it and show the result.
2. For the others, say in one sentence what will change (for example "move #12 from Sprint 4 to
   the backlog, with a comment on the issue") and wait for the user to agree. Then run it and
   report what the script printed.
3. `task estimate` changes only what is given: `--review 30m` keeps the points and the work time.
   The time estimate lives in a block at the end of the issue body; a block someone broke by
   hand counts as no estimate and is written again cleanly.
4. The script checks every number first; if one is closed, a pull request, or a feature or epic,
   nothing is changed. Pass that on and ask how to go on.

New tasks: `/scrum-github:task-new`. Starting one: `/scrum-github:task-start`. Choosing tasks for
a sprint against its capacity: `/scrum-github:sprint-fill`.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
