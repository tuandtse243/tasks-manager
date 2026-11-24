# Spec Delta

## Purpose

Cho mọi lệnh của plugin cùng biết team gồm những ai, mỗi người làm lĩnh vực gì và nhận được bao nhiêu việc mỗi sprint, để gợi ý người làm, cảnh báo login lạ và cho thấy tải của từng người.

## ADDED Requirements

### Requirement: Nguồn danh sách team
Danh sách team SHALL lấy từ khối `team` của `scrum.yml` khi khối này có ít nhất một thành viên. Khi khối này trống hoặc không có, danh sách SHALL là những người có thể được giao issue trong repo theo GitHub, không có lĩnh vực và capacity. Mọi lệnh dùng danh sách team MUST cho biết danh sách đến từ nguồn nào.

#### Scenario: Khai báo trong cấu hình
- **WHEN** `scrum.yml` có `team` gồm `tuandt` và `an-nguyen`
- **THEN** danh sách team chỉ gồm `tuandt` và `an-nguyen`, kèm lĩnh vực và capacity đã khai báo, và nguồn là cấu hình

#### Scenario: Không khai báo
- **WHEN** `scrum.yml` không có `team` và GitHub cho biết `tuandt`, `minh-ho` có thể được giao issue
- **THEN** danh sách team gồm `tuandt` và `minh-ho`, không có lĩnh vực và capacity, và nguồn là GitHub

### Requirement: Xem team
Lệnh `scrum team [--json]` SHALL in từng thành viên với login, lĩnh vực, capacity, và tải hiện tại: số task đang mở và tổng điểm của các task được giao cho người đó trong sprint đang mở. Khi không có sprint đang mở, tải SHALL được bỏ qua và lệnh nói rõ. Lệnh chỉ đọc.

#### Scenario: Có sprint đang mở
- **WHEN** Sprint 5 đang mở, `tuandt` có capacity 10 và được giao hai task 3 và 5 điểm trong Sprint 5
- **THEN** dòng của `tuandt` hiện 2 task, 8 trên 10 điểm

#### Scenario: Thành viên không có capacity
- **WHEN** `an-nguyen` không khai báo capacity và được giao một task 2 điểm trong sprint đang mở
- **THEN** dòng của `an-nguyen` hiện 1 task, 2 điểm, không có giới hạn

#### Scenario: Không có sprint đang mở
- **WHEN** repo không có sprint nào đang mở
- **THEN** lệnh in danh sách thành viên không có tải và nói không có sprint đang mở

#### Scenario: Dạng JSON
- **WHEN** người dùng chạy `scrum team --json`
- **THEN** lệnh in một đối tượng JSON gồm nguồn của danh sách và danh sách thành viên với login, lĩnh vực, capacity và tải

### Requirement: Cảnh báo login ngoài team
Khi khối `team` có thành viên, lệnh tạo task, lệnh giao task và kiểm tra plan SHALL cảnh báo với mỗi login không có trong team, nêu login đó và danh sách team. Cảnh báo MUST NOT chặn thao tác. Khi khối `team` trống, lệnh MUST NOT cảnh báo.

#### Scenario: Giao cho người ngoài team
- **WHEN** team gồm `tuandt` và `an-nguyen`, và người dùng chạy `scrum task assign 12 tuandtt`
- **THEN** lệnh cảnh báo `tuandtt` không có trong team, liệt kê `tuandt`, `an-nguyen`, và vẫn gửi yêu cầu giao việc lên GitHub

#### Scenario: Team trống
- **WHEN** `scrum.yml` không có `team` và người dùng giao task cho `bob`
- **THEN** lệnh không cảnh báo về `bob`
