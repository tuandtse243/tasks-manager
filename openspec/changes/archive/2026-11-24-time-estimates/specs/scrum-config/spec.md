# Spec Delta

## ADDED Requirements

### Requirement: Giờ review của thành viên
Mỗi thành viên trong `team` SHALL có thể có `review_hours`: số giờ người đó dành cho review mỗi sprint. Giá trị không phải số dương MUST bị từ chối khi kiểm tra cấu hình.

#### Scenario: Giá trị sai
- **WHEN** một thành viên có `review_hours: -1`
- **THEN** kiểm tra cấu hình báo lỗi nêu `team` và `review_hours`

### Requirement: Thời gian merge giữa các đợt
Khoá `planning.merge_minutes` SHALL là số nguyên không âm, mặc định 5, dùng trong mọi ước tính thời gian làm theo đợt. Giá trị khác MUST bị từ chối khi kiểm tra cấu hình.

#### Scenario: Mặc định
- **WHEN** cấu hình không có `planning.merge_minutes`
- **THEN** `scrum config` in `planning.merge_minutes` là 5

#### Scenario: Giá trị sai
- **WHEN** cấu hình đặt `planning.merge_minutes: "x"`
- **THEN** kiểm tra cấu hình báo lỗi nêu `planning.merge_minutes`
