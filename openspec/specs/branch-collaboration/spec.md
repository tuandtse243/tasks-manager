# branch-collaboration Specification

## Purpose
Gives a team the everyday branch commands for working together: keep a task branch current, see what each long-lived branch holds and what has drifted, and remove branches that are finished.

## Requirements

### Requirement: Sync a task branch
`scrum sync` SHALL fetch the working branch and merge it into the current branch. It MUST refuse on a long-lived branch and when the working tree has uncommitted changes. A hotfix branch SHALL be synced with the release branch instead.

#### Scenario: Behind the working branch
- **WHEN** `feat/12-login` is three commits behind `origin/develop` and the user runs `scrum sync`
- **THEN** `origin/develop` is merged into `feat/12-login` and the command reports three commits brought in

#### Scenario: Up to date
- **WHEN** the current branch already contains `origin/develop`
- **THEN** the command says the branch is up to date and changes nothing

#### Scenario: Uncommitted changes
- **WHEN** the working tree has uncommitted changes
- **THEN** the command refuses and tells the user to commit or stash first

#### Scenario: On a long-lived branch
- **WHEN** the current branch is `develop`
- **THEN** the command refuses and says it works on task branches

### Requirement: Sync reports conflicts
When the merge conflicts, `scrum sync` SHALL list each conflicted file with the author and subject of the last commit on the working branch that changed it, leave the merge in progress for the user to resolve, and say how to continue or abort. It MUST NOT resolve conflicts itself.

#### Scenario: Conflict
- **WHEN** merging `origin/develop` conflicts in `src/auth.ts`, last changed on `develop` by `ruby` in "feat: session timeout"
- **THEN** the command lists `src/auth.ts` with that author and subject, and the repository is left in the conflicted merge

### Requirement: Branch overview
`scrum branches` SHALL show, read-only: for each pair of consecutive long-lived branches, how many commits and which tasks the lower one has that the upper one lacks; commits of the release branch that a lower branch lacks; open promotion, release and back-merge pull requests; and task branches with no commit for `branching.stale_days` working days, with their last author. `--json` SHALL print the same as data.

#### Scenario: Waiting on develop
- **WHEN** the preset is `standard` and `develop` holds merged tasks #12 and #13 that `main` lacks
- **THEN** the overview shows `develop → main` with both tasks

#### Scenario: Drift
- **WHEN** `main` has a hotfix commit that `develop` does not contain
- **THEN** the overview shows that `develop` is missing it and names the open back-merge pull request, or says none is open

#### Scenario: Stale branch
- **WHEN** `feat/9-export` had its last commit eight working days ago by `david` and `branching.stale_days` is 5
- **THEN** the overview lists it as stale with `david`

#### Scenario: Trunk
- **WHEN** the preset is `trunk`
- **THEN** the overview shows only open pull requests and stale task branches

### Requirement: Clean up merged branches
`scrum cleanup` SHALL list local and remote branches whose pull request was merged or whose commits are all contained in a long-lived branch, and delete them only with `--yes`. It MUST NOT list long-lived branches, the current branch, or a branch with an open pull request.

#### Scenario: Preview
- **WHEN** `feat/7-signup` was squash-merged through a merged pull request and the user runs `scrum cleanup`
- **THEN** the branch is listed and nothing is deleted

#### Scenario: Delete
- **WHEN** the user runs `scrum cleanup --yes`
- **THEN** the listed branches are deleted locally and on the remote

#### Scenario: Branch with an open pull request
- **WHEN** `feat/8-profile` has an open pull request
- **THEN** it is not listed

### Requirement: Skills for the branch commands
The plugin SHALL provide the skills `sync`, `branches` and `cleanup`. The `cleanup` skill SHALL show the list and run with `--yes` only after the user agrees.

#### Scenario: Cleanup skill
- **WHEN** the user invokes `/scrum-github:cleanup`
- **THEN** the skill shows the branches to delete and asks before deleting
