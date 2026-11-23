# Spec Delta

## Purpose

Chạy các task được giao cho mình bằng agent, song song trong các worktree ở local, rồi gộp thành một pull request có sẵn mọi thứ người review cần để test lần cuối và quyết định merge.

## ADDED Requirements

### Requirement: Chọn task để chạy
`scrum run plan` SHALL chọn mặc định các task đang mở được giao cho người dùng hiện tại, trong sprint đang mở, trạng thái New và có label `ai-ready`. Với danh sách số task, lệnh SHALL chọn đúng các task đó. Task bị chặn bởi một task đang mở không nằm trong lần chạy MUST bị loại, kèm lý do. Task đã đóng, issue không phải task, hoặc pull request MUST bị loại, kèm lý do.

#### Scenario: Mặc định
- **WHEN** người dùng có #102, #107 (New, `ai-ready`) và #110 (New, không có `ai-ready`) trong sprint đang mở
- **THEN** lần chạy gồm #102 và #107, không gồm #110

#### Scenario: Bị chặn bởi task ngoài lần chạy
- **WHEN** người dùng chạy `scrum run plan 103` và #103 bị chặn bởi #102 đang mở
- **THEN** #103 bị loại với lý do bị chặn bởi #102

### Requirement: Chia đợt và xem trước
`scrum run plan` SHALL xếp các task được chọn thành đợt theo quan hệ chặn giữa chúng, và in từng đợt, task bị loại kèm lý do, và ước tính thời gian làm và review theo đợt khi có ước lượng. Với `--dry-run` hoặc khi chỉ gọi `plan`, hệ thống MUST NOT tạo nhánh, đổi trạng thái hay ghi gì lên GitHub.

#### Scenario: Hai đợt
- **WHEN** lần chạy gồm #102, #107 và #103, với #103 bị chặn bởi #102
- **THEN** đợt 1 gồm #102 và #107, đợt 2 gồm #103

#### Scenario: Xem trước không ghi
- **WHEN** người dùng chạy `/scrum-github:run --dry-run`
- **THEN** các đợt và ước tính được in, không có nhánh mới, không có trạng thái nào đổi

### Requirement: Bắt đầu lần chạy
`scrum run start` SHALL tạo ở local một nhánh tích hợp theo `run.branch_pattern` từ nhánh mặc định mới nhất, ghi trạng thái lần chạy vào `.scrum/run/<id>.json`, giao task chưa có người cho người dùng, và chuyển mọi task của lần chạy sang In progress. Khi thư mục làm việc có thay đổi chưa commit, lệnh MUST dừng trước khi đổi gì.

#### Scenario: Bắt đầu
- **WHEN** người dùng `tuandt` bắt đầu lần chạy gồm #102 và #107 trong Sprint 5
- **THEN** nhánh `run/sprint-5-tuandt` được tạo ở local, file trạng thái được ghi, và #102, #107 có trạng thái In progress

#### Scenario: Có thay đổi chưa commit
- **WHEN** thư mục làm việc có file sửa chưa commit
- **THEN** lệnh dừng, nêu cần commit hoặc stash, và không tạo nhánh hay đổi trạng thái

### Requirement: Mỗi task một worktree local
Skill `/scrum-github:run` SHALL giao mỗi task cho một agent làm việc trong một git worktree riêng, tách từ nhánh tích hợp ở đầu đợt của task đó, và chạy song song tối đa `--max-parallel` agent (mặc định `run.max_parallel`). Nhánh và worktree của từng task MUST NOT được push.

#### Scenario: Giới hạn song song
- **WHEN** đợt 1 có 5 task và `max_parallel` là 3
- **THEN** không bao giờ có quá 3 agent chạy cùng lúc

#### Scenario: Không push nhánh task
- **WHEN** lần chạy kết thúc
- **THEN** remote chỉ có nhánh tích hợp mới, không có nhánh của từng task

### Requirement: Merge theo đợt
Sau khi các task của một đợt xong, `scrum run merge` SHALL merge nhánh của từng task xong vào nhánh tích hợp, mỗi task một commit merge, rồi skill SHALL chạy lệnh test của repo trên nhánh tích hợp trước khi bắt đầu đợt sau. Khi merge gây conflict, lệnh MUST huỷ merge đó, giữ nguyên nhánh tích hợp, ghi task là conflict, và skill MUST hỏi người dùng trước khi làm tiếp.

#### Scenario: Merge sạch
- **WHEN** #102 và #107 xong ở đợt 1 không conflict
- **THEN** nhánh tích hợp có hai commit merge cho #102 và #107

#### Scenario: Conflict
- **WHEN** merge #104 vào nhánh tích hợp gây conflict
- **THEN** nhánh tích hợp không đổi so với trước merge đó, #104 được ghi là conflict, và skill hỏi người dùng

#### Scenario: Test đỏ sau merge
- **WHEN** test trên nhánh tích hợp thất bại sau khi merge đợt 1
- **THEN** skill dừng trước đợt 2, nêu test thất bại, và hỏi người dùng

### Requirement: Task lỗi
Khi agent không làm xong một task (test của task thất bại hoặc agent báo không làm được), `scrum run record` SHALL ghi task là lỗi kèm lý do, đăng comment lý do lên issue, và chuyển task về New. Task lỗi MUST NOT được merge hay đưa vào PR. Các task khác SHALL tiếp tục, trừ task bị chặn bởi task lỗi, vì chúng bị loại kèm lý do.

#### Scenario: Một task lỗi
- **WHEN** agent của #107 báo test thất bại
- **THEN** #107 có comment lý do, trạng thái New, không có trong PR, và #102 vẫn được merge

#### Scenario: Task phụ thuộc task lỗi
- **WHEN** #103 bị chặn bởi #102 và #102 lỗi
- **THEN** #103 không được chạy và được ghi là bị loại vì #102 lỗi

### Requirement: Thời gian thật
`scrum run record` SHALL ghi thời gian thật của mỗi task, từ lúc agent bắt đầu tới lúc nó xong hoặc lỗi, vào trạng thái lần chạy, và đăng lên issue một comment có khối `actual` với số phút và kết quả.

#### Scenario: Task xong
- **WHEN** agent của #102 bắt đầu lúc 10:00 và xong lúc 10:41
- **THEN** #102 có comment với khối `actual` ghi 41 phút và kết quả xong

### Requirement: Một PR gói review
`scrum run finish` SHALL push nhánh tích hợp và mở một PR vào nhánh mặc định với `Closes #N` cho mỗi task đã merge. Mô tả PR SHALL có cho mỗi task: tiêu đề, acceptance dạng checkbox lấy từ issue, thời gian ước lượng và thời gian thật, cách test tay và những chỗ cần nhìn kỹ do agent báo; và danh sách task lỗi hoặc bị loại kèm lý do. Khi không task nào được merge, lệnh MUST NOT push hay mở PR.

#### Scenario: PR cho hai task
- **WHEN** #102 và #107 đã merge vào nhánh tích hợp
- **THEN** một PR được mở có `Closes #102` và `Closes #107`, mỗi task có mục riêng với acceptance và thời gian

#### Scenario: Không có gì để mở PR
- **WHEN** mọi task của lần chạy đều lỗi
- **THEN** không có push, không có PR, và lệnh nêu không có task nào xong

### Requirement: Một PR mỗi đợt
Với `--pr-per-wave`, hệ thống SHALL mở một PR cho mỗi đợt ngay sau khi đợt đó merge và qua test. PR của đợt sau SHALL nhắm vào nhánh của PR đợt trước và nêu PR đó phải merge trước.

#### Scenario: Hai đợt
- **WHEN** lần chạy có hai đợt và dùng `--pr-per-wave`
- **THEN** có hai PR, PR thứ hai nêu cần merge PR thứ nhất trước

### Requirement: Chạy tiếp sau khi dừng
Khi có file trạng thái của một lần chạy chưa xong, `/scrum-github:run` SHALL đề nghị chạy tiếp lần đó: bỏ qua task đã xong hoặc đã merge, chạy lại task chưa xong. `scrum run status` SHALL in trạng thái từng task của một lần chạy.

#### Scenario: Bị ngắt giữa đợt 2
- **WHEN** lần chạy dừng sau khi đợt 1 đã merge và trước khi đợt 2 xong
- **THEN** chạy tiếp không chạy lại task của đợt 1 và bắt đầu lại các task của đợt 2

### Requirement: Xác nhận trước khi chạy
Skill `/scrum-github:run` SHALL trình bày các đợt, task bị loại và ước tính, nói rõ agent sẽ chạy mã và test của repo trên máy, và MUST chờ người dùng xác nhận trước `scrum run start`.

#### Scenario: Người dùng không xác nhận
- **WHEN** người dùng xem kế hoạch chạy rồi trả lời không
- **THEN** không có nhánh, worktree hay thay đổi trạng thái nào
