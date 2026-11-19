# Proposal

## Why

Plugin `scrum-github` lưu trạng thái task bằng label `status: …`. Dev làm việc tốt với cách này vì trạng thái tự đi theo PR, nhưng PO/SM không có giao diện kanban để nhìn và kéo thả task. Tự làm một board có dữ liệu riêng rồi sync ngược về GitHub sẽ tạo hai nguồn sự thật (xem `docs/huong-dan-ap-dung.md`, mục 8). GitHub Projects v2 đã có sẵn board, nên chỉ cần đồng bộ nó với label, không cần thêm hệ thống mới.

## What Changes

- Thêm khối cấu hình `project:` trong `.github/scrum.yml`, **mặc định tắt**. Repo không bật thì hành vi không đổi.
- Label `status: …` vẫn là nguồn sự thật. Field Status (single-select) của Project là bản sao, nhưng **được phép sửa từ board**.
- Đồng bộ ba chiều qua một field text `Synced status` trên Project, ghi lại giá trị lần sync gần nhất, để biết bên nào vừa đổi. Khi cả hai bên cùng đổi thì label thắng.
- Kéo thẻ sang Done trên board: đặt label Done và **đóng issue với lý do completed**. Kéo thẻ ra khỏi Done: đặt label mới và mở lại issue.
- Lệnh mới `scrum project init [--dry-run]`: kiểm tra token, tìm Project, kiểm tra các option Status khớp cấu hình, tạo các field còn thiếu, thêm task của các sprint đang mở vào Project.
- Lệnh mới `scrum project sync`: đối chiếu mọi task trong Project và áp thay đổi theo cả hai chiều.
- Workflow mới `scrum-project-sync.yml`, **chỉ cài khi `project.enabled: true`**:
  - Chạy theo lịch, vì GitHub Actions không có trigger cho sự kiện của Project.
  - Chạy theo `workflow_dispatch`.
  - Chạy khi issue đổi label hoặc milestone.
- Đổi trạng thái qua CLI hoặc qua workflow status-sync sẽ cập nhật board ngay nếu có token. Đây là best-effort: nếu lỗi thì chỉ cảnh báo, lần poll kế tiếp sẽ sửa.
- Task mới (`task new`, `plan apply`) được thêm vào Project khi tính năng đang bật.
- Field `Points` (number) trên Project được sync một chiều từ label `points: N`, để board tự cộng điểm theo cột. Có thể tắt.
- **Thay đổi hành vi hiện có**: khi một task bị mở lại mà đang có label `status: New`, trạng thái giữ là New, không chuyển sang In progress.

## Capabilities

### New Capabilities

- `project-board-sync`: đồng bộ trạng thái và điểm của task giữa label và một GitHub Projects v2. Gồm cấu hình `project:`, lệnh `project init` và `project sync`, quy tắc chọn bên thắng, workflow poll.

### Modified Capabilities

- `pr-task-linking`:
  - Requirement "Trạng thái theo vòng đời issue": mở lại task đang có status New thì giữ New.
  - Requirement "Quyền tối thiểu cho workflow": workflow sync Project (tuỳ chọn) cần secret `SCRUM_PROJECT_TOKEN`; các workflow lõi vẫn chạy không cần secret.

## Impact

- **Mã**: trong `plugins/scrum-github/`:
  - Thêm `runtime/lib/cmd_project.sh` và các file jq mới.
  - Sửa `set_status` và `cmd_task.sh` / `cmd_plan.sh`, để thêm item vào Project.
  - Sửa `event-decide.jq` cho hành vi mở lại.
  - Sửa `defaults.json`, `validate-config.jq`, `cmd_init.sh` (cài workflow có điều kiện).
  - Thêm template workflow mới. Template `scrum-status-sync.yml` thêm biến môi trường token.
- **API**: GitHub GraphQL cho Projects v2:
  - Đọc: `projectV2`, `items`, `fields`.
  - Ghi: `addProjectV2ItemById`, `updateProjectV2ItemFieldValue`, `createProjectV2Field`.
- **Bảo mật**: secret mới `SCRUM_PROJECT_TOKEN` (fine-grained PAT hoặc token GitHub App, quyền Projects read/write và Issues read/write), vì `GITHUB_TOKEN` không truy cập được Project của user/org. Dùng CLI ở máy cá nhân thì cần `gh auth refresh -s project`.
- **Repo đã cài plugin**: muốn có biến token trong status-sync thì phải chạy lại `scrum init --force-file .github/workflows/scrum-status-sync.yml`. Không chạy thì board vẫn đúng, chỉ trễ tới lần poll kế tiếp.
- **Tài liệu**: README plugin và mục 8 của `docs/huong-dan-ap-dung.md`.
- **Ngoài phạm vi**:
  - Đồng bộ realtime từ board (cần GitHub App và webhook có server riêng).
  - Field Iteration (sprint vẫn là milestone).
  - Sync điểm từ board về label.
  - Project dùng chung cho nhiều repo với cấu hình khác nhau.
