# Proposal

## Why

Plugin `scrum-github` quản lý tốt task đã có, nhưng phần đi từ yêu cầu tới task còn mỏng: `sprint-plan` chỉ nhận một feature đã rõ, cho ra danh sách task phẳng, ghi plan vào file tạm rồi bỏ, và tạo trùng issue nếu chạy lại. Ba tình huống thường gặp chưa có lời giải: chia một requirement thành task có ước lượng và xem được ở local; làm rõ một ý tưởng mơ hồ trước khi chốt scope; và kiểm tra một feature mới có hợp với dự án đang chạy hay không.

## What Changes

Ba tình huống trên là một đường ống với ba cửa vào: hiểu dự án → làm rõ yêu cầu → chia task → đưa lên GitHub. Change này làm cả đường ống, theo ba đợt dùng được độc lập (xem `tasks.md`).

**Đợt 1: plan file và `plan apply`**

- Plan được lưu trong repo đích tại `docs/plans/<slug>/plan.json`, kèm bản xem `plan.md` do lệnh sinh ra.
- Định dạng plan phiên bản 2: epic tuỳ chọn → nhiều feature → task. Task có `id` ổn định, `depends_on`, `subtasks` (thành checklist trong issue), và `issue` (số issue ghi lại sau khi tạo).
- Lệnh mới `scrum plan validate FILE` và `scrum plan render FILE`.
- `scrum plan apply FILE` chạy lại được: chỉ tạo phần chưa có, ghi số issue vào plan ngay sau mỗi lần tạo. Thêm `--dry-run` và `--update`.
- Task không gắn sprint được tạo vào backlog (issue không có milestone).
- `depends_on` thành quan hệ "blocked by" của GitHub; nếu GitHub từ chối thì ghi vào thân issue.
- Ước lượng thời gian: giữ điểm làm gốc, quy ra giờ qua khoá cấu hình mới `planning.hours_per_point`, và ra số sprint từ velocity các sprint đã đóng.
- **BREAKING**: skill `/scrum-github:sprint-plan` đổi tên thành `/scrum-github:plan`. Plan phiên bản 1 (file không có `version`) vẫn áp được như cũ.
- Label mới `type: epic` (khoá cấu hình `labels.epic`), không tính điểm.
- Agent `plan-critic` (chỉ đọc) soát bản chia task trước khi người dùng duyệt.

**Đợt 2: làm rõ yêu cầu**

- Skill mới `/scrum-github:discover`: nhận ý tưởng hoặc yêu cầu, tìm hiểu, phỏng vấn người dùng theo vòng, chốt scope, và ghi `docs/plans/<slug>/brief.md`. Không ghi gì lên GitHub.
- Agent `researcher` (chỉ đọc, có web) tìm thông tin bên ngoài và trả về kèm nguồn.
- `/scrum-github:plan` tự kiểm tra độ rõ của đầu vào; chưa đủ rõ thì đề nghị chạy `discover` trước.

**Đợt 3: hiểu dự án có sẵn**

- Skill mới `/scrum-github:project-scan`: quét repo và ghi `docs/project-context.md`, có dấu commit để biết khi nào đã cũ.
- Agent `codebase-scout` (chỉ đọc) đọc mã thay cho phiên chính.
- `discover` trên repo đã có mã sẽ kiểm tra độ phù hợp của feature với dự án và ước lượng độ phức tạp (một task, một feature, hay một epic).

**Dùng chung**

- Mượn bốn skill của `mattpocock/skills` (giấy phép MIT) mà plugin `aidw` đang dùng: `grilling`, `to-spec`, `domain-modeling`, `to-tickets`. Copy nguyên văn vào `plugins/scrum-github/vendor/pocock/`; hành vi riêng của plugin nằm trong phần adapter của từng skill.
- Việc lặp lại và xác định được thì thành lệnh của CLI `scrum`, để ba skill dùng lại và test offline được: `plan init`, `plan check`, `context inventory`, `context status`, `context stamp`, `doc check`. Phía dev có `scripts/vendor-sync.sh`.
- Một file quy tắc dùng chung cho ba skill: không ghi lên GitHub trước khi duyệt; agent chỉ đọc; sự thật lấy từ mã và web, quyết định thuộc về người dùng; phỏng đoán phải ghi thành giả định.
- Plugin vẫn độc lập với `aidw`. Plan file không chứa gì riêng của GitHub ngoài trường `issue`, để sau này `aidw` xuất sang được.

## Capabilities

### New Capabilities

- `work-plan`: plan file của một requirement trong repo đích. Gồm định dạng, kiểm tra hợp lệ, bản xem, ước lượng, và việc áp plan lên GitHub (chạy lại được, backlog, phụ thuộc, epic).
- `requirement-discovery`: làm rõ một ý tưởng hoặc yêu cầu thành brief đã chốt scope. Gồm nghiên cứu, phỏng vấn, ghi giả định, và kiểm tra độ phù hợp với dự án có sẵn.
- `project-context`: tài liệu mô tả dự án có sẵn trong repo đích, cách tạo, và cách nhận biết khi đã cũ.

### Modified Capabilities

- `task-management`: requirement "AI đề xuất tách feature thành task" đổi: lệnh là `/plan`, bản đề xuất được lưu thành plan file trước khi duyệt, có kiểm tra độ rõ của đầu vào và bước soát độc lập.
- `scrum-config`: thêm khối `planning` (`dir`, `context_file`, `hours_per_point`, `context_stale_commits`) và nhãn `labels.epic`, kèm giá trị mặc định và kiểm tra hợp lệ.

## Impact

- **Mã**: `runtime/lib/cmd_plan.sh`, file mới `runtime/lib/cmd_context.sh` và `runtime/lib/cmd_doc.sh`, các file jq mới cho plan (chuẩn hoá, kiểm tra, kế hoạch áp, bản xem), `runtime/share/plan.schema.json`, `runtime/share/defaults.json`, `runtime/lib/jq/validate-config.jq`, `runtime/lib/jq/label-plan.jq`, `runtime/bin/scrum`, `templates/scrum.yml`. Các chỗ đang loại issue feature khỏi điểm phải loại cả epic.
- **Plugin**: thư mục mới `agents/`, `vendor/pocock/`, `reference/`; skill mới `plan`, `discover`, `project-scan`; xoá `skills/sprint-plan`. Phiên bản lên 0.3.0.
- **Repo đích**: file mới dưới `docs/plans/` và `docs/project-context.md`; label mới `type: epic` sau khi chạy lại `scrum-init`. `.github/scrum/` nhận runtime mới; `vendor/` không được chép sang repo đích.
- **GitHub API**: dùng thêm `POST /repos/{owner}/{repo}/issues/{n}/dependencies/blocked_by`. Không cần quyền mới ngoài `issues: write`.
- **Tài liệu**: `plugins/scrum-github/README.md`, `docs/huong-dan-ap-dung.md`.
- **Phụ thuộc**: không thêm công cụ. `researcher` cần WebSearch/WebFetch của Claude Code; không có thì `discover` bỏ qua bước nghiên cứu web và nói rõ.
