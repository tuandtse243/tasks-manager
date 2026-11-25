# Project context: tasks-manager (scrum-github plugin)

<!-- scrum:context sha=61286a29901b date=2026-11-24 -->

<!-- Written by /scrum-github:project-scan; the line above is replaced by `scrum context stamp`.
     Keep the "## " headings exactly as they are: `scrum doc check` reads them
     (runtime/share/doc-sections.json). Every statement about the code names the file or folder
     it comes from, in parentheses. Write "unknown" (or "chưa rõ" in Vietnamese) when the
     repository does not say; never guess. Everything under "Team notes" is written by people and
     is kept as it is on every scan. -->

Paths that start with `bin/`, `runtime/`, `skills/`, `agents/`, `reference/`, `templates/`,
`wizards/`, `vendor/`, `scripts/`, `tests/` or `docs/e2e-testing.md` are under `plugins/scrum-github/`.

## Overview

This repository holds `scrum-github`, a Claude Code plugin that lets a team (PO, Scrum Master,
Dev) run Scrum on GitHub alone. Sprints are milestones, tasks are issues, and status and points
are labels; there is no separate database and no Jira or Trello (docs/adoption-guide.md,
README.md). It replaces manual steps with slash commands, a `scrum` Bash CLI and GitHub Actions
workflows installed into the target repo (plugins/scrum-github/README.md). The current version is
0.14.1 (plugins/scrum-github/.claude-plugin/plugin.json, runtime/VERSION).

What it covers today (README.md, plugins/scrum-github/README.md):

- sprints, backlog, tasks and capacity planning (`sprint-new`, `sprint-fill`, `backlog`, `task-new`, `task`);
- a `team` block with areas, capacity and review hours (runtime/lib/cmd_team.sh);
- time estimates (AI work and human review minutes) next to points (runtime/lib/jq/scrum.jq);
- AI planning from a requirement to an epic, features and tasks, reviewed once in `plan.html`
  (skills/plan/SKILL.md, runtime/share/plan.html);
- AI agents that work `ai-ready` tasks in local worktrees into one pull request (`run`;
  skills/run/SKILL.md, runtime/lib/cmd_run.sh);
- branching presets `trunk`, `standard`, `environments` with branch rules (`protect`), branch
  helpers (`sync`, `branches`, `cleanup`, `promote`, `hotfix`) (runtime/lib/branching.sh,
  runtime/lib/cmd_protect.sh, runtime/lib/cmd_branch.sh, runtime/lib/cmd_promote.sh);
- releases: version and notes from the Done tasks, a tag and GitHub Release, or a release pull
  request that publishes on merge (`release`, `release finish`; runtime/lib/cmd_release.sh);
- optional deployment workflows (Docker, Cloudflare) or Vercel settings (templates/deploy/);
- progress table, HTML burndown report, daily digest, optional GitHub Projects board.

The repo is a Claude Code marketplace named `tasks-manager`, installed with
`/plugin marketplace add tuandtse243/tasks-manager` (.claude-plugin/marketplace.json, README.md).
Who uses it in practice beyond a sandbox repo: unknown.

## Technology

- **Bash 3.2+**: the whole CLI; no associative arrays or `mapfile`, lists passed as JSON
  (runtime/bin/scrum, runtime/lib/common.sh, tests/run.sh).
- **jq**: all decisions and calculations, as about 55 pure programs sharing the module `scrum.jq`
  (runtime/lib/jq/). The README asks for jq 1.6+ (plugins/scrum-github/README.md); the code notes
  jq 1.8.2 behaviour (runtime/lib/jq/scrum.jq). The real minimum: unknown.
- **yq v4 (mikefarah)**: reads `.github/scrum.yml`; the Python `yq` is refused
  (runtime/lib/common.sh, runtime/lib/cmd_doctor.sh).
- **GitHub CLI `gh`**: REST and GraphQL through `gh api`, plus `gh pr create`, `gh repo view`,
  `gh auth status`; scopes `repo,workflow`, plus `project` for the board
  (runtime/lib/common.sh, runtime/lib/cmd_run.sh, runtime/lib/branching.sh, runtime/lib/cmd_doctor.sh).
  Minimum `gh` version: unknown.
- **git** (2.20 or later for `run`, plugins/scrum-github/README.md): task and hotfix branches,
  `sync`, `cleanup`, the run's integration branch and `--no-ff` merges, `.git/info/exclude`,
  blob hashes of generated files, inventory and staleness for `context`
  (runtime/lib/cmd_task.sh, runtime/lib/cmd_branch.sh, runtime/lib/cmd_run.sh,
  runtime/lib/cmd_init.sh, runtime/lib/cmd_context.sh).
- **curl**: only for the optional digest webhook (Slack-style or Telegram) (runtime/lib/cmd_digest.sh).
- **Data files** (runtime/share/): `defaults.json`, `doc-sections.json`, JSON Schema 2020-12
  `plan.schema.json`, the self-contained HTML templates `report.html` and `plan.html`,
  `strings.json` (every text shown or posted on GitHub, in `en` and `vi`), and `graphql/` for
  GitHub Projects v2.
- **Claude Code plugin format**: skills, agents, plugin and marketplace manifests, and a `bin/`
  that Claude Code puts on the Bash PATH (skills/, agents/, bin/scrum,
  plugins/scrum-github/.claude-plugin/plugin.json).
- **GitHub Actions** in the target repo: `actions/checkout` pinned to a full commit SHA (v4.4.0),
  sparse checkout of `.github` (templates/github/workflows/). Deploy templates use Docker
  Compose over SSH with ghcr.io, or Wrangler through `npx` (templates/deploy/).
- **OpenSpec** (`schema: spec-driven`) for specifying changes to the plugin itself (openspec/config.yaml).
- Deployment of the plugin: there is no server. `scrum init` copies the runtime into the target
  repo's `.github/scrum/`, where the workflows run it (runtime/lib/cmd_init.sh). Supported:
  github.com only (no GitHub Enterprise Server); Windows only through WSL (docs/adoption-guide.md).

## Directory structure

| Folder | What it holds |
|---|---|
| `.claude-plugin/` | Marketplace manifest `tasks-manager` pointing to `./plugins/scrum-github` (.claude-plugin/marketplace.json) |
| `.github/workflows/` | `ci.yml`: this repo's CI (tests and shellcheck) (.github/workflows/ci.yml) |
| `plugins/scrum-github/.claude-plugin/` | Plugin manifest: name, version 0.14.1, description, keywords (plugin.json) |
| `plugins/scrum-github/bin/` | `scrum`, a wrapper that forwards to `runtime/bin/scrum`; on Claude Code's PATH while the plugin is enabled (bin/scrum) |
| `plugins/scrum-github/runtime/bin/` | `scrum`, the single CLI entry point; dispatches to `lib/cmd_*.sh` (runtime/bin/scrum) |
| `plugins/scrum-github/runtime/lib/` | Shell libraries: `common.sh` (gh wrappers, helpers), `config.sh`, `project.sh` (board), `branching.sh` (branch roles), `attention.sh` (needs attention), one `cmd_*.sh` per command group (21 of them) |
| `plugins/scrum-github/runtime/lib/jq/` | Pure jq programs (`event-decide`, `label-plan`, `plan-*`, `run-*`, `release-*`, `protect-plan`, `next-step`, `mine`, `attention`, `validate-config`, ...) and the shared module `scrum.jq` |
| `plugins/scrum-github/runtime/share/` | Data: `defaults.json`, `doc-sections.json`, `plan.schema.json`, `strings.json`, `report.html`, `plan.html`, `graphql/` |
| `plugins/scrum-github/skills/` | 26 skills: `init`, `doctor`, `next`, `backlog`, `sprint-new`, `sprint-fill`, `sprint-status`, `sprint-report`, `sprint-close`, `task-new`, `task-start`, `task`, `task-pr`, `my-tasks`, `run`, `plan`, `discover`, `project-scan`, `project-setup`, `release`, `protect`, `sync`, `branches`, `cleanup`, `promote`, `hotfix` (skills/) |
| `plugins/scrum-github/agents/` | `implementer` (works one task in its own worktree, writes and commits locally) and the read-only `codebase-scout`, `plan-critic`, `researcher` (agents/*.md) |
| `plugins/scrum-github/reference/` | Shared rules and templates read by skills: `planning-rules.md`, `brief-template.md`, `project-context-template.md` |
| `plugins/scrum-github/templates/` | What `scrum init` installs: `scrum.yml`, issue form `task.yml`, PR template, five workflows (`github/workflows/`), governance files (`governance/`), deploy workflows (`deploy/docker`, `deploy/cloudflare`); and the rulesets `protect` applies (`rulesets/`) |
| `plugins/scrum-github/wizards/` | `project-board.sh`, the terminal wizard for the project board (wizards/project-board.sh) |
| `plugins/scrum-github/vendor/pocock/` | Seven unmodified skills from mattpocock/skills (MIT): `grilling`, `to-spec`, `domain-modeling`, `to-tickets`, `to-questionnaire`, `pr`, `wizard`, plus `triage/AGENT-BRIEF.md`; kept outside `skills/` so they are not commands (vendor/pocock/UPSTREAM.md) |
| `plugins/scrum-github/scripts/` | `vendor-sync.sh`, re-copies the vendored items listed in its `ITEMS` table |
| `plugins/scrum-github/tests/` | Bash test runner `run.sh`, `fake-gh` stub, 33 `test_*.sh` files (four of them `test_scenarios_*`), `fixtures/` (tests/) |
| `plugins/scrum-github/docs/` | `e2e-testing.md`, the manual end-to-end scenarios (docs/e2e-testing.md) |
| `openspec/specs/` | Main specs, one per capability (25) (openspec/specs/) |
| `openspec/changes/` | No open change; 15 finished changes under `archive/YYYY-MM-DD-<name>/`, the last `team-and-backlog-tasks` (openspec/changes/archive/) |
| `docs/` | `adoption-guide.md`, `cheat-sheet-{po,sm,dev}.md`, this context document, `diagrams/` (sprint flow as archify source, HTML and PNG) |
| `.claude/` | OpenSpec tooling only: `commands/opsx/*` and `skills/openspec-*` |

## Main flows

- **Skill → CLI**: each skill runs `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" <cmd>` from the
  target repo root and runs commands that reach GitHub outside the Claude Code sandbox; only the
  CLI touches GitHub (skills/*/SKILL.md, reference/planning-rules.md).
- **Config load**: `.github/scrum.yml` → `yq -o=json` → deep-merge over `share/defaults.json`
  (a leading `@` stripped from team logins) → `validate-config.jq`; offline `context` commands
  fall back to defaults when the file is missing (runtime/lib/config.sh).
- **`scrum init`**: create or keep `scrum.yml` (a new one gets `branching.preset: standard`);
  sync labels via `label-plan.jq` (never deletes); render templates with `{{KEY}}`
  substitution; record each written file's git blob hash in `.github/scrum/files.json`, so files
  nobody edited are updated and edited ones are reported as `conflict` (`--force-file PATH` to
  replace one); install `scrum-release.yml` only with a working branch and `deploy.yml` for
  `docker`/`cloudflare`; install CODEOWNERS, CONTRIBUTING, SECURITY and dependabot only when
  absent; copy the runtime to `.github/scrum/`; `--dry-run`. `scrum uninstall` removes what init
  installed and nobody edited (runtime/lib/cmd_init.sh, runtime/lib/cmd_uninstall.sh,
  skills/init/SKILL.md).
- **Setup guidance**: `scrum doctor` checks tools, login and scopes, configuration, labels,
  pushed files, versions, board secret, branches and rules, back-merge, governance files and
  production reviewers, read-only; `scrum next` names the one next step by a fixed priority
  (runtime/lib/cmd_doctor.sh, runtime/lib/cmd_next.sh, runtime/lib/jq/next-step.jq).
- **Team and backlog**: `scrum team` lists members (from `team`, else the repo's assignable
  users), areas, capacity and load; logins outside `team` only warn. `scrum backlog` lists open
  tasks without a milestone with points, parent and blockers (runtime/lib/cmd_team.sh,
  runtime/lib/cmd_backlog.sh, runtime/lib/common.sh).
- **Sprint new / fill / close**: new: title from `name_pattern`, a `<!-- scrum:start=… end=… -->`
  marker, overlap only warns. Fill: capacity from `--capacity` or the average velocity of up to
  three closed sprints, review minutes against `team[].review_hours`, moves tasks with `--add`.
  Close: preview, then with `--yes` record velocity, carry over open tasks (`--create-next`),
  list "merged but not released" tasks apart, post a `scrum:summary` comment on the digest issue,
  close the milestone (runtime/lib/jq/sprint-new-plan.jq, runtime/lib/jq/sprint-fill.jq,
  runtime/lib/cmd_sprint.sh, runtime/lib/jq/close-plan.jq).
- **Tasks**: `task new` goes to the open sprint, or the backlog when none is open or with
  `--backlog`, and takes `--work/--review/--by`; `task start N` creates or checks out
  `feat/{number}-{slug}` from the preset's working branch on origin (if git fails, GitHub is
  untouched), assigns me if unassigned, sets In progress; `task list|move|estimate|assign|drop`;
  `scrum mine` shows one person's open tasks everywhere, reviews waiting for them and the next
  task (runtime/lib/cmd_task.sh, runtime/lib/cmd_mine.sh, runtime/lib/jq/mine.jq).
- **Event automation** (workflow `scrum-status-sync` → `scrum event` → `event-decide.jq`): PR
  with a closing keyword opened → In progress; with `statuses.in_review`, ready → In review,
  draft or closed unmerged → In progress; merged in `trunk` → Done and issue closed; merged into
  the working branch → stays open, In review, location label `on: develop`; merged promotion →
  `on: staging` for the tasks its merge commit contains; hotfix into the release branch → Done;
  release, back-merge merges → unchanged; issue closed as completed → Done. Status never moves
  backwards (runtime/lib/cmd_event.sh, runtime/lib/jq/event-decide.jq,
  openspec/specs/pr-task-linking/spec.md).
- **PR check** (`scrum-pr-link-check`, job `pr-check` → `scrum pr-check [--title|--source|--link]`):
  Conventional Commits title, source branch allowed for the target, closing keyword or `no-task`
  label; release, promotion and back-merge PRs are exempt (runtime/lib/cmd_event.sh,
  runtime/lib/jq/scrum.jq, templates/github/workflows/scrum-pr-link-check.yml).
- **Status change**: `set_status` replaces the whole label set in one PUT, so a task has exactly
  one status, then updates the board card (runtime/lib/common.sh).
- **Branches**: `protect` previews and with `--yes` creates missing long-lived branches, rulesets
  `scrum: working|staging|release|tags`, merge settings and the Actions permission to open pull
  requests; `sync` merges the working branch (release branch on `hotfix/*`) into the task branch
  and lists conflicts; `branches` shows what each long-lived branch lacks, drift and stale
  branches; `cleanup` deletes merged branches with `--yes`; `promote` opens develop → staging
  (`environments`); `hotfix N` branches from the release branch and `hotfix prepare` commits the
  version files locally (runtime/lib/cmd_protect.sh, runtime/lib/jq/protect-plan.jq,
  runtime/lib/cmd_branch.sh, runtime/lib/cmd_promote.sh).
- **Release**: `scrum release` finds the previous version tag on the release branch, suggests
  the version (breaking label → major, any non-bug → minor, else patch) and writes notes from the
  Done tasks and their PRs. `trunk` with `VERSION --yes`: annotated tag and GitHub Release. With a
  working branch: branch `release/<tag>` from develop or staging (or `--from`), version files and
  changelog committed through the Git data API, release PR with the notes between
  `<!-- scrum-release-notes -->` markers. After its merge the `scrum-release` workflow runs
  `scrum release finish`: tag, GitHub Release, tasks Done and closed, back-merge PRs; idempotent
  (runtime/lib/cmd_release.sh, runtime/lib/jq/release-plan.jq, templates/github/workflows/scrum-release.yml).
- **AI run** (`/scrum-github:run`): `run plan` picks my New `ai-ready` tasks of the open sprint
  and splits them into waves by "blocked by"; after the user confirms, `run start --expect`
  creates the integration branch from the working branch and saves `.scrum/run/<id>.json`; per
  wave the skill spawns `implementer` agents in worktrees, `run record` keeps results and posts
  the actual time, `run merge` merges with `--no-ff`; `run finish` pushes only the integration
  branch and opens one PR (or one per wave). Records and merges share a lock file created with
  noclobber (skills/run/SKILL.md, runtime/lib/cmd_run.sh, runtime/lib/jq/run-select.jq,
  runtime/lib/jq/run-state.jq).
- **Board sync** (`scrum-project-sync`, only when `project.enabled`): compares label (L), board
  Status (B) and `Synced status` (S); only B changed → label follows; only L changed → board
  follows; both → label wins; card dragged to Done closes the issue. Runs on cron, dispatch and
  label/milestone events (openspec/specs/project-board-sync/spec.md, runtime/lib/project.sh).
- **Reporting**: `scrum status` table with "Needs attention" (stale, blocked, unassigned,
  unestimated, waiting review or release, behind); `scrum report` injects JSON into
  `report.html` with a burndown rebuilt from each task's history; `scrum digest` comments on a
  `"<sprint> digest"` issue labeled `scrum: meta` and can post to `SCRUM_DIGEST_WEBHOOK`
  (runtime/lib/cmd_report.sh, runtime/lib/attention.sh, runtime/lib/cmd_digest.sh).
- **Requirement planning**: `project-scan` → `docs/project-context.md`; `discover` →
  `<planning.dir>/<slug>/brief.md`, and `questionnaire-<who>.md` for decisions someone absent
  owns; `plan` → `plan.json`, `plan.md` and `plan.html`, with suggested assignees (from `team`) and
  sprint, reviewed by `plan-critic` unless `--quick`; `scrum plan check` validates, renders, prints
  waves, load and capacity; after one approval `scrum plan apply` creates issues in their sprint
  and assigned, writes numbers back atomically, links sub-issues and "blocked by", with an
  issue-body fallback when GitHub refuses. `--update` edits title, body, points, time estimate,
  sprint and `ai-ready` of open issues only (skills/plan/SKILL.md, skills/discover/SKILL.md,
  runtime/lib/cmd_plan.sh). After apply, GitHub is the source of truth; nothing syncs back into
  the plan (openspec/changes/archive/2026-11-19-requirement-planning/design.md).
- **Context commands**: `scrum context inventory|status|stamp` (offline) and
  `scrum doc check FILE` validate headings and the stamp against `share/doc-sections.json`
  (runtime/lib/cmd_context.sh, runtime/lib/cmd_doc.sh).

## Data model

- **Sprint**: a GitHub milestone `Sprint {n}`; dates from the `scrum:start/end` description
  marker (fallback `created_at`/`due_on`); velocity from `scrum:velocity` marker. Current sprint =
  the open sprint containing today, else the open sprint ending first (runtime/lib/jq/scrum.jq).
- **Task**: an issue that is not a PR and not labeled feature, epic or meta. Role `new`,
  `in_progress`, `in_review`, `done` (closed as completed, whatever the labels) or `dropped`
  (closed as not planned). Points from the first `points: N` label. Body sections: description,
  `### Acceptance criteria`, `### Subtasks`, "Part of #parent", and an optional
  `<!-- scrum:estimate -->` block holding `{work_minutes, review_minutes, by: ai|human}`
  (runtime/lib/jq/scrum.jq).
- **Feature / Epic**: issues labeled `type: feature` / `type: epic`; tasks are sub-issues of a
  feature, features of an epic; an epic has no points (docs/adoption-guide.md,
  openspec/specs/work-plan/spec.md).
- **Backlog**: issues with no milestone (openspec/specs/backlog/spec.md).
- **Labels**: `status: New|In progress|In review|Done` (In review only when configured),
  `points: <n>` per scale value, `bug`, `type: feature`, `type: epic`, `scrum: meta`, `no-task`,
  `ai-ready`, and one location label `on: <branch>` per lower long-lived branch (none in `trunk`);
  obsolete ones are reported, never deleted. `release.breaking_label` is read but not created
  (runtime/lib/jq/label-plan.jq, runtime/lib/jq/release-plan.jq).
- **Config `.github/scrum.yml`** (defaults in runtime/share/defaults.json, commented in
  templates/scrum.yml, documented in plugins/scrum-github/README.md "Configuration"): `version`,
  `timezone` (UTC), `language` (en|vi), `sprint.{length_days, name_pattern, working_days}`,
  `points.{scale (0,1,3,7), label_prefix}`, `statuses.{label_prefix, new, in_progress, in_review (null), done}`,
  `labels.{bug, feature, epic, meta, no_task, ai_ready}`, `branch.pattern`,
  `digest.{enabled, cron, webhook_format}`, `attention.{stale_days, review_days, behind_percent, promote_days}`,
  `colors`, `planning.{dir, context_file, hours_per_point, context_stale_commits (50), merge_minutes (5)}`,
  `run.{test_command, max_parallel (3), branch_pattern}`,
  `release.{tag_prefix (v), breaking_label, first_version, version_files, changelog}`,
  `branching.{preset, main, develop, staging, location_prefix, stale_days}` (no `preset` means
  `trunk`; `standard` and `environments` require `statuses.in_review`),
  `governance.{approvals (0-6), required_checks, codeowners}`, `deploy.platform`
  (none|vercel|cloudflare|docker), `project.{enabled, owner, number, status_field, status_options, synced_field, points_field, poll_cron}`,
  `team[] {login, areas, capacity, review_hours}` (runtime/lib/jq/validate-config.jq).
  This repo itself has no `.github/scrum.yml`.
- **Plan file v2** `<planning.dir>/<slug>/plan.json`: `version: 2`, `title`, `sprint` (name,
  `"current"` or null = backlog), `epic` or null, `features[] {id, title, body, issue, tasks[]}`,
  `assumptions[]`, `out_of_scope[]`, optional `review[]` (plan-critic findings); task `{id, title,
  body, acceptance[], subtasks[], points, estimate, depends_on[], assignees[], bug, ai_ready,
  sprint, issue}`. v1 is normalized to v2. Beside it: `plan.md`, `plan.html` and
  `.plan-snapshot.json` (the last two git-ignored by the folder's `.gitignore`)
  (runtime/share/plan.schema.json, runtime/lib/cmd_plan.sh).
- **Run state** `.scrum/run/<id>.json` (id `YYYYMMDD-HHMM-<login>`, never committed, `.scrum/`
  in `.git/info/exclude`): branch, base, waves, excluded tasks, per-task state
  (pending, running, done, merged, failed, conflict, excluded), times, PRs; lock `<id>.json.lock`
  (runtime/lib/cmd_run.sh, runtime/lib/jq/run-state.jq).
- **Generated files record** `.github/scrum/files.json`: `{version, files: {path: blob hash}}`
  (runtime/lib/cmd_init.sh).
- **Markers**: `scrum:start/end`, `scrum:velocity` (milestone); `scrum:estimate` (issue body);
  `scrum:actual`, `scrum:digest`, `scrum:summary` (comments); `scrum:deploy` (CONTRIBUTING.md);
  `scrum-release-notes`, `scrum-release-tag`, `scrum-promotion` (PR bodies)
  (runtime/lib/jq/scrum.jq, runtime/lib/jq/run-state.jq, runtime/lib/cmd_release.sh,
  runtime/lib/cmd_promote.sh, runtime/lib/cmd_init.sh).
- **Brief / context document**: required `## ` sections and the context stamp are listed in
  runtime/share/doc-sections.json.
- **Projects v2 board**: single-select `Status` (Todo / In Progress / In Review / Done; In Review
  only when configured), text `Synced status`, number `Points` (runtime/share/defaults.json,
  runtime/share/graphql/).

## External integrations

- **GitHub REST via `gh api`**: labels, milestones, issues, comments, assignees, sub-issues,
  dependencies (`issues/N/dependencies/blocked_by`), issue timeline and events, search
  (runtime/lib/common.sh, runtime/lib/cmd_plan.sh, runtime/lib/attention.sh, runtime/lib/cmd_mine.sh).
  Sub-issue and dependency links were checked on a real repository on 2026-11-19
  (docs/e2e-testing.md).
- **Branches, rules and releases**: rulesets, repository merge settings, Actions workflow
  permissions, branches and refs, the Git data API (tags, trees, commits, blobs), compare, pulls,
  tags and releases, environments, secrets (runtime/lib/cmd_protect.sh, runtime/lib/branching.sh,
  runtime/lib/cmd_release.sh, runtime/lib/cmd_doctor.sh, runtime/lib/cmd_init.sh). Classic branch
  protection is not written (runtime/lib/cmd_next.sh).
- **GitHub GraphQL (Projects v2)** via `gh api graphql -F query=@file`; uses
  `SCRUM_PROJECT_TOKEN` when set, since the workflow `GITHUB_TOKEN` cannot reach Projects
  (runtime/lib/common.sh, runtime/lib/project.sh). Fine-grained tokens: "not tested yet"
  (plugins/scrum-github/README.md).
- **GitHub Actions**: up to six workflows in the target repo (`scrum-status-sync`,
  `scrum-pr-link-check`, `scrum-daily-digest`, `scrum-project-sync`, `scrum-release`, `deploy`),
  `pull_request_target` with a sparse checkout of `.github` so PR code is never run
  (templates/github/workflows/, templates/deploy/, runtime/lib/cmd_init.sh).
- **Issue form and PR template**: `task.yml`, `pull_request_template.md` (Summary, Evidence,
  Merge Danger, Task) (templates/github/).
- **Chat webhook**: Slack, Google Chat, Mattermost or Telegram for the digest (runtime/lib/cmd_digest.sh).
- **Deploy targets**: ghcr.io and a host over SSH (Docker), Cloudflare Wrangler, or Vercel's
  own Git integration (templates/deploy/, plugins/scrum-github/README.md "Deploying").
- **Web search**: only the `researcher` agent (WebSearch, WebFetch) (agents/researcher.md).
- **Vendored upstream**: mattpocock/skills at commit `5863806…`, synced 2026-11-19 (vendor/pocock/UPSTREAM.md).

## Conventions

- **Logic in jq, I/O in shell**: decisions are pure jq run through `jqlib`, tested offline;
  skills hold no logic; repeated deterministic work becomes a `scrum` command
  (runtime/lib/common.sh, openspec/changes/archive/2026-11-19-requirement-planning/design.md).
- **Shell style**: `set -euo pipefail`, Bash 3.2 compatible, CLI messages via `die`/`warn`/`info`
  (`scrum: error:`), atomic writes via `write_atomic`, board functions return 1 with `PROJECT_ERR`
  instead of exiting (runtime/lib/common.sh, runtime/lib/project.sh). Texts posted on GitHub or
  shown in reports come from `runtime/share/strings.json` in the configured `language`
  (runtime/lib/common.sh).
- **Markers** in GitHub text are HTML comments `<!-- scrum:… -->`; the release, hotfix and
  promotion markers use `<!-- scrum-… -->` (runtime/lib/jq/scrum.jq, runtime/lib/cmd_release.sh).
- **Preview first**: `init`, `protect`, `promote`, `cleanup`, `release`, `hotfix prepare`,
  `uninstall`, `sprint close`, `sprint fill` write only with `--yes` or after a dry run; `init`,
  `project init`, `plan apply`, `protect`, `release finish` are safe to rerun
  (plugins/scrum-github/README.md, runtime/bin/scrum).
- **Names**: task branch `feat/{number}-{slug}` (slug lowercase ASCII, ≤ 40 chars), `hotfix/N-slug`,
  `release/<tag>`, integration branch `run/{sprint}-{login}`; sprint `Sprint {n}`; rulesets
  `scrum: <role>`; commands `/scrum-github:<name>` (runtime/share/defaults.json,
  runtime/lib/jq/scrum.jq, templates/rulesets/).
- **Target-repo PR rules**: Conventional Commits titles; a task branch targets the working branch,
  only `release/*` and `hotfix/*` target `main` (runtime/lib/jq/scrum.jq, runtime/lib/cmd_event.sh).
- **Skills**: YAML front matter (`name`, `description`, optional `argument-hint`) then numbered
  steps; every skill opens with the same paragraph on the full `bin/scrum` path and running
  GitHub commands outside the sandbox; a vendored skill is used with an "Adapter for X" section
  that wins where they differ; shared rules in `reference/planning-rules.md` (skills/*/SKILL.md).
- **Planning rules**: nothing goes to GitHub before user approval; agents only read (the
  `implementer` of `run` writes only in its worktree); facts cite a path or URL; tasks are
  vertical slices with a time estimate; template headings kept exactly
  (reference/planning-rules.md, agents/implementer.md).
- **Language**: new documents in this repository are in English. Main specs started in
  Vietnamese; changes since `release` are in English and requirements edited in place keep their
  language (openspec/changes/archive/2026-11-24-branching-and-release-flow/design.md). The change
  `team-and-backlog-tasks` is in Vietnamese (openspec/changes/archive/2026-11-24-team-and-backlog-tasks/proposal.md).
- **OpenSpec workflow**: `/opsx:propose` → `/opsx:apply` → `/opsx:archive` into
  `changes/archive/YYYY-MM-DD-<name>`, which merges the specs into `openspec/specs/`; specs
  written as `### Requirement:` (SHALL/MUST) with `#### Scenario:` WHEN/THEN; tasks.md items say
  how to verify (README.md "Development", .claude/commands/opsx/, openspec/specs/,
  openspec/changes/archive/2026-11-19-requirement-planning/tasks.md).
- **Team rules for adopters**: every PR closes a task or carries `no-task`; use `Closes #n`;
  don't edit `status:` labels by hand; close abandoned tasks as not planned; don't change points
  mid-sprint (docs/adoption-guide.md).
- Branching and commit rules for this repo itself: none written down (no CONTRIBUTING, PR
  template or CODEOWNERS at the root or in `.github/`).

## Running and testing

- **Install** (in Claude Code): `/plugin marketplace add tuandtse243/tasks-manager` (or `./` from
  a clone), `/plugin install scrum-github@tasks-manager`, then in the target repo
  `/scrum-github:init`, push `.github/`, `/scrum-github:protect`, `/scrum-github:doctor`
  (README.md, plugins/scrum-github/README.md).
- **Tests**: `bash plugins/scrum-github/tests/run.sh`, or with a file pattern; offline, about two
  minutes (README.md "Development"). Hand-written runner: finds `test_*` functions, runs each in
  a subshell with a temp `$T`; assertions `assert_eq`, `assert_json_eq`, `assert_contains`,
  `assert_not_contains`, `assert_status`; it unsets `GITHUB_*`, `SCRUM_PROJECT_TOKEN` and
  `SANDBOX_RUNTIME` (tests/run.sh). The `test_scenarios_*` files are black-box tests written from
  the spec scenarios of branching-and-release-flow, sharing `tests/fixtures/scenarios/helpers.sh`.
  `test_docs.sh` checks that the READMEs, the guide and the cheat sheets name only existing
  commands and every skill and configuration key (tests/test_docs.sh).
- **Fake GitHub**: `SCRUM_GH=tests/fake-gh` routes calls to fixtures (`GLOB<TAB>FILE`, `!fail`,
  `!404`, `!403`) and logs them; also `SCRUM_REPO`, `SCRUM_REPO_DIR`, `SCRUM_TODAY`, `SCRUM_NOW`,
  `SCRUM_CURL`, `SCRUM_RUN_LOCK_TRIES` (tests/fake-gh, runtime/lib/common.sh,
  runtime/lib/cmd_digest.sh, runtime/lib/cmd_run.sh).
- **Lint**: `shellcheck --severity=warning` over `bin/scrum`, `runtime/`, `scripts/`, `wizards/`
  and `tests/` (not `vendor/`), with `tests/.shellcheckrc` and `wizards/.shellcheckrc`;
  `claude plugin validate plugins/scrum-github` by hand (README.md "Development").
- **CI for this repo**: `.github/workflows/ci.yml` runs the tests on Ubuntu and shellcheck on
  every pull request and every merge, and the tests on macOS too on pull requests into `main`
  (release and hotfix) (.github/workflows/ci.yml).
- **Manual end-to-end**: scenarios against `tuandtse243/scrum-sandbox` in docs/e2e-testing.md,
  with sections up to 0.4.0 (last runs 2026-11-18 and 2026-11-19); the In review flow was checked
  on a real repository with 0.8.1 (plugins/scrum-github/README.md). A recorded run of branching,
  release, `run`, `protect` and deploy against real GitHub: unknown.

## Glossary

| Term | Meaning | Where it appears |
|---|---|---|
| Sprint | A GitHub milestone named by `sprint.name_pattern`, with start and end dates in a description marker | runtime/lib/jq/scrum.jq |
| Current sprint | The open sprint whose dates contain today, else the open sprint ending first; `"current"` in a plan | runtime/lib/jq/scrum.jq, plan.schema.json |
| Task | An issue that is not a PR, feature, epic or meta issue; the only thing that carries points. Also used for OpenSpec `tasks.md` checklist items (second sense) | runtime/lib/jq/scrum.jq, openspec/changes/*/tasks.md |
| Feature | An issue labeled `type: feature` whose sub-issues are tasks; in a plan, an entry of `features[]`; in a brief, a size class (task / feature / epic) — three senses | templates/scrum.yml, plan.schema.json, skills/discover/SKILL.md |
| Epic | An issue labeled `type: epic` whose sub-issues are features; has no points | plan.schema.json, openspec/specs/work-plan/spec.md |
| Subtask | A checklist item under `### Subtasks` inside a task issue, not a separate issue. _Avoid_ confusing with GitHub "sub-issue" (how a task hangs under a feature) | plan.schema.json, openspec/specs/task-management/spec.md |
| Backlog | Open tasks with no milestone (plan `sprint: null`) | openspec/specs/backlog/spec.md |
| Meta issue | A bookkeeping issue labeled `scrum: meta` (e.g. the digest issue), excluded from metrics | templates/scrum.yml, openspec/specs/sprint-reporting/spec.md |
| Status | Exactly one `status: New/In progress/In review/Done` label on a task. Also: the board's `Status` field, the `scrum status` command and `scrum context status` — four senses | runtime/lib/jq/scrum.jq, runtime/share/defaults.json |
| In review | Optional fourth status: a PR is ready for review, or (with a working branch) the task is merged and waits for a release | runtime/lib/jq/event-decide.jq |
| Done | Closed as completed; closed as "not planned" (dropped) counts nowhere | runtime/lib/jq/scrum.jq, README.md |
| Drop | Close a task as not planned (`task drop`) | runtime/lib/cmd_task.sh |
| Points (story points) | A value from `points.scale`, stored as a `points: N` label and copied one-way to the board's `Points` field | runtime/share/defaults.json |
| Time estimate | `work_minutes`, `review_minutes` and `by` (ai/human) in the `scrum:estimate` block; separate from points | runtime/lib/jq/scrum.jq, openspec/specs/time-estimate/spec.md |
| Actual time | Minutes a task took in a run, posted as a `scrum:actual` comment | runtime/lib/jq/run-state.jq |
| Velocity | Sum of points of tasks closed as completed in a sprint, stored as `scrum:velocity=N` | openspec/specs/sprint-lifecycle/spec.md, runtime/lib/jq/scrum.jq |
| Capacity | Of a sprint: `--capacity` or the average recent velocity. Of a person: `team[].capacity`, points per sprint — two senses | runtime/lib/jq/sprint-fill.jq, runtime/lib/jq/validate-config.jq |
| Team / area / review hours | The `team` block: members, what they usually work on, hours of review per sprint | runtime/lib/jq/validate-config.jq, runtime/lib/cmd_team.sh |
| Load | Points (and review minutes) a person holds in the open sprint or a plan | runtime/lib/cmd_team.sh, runtime/lib/jq/plan-insights.jq |
| Carry over | Moving a closing sprint's open tasks to the next sprint | runtime/lib/cmd_sprint.sh |
| Burndown | Ideal vs remaining points per day of a sprint, rebuilt from task history | runtime/lib/jq/scrum.jq, openspec/specs/sprint-reporting/spec.md |
| Needs attention | The section of status, digest and report listing stale, blocked, unassigned, unestimated tasks, tasks waiting for review or release, and a sprint behind | runtime/lib/jq/attention.jq |
| Digest | The daily progress comment on the `"<sprint> digest"` meta issue | runtime/lib/cmd_digest.sh |
| Closing keyword | close / fix / resolve and their forms, linking a PR to a task; `Solve` does not count | openspec/specs/pr-task-linking/spec.md |
| No-task | The label that exempts a PR from the link check | templates/scrum.yml |
| Preset | `branching.preset`: `trunk`, `standard` or `environments`; decides the long-lived branches | runtime/lib/jq/scrum.jq, openspec/specs/branching-presets/spec.md |
| Working branch | Where task branches start and task PRs go: `develop`, or the default branch in `trunk` | runtime/lib/branching.sh, openspec/specs/branching-presets/spec.md |
| Release branch | `branching.main`: tagged and released; only `release/*` and `hotfix/*` merge into it | runtime/lib/jq/scrum.jq |
| Long-lived branch | `main`, `develop`, `staging` of the preset, protected by `protect` | runtime/lib/jq/scrum.jq, runtime/lib/cmd_protect.sh |
| Location label | `on: <branch>`: a task In review merged into that branch and not yet released | runtime/lib/jq/scrum.jq |
| Promotion | PR from the working branch into staging (`environments`) | runtime/lib/cmd_promote.sh |
| Release PR | PR from `release/<tag>` into the release branch; its merge publishes the version | runtime/lib/cmd_release.sh |
| Back-merge | PR from the release branch into a lower long-lived branch after a release | runtime/lib/cmd_release.sh |
| Hotfix | A fix on `hotfix/N-slug` from the release branch, published on merge as a patch | runtime/lib/cmd_promote.sh |
| Drift | Commits of the release branch that a lower branch lacks | skills/branches/SKILL.md |
| Board (project) | The optional GitHub Projects v2 mirror of task status; labels stay the source of truth. _Avoid_ confusing with "project context" | runtime/lib/project.sh |
| Synced status | The board text field holding the status from the last sync | runtime/lib/project.sh |
| Plan (plan file) | `<planning.dir>/<slug>/plan.json`, how a requirement was split into epic/features/tasks. Also: the `plan` skill, the `scrum plan` CLI, and the output of internal `*-plan.jq` programs / previews — several senses | plan.schema.json, runtime/lib/jq/ |
| Plan view | The generated `plan.md`, and the review page `plan.html` beside `plan.json` | runtime/lib/cmd_plan.sh |
| Apply | `scrum plan apply`: create the plan's issues on GitHub and write their numbers back. Also `/opsx:apply` (implement OpenSpec tasks) — two senses | runtime/lib/cmd_plan.sh, .claude/commands/opsx/apply.md |
| Depends on / blocked by | A task-id dependency in the plan that becomes GitHub's "blocked by" relation | plan.schema.json |
| Wave | Tasks with no blocker among themselves, worked in parallel; the next wave starts after the previous one is merged | runtime/lib/jq/scrum.jq, runtime/lib/cmd_run.sh |
| ai-ready | The label (`labels.ai_ready`) marking a task an AI agent may work with `run` | runtime/lib/jq/run-select.jq |
| Run | One `/scrum-github:run` execution, state in `.scrum/run/<id>.json` | runtime/lib/cmd_run.sh |
| Integration branch | The run's branch (`run.branch_pattern`) that task branches merge into; the only branch a run pushes | runtime/lib/cmd_run.sh |
| Fallback | An issue-body section inside `<!-- scrum:NAME -->` markers written when GitHub refuses a sub-issue or dependency link | runtime/lib/jq/scrum.jq |
| Brief | `brief.md` written by `discover`: the clarified requirement, status draft or confirmed | reference/brief-template.md |
| Questionnaire | `questionnaire-<who>.md` beside a brief, for a decision owned by someone not in the session | skills/discover/SKILL.md |
| Size | The brief's estimate: one task, one feature or one epic | skills/discover/SKILL.md |
| Project fit | The brief's verdict: fits, fits with changes, conflicts | skills/discover/SKILL.md |
| Project context | This document (`planning.context_file`), written by `project-scan` | templates/scrum.yml |
| Stamp | The `<!-- scrum:context sha=… date=… -->` line recording the scanned commit | runtime/lib/cmd_context.sh |
| Stale | The stamped commit is more than `planning.context_stale_commits` commits behind HEAD. Also a task In progress with no activity, and a task branch without commits (`branching.stale_days`) — three senses | runtime/share/defaults.json, runtime/lib/jq/attention.jq |
| Generated file / record | A file `init` wrote, with its hash in `.github/scrum/files.json`; one still matching it is updated, an edited one is a conflict | runtime/lib/cmd_init.sh |
| Scout / Critic / Researcher / Implementer | The agents `codebase-scout`, `plan-critic`, `researcher` (read-only) and `implementer` (works one task in a worktree) | agents/*.md |
| Adapter | The section of a skill that overrides a vendored skill where they differ | skills/plan/SKILL.md |
| Vertical slice | A task that delivers one checkable behaviour on its own | reference/planning-rules.md |
| Sync | `/opsx:sync` (copy delta specs into main specs), `scrum project sync` (board), `scrum-status-sync` (events → labels), `scrum sync` (merge the working branch into a task branch) — four senses | .claude/commands/opsx/sync.md, templates/github/workflows/, runtime/lib/cmd_branch.sh |

Paths without a top-level folder are under `plugins/scrum-github/`.

## Team notes

Written by the team. Kept as it is by every scan.
