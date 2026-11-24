# repo-governance Specification

## Purpose
Protects the long-lived branches and version tags of a project and installs the files and checks a team needs to work under one set of rules, and reports when any of it is missing.

## Requirements

### Requirement: Protection preview and confirmation
`scrum protect` SHALL compare the repository with what the preset requires and print each difference: missing long-lived branches, branch and tag rules, and repository merge settings. It SHALL write only with `--yes`. `--json` SHALL print the same plan as data.

#### Scenario: Preview
- **WHEN** the user runs `scrum protect` in a repository with no rules
- **THEN** the planned branches, rules and settings are listed and nothing on GitHub changes

#### Scenario: Already protected
- **WHEN** the repository already matches the preset
- **THEN** the command says there is nothing to change

### Requirement: Long-lived branches exist
With `--yes`, `scrum protect` SHALL create each long-lived branch of the preset that does not exist, from the head of the release branch. It MUST NOT move or delete an existing branch.

#### Scenario: Standard without develop
- **WHEN** the preset is `standard`, `develop` does not exist and the user runs `scrum protect --yes`
- **THEN** `develop` is created at the head of `main`

### Requirement: Branch rules
With `--yes`, `scrum protect` SHALL apply to each long-lived branch a rule that requires a pull request, requires the configured status checks, and blocks force pushes and deletion. Merge methods SHALL be: squash and merge commit on the working branch, merge commit only on the staging and release branches, squash only on the release branch in `trunk`. The number of required approvals SHALL be `governance.approvals`.

#### Scenario: Main in standard
- **WHEN** rules are applied with preset `standard`
- **THEN** `main` requires a pull request and the required checks, allows only merge commits, and rejects force pushes and deletion

#### Scenario: Solo project
- **WHEN** `governance.approvals` is `0`
- **THEN** a pull request is still required and no approval is required

### Requirement: Version tags are protected
With `--yes`, `scrum protect` SHALL apply a rule to tags matching `<release.tag_prefix>*` that blocks updating and deleting them.

#### Scenario: Moving a tag
- **WHEN** the tag rule is in place and someone force-pushes `v1.4.0` to another commit
- **THEN** GitHub rejects the push

### Requirement: Repository merge settings
With `--yes`, `scrum protect` SHALL turn on deleting the head branch after merge and auto-merge, and SHALL allow exactly the merge methods the preset uses.

#### Scenario: Trunk
- **WHEN** settings are applied with preset `trunk`
- **THEN** squash merging is the only method allowed and head branches are deleted after merge

### Requirement: Protection that cannot be applied is reported
When GitHub refuses a rule or setting (the plan does not offer it, or the token lacks admin rights), the command SHALL say which item failed and why, continue with the remaining items, and exit non-zero.

#### Scenario: Private repository on a free plan
- **WHEN** GitHub answers 403 to creating a ruleset
- **THEN** the command reports that rules are not available for this repository on its plan, applies the merge settings, and exits non-zero

### Requirement: Governance files
`init` SHALL install `CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md` and `.github/dependabot.yml` when they do not exist. `CONTRIBUTING.md` SHALL describe the preset's branches, the pull request title rule and the release path. It MUST NOT overwrite a file the project already has.

#### Scenario: Fresh project
- **WHEN** `init` runs in a project with none of these files
- **THEN** the four files exist and `dependabot.yml` updates GitHub Actions weekly in one grouped pull request

#### Scenario: Existing CONTRIBUTING
- **WHEN** the project already has `CONTRIBUTING.md`
- **THEN** the file is left unchanged and `init` says it was skipped

### Requirement: Pull request title check
An installed check SHALL fail when a pull request title does not start with a Conventional Commits type (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `perf`, `build`, `revert`), optionally followed by a scope and `!`, then `: `. Release, back-merge and promotion pull requests SHALL be exempt.

#### Scenario: Valid title
- **WHEN** a pull request is titled `feat(auth): log in with email`
- **THEN** the check passes

#### Scenario: Invalid title
- **WHEN** a pull request is titled `Login page`
- **THEN** the check fails and shows an example of a valid title

#### Scenario: Release pull request
- **WHEN** a pull request from `release/v1.4.0` is titled `Release v1.4.0`
- **THEN** the check passes

### Requirement: Installed workflows pin actions
Every workflow the plugin installs SHALL reference third-party and GitHub actions by full commit SHA, with the version in a comment.

#### Scenario: Checkout action
- **WHEN** `init` installs a workflow that checks out the repository
- **THEN** the `uses:` line names a 40-character commit SHA

### Requirement: Diagnostics for governance
`doctor` SHALL report, each with its fix: a long-lived branch of the preset that does not exist, a default branch that is not the release branch, a long-lived branch without a rule, a missing governance file, and a release branch that holds commits the working branch lacks.

#### Scenario: Default branch is develop
- **WHEN** the preset is `standard` and the default branch of the repository is `develop`
- **THEN** `doctor` reports an error and tells the user to set the default branch to `main`

#### Scenario: Main is ahead of develop
- **WHEN** `main` has a commit that `develop` does not contain
- **THEN** `doctor` reports a warning and suggests the back-merge

#### Scenario: Unprotected main
- **WHEN** `main` has no rule
- **THEN** `doctor` reports a warning and suggests `/scrum-github:protect`
