# Tasks

Paths are relative to `plugins/scrum-github/`. Groups 2 to 5 run in parallel in separate worktrees after group 1 is committed (design.md, decision 15). Each test task names the test file; run one file with `bash tests/run.sh <name>`.

## 1. Foundation (lead, before any parallel work)

- [x] 1.1 Add the `branching`, `governance`, `deploy` blocks and the new `release` and `attention` keys to `runtime/share/defaults.json` and `jq/validate-config.jq`, including "in_review required with a working branch" and duplicate branch names; verify with new cases in `tests/test_config.sh` covering every scenario of the `scrum-config` delta and the "Unknown preset" and "Missing review status" scenarios
- [x] 1.2 Add the preset helpers to `jq/scrum.jq` (`branching`, working and release branch, `location_label`, `task_location`, `labels_with_location`, `allowed_source`) and `branch_role` in `common.sh`; verify with a new `tests/test_branching.sh` for the "Branch roles" and "Allowed source branches" scenarios
- [x] 1.3 Add `jq/branch-contents.jq` and its shell wrapper (tasks contained in a ref, via merged pull request and compare, capped at 100); verify in `tests/test_branching.sh` with `fake-gh` fixtures for contained, not contained and over-the-cap
- [x] 1.4 Add location labels to `jq/label-plan.jq` so `init` creates `on: <branch>` for each lower long-lived branch; verify in `tests/test_init.sh` for `standard`, `environments` and `trunk` (no location label)
- [x] 1.5 Register the new commands in `runtime/bin/scrum` and `bin/scrum` (`protect`, `promote`, `hotfix`, `sync`, `branches`, `cleanup`, `release finish`) with usage text, and add the shared strings (en, vi) to `strings.json`; verify `tests/test_cli.sh` lists them and unknown subcommands still fail
- [x] 1.6 Update `templates/scrum.yml` with the documented `branching` block (`preset: standard`), `statuses.in_review` on, and the commented `governance`, `release.version_files`, `deploy` keys; verify `tests/test_config.sh` validates the shipped template and that a config without `branching` still validates as `trunk`
- [x] 1.7 Run the whole suite and shellcheck, then commit; verify `bash tests/run.sh` passes and every existing test is unchanged in outcome (trunk compatibility)

## 2. Stream A: governance

- [x] 2.1 Add `templates/rulesets/{working,staging,release,tags}.json` and `jq/protect-plan.jq` that compares the repository with the preset (branches, rules, merge settings); verify against the current GitHub ruleset docs that the merge-method parameter exists and record the result in a comment in `protect-plan.jq`
- [x] 2.2 Implement `runtime/lib/cmd_protect.sh` (preview, `--json`, `--yes`, per-item failure reporting, non-zero exit when an item is refused); verify with a new `tests/test_protect.sh` covering every scenario of "Protection preview and confirmation", "Long-lived branches exist", "Branch rules", "Version tags are protected", "Repository merge settings" and "Protection that cannot be applied is reported"
- [x] 2.3 Add the governance file templates (`CODEOWNERS`, `CONTRIBUTING.md` per preset, `SECURITY.md`, `dependabot.yml`) and install them from `cmd_init.sh` without overwriting existing files; verify in `tests/test_init.sh` the "Fresh project" and "Existing CONTRIBUTING" scenarios
- [x] 2.4 Add the title and source-branch checks to `scrum pr-check` and `templates/github/workflows/scrum-pr-link-check.yml` as named steps, with the release, promotion and back-merge exemptions; verify in `tests/test_event.sh` every scenario of "Pull request title check" and "Allowed source branches"
- [x] 2.5 Pin every action in `templates/github/workflows/*.yml` and in `.github/workflows/ci.yml` of this repository to a full commit SHA with a version comment; verify with a test in `tests/test_manifest.sh` that fails on any `uses:` without a 40-character SHA
- [x] 2.6 Make scheduled and issue-triggered workflow templates check out the working branch, written by `init` from the preset; verify in `tests/test_init.sh` the "Daily digest in standard" and "Daily digest in trunk" scenarios
- [x] 2.7 Add the governance checks to `cmd_doctor.sh` and `jq/doctor-report.jq`; verify in `tests/test_doctor.sh` every scenario of "Diagnostics for governance"
- [x] 2.8 Add the `protect` skill and update the `init` and `doctor` skills; document `protect`, the `governance` block and the installed files in `README.md`; verify `tests/test_docs.sh` and `claude plugin validate plugins/scrum-github` pass

## 3. Stream B: status flow and reporting

- [x] 3.1 Pass base and head to `jq/event-decide.jq` from `cmd_event.sh` and implement the merge table of design decision 4; verify in `tests/test_event.sh` every scenario of the modified "Vòng đời PR khi bật In review", of "Task location after merge" and of "Done only on the release branch", and that all existing trunk cases still pass
- [x] 3.2 Handle the merged promotion pull request in `cmd_event.sh` (recompute contained tasks, swap the location label); verify in `tests/test_event.sh` the "Promoted to staging" and "Not in the promotion" scenarios
- [x] 3.3 Show the location of In review tasks in `jq/progress-table.jq`, `jq/digest.jq`, `jq/report-data.jq` and `jq/mine.jq`; verify in `tests/test_mine.sh` and the status and report tests the "Mixed locations" and "Trunk" scenarios
- [x] 3.4 Add "waiting to be released" to `jq/attention.jq` using the label date from the timeline; verify both scenarios of "Tasks waiting to be released need attention" in the attention tests
- [x] 3.5 List merged-but-unreleased tasks in the close preview (`cmd_sprint.sh`, `jq/close-plan.jq`); verify both scenarios of "Closing a sprint shows unreleased tasks"
- [x] 3.6 Update the `sprint-status`, `sprint-report`, `sprint-close` and `my-tasks` skills and the status section of `README.md`; verify `tests/test_docs.sh` passes

## 4. Stream C: daily commands

- [x] 4.1 Make `task start` (`cmd_task.sh`) fetch and branch from the remote working branch, with the offline fallback and warning; verify the two new scenarios of "Bắt đầu task" in the task tests and that the existing ones still pass
- [x] 4.2 Make `run` (`cmd_run.sh`) create its integration branch from the working branch and open its pull requests into it; verify the "Run in standard" scenario in the run tests and that trunk runs are unchanged
- [ ] 4.3 Update the `task-pr` skill: base branch by preset and for `hotfix/*`, Conventional Commits title, warning when behind the base; verify the two new scenarios of "Soạn mô tả PR cho task" by a documented manual run in the pull request description, and `tests/test_docs.sh` for the skill text
- [x] 4.4 Implement `sync` in a new `runtime/lib/cmd_branch.sh`; verify with a new `tests/test_branch.sh` using temporary git repositories for every scenario of "Sync a task branch" and "Sync reports conflicts"
- [x] 4.5 Implement `branches` (`cmd_branch.sh`, `jq/branches-overview.jq`, `--json`); verify in `tests/test_branch.sh` every scenario of "Branch overview"
- [x] 4.6 Implement `cleanup` (preview, `--yes`); verify in `tests/test_branch.sh` every scenario of "Clean up merged branches"
- [x] 4.7 Add the `sync`, `branches` and `cleanup` skills and update `task-start` and `run`; document the commands in `README.md` and the repository-root `docs/cheat-sheet-dev.md`; verify `tests/test_docs.sh` and `claude plugin validate plugins/scrum-github` pass

## 5. Stream D: release flow

- [x] 5.1 Extend `jq/release-plan.jq` and `cmd_release.sh` to select tasks contained in the start ref and untasked pull requests when the preset has a working branch; verify in `tests/test_release.sh` every scenario of "Tasks of a release" and "Pull requests without a task"
- [x] 5.2 Implement the version files and changelog commit on the release branch; verify in `tests/test_release.sh` both scenarios of "Version files and changelog"
- [x] 5.3 Make `scrum release --yes` open the release pull request (`release/<tag>`, `--from REF`, notes between markers) and keep the direct tag in `trunk`; verify every scenario of "Release pull request" and "Trunk releases as before"
- [x] 5.4 Implement `scrum release finish` and `templates/github/workflows/scrum-release.yml` (tag on the merge commit, GitHub Release, tasks Done, idempotent); verify every scenario of "Publishing on merge"
- [x] 5.5 Implement the back-merge pull requests in the finish step; verify every scenario of "Back-merge after the release branch changes"
- [x] 5.6 Implement `promote` in a new `runtime/lib/cmd_promote.sh`; verify with a new `tests/test_promote.sh` every scenario of "Promote the working branch to staging"
- [x] 5.7 Implement `hotfix` (start, version and version files on the hotfix branch); verify in `tests/test_promote.sh` every scenario of "Start a hotfix" and "Hotfix release"
- [x] 5.8 Add the branch flow steps to `jq/next-step.jq` and `cmd_next.sh`; verify in `tests/test_next.sh` every scenario of "Branch flow steps"
- [x] 5.9 Add the `promote` and `hotfix` skills and update `release` and `next`; rewrite "Releasing a version" in `README.md` for the three presets; verify `tests/test_docs.sh` and `claude plugin validate plugins/scrum-github` pass

## 6. Deployment templates (after merging groups 2 to 5)

- [ ] 6.1 Check the current Wrangler and Vercel docs for the flags and setting names the templates use, and note the versions checked in a comment at the top of each template
- [ ] 6.2 Add `templates/deploy/docker/deploy.yml` (image per source tree, registry, SSH deploy, manual rollback) and `templates/deploy/cloudflare/deploy.yml`; verify with a new `tests/test_deploy.sh` that the rendered workflow maps branches to environments for the three presets and names no secret value
- [ ] 6.3 Install the template of `deploy.platform` from `cmd_init.sh` without overwriting a project's own workflow, write the Vercel section into `CONTRIBUTING.md`, and list the secret names; verify in `tests/test_deploy.sh` every scenario of "Platform selection", "Vercel uses its Git integration" and "Secrets are named, never written"
- [ ] 6.4 Add the production-reviewer warning to `doctor`; verify the "No reviewer" scenario in `tests/test_doctor.sh`

## 7. Documentation and version

- [ ] 7.1 Update the repository-root `docs/adoption-guide.md` with choosing a preset, protecting the repository, the path of a task through the branches, releasing, hotfix and deployment; verify every command shown exists in `scrum help`
- [ ] 7.2 Update the repository-root `docs/cheat-sheet-dev.md`, `docs/cheat-sheet-sm.md`, `docs/cheat-sheet-po.md` and the root `README.md` table for the new flow; verify `tests/test_docs.sh` passes
- [ ] 7.3 Set version 0.13.0 in `.claude-plugin/plugin.json`, the root `README.md` and `CHANGELOG.md` (with the breaking note on Done for presets with a working branch) and update the version assertion in `tests/test_init.sh`; verify `tests/test_manifest.sh` passes

## 8. Integration checks

- [ ] 8.1 Run `bash plugins/scrum-github/tests/run.sh`, the shellcheck command from the root `README.md`, and `claude plugin validate plugins/scrum-github`; all must pass
- [ ] 8.2 Run `openspec validate branching-and-release-flow --strict`; it must pass
- [ ] 8.3 Have a read-only review agent compare the merged diff with every spec delta of this change and fix what it finds; verify by re-running 8.1
- [ ] 8.4 Walk one task through a scratch repository with preset `standard` (start, pull request into `develop`, release pull request, merge, tag, back-merge) following `docs/e2e-testing.md`, and record the result in the pull request description; if no scratch repository is available, say so in the description instead of claiming it

## Workflow follow-up

- Push the branch and open one pull request into `main`. Pushing needs the GitHub account `tuandtse243` (`gh auth switch --user tuandtse243`); confirm the account and ask the user before the first push.
- Do not merge the pull request, create tags or change repository settings without asking the user.
- After the merge, with the user's confirmation at each step: apply preset `standard` to this repository (`scrum protect`, then `--yes`); the default branch stays `main`.
- Archive the completed changes `release`, `ai-run` and `time-estimates` before archiving this one.
