## ADDED Requirements

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
