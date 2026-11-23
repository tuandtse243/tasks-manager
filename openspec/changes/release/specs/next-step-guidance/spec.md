# Spec Delta

## ADDED Requirements

### Requirement: Suggest a release
When the most recently closed sprint has Done tasks closed after the latest version tag, and no step with a higher priority applies, `scrum next` SHALL suggest `/scrum-github:release`. When the tags cannot be read, this step SHALL be skipped.

#### Scenario: Sprint done, not released
- **WHEN** Sprint 5 is closed with 4 Done tasks closed after tag `v1.4.2`, and no step with a higher priority applies
- **THEN** `scrum next` suggests `/scrum-github:release`

#### Scenario: Already released
- **WHEN** every Done task of Sprint 5 was closed before the latest tag
- **THEN** `scrum next` does not suggest a release
