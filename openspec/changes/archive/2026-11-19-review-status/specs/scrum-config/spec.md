## ADDED Requirements

### Requirement: Trạng thái In review tuỳ chọn
Khoá `statuses.in_review` SHALL mặc định không đặt (`null`), tức là tắt: plugin có ba trạng thái như cũ. Khi đặt thành một tên không rỗng, khác ba tên trạng thái còn lại, plugin có bốn trạng thái theo thứ tự New → In progress → In review → Done. Tên rỗng hoặc trùng MUST bị từ chối khi kiểm tra cấu hình.

#### Scenario: Mặc định tắt
- **WHEN** cấu hình không có `statuses.in_review`
- **THEN** mọi lệnh, workflow, bảng và báo cáo hoạt động như khi chỉ có ba trạng thái

#### Scenario: Trùng tên
- **WHEN** cấu hình đặt `statuses.in_review: Done`
- **THEN** kiểm tra cấu hình báo lỗi nêu `statuses`

### Requirement: Ngưỡng chờ review
Khoá `attention.review_days` (mặc định 2) SHALL là số nguyên không âm: số ngày làm việc một task được ở In review trước khi vào mục cần chú ý. Giá trị khác MUST bị từ chối khi kiểm tra cấu hình.

#### Scenario: Giá trị sai
- **WHEN** cấu hình đặt `attention.review_days: "x"`
- **THEN** kiểm tra cấu hình báo lỗi nêu `attention.review_days`

### Requirement: Cột board cho In review
Khoá `project.status_options.in_review` (mặc định `In Review`) SHALL là tên option của field Status ứng với In review. Khoá này chỉ được dùng khi `statuses.in_review` đặt, và khi đó MUST khác ba option còn lại.

#### Scenario: Trùng option
- **WHEN** `statuses.in_review` đặt và `project.status_options.in_review` bằng `Done`
- **THEN** kiểm tra cấu hình báo lỗi nêu `project.status_options`
