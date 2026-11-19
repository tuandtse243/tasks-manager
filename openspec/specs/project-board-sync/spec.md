# project-board-sync Specification

## Purpose

Cho phép team xem và kéo thả task trên một GitHub Projects v2 board, trong khi label `status: …` vẫn là nguồn sự thật, để board và các lệnh, báo cáo, workflow của plugin không bao giờ lệch nhau lâu dài.

## Requirements

### Requirement: Cấu hình Project
Hệ thống SHALL đọc khối `project:` trong `.github/scrum.yml` với các khoá: `enabled` (mặc định `false`), `owner`, `number`, `status_field` (mặc định `Status`), `status_options` (ánh xạ new/in_progress/done sang tên option, mặc định `Todo`/`In Progress`/`Done`), `synced_field` (mặc định `Synced status`), `points_field` (mặc định `Points`, `null` để tắt), `poll_cron` (mặc định `*/15 * * * *`).

#### Scenario: Không khai báo project
- **WHEN** `scrum.yml` không có khối `project:`
- **THEN** tính năng tắt, không lệnh nào gọi API Projects và mọi hành vi giống hệt khi chưa có tính năng

#### Scenario: Bật mà thiếu owner hoặc number
- **WHEN** `project.enabled: true` nhưng thiếu `project.number`
- **THEN** mọi lệnh dừng trước thao tác ghi, thông báo nêu khoá `project.number`

#### Scenario: Option trùng nhau
- **WHEN** hai giá trị trong `project.status_options` giống nhau
- **THEN** cấu hình bị từ chối với thông báo nêu `project.status_options`

### Requirement: Khởi tạo Project
Lệnh `project init` SHALL kiểm tra quyền truy cập Project, kiểm tra field Status có đủ ba option cấu hình, tạo field `synced_field` (text) và `points_field` (number) nếu thiếu, và thêm vào Project mọi task của các sprint đang mở. Lệnh MUST hỗ trợ `--dry-run` và MUST NOT sửa hay xoá option của field Status.

#### Scenario: Project mặc định của GitHub
- **WHEN** Project có field Status với option `Todo`, `In Progress`, `Done` và cấu hình để mặc định
- **THEN** lệnh tạo field `Synced status` và `Points`, thêm task, rồi báo số item đã thêm

#### Scenario: Thiếu option
- **WHEN** field Status không có option `In Progress`
- **THEN** lệnh dừng mà không ghi gì, thông báo tên option thiếu và gợi ý thêm option trên board hoặc sửa `project.status_options`

#### Scenario: Chạy lại
- **WHEN** chạy `project init` lần hai mà không có gì thay đổi
- **THEN** lệnh báo mọi thứ unchanged và không gọi mutation nào

#### Scenario: Token không có quyền
- **WHEN** token không đọc được Project
- **THEN** lệnh dừng, thông báo cần `SCRUM_PROJECT_TOKEN` hoặc `gh auth refresh -s project`

### Requirement: Chặn built-in workflow xung đột
Lệnh `project init` MUST dừng với lỗi khi Project còn bật một trong các built-in workflow tự đổi Status ("Item added to project", "Item closed", "Item reopened", "Pull request linked to issue", "Pull request merged"), và nêu tên workflow cần tắt. Tuỳ chọn `--allow-builtin-workflows` SHALL bỏ qua kiểm tra này.

#### Scenario: Project mới tạo từ template
- **WHEN** Project còn bật "Item reopened"
- **THEN** `project init` dừng mà không ghi gì, thông báo tắt "Item reopened" trong Settings → Workflows của Project

#### Scenario: Chấp nhận rủi ro
- **WHEN** chạy `project init --allow-builtin-workflows` khi Project còn bật "Item closed"
- **THEN** lệnh tiếp tục và in cảnh báo

### Requirement: Quyết định chiều đồng bộ
Với mỗi task trong Project, hệ thống SHALL so sánh trạng thái của label (L), option Status trên board (B) và giá trị `Synced status` (S). Chỉ B khác S thì áp B vào label. Chỉ L khác S thì áp L lên board. Cả hai khác S và khác nhau thì label thắng. Sau mỗi lần áp, S MUST bằng trạng thái cuối cùng.

#### Scenario: Kéo thẻ trên board
- **WHEN** task #5 có L=New, S=New, và người dùng kéo thẻ sang In Progress (B=In progress)
- **THEN** sau khi sync, #5 có label `status: In progress` và S=In progress

#### Scenario: PR đổi trạng thái
- **WHEN** task #5 có B=New, S=New, và merge PR làm L=Done
- **THEN** sau khi sync, thẻ #5 nằm ở cột Done và S=Done

#### Scenario: Hai bên cùng đổi
- **WHEN** S=New, label đổi thành In progress và board đổi thành Done trước cùng một lần sync
- **THEN** label giữ In progress, thẻ quay về In Progress, S=In progress, và issue có một comment nêu thay đổi trên board đã bị bỏ qua

#### Scenario: Không có thay đổi
- **WHEN** L, B và S bằng nhau
- **THEN** không có lời gọi ghi nào cho task đó

#### Scenario: Item mới chưa có S
- **WHEN** task vừa được thêm vào Project, S rỗng
- **THEN** board và S được đặt theo label, kể cả khi B đang có giá trị khác

### Requirement: Done trên board đóng issue
Khi thay đổi từ board được áp vào label, sang Done MUST đóng issue với lý do completed, còn rời khỏi Done trên một issue đã đóng MUST mở lại issue. Label MUST được đặt trước khi đổi trạng thái đóng/mở.

#### Scenario: Kéo sang Done
- **WHEN** task #7 đang mở và người dùng kéo thẻ sang Done
- **THEN** #7 có `status: Done`, đã đóng với lý do completed và được tính vào velocity

#### Scenario: Kéo từ Done về Todo
- **WHEN** task #7 đã đóng completed và người dùng kéo thẻ về Todo
- **THEN** #7 được mở lại và có `status: New`

### Requirement: Item bị bỏ qua
Hệ thống MUST NOT đổi label, trạng thái đóng/mở hay field của item là pull request, draft item, issue của repo khác, issue feature, issue meta, hoặc item có option Status không nằm trong `status_options`. Item có option lạ MUST được liệt kê trong cảnh báo.

#### Scenario: Cột tuỳ chỉnh
- **WHEN** người dùng thêm cột `Review` và kéo task #8 vào đó
- **THEN** label của #8 không đổi, lần sync in cảnh báo nêu #8 và option `Review`

#### Scenario: Issue feature trên board
- **WHEN** issue feature #9 nằm trong Project và bị kéo sang Done
- **THEN** #9 không bị đóng và không có label status

### Requirement: Đồng bộ điểm một chiều
Khi `points_field` khác `null`, hệ thống SHALL đặt giá trị field này bằng số điểm từ label `points: N`, và xoá giá trị khi task không có label điểm. Giá trị sửa trên board MUST bị ghi đè ở lần sync kế tiếp.

#### Scenario: Gắn điểm
- **WHEN** task #5 có label `points: 3`
- **THEN** sau khi sync, field Points của #5 bằng 3

#### Scenario: Sửa điểm trên board
- **WHEN** người dùng sửa Points của #5 thành 8 trên board
- **THEN** lần sync kế tiếp đặt lại thành 3 và label không đổi

### Requirement: Thêm task vào Project
Khi tính năng bật, task tạo bởi `task new`, `plan apply` hoặc gán vào milestone của một sprint đang mở SHALL được thêm vào Project, và board cùng S được đặt theo label.

#### Scenario: Tạo task
- **WHEN** người dùng chạy `task new --title "Login" --points 3` với project bật
- **THEN** task mới xuất hiện trong Project ở cột Todo với Points 3

#### Scenario: Gán milestone từ giao diện GitHub
- **WHEN** người dùng gán milestone `Sprint 4` (đang mở) cho issue #12 tạo bằng Issue Form
- **THEN** sau khi workflow chạy, #12 nằm trong Project

### Requirement: Cập nhật board ngay khi đổi trạng thái
Khi một lệnh hoặc workflow đổi trạng thái task và có token truy cập Project, hệ thống SHALL cập nhật Status và S trên board trong cùng lần chạy. Lỗi ở bước này MUST chỉ là cảnh báo, không làm lệnh thất bại.

#### Scenario: Merge PR
- **WHEN** PR "Closes #5" được merge và workflow status-sync có `SCRUM_PROJECT_TOKEN`
- **THEN** thẻ #5 sang Done trong cùng lần chạy workflow

#### Scenario: Thiếu token
- **WHEN** workflow status-sync chạy mà không có `SCRUM_PROJECT_TOKEN`
- **THEN** label vẫn đổi bình thường, job thành công kèm cảnh báo, và board được sửa ở lần poll kế tiếp

### Requirement: Workflow đồng bộ Project
Khi `project.enabled: true`, lệnh khởi tạo SHALL cài `scrum-project-sync.yml`, chạy `project sync` theo `poll_cron`, theo `workflow_dispatch`, và khi issue đổi label hoặc milestone. Khi tính năng tắt, workflow này MUST NOT được cài. Workflow MUST thất bại rõ ràng khi thiếu secret.

#### Scenario: Bật tính năng
- **WHEN** người dùng đặt `project.enabled: true` rồi chạy `scrum init`
- **THEN** `.github/workflows/scrum-project-sync.yml` được tạo với cron bằng `project.poll_cron`

#### Scenario: Thiếu secret
- **WHEN** workflow chạy mà repo chưa có secret `SCRUM_PROJECT_TOKEN`
- **THEN** job thất bại với thông báo nêu tên secret và quyền cần cấp

#### Scenario: Hai lần chạy chồng nhau
- **WHEN** lịch poll và một sự kiện issue kích hoạt workflow cùng lúc
- **THEN** các lần chạy được xếp hàng, không chạy song song
