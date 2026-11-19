# scrum-config Specification

## Purpose

Định nghĩa file cấu hình `scrum.yml` của một repo đích: nơi duy nhất khai báo thang điểm, tên trạng thái, nhịp sprint và các nhãn đặc biệt mà mọi lệnh và workflow của plugin cùng đọc.

## Requirements

### Requirement: Vị trí file cấu hình
Hệ thống SHALL đọc cấu hình từ `.github/scrum.yml` trong repo đích. Mọi lệnh trừ lệnh khởi tạo MUST dừng với thông báo hướng dẫn chạy khởi tạo khi file không tồn tại.

#### Scenario: Thiếu file cấu hình
- **WHEN** người dùng chạy lệnh tạo sprint trong repo chưa có `.github/scrum.yml`
- **THEN** lệnh kết thúc với mã lỗi khác 0, thông báo chạy `/scrum-init` trước, và không ghi gì lên GitHub

#### Scenario: Có file cấu hình
- **WHEN** repo có `.github/scrum.yml` hợp lệ và người dùng chạy một lệnh bất kỳ
- **THEN** lệnh dùng các giá trị trong file đó

### Requirement: Giá trị mặc định
Hệ thống SHALL áp giá trị mặc định cho mọi khoá không khai báo: thang điểm `0, 1, 3, 7`; trạng thái `New`, `In progress`, `Done`; độ dài sprint 5 ngày; tên sprint `Sprint {n}`; múi giờ `UTC`; mẫu branch `feat/{number}-{slug}`; digest bật.

#### Scenario: File chỉ khai báo một phần
- **WHEN** `scrum.yml` chỉ khai báo `points.scale: [1, 2, 3, 5, 8]`
- **THEN** thang điểm là 1, 2, 3, 5, 8 và mọi khoá khác nhận giá trị mặc định

#### Scenario: File rỗng
- **WHEN** `scrum.yml` tồn tại nhưng rỗng
- **THEN** hệ thống dùng toàn bộ giá trị mặc định

### Requirement: Kiểm tra hợp lệ trước khi ghi
Hệ thống MUST kiểm tra cấu hình trước mọi thao tác ghi lên GitHub và từ chối cấu hình sai, với thông báo nêu tên khoá và lý do. Cấu hình sai gồm: điểm không phải số nguyên không âm hoặc trùng nhau, độ dài sprint không dương, tên trạng thái rỗng hoặc trùng nhau, YAML không đọc được.

#### Scenario: Thang điểm có giá trị âm
- **WHEN** `points.scale` chứa `-1`
- **THEN** lệnh dừng với mã lỗi khác 0, thông báo nêu `points.scale`, và không ghi gì lên GitHub

#### Scenario: YAML hỏng
- **WHEN** `scrum.yml` có lỗi cú pháp YAML
- **THEN** lệnh dừng và báo file không đọc được kèm vị trí lỗi do bộ đọc YAML trả về

### Requirement: Kiểm tra công cụ và đăng nhập
Hệ thống MUST kiểm tra `gh`, `jq`, `yq` có trong PATH và `gh` đã đăng nhập trước khi chạy một lệnh, và dừng với thông báo nêu đúng công cụ thiếu cùng cách cài. Khi `gh` báo chưa đăng nhập trong lúc lệnh chạy bên trong sandbox của Claude Code, thông báo SHALL nói rằng sandbox có thể là nguyên nhân và dẫn tới `/scrum-github:doctor`.

#### Scenario: Thiếu yq
- **WHEN** người dùng chạy một lệnh trên máy không có `yq`
- **THEN** lệnh dừng trước mọi thao tác GitHub và thông báo cần cài `yq` (mikefarah v4)

#### Scenario: gh chưa đăng nhập
- **WHEN** `gh auth status` báo token không hợp lệ
- **THEN** lệnh dừng và hướng dẫn chạy `gh auth login`

#### Scenario: gh báo lỗi trong sandbox
- **WHEN** lệnh chạy bên trong sandbox của Claude Code và `gh auth status` báo token không hợp lệ
- **THEN** lệnh dừng, nói sandbox có thể chặn `gh` đọc token, gợi ý chạy ngoài sandbox, và dẫn tới `/scrum-github:doctor`

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
