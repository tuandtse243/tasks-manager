# Proposal

Thứ tự trong lộ trình: **5 trên 6**. Làm sau change 4, vì cả hai cùng sửa bảng tiến độ, digest và báo cáo. Đây là change chạm nhiều chỗ nhất.

## Why

Plugin chỉ có ba trạng thái: New, In progress, Done. Với nhiều team, phần lớn thời gian chờ của một task nằm ở khâu review, nhưng hiện một task đang code và một task đã mở PR chờ duyệt ba ngày trông giống hệt nhau. Trên board, cột "Review" mà team tự thêm bị đồng bộ bỏ qua kèm cảnh báo. Thêm một trạng thái tuỳ chọn cho khâu này giúp thấy được chỗ tắc mà không bắt team nào không cần phải dùng.

## What Changes

- Khoá cấu hình tuỳ chọn `statuses.in_review` (mặc định không đặt, tức là tắt). Khi đặt, ví dụ `In review`, plugin có bốn trạng thái theo thứ tự New → In progress → In review → Done. Khi không đặt, mọi hành vi giữ nguyên như hiện nay.
- Khi trạng thái này bật:
  - PR nháp có `Closes #n` được mở: task sang In progress;
  - PR sẵn sàng review (mở không nháp, hoặc chuyển từ nháp sang sẵn sàng): task sang In review;
  - PR chuyển về nháp, hoặc đóng mà không merge: task về In progress;
  - PR merge: Done, như hiện nay;
  - issue mở lại: In progress, như hiện nay.
- `scrum init` tạo label cho trạng thái mới; tắt đi thì label thành "obsolete" và không bị xoá, như các label khác.
- Bảng `status`, digest, báo cáo HTML và mục "Cần chú ý" (change 4) có thêm cột hoặc mục In review; task In review quá số ngày cấu hình được nêu là đang chờ review.
- Board: `project.status_options.in_review` ánh xạ tới một cột; kéo thẻ vào cột đó đổi label như các cột khác. Khi trạng thái bật mà board thiếu cột tương ứng, `project init` dừng và nói rõ cột nào cần tạo.
- Điểm của task In review tính là chưa xong trong burndown và velocity.
- Phiên bản plugin lên 0.8.0.

Ngoài phạm vi: trạng thái tuỳ ý do người dùng định nghĩa (chỉ thêm đúng một trạng thái có nghĩa cố định), trạng thái "Blocked" (đã thể hiện qua quan hệ "blocked by" và mục "Cần chú ý"), và trạng thái theo kết quả review (approved, changes requested).

## Capabilities

### New Capabilities

Không có.

### Modified Capabilities

- `scrum-config`: "Giá trị mặc định" và "Kiểm tra hợp lệ trước khi ghi" nhận `statuses.in_review` tuỳ chọn và `project.status_options.in_review`.
- `task-management`: "Trạng thái task là duy nhất" áp dụng cho bốn trạng thái khi bật.
- `pr-task-linking`: "Trạng thái theo vòng đời PR" thêm các chuyển đổi nháp, sẵn sàng review, đóng không merge khi trạng thái bật.
- `project-board-sync`: "Cấu hình Project", "Khởi tạo Project", "Quyết định chiều đồng bộ", "Item bị bỏ qua" tính tới cột thứ tư.
- `sprint-reporting`: "Tóm tắt tiến độ sprint", "Báo cáo HTML", "Digest hằng ngày" thêm trạng thái mới.
- `repo-bootstrap`: "Đồng bộ bộ label idempotent" thêm label trạng thái tuỳ chọn.

## Impact

- Mã: `share/defaults.json`, `validate-config.jq`, `scrum.jq` (vai trò của task, `labels_with_status`), `event-decide.jq`, `status-labels.jq`, `label-plan.jq`, `progress.jq`, `progress-table.jq`, `digest.jq`, `report-data.jq`, `share/report.html`, `project-sync-plan.jq`, `project.sh`, `cmd_event.sh`, `templates/scrum.yml`, `templates/github/workflows/scrum-status-sync.yml` (thêm kiểu sự kiện `converted_to_draft`).
- Workflow trong repo đích đã cài phải được cập nhật để nhận sự kiện mới; trước khi cập nhật, trạng thái mới chỉ không tự lùi về In progress khi PR chuyển về nháp.
- Rủi ro chính: mọi chỗ đang giả định đúng ba trạng thái. Design phải liệt kê từng chỗ, và test phải chạy cả hai chế độ (tắt và bật) để chứng minh chế độ tắt không đổi gì.
- Bật trạng thái giữa sprint không đổi task đang có: chúng chỉ sang In review ở sự kiện PR kế tiếp.
- Test: mở rộng `tests/test_event.sh`, `test_config.sh`, `test_project.sh`, `test_report.sh`, `test_init.sh` với fixture bốn trạng thái.
