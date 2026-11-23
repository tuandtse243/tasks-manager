# Project context: tasks-manager (scrum-github plugin)

<!-- scrum:context sha=cffe2020fff3 date=2026-11-19 -->

<!-- Written by /scrum-github:project-scan; the line above is replaced by `scrum context stamp`.
     Keep the "## " headings exactly as they are: `scrum doc check` reads them
     (runtime/share/doc-sections.json). Every statement about the code names the file or folder
     it comes from, in parentheses. Write "unknown" (or "chưa rõ" in Vietnamese) when the
     repository does not say; never guess. Everything under "Team notes" is written by people and
     is kept as it is on every scan. -->

## Overview

This repository holds `scrum-github`, a Claude Code plugin that lets a team (PO, Scrum Master,
Dev) run Scrum on GitHub alone. Sprints are milestones, tasks are issues, and status and points
are labels; there is no separate database and no Jira or Trello (docs/adoption-guide.md,
openspec/changes/archive/2026-11-18-scrum-github-automation/proposal.md). It replaces manual
steps (milestones, labels, issues, PR linking, status changes, progress checks) with slash
commands, a `scrum` Bash CLI and GitHub Actions workflows installed into the target repo
(plugins/scrum-github/README.md). Version 0.3.0 adds AI-assisted requirement planning: scan the
project, clarify a requirement into a brief, split it into a reviewed plan, then create the
issues (openspec/changes/requirement-planning/proposal.md, plugins/scrum-github/.claude-plugin/plugin.json).

The repo is distributed as a local Claude Code marketplace named `tasks-manager`
(.claude-plugin/marketplace.json). Who uses it in practice beyond a sandbox repo: unknown.

## Technology

- **Bash 3.2+**: the whole CLI; no associative arrays or `mapfile`, lists passed as JSON
  (plugins/scrum-github/runtime/bin/scrum, plugins/scrum-github/runtime/lib/common.sh).
- **jq 1.6+**: all decisions and calculations, as pure programs sharing the module `scrum.jq`
  (plugins/scrum-github/runtime/lib/jq/).
- **yq v4 (mikefarah)**: reads `.github/scrum.yml`; the Python `yq` is refused
  (plugins/scrum-github/runtime/lib/common.sh).
- **GitHub CLI `gh`**: every GitHub call, REST and GraphQL; scopes `repo,workflow`, plus
  `project` for the board (plugins/scrum-github/runtime/lib/common.sh, plugins/scrum-github/README.md).
  Minimum `gh` version: unknown.
- **git**: branches for `task start`, and inventory/staleness for `context`
  (plugins/scrum-github/runtime/lib/cmd_task.sh, plugins/scrum-github/runtime/lib/cmd_context.sh).
- **GraphQL** files for GitHub Projects v2 (plugins/scrum-github/runtime/share/graphql/); **JSON
  Schema 2020-12** for the plan file (plugins/scrum-github/runtime/share/plan.schema.json); one
  self-contained **HTML** report template (plugins/scrum-github/runtime/share/report.html).
- **Claude Code plugin format**: skills, agents, plugin and marketplace manifests
  (plugins/scrum-github/skills/, plugins/scrum-github/agents/, plugins/scrum-github/.claude-plugin/plugin.json).
- **GitHub Actions** in the target repo: `actions/checkout@v4` on `ubuntu-latest`
  (plugins/scrum-github/templates/github/workflows/).
- **OpenSpec** (`schema: spec-driven`) for specifying changes to the plugin itself (openspec/config.yaml).
- Deployment: there is no server. `scrum init` copies the runtime into the target repo's
  `.github/scrum/`, where the workflows run it (plugins/scrum-github/runtime/lib/cmd_init.sh).
  Supported: github.com only (no GitHub Enterprise Server); Windows only through WSL
  (docs/adoption-guide.md). Publishing beyond the local marketplace: unknown.

## Directory structure

| Folder | What it holds |
|---|---|
| `.claude-plugin/` | Marketplace manifest `tasks-manager` pointing to `./plugins/scrum-github` (.claude-plugin/marketplace.json) |
| `plugins/scrum-github/.claude-plugin/` | Plugin manifest: name, version 0.3.0, description, keywords (plugin.json) |
| `plugins/scrum-github/runtime/bin/` | `scrum`, the single CLI entry point; dispatches to `lib/cmd_*.sh` (runtime/bin/scrum) |
| `plugins/scrum-github/runtime/lib/` | Shell libraries: `common.sh` (gh wrappers, helpers), `config.sh` (load/merge/validate), `project.sh` (board sync), one `cmd_*.sh` per command group |
| `plugins/scrum-github/runtime/lib/jq/` | Pure jq decision programs (`event-decide`, `label-plan`, `plan-actions`, `plan-validate`, `burndown`, `digest`, `project-sync-plan`, `context-inventory`, ...) and the shared module `scrum.jq` |
| `plugins/scrum-github/runtime/share/` | Data: `defaults.json`, `doc-sections.json`, `plan.schema.json`, `report.html`, `graphql/` |
| `plugins/scrum-github/skills/` | 10 user-facing skills: `scrum-init`, `sprint-new`, `sprint-close`, `sprint-status`, `sprint-report`, `task-new`, `task-start`, `plan`, `discover`, `project-scan` |
| `plugins/scrum-github/agents/` | Read-only subagents: `codebase-scout`, `plan-critic`, `researcher` |
| `plugins/scrum-github/reference/` | Shared rules and templates read by skills: `planning-rules.md`, `brief-template.md`, `project-context-template.md` |
| `plugins/scrum-github/templates/` | What `scrum init` installs: `scrum.yml`, issue form `task.yml`, PR template, four workflows |
| `plugins/scrum-github/vendor/pocock/` | Four unmodified skills from mattpocock/skills (MIT): `grilling`, `to-spec`, `domain-modeling`, `to-tickets`; kept outside `skills/` so they are not commands (vendor/pocock/UPSTREAM.md) |
| `plugins/scrum-github/scripts/` | `vendor-sync.sh`, re-copies the vendored skills |
| `plugins/scrum-github/tests/` | Bash test runner `run.sh`, `fake-gh` stub, 12 `test_*.sh` files, `fixtures/` |
| `openspec/specs/` | Main specs, one per capability (7) |
| `openspec/changes/` | Change in progress `requirement-planning`; finished changes under `archive/YYYY-MM-DD-<name>/` |
| `docs/` | `adoption-guide.md`, the adoption guide; this context document |
| `.claude/` | OpenSpec tooling only: `commands/opsx/*` and `skills/openspec-*` |

## Main flows

- **Skill → CLI**: each skill runs `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" <cmd>` from the
  target repo root; only the CLI touches GitHub (plugins/scrum-github/skills/task-start/SKILL.md,
  plugins/scrum-github/reference/planning-rules.md).
- **Config load**: `.github/scrum.yml` → `yq -o=json` → deep-merge over `share/defaults.json` →
  `validate-config.jq`; offline `context` commands fall back to defaults when the file is missing
  (plugins/scrum-github/runtime/lib/config.sh).
- **`scrum init`**: create or keep `scrum.yml`; sync labels via `label-plan.jq` (never deletes);
  render templates with `{{KEY}}` substitution, reporting created/unchanged/conflict/overwritten
  (`--force` to overwrite); copy the runtime to `.github/scrum/`; `--dry-run`. The skill does
  dry-run → confirm → apply → commit (plugins/scrum-github/runtime/lib/cmd_init.sh,
  plugins/scrum-github/skills/scrum-init/SKILL.md).
- **Sprint new**: title from `name_pattern`, end = start + length − 1, milestone description gets
  a `<!-- scrum:start=… end=… -->` marker, overlap only warns, duplicate name is rejected
  (plugins/scrum-github/runtime/lib/jq/sprint-new-plan.jq, openspec/specs/sprint-lifecycle/spec.md).
- **Sprint close**: preview first; with `--yes` record velocity (`<!-- scrum:velocity=N -->`),
  move open tasks to the next sprint with a "Carried over from" comment (`--create-next` creates
  it), close the milestone (plugins/scrum-github/runtime/lib/cmd_sprint.sh, close-plan.jq).
- **Task new / start**: `task new` posts an issue from `task-payload.jq` with `status: New`;
  `task start N` first creates/checks out `feat/{number}-{slug}` from `origin/<default>` (if git
  fails, GitHub is untouched), then assigns me if unassigned and sets In progress
  (plugins/scrum-github/runtime/lib/cmd_task.sh).
- **Event automation** (workflow `scrum-status-sync` → `scrum event` → `event-decide.jq`): PR
  opened → In progress; PR merged → Done and issue closed; issue closed as completed → Done, as
  not planned → nothing; reopened → In progress; opened → points label from the form. Status
  never moves backwards (plugins/scrum-github/runtime/lib/cmd_event.sh,
  openspec/specs/pr-task-linking/spec.md).
- **PR link check** (`scrum-pr-link-check` → `scrum pr-check`): fails without a closing keyword
  (close/fix/resolve) unless labeled `no-task`; `Solve #n` gets a hint
  (plugins/scrum-github/runtime/lib/cmd_event.sh, plugins/scrum-github/runtime/lib/jq/links.jq).
- **Status change**: `set_status` replaces the whole label set in one PUT, so a task has exactly
  one status, then updates the board card (plugins/scrum-github/runtime/lib/common.sh).
- **Board sync** (`scrum-project-sync`, only when `project.enabled`): compares label (L), board
  Status (B) and `Synced status` (S); only B changed → label follows; only L changed → board
  follows; both → label wins; card dragged to Done closes the issue. Runs on cron, dispatch and
  label/milestone events (openspec/specs/project-board-sync/spec.md, plugins/scrum-github/runtime/lib/project.sh).
- **Reporting**: `scrum status` table; `scrum report` injects JSON into `report.html` →
  `scrum-reports/<sprint-slug>.html`; `scrum digest` comments on a `"<sprint> digest"` issue
  labeled `scrum: meta` (plugins/scrum-github/runtime/lib/cmd_report.sh,
  plugins/scrum-github/runtime/lib/cmd_digest.sh).
- **Requirement planning (0.3.0)**: `project-scan` → `docs/project-context.md`; `discover` →
  `<planning.dir>/<slug>/brief.md` (interview rounds via vendored `grilling`, written via
  `to-spec`); `plan` → `plan.json` + `plan.md` (drafted via `to-tickets`, reviewed by
  `plan-critic` unless `--quick`); after the user approves, `scrum plan apply` creates issues,
  writes numbers back atomically, links sub-issues and "blocked by", with an issue-body fallback
  when GitHub refuses. `--update` edits title/body/points/sprint of open issues only
  (plugins/scrum-github/skills/, plugins/scrum-github/runtime/lib/cmd_plan.sh,
  plugins/scrum-github/README.md). After apply, GitHub is the source of truth; nothing syncs back
  into the plan (openspec/changes/requirement-planning/design.md).
- **Context commands**: `scrum context inventory|status|stamp` (offline) and
  `scrum doc check FILE` validate headings and the stamp against `share/doc-sections.json`
  (plugins/scrum-github/runtime/lib/cmd_context.sh, plugins/scrum-github/runtime/bin/scrum).

## Data model

- **Sprint**: a GitHub milestone `Sprint {n}`; dates from the `scrum:start/end` description
  marker (fallback `created_at`/`due_on`); velocity from `scrum:velocity` marker. Current sprint =
  the open sprint containing today, else the open sprint ending first
  (plugins/scrum-github/runtime/lib/jq/scrum.jq).
- **Task**: an issue that is not a PR and not labeled feature, epic or meta. Role `new`,
  `in_progress`, `done` (closed as completed, whatever the labels) or `dropped` (closed as not
  planned). Points from the first `points: N` label. Body sections: description,
  `### Acceptance criteria`, `### Subtasks`, "Part of #parent" (plugins/scrum-github/runtime/lib/jq/scrum.jq).
- **Feature / Epic**: issues labeled `type: feature` / `type: epic`; tasks are sub-issues of a
  feature, features of an epic; an epic has no points (docs/adoption-guide.md,
  openspec/changes/requirement-planning/specs/work-plan/spec.md).
- **Backlog**: issues with no milestone (docs/adoption-guide.md).
- **Labels**: `status: New|In progress|Done`, `points: <n>` per scale value, `bug`,
  `type: feature`, `type: epic`, `scrum: meta`, `no-task`; obsolete ones are reported, never
  deleted (plugins/scrum-github/runtime/lib/jq/label-plan.jq).
- **Config `.github/scrum.yml`** (defaults in plugins/scrum-github/runtime/share/defaults.json,
  commented in plugins/scrum-github/templates/scrum.yml): `version`, `timezone` (UTC),
  `sprint.{length_days (5), name_pattern}`, `points.{scale (0,1,3,7), label_prefix}`,
  `statuses.{label_prefix, new, in_progress, done}`, `labels.{bug, feature, epic, meta, no_task}`,
  `branch.pattern`, `digest.{enabled, cron}`, `colors`,
  `planning.{dir (docs/plans), context_file (docs/project-context.md), hours_per_point, context_stale_commits (50)}`,
  `project.{enabled (false), owner, number, status_field, status_options, synced_field, points_field, poll_cron}`.
  This repo itself has no `.github/scrum.yml`.
- **Plan file v2** `<planning.dir>/<slug>/plan.json`: `version: 2`, `title`, `sprint` (name,
  `"current"` or null = backlog), `epic` or null, `features[] {id, title, body, issue, tasks[]}`,
  `assumptions[]`, `out_of_scope[]`; task `{id, title, body, acceptance[], subtasks[], points,
  depends_on[], assignees[], bug, sprint, issue}`. v1 `{sprint, feature, tasks}` is normalized to
  v2 (plugins/scrum-github/runtime/share/plan.schema.json, plan-normalize.jq).
- **Brief / context document**: required `## ` sections and the context stamp are listed in
  plugins/scrum-github/runtime/share/doc-sections.json.
- **Projects v2 board**: single-select `Status` (Todo / In Progress / Done), text
  `Synced status`, number `Points` (plugins/scrum-github/runtime/share/defaults.json,
  plugins/scrum-github/runtime/share/graphql/).

## External integrations

- **GitHub REST via `gh api`**: labels, milestones, issues, comments, assignees, sub-issues
  (`issues/N/sub_issues`), dependencies (`issues/N/dependencies/blocked_by`)
  (plugins/scrum-github/runtime/lib/common.sh, plugins/scrum-github/runtime/lib/cmd_plan.sh).
  Sub-issue and dependency endpoints not yet tested against real GitHub for 0.3.0
  (plugins/scrum-github/README.md).
- **GitHub GraphQL (Projects v2)** via `gh api graphql -F query=@file`; uses
  `SCRUM_PROJECT_TOKEN` when set, since the workflow `GITHUB_TOKEN` cannot reach Projects
  (plugins/scrum-github/runtime/lib/common.sh, plugins/scrum-github/runtime/lib/project.sh).
  Fine-grained tokens: "not tested yet" (plugins/scrum-github/README.md).
- **GitHub Actions**: four workflows in the target repo, `GH_TOKEN: github.token`, sparse
  checkout of `.github` only so PR code is never run
  (plugins/scrum-github/templates/github/workflows/).
- **Issue form and PR template**: `task.yml`, `pull_request_template.md`
  (plugins/scrum-github/templates/github/).
- **Web search**: only the `researcher` agent (WebSearch, WebFetch) (plugins/scrum-github/agents/researcher.md).
- **Vendored upstream**: mattpocock/skills at commit `4ae2317…` (plugins/scrum-github/vendor/pocock/UPSTREAM.md).

## Conventions

- **Logic in jq, I/O in shell**: decisions are pure jq run through `jqlib`, tested offline;
  skills hold no logic; repeated deterministic work becomes a `scrum` command
  (plugins/scrum-github/runtime/lib/common.sh, openspec/changes/requirement-planning/design.md).
- **Shell style**: `set -euo pipefail`, Bash 3.2 compatible, messages via `die`/`warn`/`info`
  (`scrum: error:`), atomic writes via `write_atomic`, board functions return 1 with `PROJECT_ERR`
  instead of exiting (plugins/scrum-github/runtime/lib/common.sh, plugins/scrum-github/runtime/lib/project.sh).
- **Markers** in GitHub text are HTML comments `<!-- scrum:… -->` (plugins/scrum-github/runtime/lib/jq/scrum.jq).
- **Idempotent**: `init`, `project init`, `plan apply` are safe to rerun (plugins/scrum-github/README.md).
- **Names**: branch `feat/{number}-{slug}` (slug lowercase ASCII, ≤ 40 chars); sprint `Sprint {n}`;
  commands `/scrum-github:<name>` (plugins/scrum-github/runtime/share/defaults.json, plugins/scrum-github/README.md).
- **Skills**: YAML front matter (`name`, `description`, optional `argument-hint`) then numbered
  steps; a vendored skill is used with an "Adapter for X" section that wins where they differ;
  shared rules in `reference/planning-rules.md` (plugins/scrum-github/skills/plan/SKILL.md).
- **Planning rules**: nothing goes to GitHub before user approval; agents only read; facts cite a
  path or URL; tasks are vertical slices; template headings kept exactly
  (plugins/scrum-github/reference/planning-rules.md).
- **Language**: everything in the repository is written in English: code, README, docs,
  commits, pull requests and new OpenSpec documents. Vietnamese only when asked for. Older
  OpenSpec documents (openspec/specs/, openspec/changes/archive/) are still in Vietnamese
  (docs/adoption-guide.md, README.md).
- **OpenSpec workflow**: propose → apply → sync → archive to `changes/archive/YYYY-MM-DD-<name>`;
  specs written as `### Requirement:` (SHALL/MUST) with `#### Scenario:` WHEN/THEN; tasks.md
  items say how to verify ("Kiểm tra: …") (.claude/commands/opsx/, openspec/specs/,
  openspec/changes/requirement-planning/tasks.md).
- **Team rules for adopters**: every PR closes a task or carries `no-task`; use `Closes #n`;
  don't edit `status:` labels by hand; close abandoned tasks as not planned; don't change points
  mid-sprint (docs/adoption-guide.md).
- Branching and commit rules for this repo itself: unknown (no config enforces them).

## Running and testing

- **Install** (in Claude Code): `/plugin marketplace add ./`, `/plugin install scrum-github@tasks-manager`,
  then `/scrum-github:scrum-init` in the target repo (plugins/scrum-github/README.md).
- **Tests**: `bash tests/run.sh` from `plugins/scrum-github/`, or `bash tests/run.sh <pattern>`;
  offline. Hand-written runner: finds `test_*` functions, runs each in a subshell with a temp
  `$T`; assertions `assert_eq`, `assert_json_eq`, `assert_contains`, `assert_not_contains`,
  `assert_status` (plugins/scrum-github/tests/run.sh).
- **Fake GitHub**: `SCRUM_GH=tests/fake-gh` routes calls to fixtures and logs them; also
  `SCRUM_REPO`, `SCRUM_REPO_DIR`, `SCRUM_TODAY`, `SCRUM_NOW` (plugins/scrum-github/tests/fake-gh,
  plugins/scrum-github/runtime/lib/common.sh).
- **Manual end-to-end**: documented scenario against a throwaway sandbox repo, last run
  2026-11-18; the 0.3.0 plan flow has not yet been run against a real repo (plugins/scrum-github/README.md).
- **CI for this repo**: none found (no workflow outside `plugins/scrum-github/templates/`).
- **Lint**: unknown (none declared).

## Glossary

| Term | Meaning | Where it appears |
|---|---|---|
| Sprint | A GitHub milestone named by `sprint.name_pattern`, with start and end dates in a description marker | runtime/lib/jq/scrum.jq |
| Current sprint | The open sprint whose dates contain today, else the open sprint ending first; `"current"` in a plan | runtime/lib/jq/scrum.jq, plan.schema.json |
| Task | An issue that is not a PR, feature, epic or meta issue; the only thing that carries points. Also used for OpenSpec `tasks.md` checklist items (second sense) | runtime/lib/jq/scrum.jq, openspec/changes/*/tasks.md |
| Feature | An issue labeled `type: feature` whose sub-issues are tasks; in a plan, an entry of `features[]`; in a brief, a size class (task / feature / epic) — three senses | templates/scrum.yml, plan.schema.json, skills/discover/SKILL.md |
| Epic | An issue labeled `type: epic` whose sub-issues are features; has no points | plan.schema.json, openspec/changes/requirement-planning/specs/work-plan/spec.md |
| Subtask | A checklist item under `### Subtasks` inside a task issue, not a separate issue. _Avoid_ confusing with GitHub "sub-issue" (how a task hangs under a feature) | plan.schema.json, openspec/specs/task-management/spec.md |
| Backlog | Issues with no milestone (plan `sprint: null`) | docs/adoption-guide.md |
| Meta issue | A bookkeeping issue labeled `scrum: meta` (e.g. the digest issue), excluded from metrics | templates/scrum.yml, openspec/specs/sprint-reporting/spec.md |
| Status | Exactly one `status: New/In progress/Done` label on a task. Also: the board's `Status` field (Todo/In Progress/Done), the `scrum status` command and `scrum context status` — four senses | runtime/lib/jq/scrum.jq, runtime/share/defaults.json |
| Done | Closed as completed; closed as "not planned" (dropped) counts nowhere | runtime/lib/jq/scrum.jq, README.md |
| Points (story points) | A value from `points.scale`, stored as a `points: N` label and copied one-way to the board's `Points` field | runtime/share/defaults.json |
| Velocity | Sum of points of tasks closed as completed in a sprint, stored as `scrum:velocity=N` | openspec/specs/sprint-lifecycle/spec.md, runtime/lib/jq/scrum.jq |
| Carry over | Moving a closing sprint's open tasks to the next sprint | runtime/lib/cmd_sprint.sh |
| Burndown | Ideal vs remaining points per day of a sprint | runtime/lib/jq/scrum.jq, openspec/specs/sprint-reporting/spec.md |
| Digest | The daily progress comment on the `"<sprint> digest"` meta issue | runtime/lib/cmd_digest.sh |
| Closing keyword | close / fix / resolve and their forms, linking a PR to a task; `Solve` does not count | openspec/specs/pr-task-linking/spec.md |
| No-task | The label that exempts a PR from the link check | templates/scrum.yml |
| Board (project) | The optional GitHub Projects v2 mirror of task status; labels stay the source of truth. _Avoid_ confusing with "project context" | runtime/lib/project.sh |
| Synced status | The board text field holding the status from the last sync | runtime/lib/project.sh |
| Plan (plan file) | `<planning.dir>/<slug>/plan.json`, how a requirement was split into epic/features/tasks. Also: the `plan` skill, the `scrum plan` CLI, and the output of internal `*-plan.jq` programs / `sprint close` preview — several senses | plan.schema.json, runtime/lib/jq/ |
| Plan view | The generated `plan.md` beside `plan.json` | runtime/lib/cmd_plan.sh |
| Apply | `scrum plan apply`: create the plan's issues on GitHub and write their numbers back. Also `/opsx:apply` (implement OpenSpec tasks) — two senses | runtime/lib/cmd_plan.sh, .claude/commands/opsx/apply.md |
| Depends on / blocked by | A task-id dependency in the plan that becomes GitHub's "blocked by" relation | plan.schema.json |
| Fallback | An issue-body section inside `<!-- scrum:NAME -->` markers written when GitHub refuses a sub-issue or dependency link | runtime/lib/jq/scrum.jq |
| Brief | `brief.md` written by `discover`: the clarified requirement, status draft or confirmed | reference/brief-template.md |
| Size | The brief's estimate: one task, one feature or one epic | skills/discover/SKILL.md |
| Project fit | The brief's verdict: fits, fits with changes, conflicts | skills/discover/SKILL.md |
| Project context | This document (`planning.context_file`), written by `project-scan` | templates/scrum.yml |
| Stamp | The `<!-- scrum:context sha=… date=… -->` line recording the scanned commit | runtime/lib/cmd_context.sh |
| Stale | The stamped commit is more than `planning.context_stale_commits` commits behind HEAD | runtime/share/defaults.json |
| Scout / Critic / Researcher | The read-only agents `codebase-scout`, `plan-critic`, `researcher` | agents/*.md |
| Adapter | The section of a skill that overrides a vendored skill where they differ | skills/plan/SKILL.md |
| Vertical slice | A task that delivers one checkable behaviour on its own | reference/planning-rules.md |
| Sync | `/opsx:sync` (copy delta specs into main specs), `scrum project sync` (board), `scrum-status-sync` (events → labels) — three senses | .claude/commands/opsx/sync.md, templates/github/workflows/ |

Paths without a top-level folder are under `plugins/scrum-github/`.

## Team notes

Written by the team. Kept as it is by every scan.
