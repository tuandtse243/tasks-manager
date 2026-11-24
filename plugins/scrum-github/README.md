# scrum-github

Run Scrum on GitHub without a separate tool. A sprint is a milestone, a task is an issue,
and a pull request with `Closes #n` moves its task through **New → In progress → Done**
on its own (with an optional In review status). Reports, burndown and a daily digest come from
the same data.

**This README is the reference:** every command and option, every configuration key, the status
rules, how data is stored, and development. For how to work with it day to day, read the
[Adoption guide](../../docs/adoption-guide.md) and the one-page cheat sheets
for the [Product Owner](../../docs/cheat-sheet-po.md), the [Scrum Master](../../docs/cheat-sheet-sm.md)
and [Developers](../../docs/cheat-sheet-dev.md).

This plugin automates the six steps of the guide "Quản lý dự án theo Scrum đơn giản với GitHub":

| Step in the guide | Done manually in the guide | What the plugin does |
|---|---|---|
| 1. Create a sprint | Create a milestone | `sprint-new` creates `Sprint {n}` with start/end dates; `sprint-fill` chooses its tasks from the backlog against the capacity |
| 2. Task states | Create labels by hand | `init` syncs status, points and helper labels |
| 3. Create a task | New issue, add labels | `task-new`, `plan` (AI breakdown into a plan file), task issue form |
| 4. Link a PR | Write `Solve #1` | `task-pr` writes the description with `Closes #`; PR template; a check that fails without a link |
| 5. Sprint review | Change labels, close issues | Status follows PR/issue events; `sprint-close` records velocity and carries over unfinished tasks |
| 6. Track progress | Filter by label | `sprint-status`, `sprint-report` (HTML burndown), daily digest |
| (after the guide) Release | Tag and write release notes by hand | `release` suggests the version and writes the notes from the Done tasks; creates the tag and the GitHub Release after you agree |

> The guide writes `Solve #1`. GitHub does not treat "Solve" as a closing keyword, so the
> issue never closes. This plugin uses `Closes #1` and its PR check points out `Solve`.

## Requirements

| Tool | Why | Install |
|---|---|---|
| [GitHub CLI](https://cli.github.com) `gh` | every GitHub call | `brew install gh`, then `gh auth login -h github.com -s repo,workflow` |
| `jq` 1.6+ | all calculations | `brew install jq` |
| `yq` v4 by mikefarah | reads `.github/scrum.yml` | `brew install yq` (the Python `yq` from pip is a different tool and is rejected) |
| Bash 3.2+ | scripts | the macOS default works |

GitHub-hosted `ubuntu-latest` runners already have all four, so the workflows need nothing extra.

## Install

In Claude Code:

```
/plugin marketplace add tuandtse243/tasks-manager
/plugin install scrum-github@tasks-manager
```

From a local clone of this repository, `/plugin marketplace add ./` at its root works too.

Then, inside a clone of the repository you want to manage:

```
/scrum-github:init
```

Commit and push the files it writes under `.github/`. Then check the whole setup at once, and
ask what to do next:

```
/scrum-github:doctor
/scrum-github:next
```

**Updating from 0.4 or earlier:** `/scrum-github:scrum-init` is now `/scrum-github:init` (the old
name was removed in 0.6.0). Run it once after updating: it starts recording the files it writes,
so this first run still reports every file that differs from the new template as a `conflict`.
From then on, files nobody edited are updated on their own.

## Commands

Plugin skills are namespaced, so each command is typed as `/scrum-github:<name>`.
Every skill runs the same script. With the plugin installed for your user, it is on the PATH of
Claude Code's shell as `scrum` (observed in Claude Code 2.1.328: a plugin installed with local
scope or loaded with `--plugin-dir` does not get its `bin/` on the PATH; skills then fall back to
the full path, and the skills now use the full path from the first call). Elsewhere run `runtime/bin/scrum <command>` (or `bin/scrum`).

| Claude Code | Script | What it does |
|---|---|---|
| `/scrum-github:init` | `scrum init [--dry-run] [--force] [--force-file PATH]` | Create `.github/scrum.yml`, sync labels, install or update templates, workflows and the runtime |
| `/scrum-github:doctor` | `scrum doctor [--json]` | Check tools, `gh` login and scopes, configuration, labels, what is pushed, versions and the board secret; each problem with its fix. Read-only |
| `/scrum-github:next` | `scrum next [--json]` | The one thing to do next, with its command; with a working branch also protect, back-merge, promote and release steps. Read-only |
| – | `scrum team [--json]` | Team members (from `team` in `.github/scrum.yml`, or GitHub's assignable users), their areas, capacity and load in the open sprint. Read-only |
| – | `scrum config` | Print the merged configuration (`.github/scrum.yml` over the defaults) as JSON; offline |
| – | `scrum uninstall [--dry-run] [--yes]` | Remove what `init` installed from the working tree; keeps `.github/scrum.yml`, files you edited, and everything on GitHub |
| `/scrum-github:sprint-new` | `scrum sprint new [--title T] [--start DATE] [--length DAYS] [--goal TEXT]` | Create the next sprint |
| `/scrum-github:backlog` | `scrum backlog [--json]` | Open tasks without a sprint: points, assignees, parent, blockers, totals |
| `/scrum-github:sprint-fill` | `scrum sprint fill [SPRINT] [--capacity N] [--add N,N,…] [--yes]` | Capacity from recent velocity, what is planned, review minutes per person against `review_hours`, and moving tasks from the backlog into the sprint |
| `/scrum-github:project-scan` | `scrum context inventory`, `scrum context status`, `scrum context stamp` | Describe an existing codebase in `docs/project-context.md` (with a commit stamp) |
| `/scrum-github:discover` | `scrum plan init`, `scrum doc check FILE` | Clarify a vague idea through research and an interview; writes `docs/plans/<slug>/brief.md` |
| `/scrum-github:plan` | `scrum team --json`, `scrum plan init`, `scrum plan check FILE [--json]`, `scrum plan apply FILE` | Break a requirement into an epic, features and tasks in a plan file, with suggested assignees and sprint; one review (`plan.html`); after approval create the issues in their sprint, assigned |
| `/scrum-github:task-new` | `scrum task new --title T [--points N] [--assignee LOGIN] [--sprint S \| --backlog] [--bug] [--work D] [--review D] [--by ai\|human]` | Create a task in the open sprint, or in the backlog when none is open (or with `--backlog`); says where it went. Optional time estimate, see "Time estimates" |
| `/scrum-github:my-tasks` | `scrum mine [--user LOGIN] [--json]` | Every open task of one person in every sprint and the backlog, what blocks them, their time estimates and the time left in the open sprint, pull requests waiting for their review, and the task to do next; offers to start it. Read-only |
| `/scrum-github:task-start` | `scrum task start N` | Assign yourself, set In progress, create branch `feat/N-slug` from the latest working branch on origin (`develop`, or the default branch in `trunk`) |
| `/scrum-github:run` | `scrum run plan [N,…]`, `scrum run start`, `scrum run record`, `scrum run merge N`, `scrum run finish [--wave W]`, `scrum run status [ID]` | Work your `ai-ready` tasks with AI agents, one local git worktree each, wave by wave, into one pull request ready for review, based on the working branch; `--dry-run` shows the plan only. See "Running tasks with agents" |
| `/scrum-github:task` | `scrum task list [--mine] [--sprint S \| --backlog] [--status ROLE]`, `scrum task move N… --sprint S \| --backlog`, `scrum task estimate N [P] [--work D] [--review D] [--by ai\|human]`, `scrum task assign N LOGIN… [--unassign]`, `scrum task drop N [--reason T]` | See tasks; move, re-estimate, assign or drop them without editing labels by hand |
| `/scrum-github:task-pr` | `gh pr create` / `gh pr edit`, after you approve; `scrum hotfix prepare` on a hotfix branch | Write the pull request description for the task of the current branch, with a Conventional Commits title, into the working branch (the release branch from `hotfix/*`); warns when the branch is behind its base |
| `/scrum-github:sprint-status` | `scrum status [SPRINT]` | Table by person and status with points; work and review minutes left when tasks have time estimates; with a working branch, where each task In review is |
| `/scrum-github:sprint-report` | `scrum report [SPRINT] [--out FILE]` | Self-contained HTML burndown and velocity |
| `/scrum-github:sprint-close` | `scrum sprint close [SPRINT] [--yes] [--create-next]` | Record velocity, carry over open tasks, close the milestone; lists merged but unreleased tasks apart; suggests a release when the sprint had Done tasks |
| `/scrum-github:release` | `scrum release [VERSION] [--since TAG] [--sprint S]… [--from REF] [--draft] [--notes-file FILE] [--json] [--yes]`, `scrum release finish [--pr N]` | Suggest the next version, write the release notes, and with `--yes` create the tag and the GitHub Release (`trunk`) or open the release pull request (presets with a working branch); `release finish` publishes after that pull request is merged. See "Releasing a version" |
| `/scrum-github:protect` | `scrum protect [--json] [--yes]` | Create the long-lived branches of the preset, apply branch and tag rules and the merge settings; preview first, writes with `--yes` |
| `/scrum-github:sync` | `scrum sync` | Merge the working branch (the release branch on a hotfix branch) into the current task branch; lists conflicts with who last changed each file |
| `/scrum-github:branches` | `scrum branches [--json]` | What each long-lived branch holds that the next one lacks, drift, open promotion, release and back-merge pull requests, stale task branches. Read-only |
| `/scrum-github:cleanup` | `scrum cleanup [--json] [--yes]` | Local and remote branches whose pull request was merged or that a long-lived branch contains (never long-lived, current or with an open pull request); deletes them with `--yes` |
| `/scrum-github:promote` | `scrum promote [--json] [--yes]` | Preset `environments`: the tasks on the working branch that staging lacks; with `--yes` open the promotion pull request |
| `/scrum-github:hotfix` | `scrum hotfix N`, `scrum hotfix prepare [--json] [--yes]` | Start a fix from the release branch (`hotfix/N-slug`), then set its version, version files and the `scrum-release-tag` marker before the pull request. See "Releasing a version" |
| `/scrum-github:project-setup` | `bash wizards/project-board.sh`, then `scrum project init` | Turn on the project board: a wizard for the steps only you can do |

Plan files have their own commands too (all but `check` and `apply` work offline):

| Script | What it does |
|---|---|
| `scrum plan init "<title>" [--slug SLUG]` | Create `<planning.dir>/<slug>/`; print its paths as JSON and which files exist |
| `scrum plan validate FILE` | Check the plan: fields, unique ids, points in the scale, dependencies (unknown, self, cycles) |
| `scrum plan render FILE [--out PATH] [--offline]` | Write the views `plan.md` (with estimates) and `plan.html` next to the plan |
| `scrum plan check FILE [--offline] [--json]` | validate, render both views, print the waves, each person's load, the sprint's capacity, warnings and what `apply` would do; writes nothing to GitHub |
| `scrum plan apply FILE [--dry-run] [--update]` | Create the missing issues, link sub-issues and dependencies, record the numbers |
| `scrum doc check FILE [--type brief\|context]` | Check the required sections of a brief or of the project context |

What changed in each version: [CHANGELOG.md](CHANGELOG.md).

`init` records what it writes in `.github/scrum/files.json`. When the configuration or the
plugin changes, it updates every file nobody edited since; a file edited by hand is reported as a
`conflict` and kept, and `--force-file PATH` replaces it. A repository set up before 0.5.0 has no
record yet, so every file whose template changed since is reported as a `conflict`, edited or not;
compare it with the template and use `--force-file` for the ones you never edited.

Workflows installed in the target repo call `scrum event`, `scrum pr-check` and `scrum digest`
(and `scrum project sync` when the project board is on, see below).

## Configuration

`.github/scrum.yml` in the target repo. Every key is optional; missing keys use these defaults:

```yaml
version: 1
timezone: UTC                      # used for "today", burndown days and the digest
language: en                       # en or vi: status table, digest, HTML report, sprint summary
sprint:
  length_days: 5                   # calendar days
  name_pattern: "Sprint {n}"
  working_days: [1, 2, 3, 4, 5]    # 1 = Monday ... 7 = Sunday; days left and the ideal line use them
points:
  scale: [0, 1, 3, 7]              # e.g. [1, 2, 3, 5, 8]
  label_prefix: "points: "
statuses:
  label_prefix: "status: "
  new: New
  in_progress: In progress
  in_review: null                  # optional fourth status, e.g. "In review"; see "How statuses change"
  done: Done
labels:
  bug: bug
  feature: "type: feature"         # parent issues created by plan; not counted in points
  epic: "type: epic"               # parent of several features; not counted in points
  meta: "scrum: meta"              # digest issues; not counted
  no_task: no-task                 # lets a PR pass the link check without a task
  ai_ready: ai-ready               # a task an AI agent may work with /scrum-github:run
branch:
  pattern: "feat/{number}-{slug}"
digest:
  enabled: true
  cron: "0 1 * * 1-5"              # baked into the workflow; re-run init after changing it
  webhook_format: slack            # slack (also Google Chat, Mattermost) or telegram; see below
attention:                         # "Needs attention" in status, digest and report
  stale_days: 2                    # In progress with no activity for this many working days
  review_days: 2                   # In review with no activity for this many working days (when on)
  behind_percent: 15               # remaining above the ideal line by more than this % of scope
  promote_days: 5                  # merged into a long-lived branch and waiting longer than this to be released
colors: {}                         # label name -> hex color, overrides the defaults
planning:
  dir: docs/plans                  # plan folders: <dir>/<slug>/plan.json, plan.md, brief.md
  context_file: docs/project-context.md   # written by project-scan
  hours_per_point: null            # e.g. 4: plan.md then shows hours next to points
  context_stale_commits: 50        # the project context counts as stale after this many commits
  merge_minutes: 5                 # merge and test time between two waves, in time estimates
run:                               # /scrum-github:run, see "Running tasks with agents" below
  test_command: ""                 # the repo's test command; empty = each agent finds it
  max_parallel: 3                  # at most this many agents at once (a whole number > 0)
  branch_pattern: "run/{sprint}-{login}"   # integration branch; also {date} (YYYY-MM-DD)
release:                           # /scrum-github:release, see "Releasing a version" below
  tag_prefix: v                    # tags are <tag_prefix>X.Y.Z; "" for none
  breaking_label: breaking         # a task with this label makes a major version
  first_version: "0.1.0"           # the first release when there is no version tag yet
  version_files: []                # files the release pull request updates: {path, pattern: "...{version}..."}
  changelog: null                  # file that gets the release notes at the top, e.g. CHANGELOG.md
branching:                         # see "Branches and releases" below
  preset: trunk                    # trunk (main only), standard (develop + main), environments (develop + staging + main);
                                   # init writes standard into a new .github/scrum.yml
  main: main                       # release branch, the default branch of the repository; tags live here
  develop: develop                 # working branch of standard and environments
  staging: staging                 # environments only
  location_prefix: "on: "          # label of a task merged into a long-lived branch: "on: develop"
  stale_days: 5                    # task branches without a commit for this many working days are stale
governance:                        # /scrum-github:protect and the files init installs
  approvals: 1                     # approvals a pull request needs, 0 to 6
  required_checks: []              # status checks each long-lived branch requires, besides the task-link check
  codeowners: []                   # owners written into CODEOWNERS, e.g. ["@acme/web"]
deploy:
  platform: none                   # none, vercel, cloudflare or docker: the deployment workflow init installs
project:                           # optional board, see "Project board" below
  enabled: false
  owner: null                      # user or organization that owns the project
  number: null                     # from the project URL: .../projects/<number>
  status_field: Status
  status_options: {new: Todo, in_progress: In Progress, in_review: In Review, done: Done}   # in_review: only when on
  synced_field: Synced status      # bookkeeping text field; hide it in views
  points_field: Points             # number field filled from "points: N"; null to turn off
  poll_cron: "*/15 * * * *"        # how often board changes reach the labels
team: []                           # members, see "Team" below; empty = the repo's assignable users
```

### Team

`team` lists who works on the repository. Each member has a `login` and, optionally, `areas`
(what they usually work on), `capacity` (points per sprint) and `review_hours` (hours of
review and manual testing per sprint, see "Time estimates"):

```yaml
team:
  - login: tuandt
    areas: [backend, api]
    capacity: 10
    review_hours: 6
  - login: an-nguyen
    areas: [frontend]
```

Logins are compared without case, and a leading `@` is dropped. Two members with the same login,
an empty login, `areas` that is not a list of texts, or a `capacity` or `review_hours` of 0 or less stop every
command with an error. When `team` is empty, the list is the people GitHub lets you assign
issues to in the repository (no areas, no capacity), and commands say so.

The list is used by `scrum team` (each person's load in the open sprint), by `/scrum-github:plan`
(suggested assignees and sprint, with each person's load against their capacity), and by
`task new`, `task assign` and `plan check`, which warn about a login that is not in `team` (only
when `team` is set; the warning never stops the command).

### Time estimates

Points measure how complex a task is; a time estimate says when it is done. When AI does most of
the work, "when" has two parts: how long the work takes, and how long a person needs to review it
and test it by hand, which is often the bottleneck. A task can carry both, next to its points
(points stay for velocity, burndown, labels and the board):

- `work_minutes`: how long the work takes;
- `review_minutes`: review and manual testing by a person;
- `by`: who does the work, `ai` (the default) or `human`.

They are stored in a block at the end of the issue body, a line people read and the data in a
hidden HTML comment:

```
<!-- scrum:estimate -->
AI ~25m · Review ~20m
<!-- {"work_minutes":25,"review_minutes":20,"by":"ai"} -->
<!-- /scrum:estimate -->
```

Set them with `scrum task new … --work 25m --review 20m [--by human]`, change them with
`scrum task estimate N [POINTS] [--work D] [--review D] [--by ai|human]` (fields not given keep
their value), or give each plan task an `estimate`. Durations are `90`, `25m`, `2h` or `1h30m`.
A task without the block has no time estimate, and a block broken by hand counts as none (the
next `task estimate` writes it again). The line follows `language`.

Where they show: `plan.md` and `plan.html` (per task, per feature, in total, and a to-scale
timeline), `scrum mine` (each task, and the time left in the open sprint), `scrum status` (work
and review left per person) and `scrum sprint fill` (review minutes per person against
`team[].review_hours`). Work time is added up **by waves**: tasks that do not depend on each
other run in parallel, so a wave takes as long as its longest task, plus
`planning.merge_minutes` to merge and run the tests; review time is the sum. For example, with
`merge_minutes: 5`, waves of (20m, 8m), (15m, 35m) and (20m) are done in
20 + 5 + 35 + 5 + 20 + 5 = 90 minutes of work.

### Needs attention, burndown and the digest in a chat

`scrum status`, the digest and the HTML report list what needs attention: tasks blocked by an open
task, tasks In progress with no activity (the issue, or an open pull request that closes it) for
`attention.stale_days` working days, tasks without an assignee or points, and a sprint behind the
ideal line. The section is left out when there is nothing.

The burndown in `scrum report` is rebuilt from each task's history: which tasks were in the sprint
and how many points they had on each day, so tasks added, removed or re-estimated mid-sprint count
from the day it happened. The report also draws the scope line. History is read for at most 100
tasks of the sprint and 30 that may have left it; the report says so when it hits a limit.

To send the digest to a chat as well, add a repository secret `SCRUM_DIGEST_WEBHOOK`:

- Slack, Google Chat or Mattermost: the incoming webhook URL, with `digest.webhook_format: slack`.
- Telegram: `https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<CHAT_ID>`, with
  `digest.webhook_format: telegram`.

A webhook that fails only warns; the digest comment is always posted. Run `/scrum-github:init`
after updating to 0.7.0 so the digest workflow passes the secret.

## Working with branches

With a working branch (`branching.preset: standard` or `environments`), every task starts from
the latest `develop` on origin and its pull request goes back into `develop`; only `hotfix/*`
starts from and returns to `main`. In `trunk` the working branch is the default branch, as
before.

| Step | Command | What happens |
|---|---|---|
| Start a task | `scrum task start N` | `git fetch origin develop`, then `feat/N-slug` from `origin/develop`. When origin cannot be reached, from the local `develop`, with a warning that it may be stale |
| Keep the branch current | `scrum sync` | Merges `origin/develop` (`origin/main` on a hotfix branch) into the current task branch with `git merge --no-edit` and says how many commits came in. Refuses on a long-lived branch and with uncommitted changes |
| Open the pull request | `/scrum-github:task-pr` | Base `develop` (`main` from `hotfix/*`), title `feat: …` or `fix: …`; warns and suggests `/scrum-github:sync` when the branch is behind its base |
| See where work is | `scrum branches [--json]` | For each pair of long-lived branches the commits and tasks the lower one has that the upper one lacks; commits of `main` a lower branch lacks and its back-merge pull request; open release, promotion and back-merge pull requests; task branches on origin without a commit for `branching.stale_days` working days, with the last author. In `trunk`, only open pull requests and stale branches. Read-only |
| Remove finished branches | `scrum cleanup [--json] [--yes]` | Lists local and remote branches whose pull request was merged (the branch tip is the pull request's head, so squash merges count) or that a long-lived branch contains. Never a long-lived branch, the current branch or a branch with an open pull request. Deletes with `--yes` (`git branch -D`, `git push origin --delete`) |

When `scrum sync` conflicts, it lists each conflicted file with the author and subject of the last
commit on the base that changed it, and leaves the merge in progress: fix the files, then
`git add` and `git merge --continue`, or `git merge --abort` to go back. It never resolves a
conflict, and it exits with an error so scripts notice.

`/scrum-github:run` follows the same rule: its integration branch starts from `origin/develop` and
its pull requests target `develop`.

## Running tasks with agents

`/scrum-github:run` lets AI agents work your tasks, several at once, and gives a person one pull
request to review instead of a pile of branches.

> **Safety.** The agents run code on your machine with your permissions: they edit files, install
> what the tests need and run the repository's tests. Each works in its own git worktree of the
> repository and commits only locally. The skill says this and waits for your yes before every
> run. Nothing is pushed but the integration branch, at the end, after its tests pass; the
> branches and worktrees of the tasks are never pushed.

What it does, in order:

1. **Choose.** `scrum run plan` (read-only) picks your open tasks in the open sprint with status
   New and the label `ai-ready` (`labels.ai_ready`), or exactly the numbers you give
   (`scrum run plan 102,107`). It leaves out, each with its reason, a task blocked by an open task
   that is not in the run (and what that task blocks in turn), a closed issue, a feature, epic or
   meta issue, and a pull request. It splits the rest into **waves** by "blocked by": the tasks of
   a wave do not block each other. It prints the waves, what is left out, and the time estimate
   by waves when the tasks have one. `--dry-run` stops here.
2. **Confirm.** The skill shows this with the safety warning and waits for your answer.
3. **Start.** `scrum run start N,N --expect N,N` runs exactly the tasks the user confirmed: it
   stops, changing nothing, when the choice differs from them now, when the working tree has
   uncommitted changes, or when the integration branch exists locally or holds other work on
   origin. It creates
   the **integration branch** `run.branch_pattern` (`run/{sprint}-{login}`, for example
   `run/sprint-5-tuandt`) from the latest working branch on origin (`develop`, or the default
   branch in `trunk`), with no upstream (never the working branch itself), saves the run in
   `.scrum/run/<id>.json` (the id is `YYYYMMDD-HHMM-<login>`, UTC; `.scrum/` is added to
   `.git/info/exclude`, so `.gitignore` is not touched), assigns you the tasks nobody has, and
   sets every task In progress.
4. **Each wave.** The skill checks out the integration branch and starts the agent
   `scrum-github:implementer` for each task, in a new worktree made by Claude Code from that
   branch, at most `--max-parallel` (`run.max_parallel`, 3) at a time. The agent follows the
   issue's acceptance criteria, writes and runs tests, commits with `#N`, never pushes, stays in
   the task's scope, and reports `{result, reason, manual_test, look_closely}`.
   `scrum run record N --started` / `--done --branch B --notes FILE` /
   `--failed --notes FILE` (or `--reason-file FILE`, or `--reason R`) keeps what happened and the
   **actual time** (the agent's own `started_at` and `ended_at` when it reports them, else from
   `--started` to the record), posted on the issue as an `actual` block next to the estimate. The
   skill writes what an agent says to a file and passes the path; agent text never goes on a
   command line. `--done` refuses the integration and working branches and a branch that does not
   grow from the run's start. Records and merges of one run wait for each other (a lock next to
   the state file), so none is lost:

   ```
   <!-- scrum:actual -->
   Actual time: 41m · done
   Estimate: AI ~20m · Review ~10m
   <!-- {"minutes":41,"result":"done","run":"20261123-1000-tuandt",...} -->
   <!-- /scrum:actual -->
   ```

   `scrum run merge N` merges each done task into the integration branch with
   `git merge --no-ff` (one merge commit per task); a task already merged by hand is recorded
   with its merge commit. Then the skill runs `run.test_command` (or the
   repository's tests it finds) on the integration branch before the next wave.
5. **Finish.** `scrum run finish` pushes the integration branch only (never over commits on
   origin it does not have, and it warns when a task branch is on origin) and opens one pull request
   into the working branch, the **review pack**: for each merged task its acceptance criteria as
   checkboxes (from the issue), the estimate against the actual time, how to test it by hand and
   what to look at closely (from the agent), and `Closes #N`; then the tasks that failed or were
   left out, with their reasons. The status workflow moves the tasks when it opens and when it is
   merged, as for any pull request. When no task was merged, nothing is pushed.

When things go wrong:

- **A task fails** (its tests fail, or the agent cannot do it, or changed nothing): it gets a
  comment with the reason and the actual time, goes back to New and stays out of the pull
  request. The tasks it blocks are left out (with a comment, back to New); the others go on.
- **A merge fails without a conflict** (commit signing, a hook): it is undone the same way and
  recorded as `merge failed: <git's message>`; fix the cause and merge again.
- **A merge conflicts**: the merge is undone, the integration branch is unchanged, the task is
  recorded as `conflict`, and the skill asks you: leave it out, or fix the conflict on the task's
  branch and run `scrum run merge N` again.
- **The tests fail** after a wave: the skill stops before the next wave and asks you.
- **The run stops** (you close the session, a conflict waits): `/scrum-github:run` finds the
  unfinished run and offers to continue it. Merged, failed and left-out tasks are skipped, done
  tasks are merged, and the tasks that had not finished run again. `scrum run status [ID]` shows
  each task of a run at any time.

`--pr-per-wave` opens one pull request per wave instead, right after the wave is merged and
tested: `scrum run finish --wave W` pushes the integration branch at that point as
`<branch>-wave-W`, based on the branch of the previous wave's pull request, and says that one
must be merged first and that the base must then be changed to the working branch (the status
rules for `Closes #N` apply only there). Each wave gets one pull request, in order: `finish` without `--wave`
refuses on such a run, `finish --wave W` refuses a wave already closed or one after a wave still
open, and `scrum run status` names the wave whose pull request is due before the next wave starts.

Mark tasks for agents with the `ai-ready` label (`scrum init` creates it), or with
`"ai_ready": true` on a plan task (`plan apply` adds the label, `plan apply --update` adds or
removes it to match). `scrum mine` and `scrum next` point to `/scrum-github:run` when you have
such tasks in the open sprint. Needs git 2.20 or later.

## Plans: from a requirement to issues

Three skills form one pipeline. Each can be used alone; `/scrum-github:plan` points to the others
when it needs them.

```
project-scan ──► docs/project-context.md          what the existing code is (optional)
discover     ──► docs/plans/<slug>/brief.md       what to build, confirmed scope (optional)
             ──► docs/plans/<slug>/questionnaire-<who>.md   only for decisions someone else owns
plan         ──► docs/plans/<slug>/plan.json      epic → features → tasks, points, dependencies,
                                                  suggested assignees and sprint
             ──► docs/plans/<slug>/plan.md        generated view with estimates
             ──► docs/plans/<slug>/plan.html      generated page to review (not committed)
plan apply   ──► GitHub issues                    after your one approval: in their sprint, assigned
```

Nothing is written to GitHub before you approve the plan. Commit the files under `docs/` yourself.

**`plan.html`** is written next to `plan.md` by `plan check`, `plan render` and `plan apply`. It is
one self-contained file (no network, light and dark, no motion when the system asks for less):
a summary, what changed since the last view (its revision goes up only when a task is added,
removed, or changes title, points, dependencies, assignees or sprint), the dependency graph by
wave (hover a task to light up its chain), when tasks have time estimates a timeline drawn to
scale (work bars by wave, merge gaps, the review bar), each person's load and the sprint's capacity, a card per
task, the plan-critic findings (the plan's optional `review` list), what `apply` will create, and
the assumptions. Its fixed text follows `language`. Offline it says that load and the GitHub
actions need GitHub. The page is for reading; you answer in the chat. `plan init` writes a
`.gitignore` in the plan folder for `plan.html` and `.plan-snapshot.json`; for a folder made before
0.9.0, `plan check` says which lines to add.

**`/scrum-github:project-scan [--full]`** reads the repository through the read-only agent
`codebase-scout` and writes the project context: overview, technology, structure, flows, data
model, integrations, conventions, how to run and test, glossary. Every statement names its file;
what the code does not say is written "unknown". A stamp line records the commit, so later
commands can tell how old it is (`scrum context status`), and the next scan re-reads only the
folders that changed. The "Team notes" section is yours and is never overwritten.

**`/scrum-github:discover <idea> [--quick | --deep]`** turns a vague idea into a brief. It looks up
facts itself (code through `codebase-scout`, the web through the read-only agent `researcher`)
and asks you only for decisions, in numbered rounds with a suggested answer each. It covers users,
main flow, data, edge cases, non-functional needs, integrations, constraints and scope. On a
repository with code it checks how the feature fits (fits / fits with changes / conflicts: you
decide) and estimates the size (one task, one feature, or an epic). It holds your words against
the glossary of the project context: a term used in another sense, or one word for two things,
becomes a question, and the settled term goes into the brief. When a decision belongs to someone
who is not in the session (the product owner, a customer), it offers to write a questionnaire
for that person next to the brief. The brief then stays `Status: draft` with an "Open questions"
section; run the command again on the same folder once the answers are in the file. Depth: `--quick` (no agents,
one round), standard (default), `--deep` (web research and an independent review of the brief).

**`/scrum-github:plan <brief | requirement> [--quick]`** splits the requirement into vertical-slice
tasks with acceptance criteria, points from your scale, subtasks and dependencies. An input that
does not say who, what outcome and when it is done gets a suggestion to run `discover` first. The
read-only agent `plan-critic` reviews the draft (missing, out of scope, too large, dependencies,
untestable criteria, fragile descriptions) before you see it, unless `--quick`. Task descriptions
are written to last in a backlog: the behaviour wanted, not the files and lines to edit, and
what is out of scope for the task. A draft brief with open questions is planned only if you
agree to turn each open question into an assumption. Before you see it, the skill suggests an
assignee for each task from `team` (by areas and current load, never a login outside the team,
never over a name you gave) and a sprint: the tasks that fit the open sprint's capacity in
dependency order go into it, the rest to the backlog with the reason. You review everything once,
in the chat and in `plan.html`: tasks with assignee and sprint, each person's load, the sprint's
capacity, the findings, and what `apply` would do; say what to change, or approve. After the
approval `apply` creates the issues already in their sprint and assigned, without asking again. Running it again on the same folder
continues the existing plan and keeps its ids and issue numbers.

### The plan file

`plan.json` (version 2, schema in `runtime/share/plan.schema.json`):

```json
{
  "version": 2,
  "title": "Blog post comments",
  "sprint": null,
  "epic": null,
  "features": [
    { "id": "F1", "title": "Comments under a post", "body": "…", "issue": null,
      "tasks": [
        { "id": "T1", "title": "Store comments", "acceptance": ["…"], "subtasks": ["Migration", "API"],
          "points": 3, "estimate": {"work_minutes": 20, "review_minutes": 15, "by": "ai"},
          "depends_on": [], "ai_ready": true, "issue": null },
        { "id": "T2", "title": "Show comments", "points": 3, "depends_on": ["T1"], "issue": null }
      ] }
  ],
  "assumptions": ["…"],
  "out_of_scope": ["…"]
}
```

- **Ids** are unique in the plan and never change. `issue` stays `null` until `apply` creates the
  issue and writes its number back, one at a time, so an interrupted run loses nothing.
- **Sprint**: a sprint name, `"current"`, or empty for the **backlog** (issues with no milestone;
  `status`, `report` and `digest` do not see them, and the board does not add them). A task's own
  `sprint` overrides the plan's. A named sprint that does not exist or is closed stops `apply`
  before anything is written.
- **Epic**: optional; gets the label `type: epic`, and its features become its sub-issues. Epics
  and features never count in points, velocity or reports.
- **Subtasks** become a checklist in the task's issue, not separate issues.
- **Dependencies** (`depends_on`) become GitHub's "blocked by" relation. Where GitHub refuses
  sub-issues or dependencies, `apply` writes a checklist or a "Blocked by" section into the issue
  body instead, between `<!-- scrum:… -->` markers that a later run replaces.
- **Estimates** in `plan.md`: points per feature and in total, tasks not estimated, hours when
  `planning.hours_per_point` is set, and the number of sprints from the average velocity of the
  last three closed sprints (skipped offline or before any sprint is closed).
- **Time estimates** (`estimate`, optional): `work_minutes` and `review_minutes` (whole minutes
  above 0) and `by` (`ai` or `human`, `ai` when left out). `apply` writes them into the issue body
  and `apply --update` updates them; `plan.md` and `plan.html` add them up (see "Time
  estimates"), and `plan.html` draws the timeline.
- **AI ready** (`ai_ready`, optional, `true` or `false`): `apply` gives the issue of a task with
  `true` the label `ai-ready` (`labels.ai_ready`), so `/scrum-github:run` picks it up;
  `apply --update` adds or removes the label to match. Left out, the label is left as it is.
- Version 1 files (`{"feature": {...}, "tasks": [...]}`, no `version`) are read as one feature
  `F1` with tasks `T1…Tn` in the current sprint, and rewritten as version 2 when numbers are
  recorded.

### Applying again

| Situation | Command | Result |
|---|---|---|
| See what would happen | `scrum plan apply FILE --dry-run` | Prints creates, links, skips; writes nothing |
| A run failed half-way | `scrum plan apply FILE` | Creates only what has no `issue` yet |
| Tasks added to the plan | `scrum plan apply FILE` | Creates only the new ones and links them |
| Titles, bodies, points, time estimates or sprints changed in the plan | `scrum plan apply FILE --update` | Updates open issues (one PATCH, one label PUT each); never status labels or assignees; closed issues are skipped and reported |

Deleting an `issue` number or changing an `id` and applying again creates a duplicate: the CLI
cannot detect it, so read the `--dry-run` output first.

## Releasing a version

`/scrum-github:release` (or `scrum release`) publishes a version of the target repository. Without
`--yes` it only prints; with `--yes` it writes to GitHub. How it publishes depends on
`branching.preset`:

| Preset | `scrum release … --yes` | Tasks of the release | Tasks become Done |
|---|---|---|---|
| `trunk` (or no `branching` block) | tag and GitHub Release on the head of `main` | closed as completed since the previous tag (or `--sprint`) | when their pull request is merged |
| `standard` | opens the release pull request `release/<tag>` → `main`, from the head of `develop` | In review, `on: develop`, contained in the start point | when the release pull request is merged |
| `environments` | the same, from the head of `staging` | In review, contained in `staging` (so `on: staging`) | when the release pull request is merged |

The release branch is `branching.main` in every preset; no command reads the default branch of the
repository for it (only `doctor` checks that the two are the same).

### Version and notes (every preset)

1. **Previous version.** The tag `<release.tag_prefix>X.Y.Z` (or `X.Y.Z`) with the highest version
   that is on the release branch (GitHub's compare says `ahead` or `identical`; at most 20 tags are
   checked, newest first; a tag on another branch is skipped). Tags read through the API, so a
   clone without tags works too. `--since TAG` names it instead. When version tags exist but none
   can be confirmed on the release branch (a comparison failed, all 20 checks were used, or none is
   on it), the command stops and asks for `--since TAG`; it never falls back to
   `release.first_version` then. Tag and branch names are URL-encoded in API paths, so a
   `tag_prefix` such as `release/` works.
2. **Version.** Without `VERSION`: major when a task has the `release.breaking_label` label,
   otherwise minor when a task has no `labels.bug` label, otherwise patch (labels compared without
   case); `release.first_version` when there is no version tag yet. A `VERSION` you give (`1.5.0`
   or `v1.5.0`) must be `X.Y.Z` and greater than the previous version, otherwise the command stops
   before writing.
3. **Notes.** Markdown in the `language` of the configuration: breaking changes, features (tasks
   without a parent first, then one heading per parent feature, from GitHub's sub-issue link or
   "Part of #N" in the body), bug fixes, then "Other" (merged pull requests without a task, presets
   with a working branch only); empty groups are left out. Each line is `- Title (#12, PR #40)`;
   an `@name` in a title is put in backticks so publishing notifies nobody. A link comparing the
   previous and the new tag ends the notes. `--notes-file FILE` replaces them with your own text.

`--json` prints `{previous, suggested, version, tag, bump, reasons, tasks, other, notes, draft,
branch, tag_exists, nothing}`; `bump` is `first`, `major`, `minor`, `patch` or `given`, and
`reasons` holds the task numbers that are breaking, features and bugs. `--yes` needs the version
shown by the preview, so what is published is what was previewed (the skill also passes the
previewed notes with `--notes-file`).

### `trunk`: tag directly

- **Tasks.** The tasks closed as completed after the time the previous tag was made (the tagger
  date of an annotated tag, else the creation time of its release, else its commit date: a task
  closed by the last merge before the tag belongs to that tag), or with `--sprint S` (repeatable)
  the Done tasks of those sprints. Not planned, epics, features, meta issues and pull requests are
  left out. Each task comes with the merged pull requests that closed it (from its timeline: a
  merged pull request whose body closes it, else the pull request whose merge commit closed the
  task), read for at most 100 tasks; a task past that, or whose timeline cannot be read, has no
  pull request number.
- **Publish** (`VERSION --yes`). The releases are read again, drafts included: a release or a
  draft for the tag stops the command before any write. An annotated tag "Release vX.Y.Z" on the
  head commit of the release branch on GitHub (`git/tags`, then `git/refs`), then a GitHub Release
  with the notes (a draft with `--draft`). If the tag already exists with a release, the command
  stops. If the tag exists without a release (a run that failed after creating it), the command
  keeps the tag and creates only the release; run the same command again, with the same options. A
  tag given as `VERSION` that is not on the release branch stops the command. With `--json --yes`
  the JSON value gains `published: {tag, url, draft, tag_created}` (progress lines go to stderr).
- `--from` is refused, and version files and the changelog are not changed in `trunk`.

### `standard` and `environments`: the release pull request

- **Start point.** The head of `develop` (`standard`), of `staging` (`environments`), or
  `--from REF` (a branch, tag or commit on GitHub): release up to a commit and leave out what was
  merged after it, for example an unfinished feature (feature flags avoid the need).
- **Tasks.** The open tasks In review with a location label (`on: develop`, `on: staging`) whose
  merged pull requests the start point contains (GitHub's compare of each merge commit, at most 100
  tasks; a task whose pull requests cannot be read is named and left out). A task whose code is not
  in the start point is not listed.
- **Pull requests without a task.** Merged pull requests into the working branch whose merge commit
  is between the previous tag and the start point (one compare, which lists up to 250 commits; the
  100 closed pull requests into the working branch updated last) and whose description closes no
  task are listed under "Other". They never change the version; a release with only those is a
  patch. Release, promotion and back-merge pull requests are left out. With no task and no such
  pull request the command says there is nothing to release and creates nothing.
- **`--yes`.** A pull request from a `release/*` branch into the release branch that is already
  open stops the command and is named. Otherwise, in order: the version files are checked (below);
  `release/<tag>` is created at the start point (`git/refs`); one commit with the version files and
  the changelog is added to it through the Git data API (`git/trees`, `git/commits`, then the
  branch is moved), none when neither is configured; then the pull request "Release <tag>" into the
  release branch, with the notes between `<!-- scrum-release-notes -->` and
  `<!-- /scrum-release-notes -->`. No tag and no GitHub Release are created here. A
  `release/<tag>` branch left by a failed run is reused. `--sprint` and `--draft` are refused.
  `--json --yes` adds `pull_request: {number, url}` and `committed` (the files).

### Version files and changelog

```yaml
release:
  version_files:
    - path: package.json                 # .json with only a path: the top-level "version" is set
    - path: pyproject.toml
      pattern: 'version = "{version}"'   # any other file: the first match with the previous version is replaced
  changelog: CHANGELOG.md                # the notes go on top, under "## vX.Y.Z (date)", after a "# ..." title line
```

A listed file that does not exist, or has no version to replace, stops the command before the
branch is created and names the file. A file that already holds the new version is left as it is.
Before the first release (no previous tag) `{version}` matches any `X.Y.Z`. The files are written
with mode 100644; a JSON file is written back with two-space indentation.

### Publishing on merge: `scrum release finish`

`init` installs `.github/workflows/scrum-release.yml` in presets with a working branch. It runs on
`pull_request_target` `closed` into the release branch, only for a merged pull request from
`release/*` or `hotfix/*`, with `contents: write`, `pull-requests: write` and `issues: write`, and
checks out only `.github` of the release branch, never the code of the pull request. It runs
`scrum release finish`, which reads the event (or `--pr N` by hand) and, each step checking first:

1. **Tag and GitHub Release.** The tag comes from the branch name (`release/v1.4.0`) or, for a
   hotfix, from the line `<!-- scrum-release-tag: v1.4.1 -->` in its description. An annotated
   tag on the merge commit, then the GitHub Release with the notes between the markers of the
   description (edits made there before the merge are published); when the markers are gone, the
   notes are written again from the tasks. A tag that already has a release is reported as already
   published and left alone; a tag left without its release by a failed run gets only the release.
2. **Tasks Done.** Every open task In review with a location label that the merge commit contains,
   and for a hotfix the tasks its description closes: `status: Done`, location label removed,
   closed as completed. A task already Done and closed is not touched.
3. **Back-merge.** For each long-lived branch below the release branch (`develop`; `staging` and
   `develop` in `environments`) that does not contain the head of the release branch, a pull
   request "Back-merge main into develop" from the release branch, unless one is open. Merge it
   with a **merge commit**, not squash: a squash breaks the history and the next release
   conflicts. `scrum next` points to an open back-merge.

A release pull request closed without merging changes nothing. The workflow can open the
back-merge only when *Allow GitHub Actions to create and approve pull requests* is on (`scrum
protect --yes` turns it on; `doctor` warns when it is off); when it cannot, the run fails after
the tag, the Release and the tasks are done, so it is seen. Pull requests opened by the
workflow's own token do not start other workflows: close and reopen the back-merge pull request
to run its required checks.

### Hotfix

`/scrum-github:hotfix` (presets `standard` and `environments`) fixes production without waiting for
the next release:

1. `scrum hotfix N` (open task only; a closed issue is refused) creates or checks out
   `hotfix/N-<slug>` from `origin/main`, assigns the task to you when nobody has it and sets it In
   progress. In `trunk` it stops: `task start` already branches from `main`.
2. `scrum hotfix prepare [--json] [--yes]` on that branch: the version it publishes (the labels of
   the task, a patch for a bug, after the highest version tag on `main`) and the marker line;
   `--json` prints `{tag, version, previous, task, marker, notes}`. With `--yes` it writes the
   version files and the changelog in the working tree and commits them (one local commit, never
   pushed).
3. The pull request (`/scrum-github:task-pr`) targets `main`, closes the task and carries the
   marker. Merging it publishes the version through `scrum release finish` and opens the
   back-merge pull requests.

### Promote (`environments`)

`/scrum-github:promote` (`scrum promote [--json] [--yes]`) lists the tasks In review `on: develop`
whose merge commits `staging` does not contain yet. With `--yes` it opens "Promote develop to
staging" with that list between `<!-- scrum-promotion -->` markers; when it is merged, the tasks
move to `on: staging` (computed from the commits). It says there is nothing to promote when
`staging` already contains the head of `develop`, names an open promotion instead of opening a
second one, and in the other presets stops and points to `/scrum-github:release`.

### Suggestions

After closing a sprint with Done tasks, `scrum sprint close` suggests
`/scrum-github:release --sprint "<sprint>"`. In `trunk`, `scrum next` suggests
`/scrum-github:release` when the most recently closed sprint has Done tasks closed after the latest
version tag: before creating a new sprint when none is open, otherwise after your own task in
progress. It reads the tags only when no step above it applies, and skips the step when they
cannot be read. With a working branch, `scrum next` suggests, right after the setup steps and in
this order: `/scrum-github:protect` when a long-lived branch has no rule, merging an open
back-merge (with its link), `/scrum-github:promote` (`environments`, tasks on `develop` and no
promotion open) and `/scrum-github:release` (tasks In review waiting on the branch the release
starts from and no release pull request open, with how many).

Creating a tag or a branch needs `contents: write` on the token; a 403 points to
`/scrum-github:doctor`. The command does not deploy, publish packages or sign tags.

## Protecting the repository

`/scrum-github:protect` (`scrum protect`) makes GitHub enforce the preset of `branching.preset`.
It reads the repository, prints what differs, and writes only with `--yes` (`--json` prints the
plan as data). It needs admin rights on the repository and is safe to run again.

| Item | What `protect --yes` does |
|---|---|
| Long-lived branches | Creates each missing one (`develop`, `staging`) at the head of `main`. Never moves or deletes a branch |
| Branch rules | One ruleset per long-lived branch, named `scrum: working`, `scrum: staging`, `scrum: release`: pull request required with `governance.approvals` approvals (0: a pull request but no approval), the required checks `pr-check` plus `governance.required_checks`, no force push, no deletion. Merge methods: squash and merge commit on the working branch, merge commit only on staging and `main`; squash only on `main` in `trunk` |
| Version tags | Ruleset `scrum: tags` on `<release.tag_prefix>*`: tags cannot be moved or deleted (creating them stays allowed, so the release workflow needs no bypass) |
| Repository settings | Deletes head branches after merge, allows auto-merge, and allows exactly the merge methods the preset uses |

Rulesets are recognised by the name prefix `scrum: `; one with a different content is updated,
one the preset no longer uses is listed as obsolete and left alone. When GitHub refuses an item
(rules are not available for a private repository on a free plan, or the token has no admin
rights), that item is reported with the reason, the others are still applied, and the command
exits with 1. The merge method per branch uses the ruleset parameter `allowed_merge_methods`.

The `governance` block of `.github/scrum.yml` (all keys optional):

```yaml
governance:
  approvals: 1             # 0 to 6
  required_checks: []      # e.g. [test, lint]; pr-check is always required
  codeowners: []           # e.g. ["@acme/web", "@tuandt"], written into CODEOWNERS by init
```

Files `init` installs for the team, only when the project has none of them (at the root, in
`.github/` or in `docs/`); they are never overwritten afterwards and `uninstall` leaves them:

| File | Content |
|---|---|
| `.github/CODEOWNERS` | `* <governance.codeowners>`, or a commented example when the list is empty |
| `.github/CONTRIBUTING.md` | The branches of the preset, where pull requests go, the title rule, the release path |
| `.github/SECURITY.md` | Supported versions and private vulnerability reporting |
| `.github/dependabot.yml` | GitHub Actions updates once a week in one grouped pull request into the working branch, titled `ci: ...`, labelled `labels.no_task` |

Checks on every pull request (`scrum-pr-link-check.yml`, job `pr-check`, one named step each,
also `scrum pr-check [--title | --source | --link]`):

- **Title**: Conventional Commits: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`,
  `perf`, `build` or `revert`, an optional `(scope)` and `!`, then `: `. Example:
  `feat(auth): log in with email`.
- **Source branch** (`standard`, `environments`): `main` accepts `release/*` and `hotfix/*`;
  staging accepts the working branch and `main`; the working branch accepts any branch but
  staging. The message names the branch to target. Always passes in `trunk`.
- **Linked task**: `Closes #N` in the description, or the `labels.no_task` label.

Release, promotion and back-merge pull requests skip all three; hotfix pull requests are checked.
Every workflow the plugin installs pins its actions to a full commit SHA with the version in a
comment, and the scheduled and issue-triggered ones check out the working branch to read the
configuration and the runtime. `/scrum-github:doctor` reports a default branch other than `main`,
a missing long-lived branch, a branch without a rule, `main` ahead of a lower branch (a missing
back-merge), missing governance files and, with a deployment platform, a `production` environment
without required reviewers.

## Deploying

`deploy.platform` in `.github/scrum.yml` (`none` by default) makes `init` install a deployment for
a web project, mapped to the long-lived branches of the preset:

| Preset | Branch → GitHub environment |
|---|---|
| `trunk` | `main` → `production` |
| `standard` | `develop` → `staging`, `main` → `production` |
| `environments` | `develop` → `development`, `staging` → `staging`, `main` → `production` |

| Platform | What `init` installs | Secrets of each GitHub environment |
|---|---|---|
| `none` | nothing | — |
| `docker` | `.github/workflows/deploy.yml`: builds the image once per source tree (tag = `git rev-parse HEAD^{tree}`), pushes it to `ghcr.io/<owner>/<repo>`, skips the build when that image exists (so a promotion or release merge with the same tree deploys the tested image), then over SSH `docker compose pull && docker compose up -d` with `IMAGE` set. A pushed version tag also tags the image with the version | `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS` (optional variable `DEPLOY_PATH`) |
| `cloudflare` | `.github/workflows/deploy.yml`: `wrangler deploy --env <environment>` (Wrangler pinned, run with `npx`), so `wrangler.toml` needs `[env.staging]`, `[env.production]`, … | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` |
| `vercel` | no workflow: Vercel deploys through its Git integration. The `CONTRIBUTING.md` that `init` writes gets a "Deployment (Vercel)" section: the production branch (`main`, Settings → Environments → Production → Branch Tracking) and the domain to assign to each other long-lived branch (Settings → Domains → Preview → Git Branch) | none in GitHub |

- Each deployment job runs in the GitHub environment of its branch, so the production one waits
  for the required reviewers of the environment `production`. `doctor` warns when a platform is
  set and `production` has no required reviewer (or does not exist), with the settings page.
- A job whose environment lacks a secret fails at its first step and names the missing secrets.
- **Rollback:** Actions → `deploy` → Run workflow with an `environment` and a released `version`
  (`v1.3.0`): the workflow checks out that tag and deploys it (Docker: the image of its tree,
  built only if it is missing) after the environment's approval.
- `init` prints the secret names to create per environment and the settings page; it never asks
  for, prints or stores a value. The templates read secrets only as `${{ secrets.NAME }}`.
- A `.github/workflows/deploy.yml` the project wrote itself (no record in `files.json` and no
  "Generated by scrum-github" header) is never touched: `init` says it was skipped, and `doctor` and
  `uninstall` leave it out. One `init` generated updates like the other generated files.

## Project board (GitHub Projects)

Optional. A GitHub Projects (v2) board shows the tasks as cards. You can drag the cards, and the
labels follow. The `status: …` labels stay the source of truth, so reports, velocity and the
PR automation keep working as before.

| Change | Reaches the other side |
|---|---|
| PR opened or merged, `task start`, issue closed or reopened | Card moves in the same workflow run, if the secret is set |
| Card dragged on the board | Label changes at the next scheduled sync (`poll_cron`), or at once with **Run workflow** on `scrum-project-sync` |
| Card dragged to Done | Label Done, and the issue is closed as completed |
| Card dragged out of Done | The issue is reopened with the label of that column |
| Both sides changed before one sync | The label wins; the card moves back and the issue gets a comment. With *Auto-close issue* on, a card dragged to Done closes the issue at once, so Done wins |
| Card in a column that is not in `status_options` (e.g. "Review") | Nothing changes; the sync prints a warning |
| `points: N` label | Copied to the Points field (one way: editing Points on the board is undone) |

### Turn it on

The quick way: `/scrum-github:project-setup`, or run the wizard yourself in a terminal, from the
root of the repository:

```
bash <plugin>/wizards/project-board.sh
```

It walks through steps 1 to 4 below and the `gh auth refresh` of step 6: it opens each page,
takes the token without showing it, sets the secret, and writes the `project:` block after
asking. It keeps the token in no file. Steps 5 to 7 are printed at the end. The same steps by hand:

1. Create a project from the **Board** template, and link it to the repository.
2. In the project, open **Workflows** and turn off: *Item added to project*, *Item closed*,
   *Item reopened*, *Pull request linked to issue*, *Pull request merged*. These change Status on
   their own. *Auto-add to project* and *Auto-close issue* can stay on.
3. Create a token, and add it as the repository secret `SCRUM_PROJECT_TOKEN`. Paste it on the
   repository's *Settings > Secrets and variables > Actions* page, or run
   `gh secret set SCRUM_PROJECT_TOKEN` in a terminal. Do not run it through a non-interactive
   shell such as Claude Code's `!`, which stores an empty secret. The token can be one of:
   - a classic personal access token with the scopes `repo` and `project`. This was tested with a
     project owned by a user.
   - a fine-grained personal access token (not tested yet):
     - Resource owner: the project's owner.
     - Repository access: this repository only.
     - Permissions: **Issues** read and write, and **Projects** read and write. For a project
       owned by an organization, Projects is under *Organization permissions*.
     - Give it an expiry date.
   - or a GitHub App installation token with the same permissions.

   `GITHUB_TOKEN` cannot reach Projects, so the plain workflow token is not enough.
4. Add the `project:` block to `.github/scrum.yml` (`enabled: true`, `owner`, `number`).
5. Run `scrum init`. This installs `scrum-project-sync.yml`. A repository set up before 0.2.0
   and not updated since may report `scrum-status-sync.yml` as a `conflict`: add
   `--force-file .github/workflows/scrum-status-sync.yml` to take the version that passes the token.
6. On your machine run `gh auth refresh -s project`, then:
   - `scrum project init --dry-run`, then `scrum project init`.
   - The command checks the Status options, stops if a conflicting workflow is still on, creates
     the *Synced status* and *Points* fields, and adds the tasks of open sprints.
7. Hide the *Synced status* field in every view. Commit and push `.github/`.

| Command | What it does |
|---|---|
| `scrum project init [--dry-run] [--allow-builtin-workflows]` | Check and prepare the project; running it again changes nothing |
| `scrum project sync` | Sync every card, and add tasks of open sprints that are missing |
| `scrum project sync --issue N` | Sync one issue (the workflow runs this when an issue's labels or milestone change) |

**Turn it off.** Set `project.enabled: false` and delete `.github/workflows/scrum-project-sync.yml`.
Labels are not touched. The fields on the project can stay or be deleted.

**Cost.** A sync reads the board in pages of 100 items, and writes board fields in batches of 20.
At `*/15 * * * *` the workflow runs about 2,900 times a month. On a private repository you can
limit it to working hours, e.g. `*/15 1-11 * * 1-5` (about 08:00–19:00 in Vietnam, Monday to Friday).

## How statuses change

The workflow `scrum-status-sync` reacts to pull request and issue events:

| Event | Task status |
|---|---|
| PR with `Closes #n` opened, reopened or edited | New → In progress (other statuses are kept) |
| PR merged | Done, and the issue is closed as completed |
| PR closed without merging | Unchanged |
| Issue closed as completed | Done |
| Issue closed as not planned | Unchanged; it never counts |
| Issue reopened | In progress, or stays New if it had `status: New` |

With `statuses.in_review` set (for example `In review`), there are four statuses, New → In
progress → In review → Done, and pull requests move tasks between them:

| Event | Task status |
|---|---|
| Draft PR with `Closes #n` opened or reopened, or a PR converted back to draft | New or In review → In progress |
| PR opened, reopened or edited while not a draft, or marked ready for review | New or In progress → In review |
| PR closed without merging | In review → In progress |
| PR merged | Done, and the issue is closed as completed |

Done is never moved back. Turning the status on mid-sprint changes no task until its next pull
request event. Run `/scrum-github:init` after setting it: it creates the `status: In review`
label and updates the status workflow (it also listens to `converted_to_draft`). With the
project board on, add an `In Review` option to the board's Status field (a column, between In
Progress and Done), or set `project.status_options.in_review` to the name of an existing one, and
run `scrum project init`; it stops if the option is missing. The status table, digest and report then have an In review column or
section, and Needs attention lists tasks waiting for review longer than `attention.review_days`.

Checked on a real repository and a user-owned board with 0.8.1: a draft PR kept the task In
progress; ready for review moved label and card to In review; back to draft, and closing without
merging, moved both back to In progress; reopening moved both to In review; the merge gave Done and
closed the issue. A card dragged to In Review set the label at the next sync.

With `branching.preset: trunk` (or no `branching` block), a merge into **any** branch closes the
task, not only a merge into the default branch. The workflow uses `pull_request_target`, so it
runs the workflow file of the PR's base branch: that branch needs `.github/` from `scrum init`.

### Status follows the code through the branches

With `branching.preset: standard` or `environments`, a task is Done only when its code reaches
the release branch (`main`). Until then it stays open and In review, and a **location label**
(`on: develop`, `on: staging`; prefix `branching.location_prefix`) says which long-lived branch
holds it. A task has at most one location label.

| Pull request merged | Task |
|---|---|
| Task branch into the working branch (`develop`) | Stays open; New or In progress → In review; gets `on: develop` |
| Promotion `develop` → `staging` (`environments`) | The tasks the merge commit contains get `on: staging` in place of `on: develop`; tasks merged into `develop` after the promoted commit keep `on: develop` |
| `release/*` into `main` | Unchanged by this workflow: `scrum release finish` sets the released tasks Done and closes them |
| `hotfix/*` into `main` | Done, closed as completed, location label removed |
| Back-merge (`main` → `develop`, `main` → `staging`) | Unchanged |
| Into any other branch (for example another task branch) | Unchanged |

Which tasks a promotion contains is computed from the commits (the merge commit of each task's
pull request compared with the promotion's merge commit), not from the pull request text. A task
on a branch does not move back to In progress when another of its pull requests is closed or made
a draft. Closing a task by hand as completed still sets Done and drops its location label.

`sprint-status`, the digest, the HTML report and `my-tasks` show each task In review as "in code
review" (no location label: its pull request is open) or "on `<branch>`". Needs attention lists a
task that has waited on a branch more than `attention.promote_days` working days, counted from
the day its location label was added (read from the issue's events). The sprint close preview
lists these tasks as "Merged but not released": they are not in the velocity, and closing carries
them over with their status and label. Release first to count them.

## How the data is stored

- **Sprint** = milestone. Start, end and velocity live in hidden markers in the milestone
  description (`<!-- scrum:start=2014-09-22 end=2014-09-26 -->`, `<!-- scrum:velocity=11 -->`),
  because a milestone only has a due date.
- **Task** = issue with one `status: …` label and at most one `points: N` label. Its time
  estimate, when it has one, is the `<!-- scrum:estimate -->` block at the end of its body.
- **Feature / epic** = issue with `type: feature` / `type: epic`; its tasks (or features) are
  sub-issues. Never counted as a task.
- **Plan** = `docs/plans/<slug>/plan.json` in the repository: a snapshot of how a requirement was
  split. After `apply`, GitHub holds the live status.
- **Done** = closed as completed. Issues closed as "not planned" count nowhere.
- **Velocity** = points of tasks closed as completed in the sprint.
- **Run** (`/scrum-github:run`) = `.scrum/run/<id>.json` in the working tree, never committed
  (`.scrum/` is in `.git/info/exclude`): the tasks, waves, branches and actual times of one run.
  The actual time of a task is also posted on its issue in a `<!-- scrum:actual -->` comment.
- **Generated files** = `.github/scrum/files.json` holds the git hash of each file `init` wrote,
  so a later `init` can tell a file edited by hand from one that is only out of date.
- **Board** (optional) = a GitHub Projects card per task. Its Status mirrors the label; the text
  field *Synced status* holds the status of the last sync, so the sync can tell which side changed.

## Development

```
bash tests/run.sh            # all tests, offline, with a fake gh
bash tests/run.sh config     # only tests/test_config.sh
```

Lint the shell code (not `vendor/`) and validate the plugin, from this directory:

```
shellcheck --severity=warning bin/scrum runtime/bin/scrum runtime/lib/*.sh scripts/*.sh wizards/*.sh tests/run.sh tests/test_*.sh tests/fake-gh
claude plugin validate .     # run by hand; CI does not install Claude Code
```

`tests/.shellcheckrc` and `wizards/.shellcheckrc` hold the settings: the test files are Bash
without a shebang, and the part of the wizard copied from `vendor/pocock/wizard/template.sh` is
not edited. The CI workflow of this repository (`.github/workflows/ci.yml`) runs the tests on
Ubuntu and the `shellcheck` command above on every pull request and every merge, and the tests
on macOS too on release and hotfix pull requests into `main`.

Calculations are pure jq programs in `runtime/lib/jq/` and are tested with JSON fixtures.
GitHub calls go through `ghx`, which tests replace with `tests/fake-gh` via `SCRUM_GH`.

Seven skills and one reference file of [mattpocock/skills](https://github.com/mattpocock/skills)
(MIT) are vendored verbatim in `vendor/pocock/`: `grilling`, `to-spec`, `domain-modeling`,
`to-tickets`, `to-questionnaire`, `pr`, `wizard`, and `triage/AGENT-BRIEF.md`. They are copied
straight from the upstream repository; `vendor/pocock/UPSTREAM.md` records the commit. The
plugin's skills read them and override what does not fit in an "adapter" section. They are
outside `skills/` so they never show up as commands, and `scrum init` does not copy them into
target repos. To update:

```
scripts/vendor-sync.sh                  # clones the upstream repository, then removes the clone
scripts/vendor-sync.sh ~/src/skills     # or: use a clone you already have
git diff vendor/                        # review what changed, and the adapters that depend on it
```

The list of what is vendored is the `ITEMS` table at the top of the script.

### End-to-end tests

The offline tests cover the logic. The steps that check the real GitHub API, the workflows,
the plan skills and the project board on a throwaway repository, with the results of the last
runs, are in [docs/e2e-testing.md](docs/e2e-testing.md).

### Running inside the Claude Code sandbox

The sandbox blocks `gh` from reading its token in the macOS keychain and from reaching GitHub, so
`gh auth status` reports "token invalid" even when you are logged in. `scrum doctor` and the
login error of every command recognize this (the sandbox sets `SANDBOX_RUNTIME=1`) and say so.
Commands that call GitHub must run outside the sandbox (you will be asked to approve them), or
adjust it with `/sandbox`.

If `scrum --version` prints something other than this plugin's version, another `scrum` comes
first on your PATH (the plugin's `bin/` comes after your own entries); use
`bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` or the full path to this repository's `bin/scrum`.
