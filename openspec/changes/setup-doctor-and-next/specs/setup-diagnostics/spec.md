## Purpose

Kiểm tra một lượt môi trường, cấu hình và phần đã cài của Scrum trong một repo, báo từng mục là đạt, cảnh báo hay lỗi kèm lệnh sửa, để người dùng thấy mọi vấn đề cài đặt cùng lúc thay vì gặp từng cái khi một lệnh khác thất bại.

## ADDED Requirements

### Requirement: Báo cáo từng mục kiểm tra
Lệnh `scrum doctor` (và skill `/scrum-github:doctor`) SHALL chạy mọi mục kiểm tra rồi in từng mục theo nhóm (công cụ, repo, cài đặt, board) với một trong bốn kết quả: đạt, cảnh báo, lỗi, bỏ qua. Mỗi mục cảnh báo hoặc lỗi MUST kèm một lệnh hoặc bước để sửa. Một mục lỗi MUST NOT làm dừng các mục sau, trừ các mục cần đúng thứ đã lỗi, khi đó các mục ấy là bỏ qua và nêu lý do.

#### Scenario: Mọi thứ đã sẵn sàng
- **WHEN** công cụ đủ, `gh` đã đăng nhập đủ scope, cấu hình hợp lệ, label đủ và workflow đã có trên nhánh mặc định
- **THEN** mọi mục là đạt và lệnh kết thúc với mã 0

#### Scenario: Nhiều lỗi cùng lúc
- **WHEN** máy thiếu `yq` và repo chưa có `.github/scrum.yml`
- **THEN** lệnh in cả hai lỗi, mỗi lỗi kèm cách sửa, rồi mới kết thúc

#### Scenario: gh chưa đăng nhập
- **WHEN** `gh` chưa đăng nhập
- **THEN** mục đăng nhập là lỗi kèm `gh auth login`, và các mục cần GitHub (label, workflow trên remote, secret) là bỏ qua với lý do `gh` chưa đăng nhập

### Requirement: Chỉ đọc và mã thoát
Lệnh `scrum doctor` MUST NOT ghi gì vào repo, vào ổ đĩa ngoài thư mục tạm, hay lên GitHub. Lệnh SHALL kết thúc với mã khác 0 khi có ít nhất một mục lỗi, và mã 0 khi chỉ có đạt, cảnh báo hoặc bỏ qua.

#### Scenario: Chỉ có cảnh báo
- **WHEN** mục duy nhất không đạt là một cảnh báo
- **THEN** lệnh kết thúc với mã 0

#### Scenario: Không ghi lên GitHub
- **WHEN** lệnh chạy xong trên một repo có lỗi cài đặt
- **THEN** không có lệnh ghi nào (POST, PATCH, PUT, DELETE) được gửi lên GitHub và working tree không đổi

### Requirement: Kết quả dạng JSON
Với `--json`, lệnh SHALL in một đối tượng JSON gồm danh sách mục kiểm tra (nhóm, mã mục, kết quả, thông báo, cách sửa) và số lỗi, số cảnh báo, thay cho bản in cho người đọc. Mã thoát giống bản không có `--json`.

#### Scenario: JSON cho một lỗi
- **WHEN** người dùng chạy `scrum doctor --json` trên máy thiếu `yq`
- **THEN** đầu ra là JSON hợp lệ có một mục với kết quả lỗi cho `yq`, kèm cách sửa, và trường số lỗi lớn hơn 0

### Requirement: Kiểm tra công cụ
Lệnh SHALL kiểm tra: `jq` có trong PATH; `yq` có và là bản mikefarah v4; `gh` có, đã đăng nhập, và token có scope `repo` và `workflow`, thêm `project` khi board đang bật. Thiếu `jq`, `yq`, `gh`, chưa đăng nhập hoặc thiếu scope `repo` là lỗi; thiếu `workflow` hoặc `project` là cảnh báo.

#### Scenario: yq sai bản
- **WHEN** `yq` trong PATH là bản Python
- **THEN** mục `yq` là lỗi, nêu bản tìm thấy và cách cài bản mikefarah

#### Scenario: Thiếu scope workflow
- **WHEN** token của `gh` có `repo` nhưng không có `workflow`
- **THEN** mục scope là cảnh báo kèm `gh auth refresh -s workflow`

#### Scenario: Board bật, thiếu scope project
- **WHEN** `project.enabled: true` và token không có scope `project`
- **THEN** mục scope là cảnh báo kèm `gh auth refresh -s project`

### Requirement: Nhận ra sandbox của Claude Code
Khi `gh` báo token không hợp lệ hoặc không gọi được GitHub trong lúc lệnh chạy bên trong sandbox của Claude Code, mục đăng nhập SHALL nói rằng sandbox chặn keychain và mạng của `gh`, và cách sửa là chạy lại lệnh ngoài sandbox, thay cho lời khuyên đăng nhập lại.

#### Scenario: Token sai trong sandbox
- **WHEN** lệnh chạy trong sandbox của Claude Code và `gh auth status` báo token không hợp lệ
- **THEN** mục đăng nhập nêu sandbox và cách chạy ngoài sandbox, không khuyên `gh auth login`

#### Scenario: Token sai ngoài sandbox
- **WHEN** lệnh chạy ngoài sandbox và `gh auth status` báo token không hợp lệ
- **THEN** mục đăng nhập là lỗi kèm `gh auth login`

### Requirement: Kiểm tra repo và cấu hình
Lệnh SHALL kiểm tra: thư mục hiện tại thuộc một repo có remote GitHub; `.github/scrum.yml` tồn tại và hợp lệ; mọi label theo cấu hình có trên GitHub với đúng màu và mô tả. Không có remote, thiếu hoặc sai cấu hình là lỗi; label thiếu hoặc lệch là cảnh báo kèm lệnh khởi tạo.

#### Scenario: Cấu hình sai
- **WHEN** `.github/scrum.yml` có `points.scale` không phải danh sách số
- **THEN** mục cấu hình là lỗi và nêu đúng lỗi kiểm tra hợp lệ

#### Scenario: Thiếu label
- **WHEN** repo không có label `type: epic`
- **THEN** mục label là cảnh báo nêu `type: epic` và cách sửa là chạy lại lệnh khởi tạo

### Requirement: Kiểm tra phần đã cài
Lệnh SHALL kiểm tra: các workflow `scrum-*` mà cấu hình cần có trên nhánh mặc định của remote; phiên bản runtime trong `.github/scrum/` so với phiên bản plugin; file sinh ra trong `.github/` so với bản lệnh khởi tạo sẽ sinh từ cấu hình hiện tại.

#### Scenario: Workflow chỉ có ở máy
- **WHEN** `.github/workflows/scrum-status-sync.yml` có trong working tree nhưng không có trên nhánh mặc định của remote
- **THEN** mục workflow là lỗi, nói file chưa được push, và cách sửa là commit rồi push `.github/`

#### Scenario: Runtime cũ hơn plugin
- **WHEN** `.github/scrum/VERSION` là 0.4.0 và plugin là 0.5.0
- **THEN** mục runtime là cảnh báo kèm lệnh khởi tạo

#### Scenario: File cũ so với cấu hình
- **WHEN** người dùng đổi `digest.cron` mà chưa chạy lại lệnh khởi tạo
- **THEN** mục file sinh ra là cảnh báo nêu `.github/workflows/scrum-daily-digest.yml` và cách sửa là chạy lại lệnh khởi tạo

### Requirement: Kiểm tra board
Khi `project.enabled: true`, lệnh SHALL kiểm tra secret `SCRUM_PROJECT_TOKEN` có trong repo và workflow đồng bộ board có trên nhánh mặc định. Thiếu secret là lỗi. Khi token không đủ quyền đọc danh sách secret, mục đó là cảnh báo nói không kiểm tra được. Khi board tắt, các mục board là bỏ qua.

#### Scenario: Thiếu secret
- **WHEN** board bật và repo không có secret `SCRUM_PROJECT_TOKEN`
- **THEN** mục secret là lỗi kèm `/scrum-github:project-setup`

#### Scenario: Không đọc được secret
- **WHEN** board bật và GitHub từ chối đọc danh sách secret
- **THEN** mục secret là cảnh báo nói không kiểm tra được và cần quyền admin của repo

#### Scenario: Board tắt
- **WHEN** `project.enabled` là `false`
- **THEN** các mục board là bỏ qua và không có lời gọi nào tới secret của repo
