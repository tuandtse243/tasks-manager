# scrum-github

Run Scrum on GitHub without a separate tool. A sprint is a milestone, a task is an issue,
and a pull request with `Closes #n` moves its task through **New → In progress → Done**
on its own. Reports, burndown and a daily digest come from the same data.

This plugin automates the six steps of the guide "Quản lý dự án theo Scrum đơn giản với GitHub":

| Step in the guide | Done manually in the guide | What the plugin does |
|---|---|---|
| 1. Create a sprint | Create a milestone | `sprint-new` creates `Sprint {n}` with start/end dates |
| 2. Task states | Create labels by hand | `scrum-init` syncs status, points and helper labels |
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
/scrum-github:scrum-init
```

Commit and push the files it writes under `.github/`.

## Commands

Plugin skills are namespaced, so each command is typed as `/scrum-github:<name>`.
Every skill runs the same script, which also works on its own: `runtime/bin/scrum <command>`.

| Claude Code | Script | What it does |
|---|---|---|
| `/scrum-github:scrum-init` | `scrum init [--dry-run] [--force] [--force-file PATH]` | Create `.github/scrum.yml`, sync labels, install templates, workflows and the runtime |
| `/scrum-github:sprint-new` | `scrum sprint new [--title T] [--start DATE] [--length DAYS] [--goal TEXT]` | Create the next sprint |
| `/scrum-github:project-scan` | `scrum context inventory`, `scrum context status`, `scrum context stamp` | Describe an existing codebase in `docs/project-context.md` (with a commit stamp) |
| `/scrum-github:discover` | `scrum plan init`, `scrum doc check FILE` | Clarify a vague idea through research and an interview; writes `docs/plans/<slug>/brief.md` |
| `/scrum-github:plan` | `scrum plan init`, `scrum plan check FILE`, `scrum plan apply FILE` | Break a requirement into an epic, features and tasks in a plan file; after approval create the issues |
| `/scrum-github:task-new` | `scrum task new --title T [--points N] [--assignee LOGIN] [--bug]` | Create a task in the current sprint |
| `/scrum-github:task-start` | `scrum task start N` | Assign yourself, set In progress, create branch `feat/N-slug` |
| `/scrum-github:task-pr` | `gh pr create` / `gh pr edit`, after you approve | Write the pull request description for the task of the current branch |
| `/scrum-github:sprint-status` | `scrum status [SPRINT]` | Table by person and status with points |
| `/scrum-github:sprint-report` | `scrum report [SPRINT] [--out FILE]` | Self-contained HTML burndown and velocity |
| `/scrum-github:sprint-close` | `scrum sprint close [SPRINT] [--yes] [--create-next]` | Record velocity, carry over open tasks, close the milestone |
| `/scrum-github:project-setup` | `bash wizards/project-board.sh`, then `scrum project init` | Turn on the project board: a wizard for the steps only you can do |

Plan files have their own commands too (all but `check` and `apply` work offline):

| Script | What it does |
|---|---|
| `scrum plan init "<title>" [--slug SLUG]` | Create `<planning.dir>/<slug>/`; print its paths as JSON and which files exist |
| `scrum plan validate FILE` | Check the plan: fields, unique ids, points in the scale, dependencies (unknown, self, cycles) |
| `scrum plan render FILE [--out PATH] [--offline]` | Write the view `plan.md` next to the plan, with estimates |
| `scrum plan check FILE [--offline]` | validate, render, then print what `apply` would do; writes nothing to GitHub |
| `scrum plan apply FILE [--dry-run] [--update]` | Create the missing issues, link sub-issues and dependencies, record the numbers |
| `scrum doc check FILE [--type brief\|context]` | Check the required sections of a brief or of the project context |

> **New in 0.4.0:** `/scrum-github:task-pr` and `/scrum-github:project-setup`; `discover` can
> write a questionnaire for someone who is not in the session; the pull request template has
> "Evidence" and "Merge Danger" sections. A repository set up earlier keeps its old template:
> run `scrum init --force-file .github/pull_request_template.md` to replace it.
>
> **Renamed in 0.3.0:** `/scrum-github:sprint-plan` is now `/scrum-github:plan`. Old plan files
> (no `version` key) still apply as before.

Workflows installed in the target repo call `scrum event`, `scrum pr-check` and `scrum digest`
(and `scrum project sync` when the project board is on, see below).

## Configuration

`.github/scrum.yml` in the target repo. Every key is optional; missing keys use these defaults:

```yaml
version: 1
timezone: UTC                      # used for "today", burndown days and the digest
sprint:
  length_days: 5
  name_pattern: "Sprint {n}"
points:
  scale: [0, 1, 3, 7]              # e.g. [1, 2, 3, 5, 8]
  label_prefix: "points: "
statuses:
  label_prefix: "status: "
  new: New
  in_progress: In progress
  done: Done
labels:
  bug: bug
  feature: "type: feature"         # parent issues created by plan; not counted in points
  epic: "type: epic"               # parent of several features; not counted in points
  meta: "scrum: meta"              # digest issues; not counted
  no_task: no-task                 # lets a PR pass the link check without a task
branch:
  pattern: "feat/{number}-{slug}"
digest:
  enabled: true
  cron: "0 1 * * 1-5"              # baked into the workflow; re-run scrum-init --force-file after changing it
colors: {}                         # label name -> hex color, overrides the defaults
planning:
  dir: docs/plans                  # plan folders: <dir>/<slug>/plan.json, plan.md, brief.md
  context_file: docs/project-context.md   # written by project-scan
  hours_per_point: null            # e.g. 4: plan.md then shows hours next to points
  context_stale_commits: 50        # the project context counts as stale after this many commits
project:                           # optional board, see "Project board" below
  enabled: false
  owner: null                      # user or organization that owns the project
  number: null                     # from the project URL: .../projects/<number>
  status_field: Status
  status_options: {new: Todo, in_progress: In Progress, done: Done}
  synced_field: Synced status      # bookkeeping text field; hide it in views
  points_field: Points             # number field filled from "points: N"; null to turn off
  poll_cron: "*/15 * * * *"        # how often board changes reach the labels
```

## Plans: from a requirement to issues

Three skills form one pipeline. Each can be used alone; `/scrum-github:plan` points to the others
when it needs them.

```
project-scan ──► docs/project-context.md          what the existing code is (optional)
discover     ──► docs/plans/<slug>/brief.md       what to build, confirmed scope (optional)
             ──► docs/plans/<slug>/questionnaire-<who>.md   only for decisions someone else owns
plan         ──► docs/plans/<slug>/plan.json      epic → features → tasks, points, dependencies
             ──► docs/plans/<slug>/plan.md        generated view with estimates
plan apply   ──► GitHub issues                    after you approve; numbers written back
```

Nothing is written to GitHub before you approve the plan. Commit the files under `docs/` yourself.

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
agree to turn each open question into an assumption. You review the table, the findings, the
estimate and what `apply` would do; edit until you approve. Running it again on the same folder
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
          "points": 3, "depends_on": [], "issue": null },
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
- Version 1 files (`{"feature": {...}, "tasks": [...]}`, no `version`) are read as one feature
  `F1` with tasks `T1…Tn` in the current sprint, and rewritten as version 2 when numbers are
  recorded.

### Applying again

| Situation | Command | Result |
|---|---|---|
| See what would happen | `scrum plan apply FILE --dry-run` | Prints creates, links, skips; writes nothing |
| A run failed half-way | `scrum plan apply FILE` | Creates only what has no `issue` yet |
| Tasks added to the plan | `scrum plan apply FILE` | Creates only the new ones and links them |
| Titles, bodies, points or sprints changed in the plan | `scrum plan apply FILE --update` | Updates open issues (one PATCH, one label PUT each); never status labels or assignees; closed issues are skipped and reported |

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
5. Run `scrum init --force-file .github/workflows/scrum-status-sync.yml`. This installs
   `scrum-project-sync.yml`, and adds the token to the status workflow of an earlier install.
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

A merge into **any** branch closes the task, not only a merge into the default branch. The
workflow uses `pull_request_target`, so it runs the workflow file of the PR's base branch: that
branch needs `.github/` from `scrum init`.

## How the data is stored

- **Sprint** = milestone. Start, end and velocity live in hidden markers in the milestone
  description (`<!-- scrum:start=2014-09-22 end=2014-09-26 -->`, `<!-- scrum:velocity=11 -->`),
  because a milestone only has a due date.
- **Task** = issue with one `status: …` label and at most one `points: N` label.
- **Feature / epic** = issue with `type: feature` / `type: epic`; its tasks (or features) are
  sub-issues. Never counted as a task.
- **Plan** = `docs/plans/<slug>/plan.json` in the repository: a snapshot of how a requirement was
  split. After `apply`, GitHub holds the live status.
- **Done** = closed as completed. Issues closed as "not planned" count nowhere.
- **Velocity** = points of tasks closed as completed in the sprint.
- **Board** (optional) = a GitHub Projects card per task. Its Status mirrors the label; the text
  field *Synced status* holds the status of the last sync, so the sync can tell which side changed.

## Development

```
bash tests/run.sh            # all tests, offline, with a fake gh
bash tests/run.sh config     # only tests/test_config.sh
```

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

The sandbox blocks `gh` from reading its token in the macOS keychain, so `gh auth status`
reports "token invalid" even when you are logged in. Commands that call GitHub must run
outside the sandbox (you will be asked to approve them), or adjust it with `/sandbox`.
