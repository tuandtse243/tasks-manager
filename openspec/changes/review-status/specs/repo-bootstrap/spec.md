## ADDED Requirements

### Requirement: Label In review
Khi `statuses.in_review` đặt, lệnh khởi tạo SHALL tạo label trạng thái cho In review như các label trạng thái khác. Khi tắt lại, label đó MUST NOT bị xoá và được báo là lỗi thời; workflow đồng bộ trạng thái SHALL nhận cả sự kiện PR chuyển về nháp.

#### Scenario: Bật In review
- **WHEN** cấu hình đặt `statuses.in_review: In review` và người dùng chạy lệnh khởi tạo
- **THEN** label `status: In review` được tạo

#### Scenario: Tắt lại
- **WHEN** repo có label `status: In review` và cấu hình bỏ `statuses.in_review`
- **THEN** label không bị xoá và lệnh báo nó lỗi thời

#### Scenario: Workflow nhận PR chuyển về nháp
- **WHEN** lệnh khởi tạo cài `scrum-status-sync.yml`
- **THEN** kiểu sự kiện `converted_to_draft` có trong `pull_request_target.types`
