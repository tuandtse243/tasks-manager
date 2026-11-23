# Spec Delta

## Purpose

Ghi cho mỗi task hai con số thời gian: làm mất bao lâu và người review, test tay mất bao lâu, cùng ai làm (AI hay người), để lập lịch và biết khi nào xong.

## ADDED Requirements

### Requirement: Định dạng thời lượng
Các lệnh nhận thời lượng SHALL chấp nhận số phút (`90`), phút có hậu tố (`25m`), giờ (`2h`) và giờ cộng phút (`1h30m`), và quy về số phút nguyên dương. Giá trị khác, gồm 0 và số âm, MUST bị từ chối trước khi ghi, kèm ví dụ định dạng hợp lệ.

#### Scenario: Giờ cộng phút
- **WHEN** người dùng truyền `--work 1h30m`
- **THEN** thời gian làm là 90 phút

#### Scenario: Không hợp lệ
- **WHEN** người dùng truyền `--review abc`
- **THEN** lệnh dừng, nêu `--review` và các định dạng hợp lệ, và không ghi gì

### Requirement: Nơi lưu ước lượng
Ước lượng của một task SHALL nằm trong khối `estimate` của plugin ở thân issue, gồm một dòng chữ cho người đọc (ví dụ "AI ~25m · Review ~20m") và dữ liệu `work_minutes`, `review_minutes`, `by`. Ghi ước lượng MUST thay khối cũ và giữ nguyên phần còn lại của thân issue. Issue không có khối này SHALL được coi là chưa có ước lượng thời gian.

#### Scenario: Ghi lần đầu
- **WHEN** issue #12 có thân "Lưu bình luận" và người dùng đặt làm 25 phút, review 20 phút, do AI làm
- **THEN** thân #12 vẫn bắt đầu bằng "Lưu bình luận" và có khối `estimate` với 25, 20 và `ai`

#### Scenario: Ghi đè
- **WHEN** #12 đã có khối `estimate` và người dùng đổi review thành 30 phút
- **THEN** #12 có đúng một khối `estimate`, với review 30 phút và thời gian làm giữ nguyên

#### Scenario: Khối hỏng
- **WHEN** dữ liệu trong khối `estimate` không đọc được
- **THEN** task được coi là chưa có ước lượng và lệnh đọc không dừng

### Requirement: Đặt ước lượng khi tạo task
`scrum task new` SHALL nhận `--work`, `--review` và `--by ai|human` (mặc định `ai` khi có `--work` hoặc `--review`) và ghi khối `estimate` vào thân issue mới.

#### Scenario: Tạo task có thời gian
- **WHEN** người dùng chạy `scrum task new --title "Fix login" --work 15m --review 10m`
- **THEN** issue mới có khối `estimate` với 15, 10 và `ai`

### Requirement: Đổi ước lượng
`scrum task estimate N [POINTS] [--work D] [--review D] [--by ai|human]` SHALL đổi điểm khi có `POINTS` như trước, và đổi các trường thời gian được truyền, giữ nguyên các trường không truyền. Lệnh MUST có ít nhất một trong `POINTS`, `--work`, `--review`, `--by`.

#### Scenario: Chỉ đổi thời gian
- **WHEN** #12 có `points: 3` và người dùng chạy `scrum task estimate 12 --review 30m`
- **THEN** #12 giữ `points: 3` và khối `estimate` có review 30 phút

#### Scenario: Không có gì để đổi
- **WHEN** người dùng chạy `scrum task estimate 12`
- **THEN** lệnh dừng, nêu cần điểm hoặc ít nhất một cờ thời gian, và không ghi gì
