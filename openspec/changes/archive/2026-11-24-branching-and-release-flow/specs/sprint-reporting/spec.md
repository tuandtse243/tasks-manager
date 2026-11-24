# Spec Delta

## ADDED Requirements

### Requirement: Location of tasks in review
In `standard` and `environments`, the status table, the daily digest, the HTML report and `my-tasks` SHALL show, for each task In review, where it is: waiting for code review (its pull request is open) or on a long-lived branch (its location label).

#### Scenario: Mixed locations
- **WHEN** #12 is In review with an open pull request and #13 is In review with `on: develop`
- **THEN** the status table shows #12 as in code review and #13 as on `develop`

#### Scenario: Trunk
- **WHEN** the preset is `trunk`
- **THEN** the outputs are the same as before this capability

### Requirement: Tasks waiting to be released need attention
"Needs attention" SHALL list a task that has been In review on a long-lived branch for more than `attention.promote_days` working days, with the branch and the number of days.

#### Scenario: Waiting on develop
- **WHEN** #13 got `on: develop` seven working days ago and `attention.promote_days` is 5
- **THEN** "Needs attention" lists #13 as waiting on `develop` for seven days

#### Scenario: Recently merged
- **WHEN** #14 got `on: develop` two working days ago
- **THEN** #14 is not listed
