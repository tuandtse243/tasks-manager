# Spec Delta

## Purpose

Cho một người thấy toàn bộ việc của mình trong một lần xem: task được giao ở mọi sprint và backlog, PR đang chờ mình review, và thứ tự nên làm theo phụ thuộc.

## ADDED Requirements

### Requirement: Việc của một người
Lệnh `scrum mine` SHALL liệt kê mọi task đang mở được giao cho người dùng hiện tại, hoặc cho `--user LOGIN`, ở mọi sprint và ở backlog. Epic, feature, issue meta và pull request MUST NOT được liệt kê. Lệnh chỉ đọc và MUST chạy được khi repo không có sprint nào đang mở.

#### Scenario: Task ở nhiều nơi
- **WHEN** `tuandt` được giao #42 trong Sprint 5, #60 trong Sprint 6 và #51 ở backlog
- **THEN** `scrum mine` chạy bởi `tuandt` liệt kê cả #42, #60 và #51

#### Scenario: Không có sprint đang mở
- **WHEN** repo không có sprint nào đang mở và `tuandt` được giao #51 ở backlog
- **THEN** lệnh liệt kê #51 và kết thúc với mã 0

#### Scenario: Xem việc của người khác
- **WHEN** người dùng chạy `scrum mine --user an-nguyen`
- **THEN** lệnh liệt kê task đang mở được giao cho `an-nguyen`

#### Scenario: Không có việc
- **WHEN** người dùng không được giao task nào đang mở
- **THEN** lệnh nói không có task nào và kết thúc với mã 0

### Requirement: Nhóm việc theo trạng thái và nơi chứa
Kết quả của `scrum mine` SHALL được nhóm theo thứ tự: task In progress, task In review (khi trạng thái này bật), task New của sprint đang mở, task của các sprint khác theo ngày kết thúc, rồi backlog. Mỗi dòng SHALL có số, điểm, tiêu đề, sprint, và các task đang mở chặn nó.

#### Scenario: Thứ tự nhóm
- **WHEN** người dùng có #42 In progress trong Sprint 5, #45 New trong Sprint 5 và #51 ở backlog
- **THEN** #42 nằm trong nhóm đang làm, #45 trong nhóm sprint hiện tại, #51 trong nhóm backlog, theo đúng thứ tự đó

#### Scenario: Task bị chặn
- **WHEN** #45 bị chặn bởi #42 đang mở
- **THEN** dòng của #45 nêu bị chặn bởi #42

### Requirement: Thứ tự nên làm
`scrum mine` SHALL đề xuất task nên làm tiếp: task In progress trước, rồi task New của sprint đang mở không bị chặn bởi task đang mở nào, theo thứ tự phụ thuộc. Task bị chặn MUST NOT được đề xuất trước task chặn nó.

#### Scenario: Đề xuất task không bị chặn
- **WHEN** người dùng không có task In progress, có #45 bị chặn bởi #42 và #47 không bị chặn, cả hai New trong sprint đang mở
- **THEN** task được đề xuất là #47

#### Scenario: Đang có task dở
- **WHEN** người dùng có #42 In progress
- **THEN** task được đề xuất là tiếp tục #42

### Requirement: PR chờ review
`scrum mine` SHALL liệt kê các pull request đang mở trong repo yêu cầu người đó review, với số, tiêu đề và tác giả. Khi GitHub không trả được danh sách này, lệnh SHALL nói phần này chưa đọc được và vẫn in phần task.

#### Scenario: Có PR chờ review
- **WHEN** PR #48 của `an-nguyen` đang mở và yêu cầu `tuandt` review
- **THEN** `scrum mine` chạy bởi `tuandt` liệt kê PR #48 và tác giả `an-nguyen`

#### Scenario: Không đọc được
- **WHEN** GitHub trả lỗi khi tìm PR chờ review
- **THEN** lệnh in phần task, nói phần PR chưa đọc được, và kết thúc với mã 0

### Requirement: Dạng JSON của việc của một người
Với `--json`, `scrum mine` SHALL in một đối tượng JSON gồm login, các nhóm task, task được đề xuất và danh sách PR chờ review.

#### Scenario: JSON
- **WHEN** người dùng chạy `scrum mine --json`
- **THEN** lệnh in JSON hợp lệ có login, các nhóm task, task được đề xuất và PR chờ review

### Requirement: Skill việc của tôi
Skill `/scrum-github:my-tasks` SHALL chạy `scrum mine`, trình bày kết quả, nói task nên làm tiếp cùng lệnh bắt đầu nó, và đề nghị chạy `/scrum-github:task-start` cho task đó. Skill MUST NOT tự bắt đầu task khi người dùng chưa đồng ý.

#### Scenario: Đề nghị bắt đầu
- **WHEN** `scrum mine` đề xuất #47
- **THEN** skill nói nên làm #47, đưa lệnh `/scrum-github:task-start 47`, và chờ người dùng đồng ý trước khi chạy
