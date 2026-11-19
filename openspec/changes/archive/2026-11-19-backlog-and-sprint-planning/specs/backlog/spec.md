## Purpose

Xác định task nào thuộc backlog (đang mở, chưa vào sprint nào) và trình bày chúng kèm điểm, người nhận, feature cha và tình trạng bị chặn, để chọn task cho một sprint.

## ADDED Requirements

### Requirement: Task thuộc backlog
Một issue SHALL thuộc backlog khi nó đang mở, không gắn milestone, và là task: không phải pull request, epic, feature hay issue meta theo cấu hình label.

#### Scenario: Issue không có milestone
- **WHEN** repo có task #30 đang mở, không có milestone
- **THEN** #30 nằm trong backlog

#### Scenario: Feature và epic không tính
- **WHEN** issue #31 có label `type: feature` và không có milestone
- **THEN** #31 không nằm trong backlog

#### Scenario: Task đã đóng không tính
- **WHEN** task #32 không có milestone và đã đóng
- **THEN** #32 không nằm trong backlog

### Requirement: Liệt kê backlog
Lệnh `scrum backlog` (và skill `/scrum-github:backlog`) SHALL liệt kê các task trong backlog theo số tăng dần, mỗi task kèm điểm, người nhận, feature cha (lấy từ dòng "Part of #N" trong nội dung), và các task chưa xong đang chặn nó; cuối danh sách là tổng số task, tổng điểm và số task chưa có điểm. Lệnh chỉ đọc. Với `--json`, lệnh in cùng dữ liệu dạng JSON.

#### Scenario: Backlog có task
- **WHEN** backlog có #30 (3 điểm, giao cho alice) và #33 (chưa có điểm)
- **THEN** lệnh in cả hai task, tổng 2 task và 3 điểm, và 1 task chưa có điểm

#### Scenario: Task bị chặn
- **WHEN** #33 bị chặn bởi #30 đang mở
- **THEN** dòng của #33 nêu bị chặn bởi #30

#### Scenario: Backlog rỗng
- **WHEN** không có task nào trong backlog
- **THEN** lệnh nói backlog rỗng và gợi ý `/scrum-github:task-new` hoặc `/scrum-github:plan`

### Requirement: Giới hạn lời gọi khi đọc quan hệ chặn
Lệnh SHALL đọc quan hệ "bị chặn bởi" cho tối đa 50 task đầu tiên của backlog; với các task sau đó, quan hệ chặn MUST được ghi là chưa kiểm tra, không được ghi là không bị chặn.

#### Scenario: Backlog lớn
- **WHEN** backlog có 60 task
- **THEN** lệnh đọc quan hệ chặn của 50 task đầu, và 10 task còn lại hiện là chưa kiểm tra quan hệ chặn
