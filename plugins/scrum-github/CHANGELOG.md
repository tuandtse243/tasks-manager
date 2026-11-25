# Changelog

All notable changes to the `scrum-github` plugin. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the plugin uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **The pull request of `scrum run` failed the plugin's own title check** in the presets
  `standard` and `environments` ("Sprint 2: 2 tasks by AI (#42, #43)" is not a Conventional
  Commit). The title is now `feat: 2 tasks by AI, Sprint 2 (#42, #43)` (and with `--pr-per-wave`
  `feat: … , Sprint 2 wave 1 (…)`); change the type when the tasks are fixes. Found by the first
  run on a real repository.
- **Agents of a run no longer stop when their worktree starts from the wrong commit.** A new
  worktree is often made from the default branch (`main`), so with the `standard` preset (and in
  wave 2) the `implementer` agent found it was not based on the integration branch and stopped.
  While it has changed nothing it now resets the worktree to the base commit, and stops only if
  that fails.

### Changed

- `scrum plan apply` ends by pointing at `plan.html` as the page to review the result on (with
  `plan.md` as the text version), and `/scrum-github:plan` offers to open it.

## [0.13.1] - 2026-11-24

### Fixed

- **Docs of AI runs.** `scrum run` creates its integration branch from the working branch of the
  preset (`develop` in `standard`) and opens its pull requests into it; the README and the
  adoption guide said the default branch.
- The marketplace description names AI runs and releases, as `plugin.json` does.

## [0.13.0] - 2026-11-24

### Breaking

- **With a working branch, a merged pull request no longer makes a task Done.** In the presets
  `standard` and `environments`, a task whose pull request is merged into `develop` stays open
  and In review with the location label `on: develop` (later `on: staging`) until a release brings
  its code into `main`; only then is it Done and closed. Until then it is not in the velocity, and
  closing the sprint carries it over. Projects without a `branching` block behave as before (preset `trunk`: a merge makes
  the task Done). A new `init` writes `branching.preset: standard` (with `statuses.in_review`) into
  the `.github/scrum.yml` it creates; an existing configuration is never changed.

### Added

- **Branching presets.** The block `branching`: `preset` (`trunk`, `standard`, `environments`),
  `main`, `develop`, `staging`, `location_prefix` (default `on: `) and `stale_days`. Every
  command asks the preset for the working branch: `task start`, `run` and `/scrum-github:task-pr`
  start from and target `origin/develop` (`main` in `trunk`). Scheduled and issue-triggered
  workflows check out the working branch. `standard` and `environments` require
  `statuses.in_review`.
- **Status follows the code.** `scrum event` adds and moves the location labels on merges into
  the working branch and on promotions, leaves release and back-merge merges to the release
  workflow, and makes a `hotfix/*` merge Done. `sprint-status`, the digest, the HTML report and
  `my-tasks` show where each task In review is; Needs attention lists tasks that waited on a
  branch longer than `attention.promote_days` (default 5); the sprint close preview lists them as
  "merged but not released".
- **Protecting the repository.** `/scrum-github:protect` and `scrum protect [--json] [--yes]`:
  creates the missing long-lived branches, one ruleset per long-lived branch (pull request with
  `governance.approvals` approvals, required checks `pr-check` plus `governance.required_checks`,
  no force push or deletion, the merge methods of the preset), a tag ruleset, and the merge
  settings. The block `governance`: `approvals`, `required_checks`, `codeowners`.
- **Governance files.** `init` installs `.github/CODEOWNERS`, `CONTRIBUTING.md` (per preset),
  `SECURITY.md` and `dependabot.yml` when the project has none, and never overwrites them.
- **Pull request checks.** The job `pr-check` checks the Conventional Commits title, the source
  branch for the base (only `release/*` and `hotfix/*` into `main`) and the linked task; also
  `scrum pr-check [--title | --source | --link]`. Release, promotion and back-merge pull requests
  are exempt. Every installed workflow pins its actions to a commit SHA.
- **Daily branch commands.** `/scrum-github:sync` (`scrum sync`) merges the latest working branch
  into the task branch and lists conflicts without resolving them; `/scrum-github:branches`
  (`scrum branches [--json]`) shows what waits on each branch, drift, back-merges and stale
  branches; `/scrum-github:cleanup` (`scrum cleanup [--json] [--yes]`) deletes merged branches.
- **Release through a pull request.** With a working branch, `scrum release … --yes` opens
  `release/<tag>` → `main` from the head of `develop` (`staging` in `environments`, or
  `--from REF`), with the notes and a commit of `release.version_files` and `release.changelog`.
  The installed workflow `scrum-release.yml` runs `scrum release finish [--pr N]` on its merge:
  tag on the merge commit, GitHub Release, released tasks Done, back-merge pull requests.
- **Hotfix and promote.** `/scrum-github:hotfix` (`scrum hotfix N`, `scrum hotfix prepare
  [--json] [--yes]`) branches from `main` and publishes a patch version on merge;
  `/scrum-github:promote` (`scrum promote [--json] [--yes]`) opens the promotion `develop` →
  `staging`. `scrum next` suggests protect, the open back-merge, promote and release.
- **Deployment.** The block `deploy` with `platform` (`none`, `vercel`, `cloudflare`, `docker`).
  `init` installs `.github/workflows/deploy.yml` for `docker` (an image per source tree in
  ghcr.io, built only when missing, deployed over SSH with Docker Compose) and `cloudflare`
  (`wrangler deploy --env <environment>`), mapping each long-lived branch to a GitHub environment
  (`staging`/`production` in `standard`; `development`/`staging`/`production` in `environments`),
  with a manual rollback to a released version and a step that names missing secrets. For
  `vercel` it writes the Vercel settings into `CONTRIBUTING.md`. It prints the secret names per
  environment and never asks for or stores a value, and never replaces a `deploy.yml` the project
  wrote itself.
- `doctor` checks the default branch, the long-lived branches and their rules, a missing
  back-merge, the governance files and, with a deployment platform, required reviewers on the
  environment `production` (with the settings page).

### Fixed

- **Parallel `scrum run` commands could lose a change to the run's state.** The lock on
  `.scrum/run/<id>.json` was a folder made with `mkdir`, which is not atomic everywhere: with the
  uutils `mkdir` of Ubuntu 26.04 (today's `ubuntu-latest` runners) several commands could hold
  the lock at once, and the last write won. The lock is now a file the shell creates with
  noclobber (`O_EXCL`), so exactly one command holds it. A `.lock` folder left by an older
  version (only when a command was killed while holding the lock) makes a run command wait and
  then stop with "remove that file": remove that folder with `rmdir`.

### Notes

- The back-merge pull request is opened by the workflow's token, which starts no workflows:
  close and reopen it to run its required checks, then merge it with a merge commit.
- Run `/scrum-github:init` after updating, then `/scrum-github:protect` when you choose a preset
  with a working branch.

## [0.12.0] - 2026-11-23

### Added

- **Releasing a version.** The skill `/scrum-github:release` and the command
  `scrum release [VERSION] [--since TAG] [--sprint S…] [--draft] [--notes-file FILE] [--json] [--yes]`
  publish a version from the Done tasks. The command finds the latest version tag (`v1.2.3` or
  `1.2.3`) on the default branch, gathers the tasks closed as completed since then (or those of
  the sprints named with `--sprint`) with the merged pull requests that closed them, suggests the
  next version (major for a task labelled `breaking`, minor for any task that is not a bug, patch
  otherwise) and writes release notes: breaking changes, features grouped by parent feature, bug
  fixes, each line with the task and pull request numbers, in the configured `language`. Without
  `--yes` it only prints them. With `VERSION --yes` (the version of the preview) it creates an
  annotated tag on the head commit of the default branch on GitHub and a GitHub Release (a draft
  with `--draft`); a release or draft already made for that tag stops it before any write. The skill shows the
  preview, explains the version, lets you change the version or edit the notes, and publishes
  only after you agree.
- The configuration block `release`: `tag_prefix` (default `v`, may be empty), `breaking_label`
  (default `breaking`) and `first_version` (default `0.1.0`, the first release when there is no
  version tag yet).
- `scrum sprint close` suggests `/scrum-github:release --sprint "<sprint>"` after closing a
  sprint with Done tasks, and `scrum next` suggests `/scrum-github:release` when the last closed
  sprint has Done tasks closed after the latest version tag.

### Notes

- Creating the tag needs `contents: write` on the token that runs the command; a 403 points to
  `/scrum-github:doctor`. A run that created the tag but not the release can be run again: it
  creates only the release.
- The command does not edit version files or `CHANGELOG.md` in the repository, does not deploy and
  does not publish packages.

## [0.11.0] - 2026-11-23

### Added

- **Running tasks with AI agents.** The skill `/scrum-github:run` works your tasks with agents:
  each task in its own local git worktree, several at once, wave by wave in the order of
  "blocked by", merged into one integration branch with the tests run after each wave, and one
  pull request for review. It shows the plan, says that the agents run code and tests on your
  machine, and waits for your yes before anything changes. `--dry-run` only shows the plan,
  `--pr-per-wave` opens one pull request per wave (each based on the one before), and
  `--max-parallel K` limits the agents at once. A run that stopped is offered to continue.
- The agent `scrum-github:implementer`: works one task in its worktree from the issue's
  acceptance criteria, writes and runs tests, commits locally with `#N`, never pushes, stays in
  the task's scope, and reports done or failed, how to test by hand and what to look at closely.
- `scrum run`, the runtime under the skill, with tests on a temporary git repository:
  - `plan [N,…] [--json]`: by default your open New tasks of the open sprint labelled
    `ai-ready`, or exactly the numbers given; the tasks left out with their reason (blocked by an
    open task outside the run, closed, a feature or a pull request); the waves; the time estimate
    by waves. Read-only.
  - `start`: stops on uncommitted changes; creates the integration branch
    (`run.branch_pattern`) from the latest default branch, saves the run in
    `.scrum/run/<id>.json` (kept out of git through `.git/info/exclude`), assigns the tasks
    nobody has and sets them In progress.
  - `record N --started | --done --branch B [--notes FILE] | --failed --reason R`: the actual
    time of each task, posted on its issue in an `actual` block next to the estimate. A failed
    task gets the reason as a comment, goes back to New, and the tasks it blocks are left out.
  - `merge N`: `git merge --no-ff`, one merge commit per task; a conflict is aborted, the
    integration branch stays as it was and the task is recorded as `conflict`.
  - `finish [--wave W]`: pushes only the integration branch and opens the pull request, a review
    pack: per task the acceptance criteria as checkboxes, estimate against actual time, how to
    test by hand, what to look at closely, and `Closes #N`; then the failed and left-out tasks.
    No push and no pull request when no task was merged.
  - `status [ID] [--json]`: each task of a run by wave, and what comes next.
- Configuration: the `run` block (`test_command`, `max_parallel`, default 3, `branch_pattern`,
  default `run/{sprint}-{login}`) and `labels.ai_ready` (default `ai-ready`), which must differ
  from the feature, epic, meta and no-task labels. `scrum init` creates the label: run
  `/scrum-github:init` once after updating.
- `plan.json` tasks take `ai_ready` (`true` or `false`): `plan apply` labels the issue, and
  `plan apply --update` adds or removes the label to match the plan.
- `scrum mine` and `scrum next` (and their skills) point to `/scrum-github:run` when you have New
  tasks labelled `ai-ready` in the open sprint that nothing open blocks; `scrum next` asks to
  continue an unfinished run first. Label names are compared without case.
- Safety of a run: `start --expect` runs only the confirmed plan; the integration branch has no
  upstream and is never the default branch; `start` and `finish` refuse to overwrite work on
  origin, and `finish` warns when a task branch is on origin; failure reasons come from files
  (`--notes`, `--reason-file`), never from agent text on a command line; `record --done` checks
  the branch; records and merges take a lock on the run's state; the agent checks that its
  worktree starts from the integration branch and reports its own start and end time.

## [0.10.0] - 2026-11-23

### Added

- **Time estimates.** A task can carry a time estimate next to its points (points stay for
  velocity, burndown, labels and the board): `work_minutes` (how long the work takes),
  `review_minutes` (a person reviewing and testing by hand) and `by` (`ai` or `human`, who does
  the work). It is stored in a small block at the end of the issue body: a line people read
  ("AI ~25m · Review ~20m") and the data in a hidden HTML comment. No label is used for time.
  An issue without the block has no time estimate; a block broken by hand reads as none.
- `scrum task new --work D --review D --by ai|human` writes the block into the new issue.
  Durations are `90`, `25m`, `2h` or `1h30m`; anything else (0 included) is refused before any
  GitHub call, with the formats.
- `plan.json` tasks take an optional `estimate`; `plan validate` checks it, `plan apply` writes
  the block and `plan apply --update` updates it when it differs from the plan.
- `plan.md` shows work and review per task, per feature and for the plan, the tasks without a
  time estimate, and the time to done by waves: the longest task of each wave plus
  `planning.merge_minutes`, then the review time. `plan.html` shows the same on the task cards
  and in two KPIs, and adds a timeline drawn to scale: one bar per estimated task placed by
  wave, the merge gaps, the review bar and a moving "now" line (off under reduced motion). The
  page has no timeline when no task has an estimate.
- `scrum mine` shows each task's time and, for the open sprint, the work left by waves of the
  blocking graph and the review minutes, with the tasks that have no time estimate.
- `scrum status` (and `/scrum-github:sprint-status`) adds "Work left" and "Review left" per
  person and in total, and the number of tasks not done without a time estimate, when a task of
  the sprint has an estimate. Without estimates the table is unchanged.
- `scrum sprint fill` prints the review minutes per person in the sprint and after adding, and
  warns when a person passes their `team[].review_hours`; the warning never stops the command.
  The backlog lists show each task's time estimate.
- Configuration: `team[].review_hours` (hours of review per sprint, a number above 0) and
  `planning.merge_minutes` (minutes to merge and test between two waves, a whole number, 0 or
  more, default 5).
- `/scrum-github:plan` estimates the time of every task (planning rule 7).

### Changed

- `scrum task estimate N [POINTS] [--work D] [--review D] [--by ai|human]`: the points are now
  optional, so the time can change alone; the fields not given keep their value. It needs points
  or at least one time flag. `task estimate N POINTS` works as before.

## [0.9.0] - 2026-11-23

### Added

- **Team.** An optional `team` block in `.github/scrum.yml`: each member's `login`, `areas` and
  `capacity` (points per sprint). Logins are not case-sensitive and a leading `@` is dropped;
  duplicates, empty logins, bad areas and a capacity of 0 or less are configuration errors.
  Without it, the team is the people GitHub lets you assign issues to in the repository.
- `scrum team [--json]`: each member's areas, capacity and load in the open sprint (open tasks,
  points against capacity). Read-only.
- `task new`, `task assign` and `plan check` warn about a login that is not in `team` (only when
  `team` is set); the warning never stops the command.
- `scrum mine [--user LOGIN] [--json]` and the skill `/scrum-github:my-tasks`: every open task of
  one person in every sprint and the backlog, grouped In progress, In review, New in the open
  sprint, other sprints, backlog, with what blocks each one; the pull requests waiting for their
  review; and the task to do next in dependency order. The skill offers
  `/scrum-github:task-start` and waits for the user.
- `task new --backlog` puts a task in the backlog while a sprint is open.
- **One approval for `/plan`.** The skill suggests an assignee for each task from the team (areas
  and load) and a sprint (what fits the open sprint's capacity in dependency order; the rest in
  the backlog), shows everything in one review and asks one question. `plan apply` then creates
  the issues with their milestone and assignees; no `sprint-fill` or assignment step afterwards.
- `plan check` prints the dependency waves, each person's load against their capacity, the
  sprint's points after apply against its capacity (average velocity), what fits and warnings;
  `plan check --json` gives the same to the skill.
- **`plan.html`.** `plan check`, `plan render` and `plan apply` write a self-contained page next
  to `plan.md`: summary, changes since the last view (with a revision number, from
  `.plan-snapshot.json`), the dependency graph by wave with hover highlighting, load and
  capacity, task cards, the plan-critic findings, what apply will do on GitHub, assumptions and
  out of scope. No network, light and dark, motion off under reduced motion, fixed text in the
  configured `language`.
- Plan files accept an optional `review` list (plan-critic findings); `plan apply` ignores it.
- `plan init` writes a `.gitignore` in the plan folder for `plan.html` and
  `.plan-snapshot.json` (an existing one is kept); `plan check` reminds older folders.

### Changed

- `scrum task new` without `--sprint` puts the task in the backlog when no sprint is open,
  instead of failing. With an open sprint it still goes into it. The output always says where
  the task went ("in Sprint 5" or "in the backlog"). `--sprint` with `--backlog` is refused, and
  a sprint that does not exist is still an error.

## [0.8.3] - 2026-11-22

### Fixed

- Skills failed their first command with `scrum: command not found` when the plugin was installed
  with local scope or right after an install, because `bin/` was not on the PATH yet. Every skill
  now calls `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum"` from the first call, and says to run commands
  that reach GitHub outside the sandbox from the start, since `gh` cannot read its keychain token
  or reach GitHub inside it.

## [0.8.2] - 2026-11-20

### Fixed

- `init` asked to add the secret `SCRUM_PROJECT_TOKEN` even when the repository had it; it now
  checks the repository's secrets first.

### Changed

- The In review status was run end to end on a real repository and board (draft, ready, back to
  draft, closed without merge, reopened, merged, and a card dragged on the board); the README
  says so and explains how to add the In Review column. The README and guide explain why a
  repository set up before 0.5.0 sees `conflict` for workflows nobody edited.

## [0.8.1] - 2026-11-20

### Added

- A listing icon, `.claude-plugin/icon.png` (1024 px), drawn from `docs/icon.svg`; a test checks it
  is a square PNG of 512 to 2048 px. The marketplace has a description. `claude plugin validate`
  now reports no warnings for either manifest.

### Changed

- The sprint flow diagram (`docs/diagrams/sprint-flow`) fits one screen from 1440×900 up, with the
  cards below it; it was 1219 px tall at 1440×900.

## [0.8.0] - 2026-11-19

### Added

- Optional fourth status `statuses.in_review` (off by default): with it set, a pull request ready
  for review moves its task to In review, a draft or a PR closed without merging moves it back to
  In progress, and a merge still means Done. `init` creates its label, the status workflow also
  listens to `converted_to_draft`, the board syncs an extra column
  (`project.status_options.in_review`), and the status table, digest, report and Needs attention
  (`attention.review_days`) show it.

### Changed

- The status workflow template listens to `converted_to_draft`; `init` updates unedited copies.
  With the status off, nothing else changes.

## [0.7.0] - 2026-11-19

### Added

- "Needs attention" in `scrum status`, the digest and the HTML report: blocked tasks, tasks In
  progress with no activity for `attention.stale_days` working days, tasks without an assignee
  or points, and a sprint behind the ideal line by more than `attention.behind_percent`.
- `sprint.working_days`: days left count working days, and the ideal line stays flat on days off.
- `language: vi`: the status table, digest, HTML report and sprint summary in Vietnamese.
- The digest can also go to Slack, Google Chat, Mattermost or Telegram through the repository
  secret `SCRUM_DIGEST_WEBHOOK` (`digest.webhook_format`).
- `scrum sprint close` posts a sprint summary (goal, velocity against the sprints before, scope
  change, done and carried-over tasks) on the sprint's digest issue.

### Changed

- **Burndown numbers change** for sprints whose scope changed: the burndown is rebuilt from each
  task's history (when it joined or left the sprint, its points on each day), and the report draws
  the scope line with the points added and removed after the first day. Velocity is unchanged.
- The digest workflow passes the optional webhook secret; `init` updates it when unedited.

## [0.6.0] - 2026-11-19

### Added

- `/scrum-github:backlog` and `scrum backlog [--json]`: open tasks without a sprint, with
  points, assignees, parent feature and open blockers (read for the first 50 tasks), totals and
  how many are not estimated.
- `/scrum-github:sprint-fill` and `scrum sprint fill [SPRINT] [--capacity N] [--add N,N,…] [--yes]`:
  capacity from the average velocity of up to three recent closed sprints, points planned and
  free, the backlog; adding tasks is previewed with warnings (over capacity, no points, blocked
  from outside the sprint) and written only with `--yes`.
- `/scrum-github:task` and `scrum task list | move | estimate | assign | drop`: see tasks, move
  them between sprints and the backlog (with a comment), re-estimate within the scale, assign or
  unassign, drop as not planned. The board is updated in the same run.
- `scrum sprint new` and `scrum next` point to `sprint-fill` when the backlog has tasks and the
  sprint has none.

### Removed

- The transition skill `/scrum-github:scrum-init`: use `/scrum-github:init` (renamed in 0.5.0).

## [0.5.0] - 2026-11-19

### Added

- `/scrum-github:doctor` and `scrum doctor [--json]`: one read-only pass over the tools (jq,
  mikefarah yq, gh login and scopes), the repository (remote, `.github/scrum.yml`, labels), what
  `init` installed (workflows on the default branch, runtime version, generated files) and the
  board secret, each problem with its fix. Recognizes a `gh` failure caused by the Claude Code
  sandbox.
- `/scrum-github:next` and `scrum next [--json]`: the one thing to do next, with its command.
- `scrum uninstall [--dry-run] [--yes]`: removes what `init` installed from the working tree,
  keeps `.github/scrum.yml`, files edited by hand and everything on GitHub.
- `scrum` is on the PATH in Claude Code (the plugin's `bin/`), so skills run `scrum …`.

### Changed

- `init` records the files it writes in `.github/scrum/files.json` and updates the ones nobody
  edited when the configuration (`points.scale`, `digest.cron`, `project.poll_cron`) or the
  plugin changes; only hand-edited files are conflicts. No more `--force-file` after a
  configuration change. A repository set up before 0.5.0 has no record yet, so the first run
  still reports differing files as conflicts.
- **Breaking:** `/scrum-github:scrum-init` is renamed `/scrum-github:init`. The old name still
  works in 0.5.x and says so; it goes away in 0.6.0.
- A `gh` login failure inside the Claude Code sandbox says so and points to
  `/scrum-github:doctor`; skills point there instead of repeating the warning.

## [0.4.0] - 2026-11-19

### Added

- `/scrum-github:task-pr` writes the pull request description for the task of the current
  branch (Summary, Evidence, Merge Danger, always `Closes #N`) and creates or edits the PR only
  after you approve it.
- `/scrum-github:project-setup` and a wizard that walk you through the steps of turning on the
  Project board that only a person can do (create the project, turn off its built-in
  workflows, create a token, set the `SCRUM_PROJECT_TOKEN` secret).
- `/scrum-github:discover` checks your terms against the Glossary of the project context, and
  writes a questionnaire for a decision that belongs to someone who is not in the session.
- Vendored verbatim from `mattpocock/skills`: `to-questionnaire`, `pr`, `wizard` and
  `triage/AGENT-BRIEF.md`.

### Changed

- The pull request template has "Evidence" and "Merge Danger" sections. A repository set up
  earlier keeps its old template: run `scrum init --force-file .github/pull_request_template.md`
  to replace it.
- `/scrum-github:plan`, the `plan-critic` agent and `/scrum-github:task-new` write task
  descriptions as behaviour with testable criteria, without file paths or line numbers.
- `scripts/vendor-sync.sh` takes skills straight from a clone of `mattpocock/skills`.
  **Breaking for maintainers:** its `SRC` argument is now the root of the upstream repository.

## [0.3.0] - 2026-11-19

### Added

- Plan files in the target repo at `docs/plans/<slug>/plan.json` (format version 2: optional
  epic, features, tasks with stable ids, `depends_on` and subtasks), with a generated `plan.md`.
- `scrum plan validate`, `scrum plan render`, and a re-runnable `scrum plan apply` with
  `--dry-run` and `--update`. Tasks without a sprint go to the backlog; `depends_on` becomes
  GitHub's "blocked by".
- Estimates in hours (`planning.hours_per_point`) and in sprints from past velocity.
- The `type: epic` label (`labels.epic`), not counted in points.
- `/scrum-github:discover` turns a vague request into a confirmed brief; the `researcher` agent
  looks things up on the web with sources.
- `/scrum-github:project-scan` writes `docs/project-context.md` with a commit stamp; the
  `codebase-scout` agent reads the code for it.
- The `plan-critic` agent reviews a task breakdown before you approve it.
- Vendored verbatim from `mattpocock/skills`: `grilling`, `to-spec`, `domain-modeling` and
  `to-tickets`.

### Changed

- **Breaking:** `/scrum-github:sprint-plan` is renamed `/scrum-github:plan`. Old plan files
  (no `version` key) still apply as before.

## [0.2.0] - 2026-11-18

### Added

- Optional sync with a GitHub Projects board (`project:` in `.github/scrum.yml`, off by
  default): the `status: …` label stays the source of truth, and the board's Status field can
  be edited too; a `Synced status` field tells which side changed.
- Dragging a card to Done closes the issue as completed; dragging it out reopens it.
- `scrum project init [--dry-run]` and `scrum project sync`, and the `scrum-project-sync.yml`
  workflow, installed only when the board is on.
- A `Points` number field on the board, synced from the `points: N` label.

### Changed

- A reopened task that has the `status: New` label stays New instead of moving to In progress.

## [0.1.0] - 2026-11-18

### Added

- The `scrum-github` plugin: sprints as milestones, tasks as issues, status and points as
  labels, native assignees, and `Closes #n` to link a pull request to its task.
- `.github/scrum.yml` for the point scale, status names, sprint length and special labels.
- `/scrum-init`, `/sprint-new`, `/sprint-plan`, `/task-new`, `/task-start`, `/sprint-status`,
  `/sprint-report` (HTML burndown) and `/sprint-close` (moves unfinished tasks, records
  velocity).
- Workflows for the target repo: status sync from pull request and issue events, a check that
  each pull request links a task, and a daily digest.
- A task issue form with a points dropdown and a pull request template with `Closes #`.

[0.8.0]: https://github.com/tuandtse243/tasks-manager/tree/main/plugins/scrum-github
[0.7.0]: https://github.com/tuandtse243/tasks-manager/commit/6defddf
[0.6.0]: https://github.com/tuandtse243/tasks-manager/commit/b47c3ac
[0.5.0]: https://github.com/tuandtse243/tasks-manager/commit/0ee7981
[0.4.0]: https://github.com/tuandtse243/tasks-manager/commit/83dd11b
[0.3.0]: https://github.com/tuandtse243/tasks-manager/commit/cffe202
[0.2.0]: https://github.com/tuandtse243/tasks-manager/tree/main/openspec/changes/archive/2026-11-18-projects-v2-board-sync
[0.1.0]: https://github.com/tuandtse243/tasks-manager/tree/main/openspec/changes/archive/2026-11-18-scrum-github-automation
