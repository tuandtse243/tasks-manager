# Spec Delta

## MODIFIED Requirements

### Requirement: Tạo task
Hệ thống SHALL tạo task thành một issue mở có tiêu đề, mô tả, label `status: New`, label điểm nếu có, người được giao nếu có, và thuộc sprint chỉ định, hoặc sprint hiện tại khi không chỉ định. Khi không chỉ định sprint và không có sprint nào đang mở, hoặc khi có `--backlog`, task SHALL được tạo ở backlog, không có milestone. Lệnh MUST in task đã vào sprint nào hoặc backlog. Điểm ngoài thang điểm MUST bị từ chối trước khi ghi.

#### Scenario: Task đầy đủ
- **WHEN** người dùng chạy `/task-new` với tiêu đề "Sign up via email, Facebook, LinkedIn", 7 điểm, giao cho `ruby`, trong `Sprint 1`
- **THEN** issue mới có label `status: New` và `points: 7`, assignee `ruby`, milestone `Sprint 1`, và lệnh in số issue cùng link

#### Scenario: Điểm không hợp lệ
- **WHEN** thang điểm là 0, 1, 3, 7 và người dùng tạo task 5 điểm
- **THEN** lệnh từ chối, liệt kê điểm hợp lệ, và không tạo issue

#### Scenario: Task là bug
- **WHEN** người dùng tạo task và đánh dấu là bug
- **THEN** issue có thêm label `bug`

#### Scenario: Chưa ước lượng
- **WHEN** người dùng tạo task không có điểm
- **THEN** issue được tạo không có label điểm

#### Scenario: Không có sprint đang mở
- **WHEN** repo không có sprint nào đang mở và người dùng chạy `scrum task new --title "Fix login"`
- **THEN** issue được tạo không có milestone, và lệnh in rằng task nằm ở backlog

#### Scenario: Có sprint đang mở
- **WHEN** Sprint 5 đang mở và người dùng chạy `scrum task new --title "Fix login"`
- **THEN** issue có milestone `Sprint 5`, và lệnh in rằng task nằm trong Sprint 5

#### Scenario: Chủ động đưa vào backlog
- **WHEN** Sprint 5 đang mở và người dùng chạy `scrum task new --title "Fix login" --backlog`
- **THEN** issue được tạo không có milestone

#### Scenario: Vừa backlog vừa sprint
- **WHEN** người dùng chạy `scrum task new --title "Fix login" --backlog --sprint "Sprint 5"`
- **THEN** lệnh dừng, nói chỉ dùng một trong hai, và không tạo issue

#### Scenario: Sprint chỉ định không tồn tại
- **WHEN** người dùng chạy `scrum task new --title "Fix login" --sprint "Sprint 9"` và repo không có Sprint 9
- **THEN** lệnh dừng với lỗi nêu Sprint 9 và không tạo issue

## ADDED Requirements

### Requirement: Đề xuất người làm và sprint trong plan
Trước khi trình bày plan, `/plan` SHALL đề xuất người làm cho mỗi task chưa có người làm, chọn trong danh sách team theo lĩnh vực của task và tải hiện tại của từng người, và đề xuất sprint: các task vừa capacity của sprint đang mở, theo thứ tự phụ thuộc, vào sprint đó; phần còn lại để ở backlog. Người làm và sprint do người dùng nêu MUST được giữ nguyên. Lệnh MUST NOT đề xuất login không có trong danh sách team.

#### Scenario: Đề xuất theo lĩnh vực
- **WHEN** team có `tuandt` với lĩnh vực backend và `an-nguyen` với lĩnh vực frontend, và plan có task "Add comment form" chưa có người làm
- **THEN** đề xuất giao task đó cho `an-nguyen`

#### Scenario: Vượt capacity
- **WHEN** Sprint 5 đang mở với capacity 15 điểm, các task của plan theo thứ tự phụ thuộc có tổng 16 điểm, và task cuối có 2 điểm
- **THEN** các task có tổng 14 điểm được đề xuất vào Sprint 5, task cuối được đề xuất ở backlog, và bản trình bày nêu lý do vượt capacity

#### Scenario: Không có sprint đang mở
- **WHEN** repo không có sprint đang mở
- **THEN** mọi task được đề xuất ở backlog và bản trình bày gợi ý `/scrum-github:sprint-new`

#### Scenario: Người dùng đã nêu người làm
- **WHEN** người dùng yêu cầu giao task T3 cho `minh-ho`
- **THEN** T3 giữ `minh-ho` và không bị đề xuất người khác

#### Scenario: Team trống, không có ai để đề xuất
- **WHEN** danh sách team rỗng
- **THEN** người làm để trống và bản trình bày nói chưa có team để đề xuất

### Requirement: Một lần duyệt plan
`/plan` SHALL trình bày trong một lần: các task với điểm, phụ thuộc, người làm và sprint đề xuất, tải từng người, mức dùng capacity của sprint, góp ý của agent soát, và các thao tác `plan apply` sẽ làm. Sau khi người dùng duyệt, lệnh SHALL áp plan để mỗi issue có ngay milestone và người được giao, MUST NOT hỏi thêm về người làm hay sprint, và MUST NOT tạo issue trước khi người dùng duyệt.

#### Scenario: Duyệt một lần
- **WHEN** người dùng xem bản trình bày có T1 giao cho `tuandt` trong Sprint 5 rồi trả lời "duyệt"
- **THEN** issue của T1 được tạo với assignee `tuandt` và milestone `Sprint 5`, và lệnh không hỏi thêm câu nào trước khi tạo

#### Scenario: Sửa trước khi duyệt
- **WHEN** người dùng yêu cầu đưa T6 vào Sprint 5
- **THEN** plan được sửa, bản trình bày được sinh lại với T6 trong Sprint 5, và chưa có issue nào được tạo
