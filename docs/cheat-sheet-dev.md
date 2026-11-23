# Cheat sheet: Developer

The commands for one task, in order. Type them in Claude Code, at the root of the project's
repository. Every option: [the plugin's README](../plugins/scrum-github/README.md).

## One task

| Step | Command | Example |
|---|---|---|
| 1. See your work and what to do next | `/scrum-github:my-tasks` | `/scrum-github:my-tasks` |
| 2. Take the task: assigned to you, In progress, branch created | `/scrum-github:task-start` | `/scrum-github:task-start 12` |
| 3. Write the code, commit, push the branch | (git as usual) | `git push -u origin feat/12-login` |
| 4. Write the PR description and open the PR | `/scrum-github:task-pr` | `/scrum-github:task-pr` |
| 5. Merge the PR | (on GitHub) | The task moves to Done and closes on its own |

`my-tasks` lists your open tasks in every sprint and the backlog, what blocks them, their time
estimates and the time left in the open sprint, the pull requests waiting for your review, and
the task to do next (it offers to start it). `/scrum-github:my-tasks for an-nguyen` shows a
teammate's.

The PR description always has `Closes #12`. Without that line the `scrum-pr-link-check` check
fails; a PR that belongs to no task gets the label `no-task`.

## Let AI agents work your tasks

| Step | Command | Example |
|---|---|---|
| See the plan only: tasks, waves, what is left out, time estimate | `/scrum-github:run --dry-run` | `/scrum-github:run --dry-run` |
| Run your New `ai-ready` tasks of the open sprint | `/scrum-github:run` | `/scrum-github:run` |
| Run only some tasks | `/scrum-github:run` | `/scrum-github:run 102,107` |
| At most K agents at once (default 3) | `/scrum-github:run --max-parallel K` | `/scrum-github:run --max-parallel 2` |
| One pull request per wave instead of one in total | `/scrum-github:run --pr-per-wave` | `/scrum-github:run --pr-per-wave` |

Each agent works one task in its own local git worktree and commits only locally. Tasks that do
not block each other run in the same wave; each wave is merged into an integration branch
(`run/{sprint}-{login}`) and tested before the next. At the end only that branch is pushed, as one
pull request to review: acceptance criteria as checkboxes, estimate against actual time, how to
test by hand, what to look at closely. The agents run code on your machine with your
permissions, so the command shows the plan and waits for your yes. If a run stops,
`/scrum-github:run` offers to continue it.

## If the repository has the In review status

| Your PR | The task |
|---|---|
| Draft | In progress |
| Ready for review | In review |
| Back to draft, or closed without merging | In progress |
| Merged | Done |

## When you need it

| What | Command | Example |
|---|---|---|
| List or change tasks | `/scrum-github:task` | `/scrum-github:task my tasks in progress` |
| Add or change a time estimate | `/scrum-github:task` | `/scrum-github:task estimate #12: work 25m, review 20m` |
| Report a bug | `/scrum-github:task-new` | `/scrum-github:task-new bug: login fails on Safari` |
| What to do next | `/scrum-github:next` | `/scrum-github:next` |
| A command fails on login or network | `/scrum-github:doctor` | `/scrum-github:doctor` |

Do not edit `status:` or `points:` labels by hand; use `/scrum-github:task`.
