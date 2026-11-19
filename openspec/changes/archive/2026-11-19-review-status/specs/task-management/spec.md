## ADDED Requirements

### Requirement: Lệnh task với In review
Khi `statuses.in_review` đặt, `scrum task list --status in_review` SHALL liệt kê task In review, và mọi thao tác đặt trạng thái MUST giữ đúng một label trạng thái trong bốn trạng thái. Khi không đặt, `--status in_review` MUST bị từ chối và nêu cách bật.

#### Scenario: Liệt kê task chờ review
- **WHEN** In review bật và người dùng chạy `scrum task list --status in_review`
- **THEN** chỉ task có label In review được in

#### Scenario: Tắt
- **WHEN** In review không bật và người dùng chạy `scrum task list --status in_review`
- **THEN** lệnh dừng và nói cần đặt `statuses.in_review`
