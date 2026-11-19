## ADDED Requirements

### Requirement: Ngày làm việc
Khoá `sprint.working_days` SHALL là danh sách thứ trong tuần theo ISO (1 là thứ 2, 7 là chủ nhật), mặc định `[1, 2, 3, 4, 5]`. Danh sách rỗng, có số ngoài 1 đến 7 hoặc có số trùng MUST bị từ chối khi kiểm tra cấu hình. `sprint.length_days` vẫn là số ngày lịch.

#### Scenario: Mặc định
- **WHEN** cấu hình không có `sprint.working_days`
- **THEN** thứ 2 tới thứ 6 là ngày làm việc

#### Scenario: Giá trị sai
- **WHEN** cấu hình đặt `sprint.working_days: [0, 1]`
- **THEN** kiểm tra cấu hình báo lỗi nêu `sprint.working_days`

### Requirement: Ngưỡng cần chú ý
Khoá `attention.stale_days` (mặc định 2) và `attention.behind_percent` (mặc định 15) SHALL là số nguyên không âm; giá trị khác MUST bị từ chối khi kiểm tra cấu hình.

#### Scenario: Ngưỡng sai
- **WHEN** cấu hình đặt `attention.stale_days: -1`
- **THEN** kiểm tra cấu hình báo lỗi nêu `attention.stale_days`

### Requirement: Ngôn ngữ
Khoá `language` SHALL nhận `en` (mặc định) hoặc `vi` và chọn ngôn ngữ cho chữ cố định của bảng tiến độ, digest, báo cáo HTML và bản tổng kết sprint. Giá trị khác MUST bị từ chối khi kiểm tra cấu hình.

#### Scenario: Ngôn ngữ không hỗ trợ
- **WHEN** cấu hình đặt `language: fr`
- **THEN** kiểm tra cấu hình báo lỗi nêu các giá trị `en`, `vi`

### Requirement: Định dạng webhook của digest
Khoá `digest.webhook_format` SHALL nhận `slack` (mặc định, dùng được cho Google Chat và Mattermost) hoặc `telegram`; giá trị khác MUST bị từ chối khi kiểm tra cấu hình. Địa chỉ webhook MUST NOT nằm trong file cấu hình mà đến từ secret hoặc biến môi trường `SCRUM_DIGEST_WEBHOOK`.

#### Scenario: Định dạng không hỗ trợ
- **WHEN** cấu hình đặt `digest.webhook_format: teams`
- **THEN** kiểm tra cấu hình báo lỗi nêu các giá trị `slack`, `telegram`
