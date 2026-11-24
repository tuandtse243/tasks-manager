# next-step-guidance Specification

## Purpose
Trả lời câu "giờ tôi làm gì tiếp": từ trạng thái của repo, sprint hiện tại và task của người đang dùng, nêu đúng một bước kế tiếp kèm lệnh, theo một thứ tự ưu tiên cố định.

## Requirements

### Requirement: Một bước kế tiếp theo thứ tự ưu tiên
Lệnh `scrum next` (và skill `/scrum-github:next`) SHALL nêu đúng một bước, là điều kiện đầu tiên đúng theo thứ tự: chưa khởi tạo; `.github/` chưa có trên nhánh mặc định của remote; không có sprint mở; sprint hiện tại đã quá ngày kết thúc; sprint hiện tại chưa có task nào trong khi backlog có task; người dùng có task In progress trong sprint; sprint có task chưa xong mà chưa có điểm, hoặc task In progress chưa giao ai; còn task New để nhận; không còn gì để nhận. Mỗi bước MUST kèm một lệnh.

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

#### Scenario: Sprint rỗng, backlog có task
- **WHEN** sprint hiện tại còn hạn, chưa có task nào, và backlog có 4 task
- **THEN** bước kế tiếp là chọn task cho sprint bằng `/scrum-github:sprint-fill`

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

### Requirement: Suggest a release
When the most recently closed sprint has Done tasks closed after the latest version tag, and no step with a higher priority applies, `scrum next` SHALL suggest `/scrum-github:release`. When the tags cannot be read, this step SHALL be skipped.

#### Scenario: Sprint done, not released
- **WHEN** Sprint 5 is closed with 4 Done tasks closed after tag `v1.4.2`, and no step with a higher priority applies
- **THEN** `scrum next` suggests `/scrum-github:release`

#### Scenario: Already released
- **WHEN** every Done task of Sprint 5 was closed before the latest tag
- **THEN** `scrum next` does not suggest a release

### Requirement: Branch flow steps
`scrum next` SHALL suggest, in this order of priority after the setup steps: protecting the repository when a long-lived branch has no rule; merging an open back-merge pull request; promoting, in `environments`, when the working branch holds tasks the staging branch lacks and no promotion is open; and releasing when In review tasks are ready on the branch the release starts from and no release pull request is open.

#### Scenario: Unprotected repository
- **WHEN** setup is complete and `main` has no rule
- **THEN** the next step is `/scrum-github:protect`

#### Scenario: Back-merge open
- **WHEN** a pull request from `main` into `develop` is open
- **THEN** the next step is to merge it, with its link

#### Scenario: Ready to release
- **WHEN** the preset is `standard`, #12 and #13 are `on: develop`, and no release pull request is open
- **THEN** the next step is `/scrum-github:release` with the number of tasks waiting

#### Scenario: Ready to promote
- **WHEN** the preset is `environments`, #12 is `on: develop` and no promotion is open
- **THEN** the next step is `/scrum-github:promote`
