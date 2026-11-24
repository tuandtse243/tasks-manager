# Spec Delta

## ADDED Requirements

### Requirement: Cấu hình chạy task bằng agent
Khối `run` SHALL có `test_command` (chuỗi, mặc định trống: agent tự tìm cách chạy test), `max_parallel` (số nguyên dương, mặc định 3) và `branch_pattern` (mặc định `run/{sprint}-{login}`, nhận `{sprint}`, `{login}`, `{date}`). Kiểm tra cấu hình MUST từ chối `max_parallel` không phải số nguyên dương và `branch_pattern` rỗng.

#### Scenario: Mặc định
- **WHEN** cấu hình không có khối `run`
- **THEN** `scrum config` in `run.max_parallel` là 3 và `run.branch_pattern` là `run/{sprint}-{login}`

#### Scenario: Song song sai
- **WHEN** cấu hình đặt `run.max_parallel: 0`
- **THEN** kiểm tra cấu hình báo lỗi nêu `run.max_parallel`

### Requirement: Nhãn ai-ready
Hệ thống SHALL đọc tên nhãn đánh dấu task sẵn sàng cho agent từ `labels.ai_ready`, mặc định `ai-ready`. Lệnh khởi tạo SHALL tạo và giữ label này giống các label khác do plugin quản lý. Tên này MUST khác các nhãn feature, epic, meta và bỏ qua kiểm tra PR.

#### Scenario: Mặc định
- **WHEN** cấu hình không có `labels.ai_ready` và người dùng chạy khởi tạo
- **THEN** repo có label `ai-ready`
