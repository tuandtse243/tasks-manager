# Proposal

## Why

Tài liệu "Quản lý dự án theo Scrum đơn giản với GitHub" mô tả 6 bước làm hoàn toàn thủ công: tạo milestone, tạo label, tạo issue, ghi `Solve #n` vào PR, tự đổi label trạng thái, lọc issue để xem tiến độ. Các bước này dễ quên và dễ lệch (dev quên đổi label; `Solve #n` không phải closing keyword nên issue không tự đóng), và không có số liệu velocity hay burndown. Gói các bước thành một plugin tự động giúp team dùng GitHub làm công cụ Scrum mà không phải nhớ quy trình.

## What Changes

- Thêm Claude Code plugin `scrum-github` trong repo này (thư mục `plugins/scrum-github/`), cài được vào bất kỳ repo GitHub nào.
- Thêm file cấu hình `scrum.yml` trong repo đích: thang điểm (mặc định 0/1/3/7), tên trạng thái, độ dài sprint, nhãn đặc biệt. Mọi lệnh và workflow đọc chung file này.
- Mô hình dữ liệu "hiện đại hoá nhẹ": milestone = sprint; label cho trạng thái (`status: New`, `status: In progress`, `status: Done`) và điểm (`points: N`); Assignees native thay cho label tên người; label `bug` có sẵn của GitHub; closing keyword `Closes #n` thay cho `Solve #n`.
- Lệnh cho người dùng qua Claude Code: khởi tạo repo (`/scrum-init`), tạo sprint (`/sprint-new`), AI tách feature thành task (`/sprint-plan`, có bước duyệt), tạo task (`/task-new`), bắt đầu task (`/task-start`), xem tiến độ (`/sprint-status`), báo cáo burndown HTML (`/sprint-report`), đóng sprint (`/sprint-close`, chuyển task dở và ghi velocity).
- GitHub Actions cài vào repo đích: đồng bộ trạng thái theo sự kiện PR/issue, kiểm tra PR có liên kết task, digest tiến độ hằng ngày.
- Issue Form cho task (dropdown điểm) và PR template có sẵn `Closes #`.
- Nội dung hiển thị trên GitHub (label, form, báo cáo, digest) bằng tiếng Anh.

## Capabilities

### New Capabilities

- `scrum-config`: định dạng, giá trị mặc định và kiểm tra hợp lệ của file `scrum.yml` trong repo đích.
- `repo-bootstrap`: khởi tạo repo đích một cách idempotent: đồng bộ bộ label, cài Issue Form, PR template và các workflow.
- `sprint-lifecycle`: tạo sprint, đóng sprint, chuyển task chưa xong sang sprint kế tiếp, ghi velocity.
- `task-management`: tạo task, AI đề xuất tách feature thành task kèm điểm (phải duyệt trước khi tạo), bắt đầu task (tạo branch, chuyển trạng thái).
- `pr-task-linking`: phát hiện liên kết PR với task, kiểm tra PR thiếu liên kết, tự đổi trạng thái task theo vòng đời PR và issue.
- `sprint-reporting`: tóm tắt tiến độ sprint theo người/trạng thái/điểm, báo cáo HTML burndown và velocity, digest hằng ngày.

### Modified Capabilities

(không có, repo chưa có spec nào)

## Impact

- **Mã mới**: `plugins/scrum-github/` (manifest plugin, skills, scripts Bash, templates `.github/`, tests) và `.claude-plugin/marketplace.json` ở gốc repo để cài plugin cục bộ. Không đụng tới `.claude/` hiện có (OpenSpec).
- **Phụ thuộc runtime**: `gh` CLI (đã đăng nhập, scope `repo` và `workflow`), `jq`, `yq` (mikefarah v4), Bash 3.2+ (bash mặc định của macOS). Runner `ubuntu-latest` của GitHub Actions có sẵn cả bốn.
- **Hệ thống ngoài**: ghi label, milestone, issue, branch, file `.github/` lên repo GitHub đích. Kiểm thử end-to-end trên một repo sandbox riêng, không phải repo này (repo này chưa có remote).
- **Ngoài phạm vi**: GitHub Projects v2, MCP server, đồng bộ hai chiều với công cụ khác.
