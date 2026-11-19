# Proposal

Thứ tự trong lộ trình: **4 trên 6**. Độc lập với change 2 và 3; nên xong trước change 5 vì cả hai cùng sửa phần báo cáo.

## Why

Bảng tiến độ và digest hiện chỉ đếm: bao nhiêu task ở mỗi trạng thái, còn bao nhiêu điểm. Chúng không chỉ ra thứ Scrum Master cần nhìn mỗi sáng: task đang bị chặn, task In progress nhiều ngày không động, task chưa giao, sprint đang chậm. Đường burndown cũng sai theo hai cách đã ghi ở mục "Giới hạn": nó dùng điểm hiện tại và coi mọi task có mặt từ ngày đầu, và đường lý tưởng giảm đều qua cả thứ bảy, chủ nhật. Digest chỉ là comment trên một issue nên ít người thấy, và cùng với báo cáo HTML nó viết cứng tiếng Anh trong khi team dùng tiếng Việt.

## What Changes

- `scrum status`, digest và báo cáo HTML có thêm mục "Cần chú ý", liệt kê:
  - task bị chặn bởi task chưa xong;
  - task In progress không có hoạt động (commit trên PR liên kết, comment, đổi label) trong `attention.stale_days` ngày làm việc;
  - task trong sprint chưa có người nhận hoặc chưa có điểm;
  - sprint chậm hơn đường lý tưởng quá `attention.behind_percent`.
  Mục này không hiện khi không có gì.
- Burndown tính lại từ lịch sử của issue (thời điểm vào sprint, rời sprint, đổi label điểm): điểm còn lại mỗi ngày dùng phạm vi và điểm đúng của ngày đó. Báo cáo HTML vẽ thêm đường phạm vi và ghi số điểm thêm vào, bỏ ra sau ngày đầu.
- Khoá cấu hình mới `sprint.working_days` (mặc định thứ 2 đến thứ 6): đường lý tưởng đi ngang trong ngày nghỉ, và "số ngày còn lại" đếm ngày làm việc. `sprint.length_days` vẫn là ngày lịch.
- Khoá cấu hình mới `language` (`en` mặc định, `vi`): dịch chữ cố định trong digest, bảng `status` và báo cáo HTML. Tên trạng thái vẫn lấy từ `statuses`.
- Digest gửi thêm tới webhook khi repo có secret `SCRUM_DIGEST_WEBHOOK`; `digest.webhook_format` chọn `slack` (mặc định, cũng hợp với Google Chat và Mattermost) hoặc `telegram`. Webhook lỗi thì workflow cảnh báo nhưng comment trên issue vẫn được đăng.
- `sprint-close` đăng bản tổng kết sprint (mục tiêu, velocity so với ba sprint trước, task xong, task chuyển tiếp, phạm vi thay đổi) thành một comment trên issue digest của sprint đó.
- Phiên bản plugin lên 0.7.0.

Ngoài phạm vi: retro có cấu trúc, lịch nghỉ lễ, biểu đồ ngoài burndown và velocity, publish báo cáo HTML lên GitHub Pages, và thông báo theo từng người.

## Capabilities

### New Capabilities

Không có.

### Modified Capabilities

- `sprint-reporting`: "Đường burndown" đổi sang tính theo lịch sử và ngày làm việc; "Tóm tắt tiến độ sprint", "Báo cáo HTML", "Digest hằng ngày" thêm mục cần chú ý, ngôn ngữ và webhook.
- `scrum-config`: thêm `sprint.working_days`, `attention.*`, `language`, `digest.webhook_format` và quy tắc kiểm tra của chúng.
- `sprint-lifecycle`: "Đóng sprint" thêm bản tổng kết.
- `repo-bootstrap`: workflow digest nhận thêm secret webhook.
- `pr-task-linking`: "Quyền tối thiểu cho workflow" cho phép workflow digest đọc secret tuỳ chọn `SCRUM_DIGEST_WEBHOOK`.

## Impact

- Mã: `runtime/lib/jq/scrum.jq` (burndown, progress), `digest.jq`, `progress-table.jq`, `report-data.jq`, `share/report.html`, `cmd_digest.sh`, `cmd_report.sh`, `cmd_sprint.sh`, `share/defaults.json`, `validate-config.jq`, `templates/scrum.yml`, `templates/github/workflows/scrum-daily-digest.yml`; file mới cho chuỗi dịch.
- API GitHub: burndown theo lịch sử cần timeline của từng issue trong sprint (một lời gọi mỗi issue, có phân trang). Sprint 50 task là khoảng 50 lời gọi mỗi lần chạy `report` hoặc `digest`; design phải chốt cách giới hạn (chỉ lấy timeline cho `report`, hay cả `digest`).
- **Đổi số liệu**: burndown của sprint có thay đổi phạm vi sẽ khác với bản trước. Velocity không đổi cách tính.
- Repo đích đã cài: workflow digest cũ không có secret webhook; với change 2 thì `init` tự cập nhật file chưa bị sửa, nếu không thì cần `--force-file`.
- Secret webhook được đọc trong GitHub Actions; ở máy cá nhân `scrum digest` chỉ gửi webhook khi biến môi trường được đặt.
- Test: fixture timeline, test cho ngày làm việc, cho từng loại "cần chú ý", cho cả hai ngôn ngữ, và cho webhook với `curl` giả.
- Xoá hai dòng tương ứng khỏi mục "Giới hạn hiện tại" của hướng dẫn.
