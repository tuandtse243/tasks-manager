# Design

## Context

Động cơ: xem proposal.md, mục Why. Yêu cầu: các spec delta. Trạng thái hiện tại cần biết:

- `scrum.jq` có `progress` (bảng), `burndown` (điểm hiện tại, mọi task tính từ ngày đầu), `days_left` (ngày lịch). `progress-table.jq`, `digest.jq` và `share/report.html` viết cứng tiếng Anh.
- `cmd_backlog.sh` (change 3) đã đọc quan hệ "blocked by" cho tối đa 50 task; `links.jq` tách các tham chiếu đóng (`Closes #n`) trong một nội dung.
- Change 2: `init` tự cập nhật workflow chưa bị sửa, nên thêm secret vào template digest là đủ cho đa số repo.

## Goals / Non-Goals

**Goals:**

- Mọi phép tính (ngày làm việc, cần chú ý, dựng lại lịch sử) là jq thuần, test bằng fixture.
- `status` và digest không tốn thêm nhiều lời gọi: lịch sử issue chỉ đọc ở `report` và `sprint close`.

**Non-Goals:**

- Ngày lễ, sức chứa theo người, retro (proposal, Ngoài phạm vi).
- Dịch tên trạng thái hay label: lấy từ cấu hình.

## Decisions

### 1. Ngày làm việc

`working_days($cfg)` trả danh sách thứ ISO; `is_working_day` đọc thứ của một ngày bằng `strptime | mktime | strftime("%u")`. `days_left` đếm ngày làm việc từ hôm nay (tính cả hôm nay) tới ngày cuối. Đường lý tưởng: với `W` là số ngày làm việc của sprint và `k(d)` là số ngày làm việc trước ngày `d`, `ideal(d) = scope_đầu × (1 − k(d)/(W − 1))` (W ≤ 1 thì ngày cuối là 0). Sprint thứ 2 tới thứ 6 cho đúng các số như cũ; qua cuối tuần thì `k` không tăng nên đường đi ngang.

### 2. Lịch sử issue: chỉ cho `report` và `sprint close`

- Mỗi task đang thuộc sprint: `repos/{repo}/issues/{n}/events` (phân trang), tối đa 100 task.
- Task đã rời sprint: một lời gọi tìm kiếm `search/issues?q=repo:{repo} is:issue updated:>={start} -milestone:"{title}"`, lấy tối đa 30 ứng viên, đọc events của từng ứng viên và giữ những task có sự kiện `demilestoned` khỏi sprint này.
- Không đọc events cho `status` và digest: chúng dùng số liệu hiện tại (proposal để design chọn; chọn như vậy để digest hằng ngày không tốn 50 lời gọi).
- Vượt giới hạn thì burndown dùng số liệu hiện tại cho phần còn lại và báo cáo ghi một dòng nói vậy.

`history.jq` dựng trạng thái của một issue vào cuối một ngày bằng cách đi ngược các sự kiện sau thời điểm đó từ trạng thái hiện tại: `labeled X` → bỏ X, `unlabeled X` → thêm X, `milestoned` vào sprint → chưa thuộc sprint, `demilestoned` khỏi sprint → còn thuộc sprint, `closed`/`reopened` → đảo trạng thái. Lý do đóng lấy từ sự kiện `closed` nếu có, không thì từ issue. Đi ngược chỉ cần trạng thái hiện tại và các sự kiện, không cần biết trạng thái lúc tạo issue.

Burndown trả thêm `scope` mỗi ngày, `added` và `removed` (điểm của task vào hoặc rời phạm vi sau ngày đầu, tính theo điểm lúc vào hoặc rời).

### 3. Cần chú ý

`attention.jq` nhận task của sprint, bản đồ chặn (dùng lại `fetch_backlog`'s cách đọc, tối đa 50 task chưa xong), danh sách PR đang mở (một lời gọi phân trang `repos/{repo}/pulls?state=open`), hôm nay và burndown hôm nay. Hoạt động của task = max(`updated_at` của issue, `updated_at` của các PR mở có tham chiếu đóng tới nó qua `links.jq`). "Chậm" so sánh điểm còn lại hiện tại với `ideal(hôm nay)` của burndown tính bằng số liệu hiện tại. Kết quả là danh sách `{kind, number?, text_key, args}` để dịch sau.

### 4. Ngôn ngữ

`share/strings.json` có hai khoá `en`, `vi`, mỗi khoá là một bảng chuỗi có chỗ trống `{name}`. Hàm jq `tr($s; $key; $args)` thay chỗ trống. Chương trình jq nhận `--argjson strings` là bảng của ngôn ngữ đã chọn; `report-data.jq` nhúng bảng đó cho `report.html`, JS đọc `d.strings`. Test kiểm tra hai bảng có cùng khoá.

### 5. Webhook

`cmd_digest.sh` sau khi đăng comment: nếu `SCRUM_DIGEST_WEBHOOK` có giá trị thì POST JSON bằng `curl` (`SCRUM_CURL` thay được trong test): `slack` → `{"text": nội dung}`; `telegram` → `{"text": nội dung, "disable_web_page_preview": true}` tới URL người dùng đặt (URL `sendMessage` của bot có `chat_id`). Nội dung bỏ dòng marker HTML. Lỗi `curl` hoặc mã HTTP ≥ 400 → cảnh báo, mã thoát 0. Template workflow digest thêm `SCRUM_DIGEST_WEBHOOK: ${{ secrets.SCRUM_DIGEST_WEBHOOK }}`.

### 6. Tổng kết khi đóng sprint

Sau khi đóng milestone, `cmd_sprint_close` đọc lịch sử (như `report`), tìm hoặc tạo issue digest của sprint (dùng chung hàm với `cmd_digest.sh`), và đăng `sprint-summary.jq`. Mọi lỗi ở bước này là cảnh báo: milestone đã đóng.

## Risks / Trade-offs

- [Burndown đổi số với sprint có thay đổi phạm vi] → đúng ý proposal; CHANGELOG ghi rõ.
- [Repo lớn: tìm task rời sprint trả nhiều ứng viên] → tối đa 30; ghi trong báo cáo khi chạm giới hạn.
- [`updated_at` của issue đổi cả khi có người chỉ sửa tiêu đề] → coi là hoạt động; chấp nhận vì sai về phía không cảnh báo.
- [Telegram cần `chat_id`] → ghi trong tài liệu: đặt URL `https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<ID>` làm secret.

## Migration Plan

Nâng lên 0.7.0 rồi chạy `/scrum-github:init` để cập nhật workflow digest (tự động nếu chưa sửa tay), commit và push. Không cần đổi cấu hình; muốn tiếng Việt thì thêm `language: vi`.
