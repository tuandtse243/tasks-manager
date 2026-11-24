# Proposal

## Why

The plugin manages tasks and sprints but leaves the repository itself unmanaged: nothing protects `main`, every command assumes one branch, a task is Done as soon as a pull request merges anywhere, the version is edited by hand in three files, and there is no deployment flow. A lead who scaffolds a project for a team needs the whole path set up once: branches, protection, review, status that follows the code through the branches, release and deployment. This repository has the same gaps (no ruleset on `main`, all merge methods on, no CODEOWNERS or Dependabot).

## What Changes

- **Branching presets.** New `branching.preset`: `standard` (`develop` + `main`, written by `init` for new setups), `environments` (`develop` + `staging` + `main`), `trunk` (`main` only, today's behaviour and the value assumed when the block is missing). The default branch of the repository is always `main`; tags live only on `main`. Code moves one way: task branch → `develop` → (`staging`) → `main`; only `hotfix/*` starts from `main`.
- **Task status follows the code. BREAKING for presets with `develop`:** a merged pull request no longer makes a task Done. The task stays `In review` with a location label (`on: develop`, `on: staging`) and becomes Done, and is closed, only when its code is merged into `main`. `statuses.in_review` is required in these presets. `trunk` is unchanged.
- **Repository protection.** New `scrum protect`: creates the long-lived branches, applies rulesets per branch (pull request required, required checks, no force push, no deletion, merge methods), a tag rule for `v*`, and the merge settings of the repository. Preview first, writes with `--yes`.
- **Scaffold.** `init` also installs `CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md`, `dependabot.yml`, a pull request title check (Conventional Commits) and a source-branch check; installed workflows pin actions by commit SHA. `doctor` checks all of it.
- **Release by pull request** (presets with `develop`): `scrum release --yes` opens a release pull request into `main` from a `release/<tag>` branch, with the version chosen from task labels, the notes, and the configured version files and changelog updated. Merging it creates the tag and the GitHub Release, moves the contained tasks to Done and opens a back-merge pull request. Pull requests without a task are listed under "Other" and never cause a release on their own.
- **New commands:** `promote` (develop → staging), `hotfix` (fix from `main`, patch release, back-merge), `sync` (bring the working branch into the current task branch), `branches` (what each branch holds that the next lacks, drift, stale branches), `cleanup` (delete merged branches after confirmation).
- **Existing commands follow the preset:** `task-start`, `task-pr`, `run` use the working branch as base; `sprint-status`, `sprint-report`, the digest and `my-tasks` show where an In review task is and flag tasks waiting to be promoted; `sprint-close` and `next` remind to release, because only tasks on `main` count as Done.
- **Deployment templates for web:** `deploy.platform` (`vercel`, `cloudflare`, `docker`, `none`) installs a deployment workflow mapped to the preset's branches, with approval before production and a rollback.
- Scheduled and issue-triggered workflows stay on the default branch (a GitHub rule) and check out the working branch for configuration and runtime.
- Plugin version 0.13.0. This repository adopts `standard` after the change is merged.

Out of scope: merge queue, signed commits, organization-level rulesets, monorepo versioning, mobile or library publishing, feature-flag tooling, changing how `trunk` releases.

## Capabilities

### New Capabilities

- `branching-presets`: the three presets, the role of each branch, which branch commands start from and target, and which source branches each long-lived branch accepts.
- `repo-governance`: protection of branches and tags, repository merge settings, the governance files and checks installed in a project, and their diagnostics.
- `release-pr`: releasing through a pull request into `main`: the release branch, contained tasks, tag and GitHub Release on merge, Done on merge, back-merge.
- `branch-promotion`: promoting `develop` to `staging` and the hotfix path from `main`.
- `branch-collaboration`: day-to-day branch commands for a team: `sync`, `branches`, `cleanup`.
- `deploy-templates`: deployment workflows for web projects per platform, mapped to the preset's branches.

### Modified Capabilities

- `pr-task-linking`: status on merge depends on the preset; location labels; Done only on `main`; pull request description targets the preset's base branch.
- `task-management`: starting a task branches from the working branch.
- `scrum-config`: new `branching`, `governance` and `deploy` blocks and new `release` keys.
- `sprint-reporting`: location of In review tasks and a "waiting to be promoted" attention item.
- `sprint-lifecycle`: closing a sprint reminds to release tasks that are not on `main` yet.
- `next-step-guidance`: steps for promote, release, back-merge and protection.

## Impact

- Code (from `plugins/scrum-github/`): `runtime/lib/jq/scrum.jq` (preset helpers), `event-decide.jq`, `cmd_event.sh`, `cmd_task.sh`, `cmd_run.sh`, `cmd_release.sh`, `release-plan.jq`, `release-notes.jq`, `cmd_init.sh`, `cmd_doctor.sh`, `cmd_sprint.sh`, `cmd_next.sh`, `next-step.jq`, `attention.jq`, `progress-table.jq`, `digest.jq`, `mine.jq`, `validate-config.jq`, `defaults.json`, `strings.json`, `runtime/bin/scrum`; new `cmd_protect.sh`, `cmd_branch.sh` (sync, branches, cleanup), `cmd_promote.sh` (promote, hotfix) and their jq.
- Templates: new workflows (release finish, back-merge, title and source checks, deploy per platform), rulesets as JSON, governance files; existing workflows pinned by SHA and reading the working branch.
- Skills: new `protect`, `promote`, `hotfix`, `sync`, `branches`, `cleanup`; updated `init`, `doctor`, `task-start`, `task-pr`, `run`, `release`, `sprint-status`, `sprint-close`, `next`, `my-tasks`.
- GitHub API: rulesets, repository settings, branches, environments (admin rights needed for `protect`); `contents: write` and `pull-requests: write` for the release workflow.
- Compatibility: a configuration without `branching` behaves as `trunk`, so installed projects keep working. The `release` and `ai-run` changes are implemented but not archived; they should be archived before this change is.
- Docs: README, adoption guide, cheat sheets, CHANGELOG; tests with `fake-gh` for every new command.
