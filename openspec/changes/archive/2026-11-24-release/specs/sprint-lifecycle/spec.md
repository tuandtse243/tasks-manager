# Spec Delta

## ADDED Requirements

### Requirement: Suggest a release after closing a sprint
After closing a sprint with at least one Done task, the sprint close command SHALL suggest `/scrum-github:release --sprint "<sprint name>"`. The suggestion MUST NOT be printed when the sprint has no Done task.

#### Scenario: Done tasks
- **WHEN** the user closes Sprint 5 with 4 Done tasks
- **THEN** the command suggests `/scrum-github:release --sprint "Sprint 5"`

#### Scenario: No Done task
- **WHEN** the user closes a sprint with no Done task
- **THEN** the command does not suggest a release
