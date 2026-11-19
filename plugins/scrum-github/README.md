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
| 4. Link a PR | Write `Solve #1` | PR template with `Closes #`, a check that fails without a link |
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

From the root of this repository, in Claude Code:

```
/plugin marketplace add ./
/plugin install scrum-github@task-manageer
```

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
| `/scrum-github:sprint-status` | `scrum status [SPRINT]` | Table by person and status with points |
| `/scrum-github:sprint-report` | `scrum report [SPRINT] [--out FILE]` | Self-contained HTML burndown and velocity |
| `/scrum-github:sprint-close` | `scrum sprint close [SPRINT] [--yes] [--create-next]` | Record velocity, carry over open tasks, close the milestone |

Plan files have their own commands too (all but `check` and `apply` work offline):

| Script | What it does |
|---|---|
| `scrum plan init "<title>" [--slug SLUG]` | Create `<planning.dir>/<slug>/`; print its paths as JSON and which files exist |
| `scrum plan validate FILE` | Check the plan: fields, unique ids, points in the scale, dependencies (unknown, self, cycles) |
| `scrum plan render FILE [--out PATH] [--offline]` | Write the view `plan.md` next to the plan, with estimates |
| `scrum plan check FILE [--offline]` | validate, render, then print what `apply` would do; writes nothing to GitHub |
| `scrum plan apply FILE [--dry-run] [--update]` | Create the missing issues, link sub-issues and dependencies, record the numbers |
| `scrum doc check FILE [--type brief\|context]` | Check the required sections of a brief or of the project context |

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
decide) and estimates the size (one task, one feature, or an epic). Depth: `--quick` (no agents,
one round), standard (default), `--deep` (web research and an independent review of the brief).

**`/scrum-github:plan <brief | requirement> [--quick]`** splits the requirement into vertical-slice
tasks with acceptance criteria, points from your scale, subtasks and dependencies. An input that
does not say who, what outcome and when it is done gets a suggestion to run `discover` first. The
read-only agent `plan-critic` reviews the draft (missing, out of scope, too large, dependencies,
untestable criteria) before you see it, unless `--quick`. You review the table, the findings, the
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

Four skills of [mattpocock/skills](https://github.com/mattpocock/skills) (MIT) are vendored
verbatim in `vendor/pocock/` (`grilling`, `to-spec`, `domain-modeling`, `to-tickets`), taken
through the `aidw` plugin; `vendor/pocock/UPSTREAM.md` records the commit. The plugin's skills read
them and override what does not fit in an "adapter" section. They are outside `skills/` so they
never show up as commands, and `scrum init` does not copy them into target repos. To update:
`scripts/vendor-sync.sh <aidw>/vendor/pocock`, then review `git diff`.

### End-to-end test on a sandbox repository

The offline tests cover the logic; this scenario checks the real GitHub API and workflows.
Use a throwaway private repository: every step writes labels, milestones, issues and pull requests.
`SCRUM` is the path to `runtime/bin/scrum` in this plugin.

```bash
gh repo create <you>/scrum-sandbox --private --add-readme
gh repo clone <you>/scrum-sandbox && cd scrum-sandbox

# 1. Set up (run twice: the second run must report everything unchanged)
bash "$SCRUM" init --dry-run
bash "$SCRUM" init
git add .github && git commit -m "Set up Scrum on GitHub" && git push
bash "$SCRUM" init

# 2. The guide's example: a 5-day sprint and four tasks
bash "$SCRUM" sprint new --start <monday> --goal "Register, login, post, comment"
bash "$SCRUM" task new --title "Sign up via email, Facebook, LinkedIn" --points 7 --assignee <you>
bash "$SCRUM" task new --title "Login" --points 3 --assignee <you>
bash "$SCRUM" task new --title "Write a post" --points 1 --assignee <you>
bash "$SCRUM" task new --title "Add a comment" --points 3
bash "$SCRUM" task new --title "x" --points 5          # must fail: 5 is not in the scale

# 3. Pull requests
bash "$SCRUM" task start 2                             # branch feat/2-login, #2 In progress
#    commit, push, open a PR with "Closes #2"
#    open a PR from another branch with "Closes #1"    -> #1 moves New -> In progress
#    open a PR with "Solve #3"                         -> scrum-pr-link-check fails and suggests "Closes #3"
#    merge the first two PRs                           -> #1 and #2 Done and closed
#    edit the third PR to "Closes #3"                  -> check passes, #3 In progress

# 4. Progress, report, digest, close
bash "$SCRUM" status
bash "$SCRUM" report --out sprint-1.html               # open it offline
gh workflow run scrum-daily-digest.yml                 # comment on the "Sprint 1 digest" issue
bash "$SCRUM" sprint close                             # plan only
bash "$SCRUM" sprint close --yes --create-next         # velocity recorded, #3 #4 moved to Sprint 2

# 5. Feature breakdown (what /scrum-github:plan applies after approval)
bash "$SCRUM" plan apply plan.json                     # feature issue + tasks as sub-issues
```

Result of the last run (2026-11-18, `tuandtse243/scrum-sandbox`): every step behaved as described.
`init` created 10 labels and 5 files, the second run changed nothing. PR events moved #1 and #2
through In progress to Done and closed them; the `Solve #3` PR failed the check with the
suggestion, and passed after the edit. `status` showed 10 of 14 points done (71%), the report's
burndown read 14, 14, 4 for the first three days, the digest posted on issue #8, and closing the
sprint recorded velocity 10, created Sprint 2 and moved #3 and #4 with a comment. `plan apply`
created feature #9 with #10 and #11 as sub-issues.

#### Plans (0.3.0)

Run inside a sandbox clone that has some code, after `scrum init` (for the `type: epic` label).

```bash
# Offline first: no GitHub call, no write outside docs/
bash "$SCRUM" context inventory                        # has_code: true
bash "$SCRUM" plan init "Blog post comments"           # docs/plans/blog-post-comments/
#    write docs/plans/blog-post-comments/plan.json: an epic, two features, a dependency,
#    one task with "sprint": null (backlog) and the others with "sprint": "current"
bash "$SCRUM" plan validate docs/plans/blog-post-comments/plan.json
bash "$SCRUM" plan render docs/plans/blog-post-comments/plan.json --offline

# Against GitHub
bash "$SCRUM" plan check docs/plans/blog-post-comments/plan.json      # actions, nothing written
bash "$SCRUM" plan apply docs/plans/blog-post-comments/plan.json      # epic, features, tasks, links
bash "$SCRUM" plan apply docs/plans/blog-post-comments/plan.json      # second run: "Nothing to do"
#    set "sprint": "Sprint 1" on the backlog task
bash "$SCRUM" plan apply docs/plans/blog-post-comments/plan.json --dry-run --update
bash "$SCRUM" plan apply docs/plans/blog-post-comments/plan.json --update   # milestone set
bash "$SCRUM" status                                   # epic and feature not counted

# Skills, in Claude Code
/scrum-github:project-scan                             # docs/project-context.md with a stamp
/scrum-github:discover let readers comment under a post
/scrum-github:plan docs/plans/<slug>/brief.md
```

Not run on a sandbox repository yet for 0.3.0: the offline tests (`tests/test_plan.sh`,
`test_doc.sh`, `test_context.sh`) cover the logic with a fake `gh`, and the request and answer
shapes of `sub_issues` and `dependencies/blocked_by` follow GitHub's REST documentation.

#### Project board (0.2.0)

```bash
gh auth refresh -s project
gh project create --owner <you> --title "scrum-sandbox board"      # then link it to the repo
#    turn off the conflicting built-in workflows (project > Workflows)
#    add the secret SCRUM_PROJECT_TOKEN (classic token: repo, project)
#    add project: {enabled: true, owner: <you>, number: <n>} to .github/scrum.yml
bash "$SCRUM" init --force-file .github/workflows/scrum-status-sync.yml   # push .github
bash "$SCRUM" project init --dry-run
bash "$SCRUM" project init                             # twice: the second run changes nothing
gh workflow run scrum-project-sync.yml                 # green: "0 added, 0 changed, N unchanged"
#    open and merge a PR "Closes #4"                   -> card In Progress, then Done, in the status-sync run
#    drag a card Todo -> In Progress, run the sync      -> label "status: In progress"
#    drag a card to Done, run the sync                 -> issue closed as completed
#    drag it back to Todo, run the sync                -> issue reopened, label New, status-sync keeps New
bash "$SCRUM" task new --title "x" --points 1           # card added in Todo with Points 1
```

Result of the last run (2026-11-18, `tuandtse243/scrum-sandbox`, project #1):
- `project init` created *Synced status* and *Points*, and added #3, #4, #10 and #11 in their
  columns with their points. The second run changed nothing.
- The workflow failed with a clear error while the secret was empty, and again while it held a
  bad token (HTTP 401). It passed once the secret held a classic token with `repo` and `project`.
- The PR for #4 moved its card to In Progress and then to Done, within the status-sync runs.
- Dragging #10 changed its label.
- Dragging #11 to Done closed it as completed. Dragging it back to Todo reopened it as New, and
  the status-sync run for the reopen reported "already new".
- A label change started `project sync --issue 3` through `issues.labeled`.
- `task new` put #13 on the board.

Covered only by the offline tests:
- **"Both sides changed: the label wins."** Here, dragging #3 to Done while setting its label to
  New ended as Done, because the built-in *Auto-close issue* closes the issue as soon as the card
  reaches Done, and a completed issue counts as Done. The end state agrees on both sides.
- **A column that is not in `status_options`.** Adding an option through the API recreates every
  option and empties the cards' Status, so this needs the board UI.

### Running inside the Claude Code sandbox

The sandbox blocks `gh` from reading its token in the macOS keychain, so `gh auth status`
reports "token invalid" even when you are logged in. Commands that call GitHub must run
outside the sandbox (you will be asked to approve them), or adjust it with `/sandbox`.
