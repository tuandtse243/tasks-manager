# branching-presets Specification

## Purpose
Defines how a project's long-lived branches are organised (one of three presets), what role each branch has, and which branch every command starts from and targets, so a whole team follows the same path from a task branch to production.

## Requirements

### Requirement: Preset selection
The configuration key `branching.preset` SHALL accept `trunk`, `standard` and `environments`. A configuration without a `branching` block SHALL behave as `trunk`. `init` SHALL write `preset: standard` into a configuration it creates.

#### Scenario: No branching block
- **WHEN** `.github/scrum.yml` has no `branching` block
- **THEN** every command behaves as with `preset: trunk`

#### Scenario: New setup
- **WHEN** `init` creates `.github/scrum.yml` in a repository that has none
- **THEN** the file contains `branching.preset: standard`

#### Scenario: Unknown preset
- **WHEN** `branching.preset` is `gitflow`
- **THEN** configuration validation fails and names the three accepted values

### Requirement: Branch roles
Each preset SHALL define a release branch and a working branch. The release branch is `branching.main` (default `main`) in every preset. The working branch is `branching.develop` (default `develop`) in `standard` and `environments`, and the release branch in `trunk`. `environments` adds a staging branch, `branching.staging` (default `staging`), between the two.

#### Scenario: Standard
- **WHEN** the preset is `standard` with default names
- **THEN** the working branch is `develop` and the release branch is `main`

#### Scenario: Trunk
- **WHEN** the preset is `trunk`
- **THEN** the working branch and the release branch are both `main`

#### Scenario: Renamed working branch
- **WHEN** the preset is `standard` and `branching.develop` is `dev`
- **THEN** the working branch is `dev`

### Requirement: Commands use the working branch
Commands that create a branch for work or open a pull request for it SHALL use the working branch as the base: `task start` creates the task branch from it, `task-pr` targets it, and `run` creates its integration branch from it and opens its pull requests into it. They SHALL read the remote state of that branch, not a possibly stale local copy.

#### Scenario: Run in standard
- **WHEN** the preset is `standard` and the user starts a run
- **THEN** the integration branch is created from `origin/develop` and its pull request targets `develop`

#### Scenario: Pull request of a task branch
- **WHEN** the preset is `standard` and `/task-pr` runs on `feat/12-login`
- **THEN** the pull request is opened with base `develop`

### Requirement: Allowed source branches
In `standard` and `environments`, a pull request check SHALL fail when the head branch is not allowed for the base branch. The release branch accepts `release/*` and `hotfix/*`. The staging branch accepts the working branch and the release branch. The working branch accepts any branch except the staging branch. In `trunk` the check SHALL always pass.

#### Scenario: Task branch into main
- **WHEN** the preset is `standard` and a pull request from `feat/12-login` targets `main`
- **THEN** the check fails and says the branch must target `develop`

#### Scenario: Release branch into main
- **WHEN** a pull request from `release/v1.4.0` targets `main`
- **THEN** the check passes

#### Scenario: Back-merge into develop
- **WHEN** a pull request from `main` targets `develop`
- **THEN** the check passes

#### Scenario: Trunk
- **WHEN** the preset is `trunk` and a pull request from `feat/12-login` targets `main`
- **THEN** the check passes

### Requirement: Review status is required with a working branch
In `standard` and `environments`, configuration validation SHALL fail when `statuses.in_review` is not set, because a task waits in that status between its merge and the release.

#### Scenario: Missing review status
- **WHEN** the preset is `standard` and `statuses.in_review` is not set
- **THEN** validation fails and says which key to set

### Requirement: Background jobs read the working branch
Workflows that GitHub starts from the default branch (scheduled ones and those triggered by issues) SHALL check out the working branch to read the configuration and the runtime.

#### Scenario: Daily digest in standard
- **WHEN** the scheduled digest workflow runs in a project with preset `standard`
- **THEN** it checks out `develop` before running the digest

#### Scenario: Daily digest in trunk
- **WHEN** the scheduled digest workflow runs in a project with preset `trunk`
- **THEN** it checks out `main`
