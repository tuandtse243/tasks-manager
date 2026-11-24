---
name: my-tasks
description: Show everything one person has to do in Scrum on GitHub - their open tasks in every sprint and the backlog, grouped by status and sprint with what blocks them, the pull requests waiting for their review, and the task to do next in dependency order - then offer to start that task. Read-only until the user agrees. Use when the user asks what they (or a teammate) have to do, what is on their plate, what to work on next, how long their work in the sprint will take, or which reviews are waiting for them.
---

# My tasks

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository. It only reads from GitHub.

1. Run `scrum mine` for the user themself, or `scrum mine --user LOGIN` when they ask about
   someone else. Add `--json` when you need the data for a further question.
2. Show the groups as printed, in their order: In progress, In review (when that status is on),
   New in the open sprint, other sprints by end date, then the backlog. Each line has the number,
   points, sprint, title, the time estimate when the task has one ("[AI 20m, review 15m]") and the
   open tasks that block it. With a working branch (`standard` or `environments`) a task In review
   also says where it is: "(in code review)" while its pull request is open, "(on develop)" once
   merged there and waiting for the release.
   Then give the "Time left in <sprint>" line: about how long the work on their open tasks of the
   open sprint takes, counted by waves like the plan view (tasks that do not block each other run
   in parallel, `planning.merge_minutes` after each wave), and the minutes of review. Name the
   tasks without a time estimate; `scrum task estimate N --work D --review D` adds one.
3. Say which task to do next, as the output's "Next:" line gives it: continue the task In
   progress, or start the first New task of the open sprint that nothing open blocks. Never
   suggest a blocked task before the task that blocks it. When "Next:" names no task, say why
   (no open sprint, everything blocked) and suggest what helps: `/scrum-github:sprint-new`, or
   finishing the blocking task.
4. List the pull requests waiting for their review (number, title, author). If the output says
   this part could not be read from GitHub, say so; the task list is still complete.
5. For a task to start, give the command `/scrum-github:task-start N` and ask whether to run it.
   Run it only after the user agrees; do not start, assign or move anything on your own. For a
   task to continue, just name it (it is already started).
6. When the output says AI agents can work some of the tasks (New tasks of the open sprint
   labelled `ai-ready`), say so and offer `/scrum-github:run`: it shows the run plan first and
   asks before anything starts. Run it only after the user agrees.

"blocked-by not checked" means the task is past the first 50 read, or GitHub did not return its
blockers; it does not mean the task is free, so it is never suggested as next.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
