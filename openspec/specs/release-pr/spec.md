# release-pr Specification

## Purpose
Publishes a version through a pull request into the release branch in projects that have a working branch: the pull request carries the version and the notes, and merging it creates the tag, the GitHub Release and marks the released tasks Done.

## Requirements

### Requirement: Release pull request
In `standard` and `environments`, `scrum release … --yes` SHALL create the branch `release/<tag>` and open a pull request from it into the release branch, titled `Release <tag>`, with the release notes as its body. It MUST NOT create the tag or the GitHub Release itself. The branch starts from the head of the working branch in `standard`, of the staging branch in `environments`, or from `--from REF` when given.

#### Scenario: Standard
- **WHEN** the preset is `standard` and the user runs `scrum release 1.4.0 --yes`
- **THEN** `release/v1.4.0` exists at the head of `develop`, a pull request "Release v1.4.0" into `main` is open, and no tag `v1.4.0` exists

#### Scenario: Environments
- **WHEN** the preset is `environments` and the user runs `scrum release 1.4.0 --yes`
- **THEN** `release/v1.4.0` starts at the head of `staging`

#### Scenario: Release up to a commit
- **WHEN** the user runs `scrum release 1.4.0 --from abc123 --yes`
- **THEN** `release/v1.4.0` starts at commit `abc123` and later commits on `develop` are not in the release

#### Scenario: Release already open
- **WHEN** a pull request from a `release/*` branch into the release branch is already open
- **THEN** the command stops and names that pull request

### Requirement: Tasks of a release
In `standard` and `environments`, the release SHALL contain the tasks that are In review and whose merged pull request is contained in the release branch. Tasks whose code is not in the release branch MUST NOT be listed. The suggested version follows the same label rules as before, applied to these tasks.

#### Scenario: Task merged after the release point
- **WHEN** #12 was merged into `develop` before commit `abc123`, #13 after it, and the user runs `scrum release --from abc123`
- **THEN** the preview lists #12 and not #13

#### Scenario: Environments, task not promoted
- **WHEN** the preset is `environments`, #12 is `on: staging` and #13 is `on: develop`
- **THEN** the preview lists #12 and not #13

#### Scenario: Nothing to release
- **WHEN** no In review task is contained in the release branch and no untasked pull request is
- **THEN** the command says there is nothing to release and creates nothing

### Requirement: Pull requests without a task
Merged pull requests contained in the release that link no task SHALL be listed in the notes under an "Other" group. They MUST NOT change the suggested version, and a release that would contain only such pull requests SHALL be suggested as a patch.

#### Scenario: Dependency update
- **WHEN** the release contains task #12 (a feature) and an untasked pull request #40 "chore: bump actions"
- **THEN** the notes list #40 under "Other" and the suggested version is a minor bump

### Requirement: Version files and changelog
When `release.version_files` or `release.changelog` is set, the command SHALL commit on the release branch the new version in each listed file and the release notes at the top of the changelog, before opening the pull request. With neither set, the release branch SHALL carry no extra commit.

#### Scenario: Version file
- **WHEN** `release.version_files` lists `package.json` and the release is `1.4.0`
- **THEN** the release branch has one commit that sets the version in `package.json` to `1.4.0`

#### Scenario: File without a version
- **WHEN** a listed file contains no version to replace
- **THEN** the command stops before creating the branch and names the file

### Requirement: Publishing on merge
When a pull request from `release/*` or `hotfix/*` is merged into the release branch, the installed workflow SHALL create the annotated tag on the merge commit, create the GitHub Release with the notes, move every contained task to Done, remove its location label and close it as completed. Running it again for the same merge MUST NOT create a second tag or Release.

#### Scenario: Release merged
- **WHEN** "Release v1.4.0" containing #12 is merged into `main`
- **THEN** tag `v1.4.0` points at the merge commit, the GitHub Release exists, and #12 is `status: Done`, closed, with no location label

#### Scenario: Workflow runs twice
- **WHEN** the workflow is re-run after it already published `v1.4.0`
- **THEN** it reports the version as already published and changes nothing

#### Scenario: Release pull request closed without merging
- **WHEN** the release pull request is closed without merging
- **THEN** no tag is created and task statuses do not change

### Requirement: Back-merge after the release branch changes
After a merge into the release branch, the workflow SHALL open a pull request from the release branch into each lower long-lived branch that does not contain its head, unless such a pull request is already open.

#### Scenario: After a release in standard
- **WHEN** "Release v1.4.0" is merged into `main`
- **THEN** a pull request from `main` into `develop` is opened

#### Scenario: Environments
- **WHEN** a hotfix is merged into `main` with preset `environments`
- **THEN** pull requests from `main` into `staging` and into `develop` are opened

#### Scenario: Already open
- **WHEN** a pull request from `main` into `develop` is already open
- **THEN** no second one is opened

### Requirement: Trunk releases as before
In `trunk`, `scrum release` SHALL keep creating the tag and the GitHub Release directly on the head of the release branch, and no release pull request is opened.

#### Scenario: Trunk
- **WHEN** the preset is `trunk` and the user runs `scrum release 1.4.0 --yes`
- **THEN** tag `v1.4.0` and its GitHub Release are created and no pull request is opened
