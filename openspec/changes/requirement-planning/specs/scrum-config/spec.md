# Spec Delta

## ADDED Requirements

### Requirement: Cấu hình planning
Hệ thống SHALL đọc khối `planning` trong `scrum.yml` với các khoá: `dir` (thư mục chứa plan, mặc định `docs/plans`), `context_file` (tài liệu ngữ cảnh dự án, mặc định `docs/project-context.md`), `hours_per_point` (số giờ cho một điểm, mặc định không đặt), và `context_stale_commits` (mặc định 50). Cấu hình sai MUST bị từ chối: `dir` hoặc `context_file` rỗng, là đường dẫn tuyệt đối hoặc chứa `..`; `hours_per_point` không phải số dương; `context_stale_commits` không phải số nguyên dương.

#### Scenario: Không khai báo
- **WHEN** `scrum.yml` không có khối `planning`
- **THEN** `scrum config` in `planning.dir` là `docs/plans`, `planning.context_file` là `docs/project-context.md`, `planning.hours_per_point` rỗng, và `planning.context_stale_commits` là 50

#### Scenario: Đổi thư mục plan
- **WHEN** `planning.dir` là `planning`
- **THEN** plan mới được ghi dưới `planning/<slug>/`

#### Scenario: Giờ mỗi điểm không hợp lệ
- **WHEN** `planning.hours_per_point` là `0`
- **THEN** lệnh dừng với mã lỗi khác 0 và thông báo nêu `planning.hours_per_point`

#### Scenario: Ngưỡng độ cũ không hợp lệ
- **WHEN** `planning.context_stale_commits` là `-1`
- **THEN** lệnh dừng với mã lỗi khác 0 và thông báo nêu `planning.context_stale_commits`

#### Scenario: Thư mục ra ngoài repo
- **WHEN** `planning.dir` là `../plans`
- **THEN** lệnh dừng với mã lỗi khác 0 và thông báo nêu `planning.dir`

### Requirement: Nhãn epic
Hệ thống SHALL đọc tên nhãn epic từ `labels.epic`, mặc định `type: epic`. Lệnh khởi tạo SHALL tạo và giữ label này giống các label khác do plugin quản lý. Tên nhãn epic MUST khác các nhãn feature, meta và bỏ qua kiểm tra PR.

#### Scenario: Mặc định
- **WHEN** `scrum.yml` không khai báo `labels.epic` và người dùng chạy `/scrum-init`
- **THEN** repo có label `type: epic`

#### Scenario: Repo cài bản cũ
- **WHEN** repo đã chạy `/scrum-init` bằng phiên bản chưa có nhãn epic và chạy lại bằng phiên bản mới
- **THEN** chỉ label `type: epic` được tạo và các label khác được báo không đổi

#### Scenario: Trùng tên
- **WHEN** `labels.epic` và `labels.feature` cùng là `type: feature`
- **THEN** lệnh dừng với mã lỗi khác 0 và thông báo nêu `labels.epic`
