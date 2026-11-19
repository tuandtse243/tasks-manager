# Design

## Context

Động cơ: xem proposal.md, mục Why. Yêu cầu: các spec delta. Mọi chỗ đang giả định đúng ba trạng thái (tìm bằng `grep` trên `runtime/`):

| Chỗ | Giả định |
|---|---|
| `scrum.jq`: `status_labels`, `task_role`, `roles`, `project_meta` (options thiếu), `plan_item` | danh sách cố định new/in_progress/done |
| `progress` (scrum.jq), `progress-table.jq`, `report.html` | ba nhóm và ba cột |
| `digest.jq` | mục "In progress" và "Not started" |
| `attention.jq` | "không động" chỉ xét In progress |
| `label-plan.jq` | ba label trạng thái kèm màu, mô tả |
| `validate-config.jq` | ba tên trạng thái, ba option board |
| `event-decide.jq`, `cmd_event.sh` | PR mở chỉ chuyển New → In progress; PR đóng không merge bị bỏ qua |
| `cmd_task.sh` (`task list --status`) | ba giá trị |
| `templates/github/workflows/scrum-status-sync.yml` | không nhận `converted_to_draft` |
| `report-data.jq` | `statuses` có ba khoá |

## Goals / Non-Goals

**Goals:**

- Chế độ tắt không đổi gì: mọi test hiện có chạy không sửa, và output JSON không có khoá mới (`in_review` chỉ xuất hiện khi bật).
- Một hàm duy nhất trả danh sách trạng thái đang dùng, mọi chỗ khác đọc từ đó.

**Non-Goals:** trạng thái tuỳ ý, "Blocked", kết quả review (proposal, Ngoài phạm vi).

## Decisions

### 1. `roles($cfg)` là nguồn duy nhất

`roles($cfg)`: `["new", "in_progress"] + (if in_review then ["in_review"] else [] end) + ["done"]`. `review_on($cfg)`: `statuses.in_review` là chuỗi không rỗng. `status_labels`, `label-plan`, `validate-config`, board (`roles` của Project, options thiếu, cột hợp lệ) và `task list --status` đọc từ đó. `task_role` xét label In review (khi bật) sau Done và trước In progress.

`progress` chỉ thêm nhóm `in_review` khi bật; bảng, báo cáo HTML và digest dựng cột và mục từ `roles($cfg)`, nên chế độ tắt cho đúng output cũ.

### 2. Sự kiện PR

`cmd_event.sh` truyền thêm `--argjson draft` (từ `pull_request.draft`) và các kind mới:

| Hành động | Kind |
|---|---|
| opened, reopened, edited, ready_for_review | `pr_open` (kèm `draft`) |
| converted_to_draft | `pr_draft` |
| closed, không merge | `pr_closed` |
| closed, merge | `pr_merged` |

`event-decide.jq`: khi tắt, `pr_open` như cũ (bất kể `draft`), `pr_draft` và `pr_closed` không đổi gì. Khi bật: `pr_open` nháp hoặc `pr_draft` → In progress từ New/In review; `pr_open` không nháp → In review từ New/In progress; `pr_closed` → In progress chỉ từ In review; `pr_merged` → Done như cũ.

Workflow status-sync thêm `converted_to_draft` vào `types`. Repo chưa cập nhật workflow (sửa tay) chỉ thiếu bước lùi về In progress khi PR về nháp; `init` cập nhật tự động file chưa sửa (change 2).

### 3. Board

`project.status_options.in_review` mặc định `In Review` trong `defaults.json`. Khi bật, `roles($cfg)` có `in_review` nên `project_meta` báo thiếu option và `project init` dừng như với các option khác; `plan_item` coi cột In Review là hợp lệ. Khi tắt, cột đó là cột lạ và bị bỏ qua kèm cảnh báo như hiện nay.

### 4. Cần chú ý

`attention.jq` thêm loại `review`: task In review không có hoạt động trong `attention.review_days` ngày làm việc (cùng cách đo hoạt động như "không động"). Loại `stale` vẫn chỉ xét In progress.

### 5. Label

`label-plan.jq` thêm label In review (màu `1d76db`, mô tả "Task waiting for review") khi bật; khi tắt, label `status: In review` có sẵn rơi vào `obsolete` theo quy tắc tiền tố hiện có.

## Risks / Trade-offs

- [Một chỗ giả định ba trạng thái bị sót] → test chạy cả hai chế độ; bảng ở Context liệt kê từng chỗ và mỗi chỗ có test bật.
- [Team bật In review giữa sprint] → task hiện có chỉ sang In review ở sự kiện PR kế tiếp (proposal); ghi trong tài liệu.
- [PR nháp chuyển sang sẵn sàng review khi workflow cũ chưa nhận `ready_for_review`] → workflow hiện đã nhận `ready_for_review`; chỉ `converted_to_draft` là mới.

## Migration Plan

Nâng lên 0.8.0, chạy `/scrum-github:init` (cập nhật workflow status-sync), commit và push. Muốn bật: đặt `statuses.in_review: In review`, chạy lại `init` để tạo label, và nếu dùng board thì thêm cột `In Review` rồi `scrum project init`.
