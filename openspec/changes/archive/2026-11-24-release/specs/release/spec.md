# Spec Delta

## Purpose

Publish a version of the target repository from the tasks that are done: choose the version number, write release notes from tasks and pull requests, then create the tag and GitHub Release after the user confirms.

## ADDED Requirements

### Requirement: Previous version
`scrum release` SHALL take as the previous version the tag of the form `<tag_prefix>X.Y.Z` (or `X.Y.Z`) with the highest semver that is reachable from the default branch. With `--since TAG`, the command SHALL use that tag. When there is no version tag, the suggested version SHALL be `release.first_version`.

#### Scenario: Several tags
- **WHEN** the repository has tags `v0.9.0`, `v0.11.0` and `v0.10.0`
- **THEN** the previous version is `v0.11.0`

#### Scenario: No tag yet
- **WHEN** the repository has no version tag and `release.first_version` is `0.1.0`
- **THEN** the suggested version is `0.1.0`

### Requirement: Gather done tasks
The command SHALL gather the tasks closed as completed after the previous tag, or only the tasks of the sprints named with `--sprint`. Tasks closed as not planned, epics, features, meta issues and pull requests MUST NOT be gathered. Each task SHALL come with the merged pull requests that closed it, when they can be read.

#### Scenario: Since the previous tag
- **WHEN** the previous tag's commit is from 2026-11-10, #12 was closed as completed on 2026-11-15 and #13 was closed as not planned on 2026-11-16
- **THEN** the release contains #12 and not #13

#### Scenario: By sprint
- **WHEN** the user runs `scrum release --sprint "Sprint 5"`
- **THEN** the release contains only the Done tasks of Sprint 5

#### Scenario: Nothing to release
- **WHEN** no task was completed since the previous tag
- **THEN** the command says there is nothing to release, exits with 0 and writes nothing

### Requirement: Suggested version
When the user gives no `VERSION`, the command SHALL bump the previous version: major when a task has the `release.breaking_label` label, otherwise minor when a task has no bug label, otherwise patch. A `VERSION` given by the user MUST be semver and MUST be greater than the previous version, otherwise the command stops before writing.

#### Scenario: Only bugs
- **WHEN** the previous version is `v1.4.2` and every gathered task has the `bug` label
- **THEN** the suggested version is `v1.4.3`

#### Scenario: A feature
- **WHEN** the previous version is `v1.4.2` and one task has no `bug` label
- **THEN** the suggested version is `v1.5.0`

#### Scenario: A breaking change
- **WHEN** the previous version is `v1.4.2` and one task has the `breaking` label
- **THEN** the suggested version is `v2.0.0`

#### Scenario: Invalid version given
- **WHEN** the previous version is `v1.4.2` and the user runs `scrum release 1.4.0`
- **THEN** the command stops, says the version must be greater than `v1.4.2`, and writes nothing

### Requirement: Release notes
The release notes SHALL have these groups in order: breaking changes, features (grouped by parent feature when there is one), bug fixes; empty groups are not printed. Each line SHALL have the task title, the task number and the numbers of the pull requests that closed it. Fixed text follows the `language` key.

#### Scenario: Parent feature
- **WHEN** #12 and #13 are sub-issues of feature #10 "Comments", and #14 is a bug
- **THEN** the notes have a features group with the heading "Comments" holding #12 and #13, and a bug fixes group holding #14

### Requirement: Preview and confirmation
Without `--yes`, `scrum release` SHALL only print the previous version, the new version, the tasks and the release notes, and MUST NOT write anything to GitHub. The skill `/scrum-github:release` SHALL show the preview, let the user change the version or edit the notes, and MUST wait for the user's agreement before running with `--yes`.

#### Scenario: Preview
- **WHEN** the user runs `scrum release`
- **THEN** the command prints the new version and the release notes, and makes no write call to GitHub

### Requirement: Tag and GitHub Release
With `--yes`, the command SHALL create an annotated tag named after the new version on the head commit of the default branch on GitHub, then a GitHub Release for that tag with the release notes; with `--draft` the release is a draft. When the tag already exists and already has a release, the command MUST stop before writing. When creating the release fails after the tag was created, the command SHALL say the tag exists and that running it again creates only the release.

#### Scenario: Release
- **WHEN** the user runs `scrum release --yes` and the new version is `v1.5.0`
- **THEN** GitHub has a tag `v1.5.0` on the head commit of the default branch and a release `v1.5.0` with the release notes

#### Scenario: Tag already released
- **WHEN** tag `v1.5.0` and its release already exist and the user runs `scrum release 1.5.0 --yes`
- **THEN** the command stops, says the version is already released, and writes nothing

#### Scenario: Release failed after the tag
- **WHEN** a previous run created tag `v1.5.0` but failed to create the release, and the user runs `scrum release 1.5.0 --yes` again
- **THEN** only the release is created, and the tag is not changed
