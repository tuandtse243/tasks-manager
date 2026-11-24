# Spec Delta

## ADDED Requirements

### Requirement: Branching block
The configuration SHALL accept a `branching` block: `preset` (`trunk`, `standard`, `environments`), `main` (default `main`), `develop` (default `develop`), `staging` (default `staging`), `location_prefix` (default `on: `) and `stale_days` (default 5, a positive integer). Validation SHALL reject two branches of the preset that have the same name.

#### Scenario: Defaults
- **WHEN** the block is `branching: {preset: standard}`
- **THEN** the branches are `main` and `develop`, the location prefix is `on: ` and `stale_days` is 5

#### Scenario: Duplicate branch names
- **WHEN** `branching.develop` and `branching.main` are both `main` with preset `standard`
- **THEN** validation fails and names the two keys

### Requirement: Governance block
The configuration SHALL accept a `governance` block: `approvals` (default 1, an integer from 0 to 6), `required_checks` (a list of check names, default empty) and `codeowners` (a list of GitHub logins or teams, default empty).

#### Scenario: Solo project
- **WHEN** `governance.approvals` is `0`
- **THEN** validation passes

#### Scenario: Invalid approvals
- **WHEN** `governance.approvals` is `-1`
- **THEN** validation fails and names the key

### Requirement: Release files
The `release` block SHALL accept `version_files`, a list of entries with a `path` and an optional `pattern` that contains `{version}`, and `changelog`, a path or null (default). Validation SHALL reject an entry without `path` and a `pattern` without `{version}`.

#### Scenario: JSON manifest
- **WHEN** `release.version_files` is `[{path: package.json}]`
- **THEN** validation passes and the release updates the `version` field of that file

#### Scenario: Pattern without placeholder
- **WHEN** an entry has `pattern: "version 1.0"`
- **THEN** validation fails and says the pattern needs `{version}`

### Requirement: Deploy block
The configuration SHALL accept a `deploy` block with `platform`: `none` (default), `vercel`, `cloudflare` or `docker`.

#### Scenario: Unknown platform
- **WHEN** `deploy.platform` is `heroku`
- **THEN** validation fails and lists the accepted platforms

### Requirement: Attention threshold for promotion
The `attention` block SHALL accept `promote_days` (default 5, a positive integer): the number of working days a task may wait In review on a long-lived branch before it needs attention.

#### Scenario: Default
- **WHEN** `attention.promote_days` is not set
- **THEN** the threshold is 5 working days
