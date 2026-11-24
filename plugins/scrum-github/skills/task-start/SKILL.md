---
name: task-start
description: Start working on a Scrum task - assign it to me if unassigned, set its status to In progress and create or check out its branch (feat/<number>-<slug>). Use when the user says they start, pick up or work on issue/task #N.
---

# Start a task

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository (it creates a local branch there).

1. Get the issue number from the user's request.
2. Run `scrum task start N`. A new branch starts from the latest working branch on origin
   (`origin/develop` in the `standard` and `environments` presets, the default branch in `trunk`).
   When origin cannot be reached, it starts from the local copy of that branch and warns that it
   may be stale: pass the warning on, and suggest `/scrum-github:sync` once the network is back.
3. Report the branch, the branch it started from, the status change and any note (for example the
   task is assigned to someone else). Say that `/scrum-github:task-pr` writes the pull request
   description when the work is ready, and that a description written by hand needs `Closes #N`:
   the PR check fails without it. In `trunk` merging the PR moves the task to Done; with a working
   branch the task stays In review on that branch until it is released to the release branch.

If git refuses to switch branches because of uncommitted changes, tell the user; nothing was
changed on GitHub in that case.
If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
