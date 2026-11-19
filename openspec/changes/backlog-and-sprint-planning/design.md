# Design

## Context

Động cơ: xem proposal.md, mục Why. Yêu cầu: các spec delta của change này. Trạng thái hiện tại cần biết:

- `scrum.jq` đã có `is_task`, `task_role`, `task_points`, `report_tasks`, `sprint_info` (velocity đọc từ marker `scrum:velocity=` trong mô tả milestone). `plan-render.jq` tính trung bình velocity của ba sprint đóng gần nhất.
- `set_status` thay toàn bộ label bằng một lệnh PUT; `project_touch REPO N` cập nhật board (best effort) và thêm task vào board khi nó thuộc sprint đang mở.
- `cmd_plan.sh` đã đọc quan hệ chặn bằng `repos/{repo}/issues/{n}/dependencies/blocked_by`.
- Task tạo từ plan hoặc `task new` có dòng "Part of #N" trong nội dung khi có feature cha.
- Change 2 đã thêm `scrum next` với `next-step.jq`, và để lại skill chuyển tiếp `scrum-init` "xoá ở 0.6.0".

## Goals / Non-Goals

**Goals:**

- Mọi quyết định (task nào thuộc backlog, sức chứa, cảnh báo khi thêm, label sau khi ước lượng) là jq thuần, test offline.
- Lệnh ghi dùng chung một bước kiểm tra "là task đang mở" và chạy kiểm tra cho cả danh sách trước khi ghi task đầu tiên.

**Non-Goals:**

- Không xếp hạng backlog, không sức chứa theo người (proposal, Ngoài phạm vi).
- Không đọc quan hệ cha bằng API sub-issue: dòng "Part of #N" đủ cho task do plugin tạo; task tạo tay không có cha thì để trống.

## Decisions

### 1. Tên: `sprint fill` / `/scrum-github:sprint-fill`

Proposal để design chọn giữa `sprint-plan` và tên khác. `sprint-plan` là tên của skill `plan` trước 0.3.0, nên người dùng cũ gõ nó sẽ được một việc khác hẳn. Chọn `sprint-fill` cho skill và `scrum sprint fill` cho CLI (cùng một tên, thay cho `sprint plan` trong proposal) để hai nơi không lệch nhau.

### 2. Một skill `task` cho các lệnh task mới

Năm lệnh (`list`, `move`, `estimate`, `assign`, `drop`) đi qua một skill `/scrum-github:task` nhận yêu cầu bằng lời, thay cho năm skill. Danh sách lệnh trong Claude Code đã có 15 skill; thêm năm skill nhỏ làm việc chọn lệnh khó hơn. `task-new`, `task-start`, `task-pr` giữ nguyên vì có quy trình riêng.

### 3. Dữ liệu backlog

- Một lời gọi phân trang: `repos/{repo}/issues?milestone=none&state=open&per_page=100`, lọc bằng `is_task` (bỏ PR, epic, feature, meta).
- Quan hệ chặn: `issues/{n}/dependencies/blocked_by` cho tối đa 50 task đầu (theo số tăng dần); task sau đó có `blocked_by: null` nghĩa là chưa kiểm tra. Chỉ giữ task chặn còn mở. Lỗi khi đọc của một task (repo không bật dependencies) cũng thành `null`.
- Cha: số trong dòng "Part of #N" của nội dung.
- `backlog.jq` nhận issues và bản đồ chặn, trả `{tasks, total, points, unestimated}`; `scrum backlog` và `scrum sprint fill` dùng chung.

### 4. Sức chứa và kế hoạch thêm

`sprint-fill.jq` nhận milestones, sprint, issues của sprint, backlog (đã có quan hệ chặn), danh sách `--add` và `--capacity`:

- velocity: trung bình (làm tròn xuống) của tối đa ba sprint đóng gần nhất có velocity, như `plan-render.jq`; tách thành hàm `recent_velocity` trong `scrum.jq` để hai chương trình dùng chung;
- đã có: tổng điểm task chưa bị bỏ trong sprint (`report_tasks`);
- với `--add`: số không nằm trong backlog (không tồn tại, đã đóng, đã có milestone, không phải task) là lỗi; cảnh báo vượt sức chứa, chưa có điểm, bị chặn bởi task chưa xong không nằm trong sprint và không nằm trong danh sách thêm.

Shell chỉ ghi khi `--yes` và không có lỗi: PATCH `milestone`, POST comment, rồi `project_touch`.

### 5. Lệnh task ghi

- Kiểm tra chung `task_issue REPO N`: đọc issue, dừng khi là PR, đã đóng, hoặc không phải task. `move` và `assign` kiểm tra toàn bộ danh sách trước khi ghi.
- `move`: PATCH `milestone` (số hoặc `null`) rồi comment "Moved from X to Y". Sprint đích phải đang mở.
- `estimate`: `points-labels.jq` tính bộ label mới (bỏ mọi label có tiền tố điểm, thêm label mới) rồi PUT một lần, cùng cách `set_status` giữ đúng một label trạng thái.
- `assign`: POST hoặc DELETE `issues/{n}/assignees`.
- `drop`: PATCH `state: closed, state_reason: not_planned`, comment lý do nếu có.
- Sau mỗi lần ghi: `project_touch`.

### 6. `next` và `sprint new`

- `next-step.jq` nhận thêm `--argjson backlog_count N`; bước "fill" nằm sau "sprint-close" và trước "continue": sprint còn hạn, `report_tasks` của sprint rỗng, backlog > 0. Shell chỉ đếm backlog khi sprint rỗng (một lời gọi).
- `sprint new` đếm backlog sau khi tạo sprint và in gợi ý `/scrum-github:sprint-fill` khi > 0. Lỗi khi đếm chỉ làm mất gợi ý, không làm lệnh thất bại.

### 7. Xoá skill chuyển tiếp `scrum-init`

Đúng hẹn ở change 2: 0.6.0 xoá `skills/scrum-init/`; test "chỉ skill chuyển tiếp có tên cũ" đổi thành "không còn tên cũ ngoài CHANGELOG".

## Risks / Trade-offs

- [Backlog vài trăm task] → tối đa 50 lời gọi đọc quan hệ chặn, phần còn lại hiện "chưa kiểm tra"; một lời gọi phân trang cho danh sách.
- [Task tạo tay không có "Part of #N"] → cột cha để trống; đúng với dữ liệu hiện có, không đoán.
- [Đổi milestone trên web cùng lúc với `sprint fill`] → lệnh ghi đè milestone theo yêu cầu cuối; comment để lại dấu vết.
- [Người dùng 0.5 vẫn gõ `/scrum-github:scrum-init`] → skill không còn; CHANGELOG và README ghi rõ từ 0.5.0.

## Migration Plan

Không đổi dữ liệu. Nâng lên 0.6.0 là đủ; không cần chạy lại `init` (không đổi template).
