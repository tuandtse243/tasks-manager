# Spec Delta

## ADDED Requirements

### Requirement: Release configuration
The `release` block SHALL have `tag_prefix` (default `v`, may be empty), `breaking_label` (default `breaking`) and `first_version` (default `0.1.0`). The configuration check MUST reject a `first_version` that is not semver `X.Y.Z` and an empty `breaking_label`.

#### Scenario: Defaults
- **WHEN** the configuration has no `release` block
- **THEN** `scrum config` prints `release.tag_prefix` as `v`, `release.breaking_label` as `breaking` and `release.first_version` as `0.1.0`

#### Scenario: Invalid first version
- **WHEN** the configuration sets `release.first_version: "1.0"`
- **THEN** the configuration check reports an error naming `release.first_version`
