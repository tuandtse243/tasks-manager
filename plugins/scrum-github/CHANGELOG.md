# Changelog

All notable changes to the `scrum-github` plugin. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the plugin uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
