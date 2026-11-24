# Cheat sheet: Product Owner

The Product Owner's commands in the order a sprint uses them. Type them in Claude Code, at the
root of the project's repository. Every option: [the plugin's README](../plugins/scrum-github/README.md).

## Before Sprint Planning

| What | Command | Example |
|---|---|---|
| Clarify a vague idea | `/scrum-github:discover` | `/scrum-github:discover let users comment under a post` |
| Split a requirement into an epic, features and tasks | `/scrum-github:plan` | `/scrum-github:plan docs/plans/blog-comments/brief.md` |
| See the work that is in no sprint | `/scrum-github:backlog` | `/scrum-github:backlog which tasks are not estimated?` |
| Add a single task or bug | `/scrum-github:task-new` | `/scrum-github:task-new bug: Save button does nothing on Safari, 3 points` |
| Add a task to the backlog on purpose | `/scrum-github:task-new` | `/scrum-github:task-new export to CSV, backlog` |

`discover` and `plan` write files under `docs/plans/<slug>/` for you to read and edit. `plan`
suggests an assignee for each task (from the `team` block in `.github/scrum.yml`, by areas and
load) and a sprint (what fits the open sprint's capacity, the rest to the backlog). You review it
once, in the chat and in the generated page `plan.html` (dependency graph, timeline, each
person's load, the plan-critic findings, what will be created); say what to change, or approve.
Only after your approval are the issues created on GitHub, already assigned and in their sprint.
Running `plan` again on the same folder continues the same plan without duplicates.

`task-new` puts a task in the open sprint, or in the backlog when no sprint is open (or when you
ask for the backlog), and says where it went.

## Estimates

Points measure how complex a task is; a time estimate says when it is done. With AI doing most
of the work, a time estimate has two parts: the work, and a person's review and manual testing,
which is often the bottleneck.

| What | Command | Example |
|---|---|---|
| Points and time when creating a task | `/scrum-github:task-new` | `/scrum-github:task-new Store comments, 3 points, work 25m, review 20m` |
| Change points or time later | `/scrum-github:task` | `/scrum-github:task #12 is 7 points, review 45m` |
| Work done by a person, not AI | `/scrum-github:task` | `/scrum-github:task #12: done by a human, work 2h` |

Behind these are `--work`, `--review` and `--by ai|human` (`ai` by default); durations are `90`,
`25m`, `2h` or `1h30m`. In a plan, each task can carry an `estimate`. Work time adds up by waves
(tasks that do not block each other run in parallel), review time is the sum. Both show in
`plan.md` and `plan.html`, `my-tasks`, `sprint-status` and `sprint-fill`.

## During Sprint Planning

| What | Command | Example |
|---|---|---|
| Choose tasks that fit the sprint's capacity | `/scrum-github:sprint-fill` | `/scrum-github:sprint-fill capacity 20 points` |
| Change points, move a task back to the backlog, drop a task | `/scrum-github:task` | `/scrum-github:task move #12 to the backlog` |

The default capacity is the average velocity of up to the last three closed sprints.
`sprint-fill` also compares each person's review minutes with their `review_hours` in `team`.

## During the sprint

| What | Command | Example |
|---|---|---|
| Progress and "Needs attention" | `/scrum-github:sprint-status` | `/scrum-github:sprint-status how many points are left?` |
| HTML report for stakeholders | `/scrum-github:sprint-report` | `/scrum-github:sprint-report` |

The digest is posted every morning on the issue `Sprint N digest` (and in a chat channel if the
repository has the secret `SCRUM_DIGEST_WEBHOOK`).

When the repository has a `develop` branch (presets `standard` and `environments`), a task whose
pull request is merged is **not Done yet**: it stays In review, shown as "on `develop`" (or "on
`staging`"), until a release brings it into `main`. Then it is Done and closed. To see what is
merged but not released: `/scrum-github:branches`. A version is published by the Scrum Master or
tech lead with `/scrum-github:release`.

## End of the sprint

The Sprint Review uses the summary the Scrum Master posts when closing the sprint (a comment on
the issue `Sprint N digest`): velocity, tasks done, tasks carried over, scope changes. With a
`develop` branch, only released tasks count in the velocity; the summary lists the others as
"merged but not released".

Not sure what to do next: `/scrum-github:next`. A command fails: `/scrum-github:doctor`.
