# Spec Delta

## ADDED Requirements

### Requirement: Branch flow steps
`scrum next` SHALL suggest, in this order of priority after the setup steps: protecting the repository when a long-lived branch has no rule; merging an open back-merge pull request; promoting, in `environments`, when the working branch holds tasks the staging branch lacks and no promotion is open; and releasing when In review tasks are ready on the branch the release starts from and no release pull request is open.

#### Scenario: Unprotected repository
- **WHEN** setup is complete and `main` has no rule
- **THEN** the next step is `/scrum-github:protect`

#### Scenario: Back-merge open
- **WHEN** a pull request from `main` into `develop` is open
- **THEN** the next step is to merge it, with its link

#### Scenario: Ready to release
- **WHEN** the preset is `standard`, #12 and #13 are `on: develop`, and no release pull request is open
- **THEN** the next step is `/scrum-github:release` with the number of tasks waiting

#### Scenario: Ready to promote
- **WHEN** the preset is `environments`, #12 is `on: develop` and no promotion is open
- **THEN** the next step is `/scrum-github:promote`
