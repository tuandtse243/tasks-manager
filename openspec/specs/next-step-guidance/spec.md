# next-step-guidance Specification

## Purpose
Trả lời câu "giờ tôi làm gì tiếp": từ trạng thái của repo, sprint hiện tại và task của người đang dùng, nêu đúng một bước kế tiếp kèm lệnh, theo một thứ tự ưu tiên cố định.

## Requirements

### Requirement: Một bước kế tiếp theo thứ tự ưu tiên
Lệnh `scrum next` (và skill `/scrum-github:next`) SHALL nêu đúng một bước, là điều kiện đầu tiên đúng theo thứ tự: chưa khởi tạo; `.github/` chưa có trên nhánh mặc định của remote; không có sprint mở; sprint hiện tại đã quá ngày kết thúc; người dùng có task In progress trong sprint; sprint có task chưa xong mà chưa có điểm, hoặc task In progress chưa giao ai; còn task New để nhận; không còn gì để nhận. Mỗi bước MUST kèm một lệnh.

#### Scenario: Chưa khởi tạo
- **WHEN** repo chưa có `.github/scrum.yml`
- **THEN** bước kế tiếp là khởi tạo, lệnh là `/scrum-github:init`, và không có lời gọi nào lên GitHub

#### Scenario: Chưa push
- **WHEN** repo có `.github/scrum.yml` nhưng nhánh mặc định của remote chưa có workflow `scrum-status-sync.yml`
- **THEN** bước kế tiếp là commit và push `.github/`, kèm lệnh git

#### Scenario: Không có sprint mở
- **WHEN** đã cài và push, và không có milestone sprint nào đang mở
- **THEN** bước kế tiếp là tạo sprint bằng `/scrum-github:sprint-new`

#### Scenario: Sprint quá hạn
- **WHEN** sprint hiện tại có ngày kết thúc trước hôm nay
- **THEN** bước kế tiếp là đóng sprint bằng `/scrum-github:sprint-close`, kể cả khi người dùng còn task In progress

#### Scenario: Đang làm dở
- **WHEN** sprint còn hạn và người dùng được giao task #12 đang In progress
- **THEN** bước kế tiếp nêu #12 và gợi ý mở pull request bằng `/scrum-github:task-pr` khi xong

#### Scenario: Task chưa có điểm
- **WHEN** người dùng không có task In progress và sprint có task #15 không có label điểm
- **THEN** bước kế tiếp nêu #15 cần ước lượng, kèm lệnh gắn label điểm

#### Scenario: Task In progress không ai giữ
- **WHEN** người dùng không có task In progress, mọi task chưa xong đã có điểm, và task #16 đang In progress mà không giao cho ai
- **THEN** bước kế tiếp nêu #16 cần người nhận, kèm lệnh giao task

#### Scenario: Nhận task mới
- **WHEN** mọi task chưa xong trong sprint đã có điểm, người dùng không có task In progress, và có task New #20 giao cho người dùng
- **THEN** bước kế tiếp là bắt đầu #20 bằng `/scrum-github:task-start 20`

#### Scenario: Hết việc
- **WHEN** sprint không còn task New nào và người dùng không có task In progress
- **THEN** bước kế tiếp nói không còn task để nhận, nêu số ngày còn lại, và gợi ý `/scrum-github:sprint-status`

### Requirement: Chọn task New để nhận
Khi bước kế tiếp là nhận task, lệnh SHALL chọn task New giao cho người dùng có số nhỏ nhất; nếu không có, chọn task New chưa giao ai có số nhỏ nhất. Task New đã giao cho người khác MUST NOT được gợi ý.

#### Scenario: Chỉ còn task chưa giao
- **WHEN** sprint có task New #21 và #24 chưa giao ai, và task New #22 giao cho người khác
- **THEN** bước kế tiếp là bắt đầu #21

### Requirement: Chỉ đọc và dạng JSON
Lệnh `scrum next` MUST NOT ghi gì lên GitHub hay vào repo. Với `--json`, lệnh SHALL in một đối tượng JSON gồm mã bước, thông báo, lệnh, và số các issue liên quan.

#### Scenario: JSON khi đang làm dở
- **WHEN** người dùng chạy `scrum next --json` lúc có task #12 In progress
- **THEN** đầu ra là JSON hợp lệ có mã bước của trường hợp đang làm dở và danh sách issue chứa 12, và không có lời gọi ghi nào lên GitHub
