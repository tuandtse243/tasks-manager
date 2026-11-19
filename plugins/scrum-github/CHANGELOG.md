# Changelog

All notable changes to the `scrum-github` plugin. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the plugin uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.4.0]: https://github.com/tuandtse243/tasks-manager/commit/83dd11b
[0.3.0]: https://github.com/tuandtse243/tasks-manager/commit/cffe202
[0.2.0]: https://github.com/tuandtse243/tasks-manager/tree/main/openspec/changes/archive/2026-11-18-projects-v2-board-sync
[0.1.0]: https://github.com/tuandtse243/tasks-manager/tree/main/openspec/changes/archive/2026-11-18-scrum-github-automation
