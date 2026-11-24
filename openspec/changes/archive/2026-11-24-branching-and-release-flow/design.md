# Design

Paths are relative to `plugins/scrum-github/` unless they start with `.github/` or `openspec/`.

## Context

See proposal.md for the motivation. What the code does today, and what constrains the approach:

- `scrum event` (`runtime/lib/cmd_event.sh`, `jq/event-decide.jq`) reads `Closes #n` from the pull request body itself (`jq/links.jq`) and decides the new labels. It does not depend on GitHub closing the issue, and it does not look at the base branch: a merge anywhere means Done.
- `statuses.in_review` is optional. Without it a merged pull request is the only status change after In progress.
- `release_default_branch` (`cmd_release.sh`) and `cmd_run.sh` read the default branch of the repository and use it as base and as the place to tag. `cmd_task.sh` creates the task branch from the default branch.
- `scrum release` writes nothing into the repository (version files and changelog were out of scope) and creates the tag through the API on the head of the default branch.
- Every writing command previews first and writes with `--yes`; all writes go through `gh_send`; shared jq helpers live in `jq/scrum.jq` because a jq library cannot include another one.
- `init` copies `templates/github/**` into the project and the runtime into `.github/scrum/`. Workflows triggered by `pull_request_target` run the file of the base branch; scheduled workflows and those triggered by `issues` run the file of the default branch only (a GitHub rule).
- Main specs are written in Vietnamese; changes since `release` are written in English. New requirements here are in English; requirements modified in place keep their language.
- The changes `release`, `ai-run` and `time-estimates` are complete but not archived, so `openspec/specs/` has no `release` or `ai-run` capability yet.

## Goals / Non-Goals

**Goals:**

- One place decides branch roles (`jq/scrum.jq`), and every command asks it instead of the default branch.
- `trunk` behaves exactly as today: an installed project that upgrades sees no change until it adds a `branching` block.
- Everything that changes GitHub settings is previewed and confirmed, and can be run again safely.
- Decision logic stays in pure jq, testable offline with `fake-gh`.

**Non-Goals:**

- Enforcing the merge method per pull request before the merge (GitHub offers rules per branch, not per source branch).
- Managing secrets, cloud accounts or DNS for deployments.
- Rewriting existing specs into one language.

## Decisions

### 1. Preset helpers in `scrum.jq`

`branching($cfg)` returns `{preset, main, develop, staging, working, release, lower: [...], chain: [...]}`; `working_branch`, `release_branch`, `has_working_branch`, `location_label($cfg; $branch)`, `task_location($cfg)` and `allowed_source($cfg; $head; $base)` build on it. Shell gets them through one `branch_role ROLE` function in `common.sh`. No command reads `default_branch` any more except `doctor`, which checks that it equals the release branch.

Alternative considered: keep using the default branch and ask projects to make `develop` the default. Rejected: GitHub would then close tasks on merge into `develop`, and a marketplace or a clone would serve unreleased code.

### 2. A missing `branching` block means `trunk`; `init` writes `standard`

`defaults.json` has no `branching.preset`; `branching()` falls back to `trunk`. `templates/scrum.yml` ships with `preset: standard` and `statuses.in_review: In review` uncommented, so new projects start on the default the user chose, and existing projects are untouched. `doctor` adds an informational line suggesting a preset when the block is missing.

### 3. Location is a label, not a status

One status (`In review`) plus one label `on: <branch>` per long-lived branch below the release branch. `init` creates these labels from the preset. Rationale: the status set stays small and the Projects board mapping (`project.sh`) is untouched; the location is shown by reports and filters. The date a task reached a branch comes from the issue timeline (`labeled` event), read only for tasks In review, with the same cap as `blocked_map`.

Alternative considered: statuses `On develop` / `On staging`. Rejected by the user in favour of one status with a label.

### 4. Event rules take the base branch

`cmd_event.sh` passes `base` (the pull request's base ref) and `head` to `event-decide.jq`, and maps a merged pull request to one of:

| Preset | Merged into | Decision |
|---|---|---|
| trunk | anything | Done, close (unchanged) |
| standard / environments | working branch | keep In review, set location label, stay open |
| environments | staging, from working branch | handled by the promotion step (decision 6) |
| standard / environments | release branch, from `hotfix/*` | Done, close |
| standard / environments | release branch, from `release/*` | handled by release finish (decision 7) |
| standard / environments | any other branch | no change |

`labels_with_status` gains a sibling `labels_with_location` that removes other location labels. The `issue_closed` rule stays: closing a task by hand as completed still sets Done.

### 5. Which tasks a branch contains

Used by promote, release, `branches` and the promotion event. For each open task In review with a location label: find the merged pull request that links it (issue timeline, as `closing_refs` does today), take its `merge_commit_sha`, and ask `GET repos/{r}/compare/{sha}...{ref}`: status `ahead` or `identical` means `ref` contains it. This is the reachability check `cmd_release.sh` already uses for tags. Capped at 100 tasks; past the cap the command says the list is incomplete. Pure selection lives in a new `jq/branch-contents.jq`.

Alternative considered: parsing `(#123)` out of squash commit subjects in the compare range. Rejected: it depends on the commit message format and breaks for merge commits.

### 6. Promotion is a plain pull request

`scrum promote --yes` opens `develop → staging` with a generated body (task list between two markers). When it merges, `scrum event` sees base = staging and head = working branch, recomputes the contained tasks (decision 5 against the merge commit) and swaps their location label. The body is informational only; the labels are computed from the commits.

### 7. Release branch and finish

`scrum release --yes` with a working branch: resolve the start ref (working, staging or `--from`), compute contained tasks (5) and untasked pull requests (merged pull requests in `compare/<prev tag>...<start>` with no task link), choose the version, create `release/<tag>` through the API, commit version files and changelog with the contents API (one commit; skipped when neither is configured), open the pull request with the notes between markers `<!-- scrum-release-notes -->`.

A new workflow `scrum-release.yml` (`pull_request_target: closed` on the release branch) runs `scrum release finish`: for a merged `release/*` or `hotfix/*` head it reads the tag from the branch name (release) or from the marker in the body (hotfix), then runs the existing write steps of `cmd_release.sh` (annotated tag on the merge commit, GitHub Release with the notes from the body), sets the contained tasks Done and closes them, and opens the back-merge pull requests. Every step first checks whether its result exists, so a re-run is safe. Permissions: `contents: write`, `pull-requests: write`, `issues: write`; the workflow checks out only `.github` of the base branch, never pull request code, like `scrum-status-sync.yml`.

Version files: an entry with only `path` ending in `.json` updates the top-level `version` with jq; any other entry needs `pattern` with `{version}`, and the first match of the pattern with the previous version is replaced. A file where nothing matches stops the command before anything is created.

Alternative considered: opening the release pull request straight from `develop`. Rejected: there would be nowhere to commit the version files, and `develop` moving during review would change the release.

### 8. Back-merge

After a merge into the release branch, for each lower long-lived branch that does not contain it (compare), open a pull request `main → <branch>` titled `Back-merge main into <branch>` unless one is open. It is merged with a merge commit, which is why the working branch allows both squash and merge commits. The title, source-branch and task-link checks exempt it. `doctor`, `branches` and `next` surface an open or missing back-merge.

### 9. Protection through rulesets, kept as JSON templates

`templates/rulesets/{working,staging,release,tags}.json` with placeholders for branch names, checks and approvals. `scrum protect` reads `GET repos/{r}/rulesets`, matches by a fixed name prefix `scrum: `, and creates or updates. Repository settings go through `PATCH repos/{r}`. Branch creation uses `POST git/refs` from the release head. A 403 or 404 on rulesets is reported per item (plan or permission) and does not stop the other items. The tag rule blocks update and deletion only, not creation, so the release workflow's token needs no bypass.

To verify during implementation against the current GitHub docs: the ruleset pull request rule's allowed merge methods parameter. If it is not available, the fallback is the repository-level setting plus the documented convention, and `protect` says so.

### 10. Checks run in one workflow

`scrum-pr-link-check.yml` already runs `scrum pr-check`. It gains the title and source-branch checks as separate named steps of the same job, so a project has one required check name to configure (`governance.required_checks` defaults to it plus nothing else; the project adds its CI). Exemptions (release, promotion, back-merge) are decided in jq from head and base.

### 11. Daily branch commands are local git plus read-only API

`cmd_branch.sh`: `sync` (fetch, `git merge --no-edit origin/<working>`; on conflict, `git diff --name-only --diff-filter=U` and `git log -1 --format='%an%x09%s' origin/<working> -- <file>`), `branches` (compare API for each pair, open pull requests, `for-each-ref` for stale branches using the working-day helper already used by attention), `cleanup` (merged pull requests' head refs plus `git branch --merged`, deletion through `git branch -d/-D` and `git push --delete` after `--yes`).

### 12. Deployment templates

`templates/deploy/{docker,cloudflare}/deploy.yml` with the branch → environment map filled in by `init` from the preset. Docker: the image tag is the git tree hash (`git rev-parse HEAD^{tree}`), so a promotion merge with an unchanged tree reuses the image; released versions are also tagged with the version for rollback. Deploy step: SSH, `docker compose pull && docker compose up -d`. Cloudflare: `wrangler deploy --env <environment>`. Vercel: no workflow, a section in `CONTRIBUTING.md`. `workflow_dispatch` inputs `environment` and `version` give the rollback. Generated files carry the "Generated by scrum-github" header that `init` already uses to tell its own files from the project's.

To verify during implementation: the current Wrangler deploy flags and the Vercel production-branch setting names.

### 13. Background workflows read the working branch

`scrum-daily-digest.yml` and the `issues` part of the status sync add `ref: <working branch>` to their checkout; `init` writes the name from the preset. The file itself must reach the default branch to take effect; `doctor` already compares installed files with what is pushed and will name the branch.

### 14. Specs: additive where the target capability is not in main specs yet

`release` and `ai-run` are not archived, so their behaviour changes are written as new requirements in `release-pr` and `branching-presets` instead of modifying requirements that do not exist in `openspec/specs/` yet. Archive those changes before this one.

### 15. Parallel work: one foundation, then disjoint streams

Shared files (`scrum.jq`, `defaults.json`, `validate-config.jq`, `strings.json`, `runtime/bin/scrum`, `templates/scrum.yml`, `label-plan.jq`) are changed once, first, by the lead (task group 1). After that commit, four streams run in parallel in separate git worktrees and own separate files:

| Stream | Task group | Owns |
|---|---|---|
| A governance | 2 | `cmd_protect.sh`, `cmd_init.sh`, `cmd_doctor.sh`, `templates/rulesets/`, governance file templates, check workflow, `skills/protect`, `skills/init`, `skills/doctor` |
| B status flow | 3 | `cmd_event.sh`, `event-decide.jq`, `attention.jq`, `progress-table.jq`, `digest.jq`, `mine.jq`, `cmd_sprint.sh`, `close-plan.jq`, report data, their skills |
| C daily commands | 4 | `cmd_task.sh`, `cmd_run.sh`, `cmd_branch.sh`, `branch-contents.jq`, `skills/task-start`, `task-pr`, `run`, `sync`, `branches`, `cleanup` |
| D release flow | 5 | `cmd_release.sh`, `release-plan.jq`, `release-notes.jq`, `cmd_promote.sh`, `scrum-release.yml`, `cmd_next.sh`, `next-step.jq`, `skills/release`, `promote`, `hotfix`, `next` |

Streams B, C and D all need "which tasks a branch contains": `branch-contents.jq` and its shell wrapper belong to the foundation, not to stream C, so nobody waits. A stream that needs a new string or helper adds it in its own clearly separated block at the end of the shared file, and the lead resolves those appends at merge. Group 6 (deployment, docs, version) runs after the merge. A separate test agent writes the scenario tests from the specs, one file per stream, without reading the implementation first; a read-only review agent reads the merged diff against the specs before the pull request is opened.

## Risks / Trade-offs

- [Velocity drops when a sprint ends without a release] → `sprint-close` and `next` say so before closing; the user accepted this definition of Done.
- [An unfinished feature on `develop` blocks a release] → `release --from REF` releases up to a chosen commit; the docs recommend feature flags.
- [Squash-merging a back-merge breaks ancestry and the next release conflicts] → the back-merge body says to use a merge commit; `branches` and `doctor` detect that the release branch is still not contained.
- [Rulesets unavailable (private repository on a free plan) or no admin rights] → `protect` reports each refused item and still applies the rest; `doctor` keeps warning.
- [The contained-tasks check costs one compare call per task] → capped at 100 tasks, results cached within one command run; the cap is reported.
- [A project upgrades and its installed `event` runtime disagrees with labels created by a newer CLI] → the preset is read from the same `scrum.yml`; `doctor` already reports a runtime older than the plugin.
- [Hand-edited release pull request body loses the notes markers] → `release finish` falls back to regenerating the notes from the contained tasks.
- [One very large pull request] → the streams are reviewable commit by commit; the review agent works per stream.

## Migration Plan

1. No migration for installed projects: no `branching` block means `trunk`.
2. To adopt a preset: add the `branching` block (and `statuses.in_review`), run `init` (labels, workflows, files), push `.github/` to the default branch, run `protect --yes`.
3. This repository, after the pull request is merged and with the user's confirmation at each step: set `preset: standard` in `.github/scrum.yml` if it uses the plugin on itself, run `scrum protect` to preview, then `--yes` (creates `develop`, rules, settings). The default branch stays `main`, so the marketplace keeps serving released code.
4. Rollback: remove the `branching` block (back to `trunk`), delete the rulesets named `scrum: …`; location labels are ignored in `trunk`.

## Open Questions

- Exact wording of the Vercel settings section and the Wrangler flags: checked against current docs when the templates are written; does not change specs or tasks.
