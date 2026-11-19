---
name: task
description: List or change Scrum tasks on GitHub without editing labels by hand - list tasks (mine, by sprint, the backlog, by status), move tasks between sprints and the backlog, re-estimate points, assign or unassign people, or drop a task as not planned. Use when the user asks to see tasks, move a task to another sprint or back to the backlog, change its points, assign it, or drop it.
argument-hint: "[what to do, e.g. move #12 to the backlog]"
---

# Work with tasks

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.
Run it from the root of the target repository.

Pick the command from the user's request:

| The user wants to | Command |
|---|---|
| see tasks | `scrum task list [--mine] [--sprint "Sprint N" \| --backlog] [--status new\|in_progress\|done]` |
| move tasks | `scrum task move N[,N…] --sprint "Sprint N"` or `--backlog` |
| change points | `scrum task estimate N POINTS` (must be in the point scale) |
| assign / unassign | `scrum task assign N LOGIN… [--unassign]` |
| drop a task | `scrum task drop N [--reason "…"]` (closed as not planned: counts nowhere) |

1. `list` only reads: run it and show the result.
2. For the others, say in one sentence what will change (for example "move #12 from Sprint 4 to
   the backlog, with a comment on the issue") and wait for the user to agree. Then run it and
   report what the script printed.
3. The script checks every number first; if one is closed, a pull request, or a feature or epic,
   nothing is changed. Pass that on and ask how to go on.

New tasks: `/scrum-github:task-new`. Starting one: `/scrum-github:task-start`. Choosing tasks for
a sprint against its capacity: `/scrum-github:sprint-fill`.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
