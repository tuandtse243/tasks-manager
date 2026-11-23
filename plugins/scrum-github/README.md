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
| `/scrum-github:next` | `scrum next [--json]` | The one thing to do next, with its command. Read-only |
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
| `/scrum-github:task-start` | `scrum task start N` | Assign yourself, set In progress, create branch `feat/N-slug` |
| `/scrum-github:run` | `scrum run plan [N,…]`, `scrum run start`, `scrum run record`, `scrum run merge N`, `scrum run finish [--wave W]`, `scrum run status [ID]` | Work your `ai-ready` tasks with AI agents, one local git worktree each, wave by wave, into one pull request ready for review; `--dry-run` shows the plan only. See "Running tasks with agents" |
| `/scrum-github:task` | `scrum task list [--mine] [--sprint S \| --backlog] [--status ROLE]`, `scrum task move N… --sprint S \| --backlog`, `scrum task estimate N [P] [--work D] [--review D] [--by ai\|human]`, `scrum task assign N LOGIN… [--unassign]`, `scrum task drop N [--reason T]` | See tasks; move, re-estimate, assign or drop them without editing labels by hand |
| `/scrum-github:task-pr` | `gh pr create` / `gh pr edit`, after you approve | Write the pull request description for the task of the current branch |
| `/scrum-github:sprint-status` | `scrum status [SPRINT]` | Table by person and status with points; work and review minutes left when tasks have time estimates |
| `/scrum-github:sprint-report` | `scrum report [SPRINT] [--out FILE]` | Self-contained HTML burndown and velocity |
| `/scrum-github:sprint-close` | `scrum sprint close [SPRINT] [--yes] [--create-next]` | Record velocity, carry over open tasks, close the milestone |
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
   `run/sprint-5-tuandt`) from the latest default branch, with no upstream (never the default
   branch itself), saves the run in
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
   command line. `--done` refuses the integration and default branches and a branch that does not
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
   into the default branch, the **review pack**: for each merged task its acceptance criteria as
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
must be merged first and that the base must then be changed to the default branch (`Closes #N`
only closes tasks there). Each wave gets one pull request, in order: `finish` without `--wave`
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

A merge into **any** branch closes the task, not only a merge into the default branch. The
workflow uses `pull_request_target`, so it runs the workflow file of the PR's base branch: that
branch needs `.github/` from `scrum init`.

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
Ubuntu and the `shellcheck` command above on every pull request, and the tests on macOS too on
every push to `main`.

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
