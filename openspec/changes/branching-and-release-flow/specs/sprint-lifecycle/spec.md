# Spec Delta

## ADDED Requirements

### Requirement: Closing a sprint shows unreleased tasks
In `standard` and `environments`, the preview of closing a sprint SHALL list separately the tasks that are In review on a long-lived branch, say that they are not counted in the velocity because they are not released, and suggest releasing before closing. The close itself SHALL treat them like other unfinished tasks.

#### Scenario: Merged but not released
- **WHEN** the sprint has #12 Done and #13 In review with `on: develop`, and the user previews the close
- **THEN** the velocity counts only #12, #13 is listed as merged but not released, and the preview suggests `/scrum-github:release`

#### Scenario: Close without releasing
- **WHEN** the user confirms the close anyway
- **THEN** #13 moves to the next sprint like any unfinished task and keeps its status and location label
