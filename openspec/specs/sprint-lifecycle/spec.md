# sprint-lifecycle Specification

## Purpose

Quản lý vòng đời một sprint trên GitHub (mỗi sprint là một milestone): tạo sprint với khoảng ngày rõ ràng, xác định sprint hiện tại, và đóng sprint kèm ghi velocity và chuyển task chưa xong.

## Requirements

### Requirement: Tạo sprint
Hệ thống SHALL tạo sprint thành một milestone mở có tiêu đề theo mẫu tên sprint, hạn chót là ngày kết thúc, và mô tả chứa mục tiêu sprint cùng ngày bắt đầu và kết thúc ở dạng đọc được bằng máy. Nếu không chỉ định, số sprint là số lớn nhất hiện có cộng một, ngày bắt đầu là hôm nay, ngày kết thúc là ngày bắt đầu cộng độ dài sprint trừ một.

#### Scenario: Sprint đầu tiên
- **WHEN** repo chưa có sprint nào và người dùng chạy `/sprint-new` với ngày bắt đầu 2014-09-22, độ dài 5 ngày, mục tiêu "Register, login, post, comment"
- **THEN** milestone `Sprint 1` được tạo với hạn 2014-09-26 và mô tả chứa mục tiêu cùng khoảng ngày 2014-09-22 đến 2014-09-26

#### Scenario: Sprint kế tiếp
- **WHEN** repo đã có `Sprint 1` và `Sprint 2` và người dùng chạy `/sprint-new` không kèm tên
- **THEN** milestone `Sprint 3` được tạo

#### Scenario: Trùng tên
- **WHEN** người dùng tạo sprint với tên đã có milestone
- **THEN** lệnh từ chối, không tạo milestone, và báo tên đã tồn tại

#### Scenario: Chồng lấn khoảng ngày
- **WHEN** khoảng ngày của sprint mới chồng lên một sprint đang mở
- **THEN** sprint vẫn được tạo và lệnh in cảnh báo nêu tên sprint bị chồng lấn

### Requirement: Xác định sprint hiện tại
Hệ thống SHALL coi sprint hiện tại là sprint đang mở có khoảng ngày chứa ngày hôm nay theo múi giờ cấu hình; nếu không có, là sprint đang mở có hạn chót sớm nhất. Lệnh nào cần sprint mà không có sprint đang mở MUST dừng và hướng dẫn tạo sprint.

#### Scenario: Hôm nay nằm trong sprint
- **WHEN** hôm nay là 2014-09-24 và `Sprint 1` chạy từ 2014-09-22 đến 2014-09-26
- **THEN** sprint hiện tại là `Sprint 1`

#### Scenario: Không có sprint mở
- **WHEN** mọi milestone đã đóng và người dùng chạy `/task-new` không chỉ định sprint
- **THEN** lệnh dừng và hướng dẫn chạy `/sprint-new`

### Requirement: Đóng sprint
Lệnh đóng sprint SHALL hiển thị kế hoạch (velocity, task đã xong, task chuyển sang sprint sau) và chỉ ghi lên GitHub sau khi người dùng xác nhận. Khi ghi, hệ thống ghi velocity vào mô tả milestone, đóng milestone, rồi đăng bản tổng kết sprint (mục tiêu, velocity so với trung bình tối đa ba sprint đóng trước, task xong, task chuyển tiếp, điểm thêm vào và bỏ ra sau ngày đầu) thành một comment trên issue digest của sprint đó, tạo issue digest nếu chưa có, theo ngôn ngữ cấu hình. Lỗi khi đăng bản tổng kết MUST chỉ là cảnh báo.

#### Scenario: Xác nhận đóng sprint
- **WHEN** `Sprint 1` có 3 task xong tổng 11 điểm và 1 task chưa xong, người dùng chạy `/sprint-close` và xác nhận
- **THEN** mô tả milestone ghi velocity 11, milestone được đóng, và lệnh in tóm tắt sprint

#### Scenario: Huỷ
- **WHEN** người dùng xem kế hoạch đóng sprint và không xác nhận
- **THEN** không có gì trên GitHub thay đổi

#### Scenario: Sprint đã đóng
- **WHEN** người dùng chạy `/sprint-close` cho một sprint đã đóng
- **THEN** lệnh báo sprint đã đóng và không ghi gì

#### Scenario: Bản tổng kết
- **WHEN** `Sprint 3` có velocity 11, ba sprint trước có velocity 9, 10, 11, và người dùng xác nhận đóng
- **THEN** issue "Sprint 3 digest" có một comment tổng kết nêu velocity 11 so với trung bình 10, các task xong và các task chuyển sang sprint sau

### Requirement: Cách tính velocity
Velocity của một sprint SHALL là tổng điểm của các task thuộc sprint đó được đóng với lý do hoàn thành. Task đóng với lý do không làm, issue feature, issue meta và pull request MUST NOT được tính.

#### Scenario: Task đóng vì không làm
- **WHEN** một task 3 điểm trong sprint được đóng với lý do "not planned"
- **THEN** 3 điểm đó không được tính vào velocity

#### Scenario: Task chưa ước lượng
- **WHEN** một task đã xong không có label điểm
- **THEN** task đó góp 0 điểm và tóm tắt sprint nêu số task chưa ước lượng

### Requirement: Chuyển task chưa xong
Khi đóng sprint, hệ thống SHALL chuyển mọi task còn mở sang sprint kế tiếp và thêm comment vào từng task nêu sprint cũ. Nếu chưa có sprint kế tiếp, lệnh MUST đề xuất tạo sprint đó theo giá trị mặc định và chỉ tạo khi người dùng xác nhận.

#### Scenario: Có sprint kế tiếp
- **WHEN** `Sprint 1` đóng với task #4 còn mở và `Sprint 2` đã tồn tại
- **THEN** task #4 thuộc `Sprint 2`, giữ nguyên trạng thái, và có comment "Carried over from Sprint 1"

#### Scenario: Chưa có sprint kế tiếp
- **WHEN** `Sprint 1` đóng với task còn mở và chưa có sprint nào khác
- **THEN** lệnh đề xuất tạo `Sprint 2` bắt đầu ngày sau hạn `Sprint 1`, và chỉ chuyển task sau khi người dùng xác nhận

### Requirement: Sức chứa của sprint
Lệnh `scrum sprint fill [SPRINT]` (và skill `/scrum-github:sprint-fill`) SHALL in sức chứa của sprint, điểm đã có trong sprint, điểm còn trống và backlog để chọn. Sức chứa mặc định là trung bình velocity của tối đa ba sprint đã đóng gần nhất có velocity; `--capacity N` thay giá trị đó. Khi chưa có sprint đóng nào có velocity và không có `--capacity`, lệnh MUST nói chưa có số liệu velocity thay vì đoán.

#### Scenario: Có velocity
- **WHEN** ba sprint đóng gần nhất có velocity 10, 12 và 14, và sprint hiện tại đã có 5 điểm
- **THEN** lệnh in sức chứa 12, đã có 5, còn trống 7, rồi liệt kê backlog

#### Scenario: Chưa có velocity
- **WHEN** chưa có sprint nào đóng
- **THEN** lệnh nói chưa có số liệu velocity, gợi ý `--capacity N`, và vẫn liệt kê backlog

#### Scenario: Ghi đè sức chứa
- **WHEN** người dùng chạy `scrum sprint fill --capacity 8`
- **THEN** sức chứa là 8 bất kể velocity

### Requirement: Đưa task từ backlog vào sprint
Với `--add N,N,…`, lệnh SHALL xem trước việc đưa các task đó vào sprint và cảnh báo khi tổng điểm vượt sức chứa, khi task chưa có điểm, hoặc khi task bị chặn bởi một task chưa xong nằm ngoài sprint. Lệnh MUST chỉ gán milestone khi có `--yes`, MUST dừng mà không ghi gì khi một số không phải task đang mở, và SHALL ghi một comment lên mỗi task được chuyển.

#### Scenario: Xem trước
- **WHEN** người dùng chạy `scrum sprint fill --add 30,33` không có `--yes`
- **THEN** lệnh in hai task sẽ được đưa vào, tổng điểm sau khi thêm, các cảnh báo, và không có lời gọi ghi nào lên GitHub

#### Scenario: Vượt sức chứa
- **WHEN** sức chứa còn trống 2 điểm và người dùng thêm một task 3 điểm
- **THEN** lệnh cảnh báo vượt sức chứa 1 điểm, và vẫn ghi được nếu có `--yes`

#### Scenario: Bị chặn bởi task ngoài sprint
- **WHEN** #33 bị chặn bởi #30 đang mở và người dùng chỉ thêm #33
- **THEN** lệnh cảnh báo #33 bị chặn bởi #30 nằm ngoài sprint

#### Scenario: Ghi
- **WHEN** người dùng chạy `scrum sprint fill --add 30 --yes`
- **THEN** #30 được gán milestone của sprint và có một comment nói đã chuyển từ backlog vào sprint

#### Scenario: Số không hợp lệ
- **WHEN** danh sách có #31 là feature
- **THEN** lệnh dừng, nêu #31 không phải task, và không ghi gì

### Requirement: Gợi ý lập kế hoạch sau khi tạo sprint
Sau khi tạo sprint, lệnh tạo sprint SHALL gợi ý `/scrum-github:sprint-fill` khi backlog có ít nhất một task.

#### Scenario: Backlog có task
- **WHEN** người dùng tạo Sprint 5 và backlog có 4 task
- **THEN** lệnh in gợi ý chọn task cho Sprint 5 bằng `/scrum-github:sprint-fill`

### Requirement: Suggest a release after closing a sprint
After closing a sprint with at least one Done task, the sprint close command SHALL suggest `/scrum-github:release --sprint "<sprint name>"`. The suggestion MUST NOT be printed when the sprint has no Done task.

#### Scenario: Done tasks
- **WHEN** the user closes Sprint 5 with 4 Done tasks
- **THEN** the command suggests `/scrum-github:release --sprint "Sprint 5"`

#### Scenario: No Done task
- **WHEN** the user closes a sprint with no Done task
- **THEN** the command does not suggest a release

### Requirement: Giờ review khi lập kế hoạch sprint
`scrum sprint fill` SHALL in tổng phút review của các task đã có trong sprint và, khi có `--add`, của sprint sau khi thêm, theo từng người được giao. Khi một thành viên có `review_hours`, lệnh SHALL cảnh báo nếu tổng phút review giao cho họ vượt `review_hours` × 60. Cảnh báo MUST NOT chặn việc thêm task.

#### Scenario: Vượt giờ review
- **WHEN** `an-nguyen` có `review_hours: 2`, đang có 90 phút review trong sprint, và người dùng xem trước việc thêm một task review 45 phút giao cho họ
- **THEN** lệnh cảnh báo `an-nguyen` có 135 trên 120 phút review

#### Scenario: Không khai báo giờ review
- **WHEN** không thành viên nào có `review_hours`
- **THEN** lệnh in tổng phút review và không cảnh báo

### Requirement: Closing a sprint shows unreleased tasks
In `standard` and `environments`, the preview of closing a sprint SHALL list separately the tasks that are In review on a long-lived branch, say that they are not counted in the velocity because they are not released, and suggest releasing before closing. The close itself SHALL treat them like other unfinished tasks.

#### Scenario: Merged but not released
- **WHEN** the sprint has #12 Done and #13 In review with `on: develop`, and the user previews the close
- **THEN** the velocity counts only #12, #13 is listed as merged but not released, and the preview suggests `/scrum-github:release`

#### Scenario: Close without releasing
- **WHEN** the user confirms the close anyway
- **THEN** #13 moves to the next sprint like any unfinished task and keeps its status and location label
