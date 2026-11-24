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

### Requirement: Release configuration
The `release` block SHALL have `tag_prefix` (default `v`, may be empty), `breaking_label` (default `breaking`) and `first_version` (default `0.1.0`). The configuration check MUST reject a `first_version` that is not semver `X.Y.Z` and an empty `breaking_label`.

#### Scenario: Defaults
- **WHEN** the configuration has no `release` block
- **THEN** `scrum config` prints `release.tag_prefix` as `v`, `release.breaking_label` as `breaking` and `release.first_version` as `0.1.0`

#### Scenario: Invalid first version
- **WHEN** the configuration sets `release.first_version: "1.0"`
- **THEN** the configuration check reports an error naming `release.first_version`

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

### Requirement: Branching block
The configuration SHALL accept a `branching` block: `preset` (`trunk`, `standard`, `environments`), `main` (default `main`), `develop` (default `develop`), `staging` (default `staging`), `location_prefix` (default `on: `) and `stale_days` (default 5, a positive integer). Validation SHALL reject two branches of the preset that have the same name.

#### Scenario: Defaults
- **WHEN** the block is `branching: {preset: standard}`
- **THEN** the branches are `main` and `develop`, the location prefix is `on: ` and `stale_days` is 5

#### Scenario: Duplicate branch names
- **WHEN** `branching.develop` and `branching.main` are both `main` with preset `standard`
- **THEN** validation fails and names the two keys

### Requirement: Governance block
The configuration SHALL accept a `governance` block: `approvals` (default 1, an integer from 0 to 6), `required_checks` (a list of check names, default empty) and `codeowners` (a list of GitHub logins or teams, default empty).

#### Scenario: Solo project
- **WHEN** `governance.approvals` is `0`
- **THEN** validation passes

#### Scenario: Invalid approvals
- **WHEN** `governance.approvals` is `-1`
- **THEN** validation fails and names the key

### Requirement: Release files
The `release` block SHALL accept `version_files`, a list of entries with a `path` and an optional `pattern` that contains `{version}`, and `changelog`, a path or null (default). Validation SHALL reject an entry without `path` and a `pattern` without `{version}`.

#### Scenario: JSON manifest
- **WHEN** `release.version_files` is `[{path: package.json}]`
- **THEN** validation passes and the release updates the `version` field of that file

#### Scenario: Pattern without placeholder
- **WHEN** an entry has `pattern: "version 1.0"`
- **THEN** validation fails and says the pattern needs `{version}`

### Requirement: Deploy block
The configuration SHALL accept a `deploy` block with `platform`: `none` (default), `vercel`, `cloudflare` or `docker`.

#### Scenario: Unknown platform
- **WHEN** `deploy.platform` is `heroku`
- **THEN** validation fails and lists the accepted platforms

### Requirement: Attention threshold for promotion
The `attention` block SHALL accept `promote_days` (default 5, a positive integer): the number of working days a task may wait In review on a long-lived branch before it needs attention.

#### Scenario: Default
- **WHEN** `attention.promote_days` is not set
- **THEN** the threshold is 5 working days

### Requirement: Khối team
Khoá `team` SHALL là danh sách thành viên, mặc định rỗng. Mỗi thành viên có `login` (bắt buộc), `areas` (danh sách lĩnh vực, tuỳ chọn) và `capacity` (số điểm mỗi sprint, tuỳ chọn). Kiểm tra cấu hình MUST từ chối: `login` rỗng, có ký tự không hợp lệ với login GitHub, hoặc trùng nhau (không phân biệt hoa thường); `areas` không phải danh sách chuỗi không rỗng; `capacity` không phải số dương.

#### Scenario: Không khai báo
- **WHEN** `scrum.yml` không có khoá `team`
- **THEN** `scrum config` in `team` là danh sách rỗng

#### Scenario: Khai báo đầy đủ
- **WHEN** `team` có `login: tuandt`, `areas: [backend]`, `capacity: 10`
- **THEN** cấu hình hợp lệ và `scrum config` in đúng các giá trị đó

#### Scenario: Login trùng
- **WHEN** `team` có hai thành viên `TuanDT` và `tuandt`
- **THEN** kiểm tra cấu hình báo lỗi nêu `team` và login bị trùng

#### Scenario: Capacity sai
- **WHEN** một thành viên có `capacity: 0`
- **THEN** kiểm tra cấu hình báo lỗi nêu `team` và `capacity`

#### Scenario: Login có @
- **WHEN** một thành viên có `login: "@tuandt"`
- **THEN** login được hiểu là `tuandt`
