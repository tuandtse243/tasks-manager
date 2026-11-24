# Proposal

## Why

The plugin takes a task from planning to merge and closes the sprint, but stops before the last step: publishing a version. Teams pick the version number by hand, gather what was done from issues and pull requests by hand, and create the tag and GitHub Release by hand. This repository released 0.11.0 the same way. The plugin already has everything needed: Done tasks per sprint, bug and feature labels, and the pull requests that closed each task.

## What Changes

- New command `scrum release [VERSION] [--since TAG] [--sprint S…] [--draft] [--notes-file FILE] [--json] [--yes]` and skill `/scrum-github:release`:
  - Finds the latest version tag (`v1.2.3` or `1.2.3`) reachable from the default branch.
  - Gathers the tasks closed as completed since that tag, or those of the named sprints, with the merged pull requests that closed each one.
  - Suggests the next version by semver: a task labelled `release.breaking_label` bumps major, any task that is not a bug bumps minor, otherwise patch. A `VERSION` given by the user is used as is.
  - Writes release notes in groups (breaking changes, features grouped by parent feature, bug fixes), each line with the task and pull request numbers, following the `language` key.
- The command writes only with `--yes`: it creates an annotated tag on the head commit of the remote default branch and a GitHub Release (a draft with `--draft`). Without `--yes` it only prints the version, the tasks and the release notes.
- The skill shows the preview, lets the user change the version or edit the notes, and runs with `--yes` only after the user agrees.
- New configuration block `release`: `tag_prefix` (default `v`), `breaking_label` (default `breaking`), `first_version` (default `0.1.0`, used when there is no version tag yet).
- `sprint close` suggests `/scrum-github:release` after closing a sprint with Done tasks. `scrum next` suggests releasing when the last closed sprint has Done tasks that are in no version yet.
- Plugin version 0.12.0.

Out of scope: editing version files in the code (`package.json`, `VERSION`…), writing `CHANGELOG.md` into the repository, deploying, publishing to a package registry, signed tags.

## Capabilities

### New Capabilities

- `release`: publish a version from Done tasks: find the previous tag, gather tasks, suggest the version, write the release notes, create the tag and GitHub Release after the user confirms.

### Modified Capabilities

- `scrum-config`: the `release` block.
- `sprint-lifecycle`: closing a sprint suggests a release.
- `next-step-guidance`: a release step.

## Impact

- Code (from `plugins/scrum-github/`): new `runtime/lib/cmd_release.sh`; new jq `release-plan.jq` (version choice, task selection) and `release-notes.jq`; `runtime/bin/scrum`; `defaults.json`, `validate-config.jq`; `strings.json`; `next-step.jq`, `cmd_next.sh`; `cmd_sprint.sh` (suggestion after close).
- Skills: new `release`; `sprint-close` and `next` updated.
- GitHub API: read tags (`repos/{r}/tags`), compare commits (`repos/{r}/compare`), closed issues by milestone or by time, issue timelines for the closing pull requests; write `git/tags`, `git/refs`, `releases`. Needs `contents: write` on the user's token, nothing new for workflows.
- Tests: `tests/test_release.sh` with `fake-gh`.
