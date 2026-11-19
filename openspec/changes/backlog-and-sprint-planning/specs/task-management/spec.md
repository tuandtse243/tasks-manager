## ADDED Requirements

### Requirement: Liệt kê task
Lệnh `scrum task list` SHALL liệt kê task của sprint hiện tại (mặc định), của một sprint (`--sprint S`) hoặc của backlog (`--backlog`), lọc được theo người dùng hiện tại (`--mine`) và theo trạng thái (`--status new|in_progress|done`). Mỗi dòng có số, trạng thái, điểm, người nhận và tiêu đề. Với `--json`, lệnh in JSON. Lệnh chỉ đọc.

#### Scenario: Task của tôi đang làm
- **WHEN** người dùng chạy `scrum task list --mine --status in_progress`
- **THEN** chỉ các task In progress giao cho người dùng trong sprint hiện tại được in

#### Scenario: Backlog
- **WHEN** người dùng chạy `scrum task list --backlog`
- **THEN** các task đang mở không có milestone được in

### Requirement: Chuyển task giữa sprint và backlog
Lệnh `scrum task move N… --sprint S` hoặc `--backlog` SHALL gán milestone của sprint S (phải đang mở) hoặc bỏ milestone cho từng task, rồi ghi một comment nêu nguồn và đích. Task đã đóng hoặc issue không phải task MUST bị từ chối trước khi ghi bất cứ gì.

#### Scenario: Đưa về backlog
- **WHEN** người dùng chạy `scrum task move 12 --backlog` cho task #12 trong Sprint 4
- **THEN** #12 không còn milestone, và có comment "Moved from Sprint 4 to the backlog"

#### Scenario: Sprint đã đóng
- **WHEN** người dùng chuyển task vào Sprint 2 đã đóng
- **THEN** lệnh dừng, nói Sprint 2 đã đóng, và không ghi gì

### Requirement: Ước lượng lại task
Lệnh `scrum task estimate N POINTS` SHALL thay label điểm của task bằng đúng một label điểm mới. Giá trị không có trong thang điểm MUST bị từ chối trước khi ghi và lệnh nêu các giá trị hợp lệ.

#### Scenario: Đổi điểm
- **WHEN** task #12 có `points: 3` và người dùng chạy `scrum task estimate 12 7`
- **THEN** #12 có `points: 7` và không còn `points: 3`

#### Scenario: Ngoài thang điểm
- **WHEN** thang điểm là 0, 1, 3, 7 và người dùng chạy `scrum task estimate 12 5`
- **THEN** lệnh dừng, nêu các giá trị hợp lệ, và không ghi gì

### Requirement: Giao task
Lệnh `scrum task assign N LOGIN…` SHALL thêm người nhận cho task; với `--unassign`, lệnh SHALL gỡ những người đó. `@` ở đầu login được bỏ qua.

#### Scenario: Giao
- **WHEN** người dùng chạy `scrum task assign 12 @alice bob`
- **THEN** alice và bob là người nhận của #12

#### Scenario: Gỡ giao
- **WHEN** người dùng chạy `scrum task assign 12 alice --unassign`
- **THEN** alice không còn là người nhận của #12

### Requirement: Bỏ task
Lệnh `scrum task drop N [--reason TEXT]` SHALL đóng task với lý do "not planned", để task không tính vào điểm hay velocity, và ghi comment kèm lý do khi có.

#### Scenario: Bỏ task có lý do
- **WHEN** người dùng chạy `scrum task drop 12 --reason "Đã có thư viện làm việc này"`
- **THEN** #12 đóng với lý do not planned, có comment chứa lý do, và không tính vào velocity của sprint

### Requirement: Skill cho các lệnh task
Skill `/scrum-github:task` SHALL nhận yêu cầu bằng lời về liệt kê, chuyển, ước lượng, giao hoặc bỏ task, chạy lệnh tương ứng, và với lệnh ghi MUST nói lại thay đổi sẽ làm và chờ người dùng đồng ý trước khi chạy.

#### Scenario: Yêu cầu bằng lời
- **WHEN** người dùng gõ `/scrum-github:task đưa #12 về backlog`
- **THEN** skill nói sẽ chuyển #12 về backlog, chờ đồng ý, rồi chạy `scrum task move 12 --backlog`
