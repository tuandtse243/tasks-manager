# branch-promotion Specification

## Purpose
Moves code between long-lived branches outside the normal release: promoting the working branch to the staging branch for testing, and fixing production from the release branch without waiting for the next release.

## Requirements

### Requirement: Promote the working branch to staging
In `environments`, `scrum promote` SHALL list the tasks on the working branch that the staging branch does not contain yet, and with `--yes` open a pull request from the working branch into the staging branch that lists them. Without `--yes` it SHALL only preview. In other presets it SHALL stop and say that the preset has no staging branch.

#### Scenario: Preview
- **WHEN** the preset is `environments`, #12 and #13 are `on: develop`, and the user runs `scrum promote`
- **THEN** both tasks are listed and no pull request is opened

#### Scenario: Open the promotion
- **WHEN** the user runs `scrum promote --yes`
- **THEN** a pull request from `develop` into `staging` is opened and its body lists #12 and #13

#### Scenario: Nothing to promote
- **WHEN** `staging` already contains the head of `develop`
- **THEN** the command says there is nothing to promote

#### Scenario: Promotion already open
- **WHEN** a pull request from `develop` into `staging` is already open
- **THEN** the command names that pull request and opens no other

#### Scenario: Standard preset
- **WHEN** the preset is `standard` and the user runs `scrum promote`
- **THEN** the command stops and points to `/scrum-github:release`

### Requirement: Start a hotfix
In `standard` and `environments`, `scrum hotfix N` SHALL, for an open task: assign it to the current user when unassigned, set it In progress, and create and check out `hotfix/N-<slug>` from the remote head of the release branch. It MUST refuse a closed issue. In `trunk` it SHALL stop and say that `task start` already branches from the release branch.

#### Scenario: Start
- **WHEN** the user runs `scrum hotfix 31` for the open task #31 "Payment fails"
- **THEN** #31 is In progress and `hotfix/31-payment-fails` is checked out, created from `origin/main`

#### Scenario: Closed issue
- **WHEN** #31 is closed
- **THEN** the command refuses and changes nothing

### Requirement: Hotfix release
A hotfix pull request SHALL target the release branch. Before it is opened, the command that prepares it SHALL choose the version from the labels of the hotfix task (a patch for a bug) and apply the configured version files and changelog on the hotfix branch, so that merging publishes the version like a release pull request does.

#### Scenario: Hotfix merged
- **WHEN** the previous version is `v1.4.0`, the hotfix for bug #31 is merged into `main`
- **THEN** tag `v1.4.1` and its GitHub Release exist, #31 is Done and closed, and a back-merge pull request into `develop` is open

#### Scenario: Pull request of a hotfix branch
- **WHEN** `/task-pr` runs on `hotfix/31-payment-fails`
- **THEN** the pull request is opened with base `main` and its description states the version it will publish
