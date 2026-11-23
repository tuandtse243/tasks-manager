# Proposal

Thứ tự trong lộ trình: **2 trên 3**. Cần `team-and-backlog-tasks` (danh sách team, `scrum mine`, `plan.html`). Change 3 (`ai-run`) dùng ước lượng của change này để lập lịch chạy và so với thời gian thật.

## Why

Task của team giờ chủ yếu do AI làm, nên câu hỏi "bao giờ xong" có hai phần khác nhau: AI làm mất bao lâu, và người review, test tay lần cuối mất bao lâu. Points chỉ đo độ phức tạp, `planning.hours_per_point` quy đổi một chiều và không tách hai phần này. Khi AI làm nhanh, nút cổ chai là giờ review của người, nhưng hiện không có chỗ nào ghi hay cộng được con số đó. Points vẫn được giữ: velocity, burndown, label và board không đổi.

## What Changes

- Mỗi task có thể có ước lượng thời gian: `work_minutes` (thời gian làm), `review_minutes` (thời gian người review và test tay), và `by` (`ai` hoặc `human`, ai làm). Ước lượng đứng cạnh points, không thay points.
- Ước lượng được lưu trên GitHub trong một khối của plugin ở thân issue (`<!-- scrum:estimate -->`). Khối có một dòng chữ cho người đọc và dữ liệu cho plugin. Không dùng label cho thời gian.
- `plan.json`: task có trường `estimate`. `plan validate` kiểm tra trường này, `plan apply` ghi khối ước lượng, `plan apply --update` cập nhật khối.
- `plan.md` và `plan.html` hiện thời gian từng task và tổng. `plan.html` có thêm dòng thời gian vẽ đúng tỉ lệ: các đợt chạy song song, khoảng merge và test giữa các đợt, rồi phần review của người. Ước tính thời điểm xong bằng tổng thời gian làm lâu nhất của mỗi đợt cộng thời gian merge, không phải tổng thời gian mọi task.
- `scrum task new` và `scrum task estimate` nhận `--work 25m`, `--review 20m`, `--by ai|human`. `task estimate` không còn bắt buộc phải có điểm khi chỉ đổi thời gian.
- `scrum mine` hiện thời gian từng task và ước tính cho phần việc còn lại của sprint đang mở.
- Bảng tiến độ sprint (`sprint-status`) hiện phút làm và phút review còn lại theo từng người, và số task chưa có ước lượng thời gian.
- Thành viên team có thể khai báo `review_hours` (số giờ review mỗi sprint). `sprint-fill` và `plan check` cảnh báo khi tổng phút review giao cho một người vượt mức này.
- Khoá mới `planning.merge_minutes` (mặc định 5): thời gian merge và chạy test giữa hai đợt, dùng cho ước tính.
- Phiên bản plugin lên 0.10.0.

Ngoài phạm vi: đo thời gian thật và hiệu chỉnh ước lượng (change 3); đồng bộ thời gian lên field của Project board; bỏ points.

## Capabilities

### New Capabilities

- `time-estimate`: ước lượng thời gian của một task: định dạng thời lượng, nơi lưu trên GitHub, cách đọc lại, và các lệnh đặt hay đổi nó.

### Modified Capabilities

- `work-plan`: trường `estimate` trong plan, ghi khối ước lượng khi áp plan, thời gian trong bản xem và dòng thời gian của `plan.html`.
- `my-work`: thời gian từng task và ước tính phần việc còn lại.
- `sprint-reporting`: thời gian còn lại theo người trong bảng tiến độ.
- `sprint-lifecycle`: `sprint-fill` cộng phút review và cảnh báo vượt giờ review.
- `scrum-config`: `team[].review_hours` và `planning.merge_minutes`.

## Impact

- Mã (tính từ `plugins/scrum-github/`): `scrum.jq` (đọc, ghi khối `estimate`, định dạng thời lượng); `task-payload.jq`; `cmd_task.sh` (`new`, `estimate`); `plan-validate.jq`, `plan-actions.jq`, `plan-render.jq`, dữ liệu và template `plan.html`; `mine.jq`; `progress-table.jq`; `sprint-fill.jq`; `validate-config.jq`, `defaults.json`; `plan.schema.json`; `strings.json`.
- Skill: `plan` (ước lượng thời gian khi chia task), `task-new`, `task`, `sprint-status`, `sprint-fill`, `my-tasks`.
- Tương thích: task không có khối ước lượng vẫn hoạt động như cũ, chỉ không có thời gian. `task estimate N POINTS` giữ nguyên cách gọi.
- Test: `tests/test_estimate.sh` mới; mở rộng `test_task.sh`, `test_plan.sh`, `test_mine.sh`, `test_report.sh`, `test_sprint.sh`, `test_config.sh`.
