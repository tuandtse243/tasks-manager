# sprint-reporting Specification

## Purpose

Cho team biết sprint đang đi tới đâu: tóm tắt nhanh theo người và trạng thái, báo cáo HTML có burndown và velocity, và digest tự đăng mỗi ngày làm việc.

## Requirements

### Requirement: Phạm vi số liệu
Mọi số liệu báo cáo SHALL chỉ tính task của sprint đang xét. Pull request, issue feature và issue meta MUST NOT được tính. Task đóng với lý do không làm MUST NOT được tính vào điểm còn lại hay điểm đã xong.

#### Scenario: Có issue feature trong sprint
- **WHEN** `Sprint 1` có một issue feature và ba task
- **THEN** báo cáo chỉ đếm ba task

### Requirement: Tóm tắt tiến độ sprint
Lệnh tiến độ SHALL in bảng theo từng người được giao (task không giao ai gộp vào nhóm "Unassigned"), mỗi dòng có số task và tổng điểm ở từng trạng thái, cùng dòng tổng, phần trăm điểm đã xong, số task chưa ước lượng và số ngày làm việc còn lại của sprint, rồi mục "Cần chú ý" khi có ít nhất một mục. Chữ cố định theo ngôn ngữ cấu hình. Lệnh MUST NOT ghi gì lên GitHub.

#### Scenario: Ví dụ trong tài liệu
- **WHEN** trong `Sprint 1`, `david` có 1 task Done, 1 task In progress, 1 task New
- **THEN** dòng của `david` hiện 1 Done, 1 In progress, 1 New kèm điểm từng nhóm

#### Scenario: Task giao cho hai người
- **WHEN** một task được giao cho cả `david` và `ruby`
- **THEN** task xuất hiện ở dòng của cả hai người nhưng chỉ được tính một lần ở dòng tổng

#### Scenario: Chọn sprint khác
- **WHEN** người dùng chạy `/sprint-status "Sprint 1"` khi sprint hiện tại là `Sprint 2`
- **THEN** bảng hiện số liệu của `Sprint 1`

#### Scenario: Ngày còn lại không tính cuối tuần
- **WHEN** hôm nay là thứ 6 và sprint kết thúc thứ 3 tuần sau, với `sprint.working_days` mặc định
- **THEN** số ngày còn lại là 3 (thứ 6, thứ 2, thứ 3)

#### Scenario: Tiếng Việt
- **WHEN** cấu hình đặt `language: vi`
- **THEN** tiêu đề cột, dòng tổng và các câu cố định của bảng là tiếng Việt, còn tên trạng thái lấy từ `statuses`

### Requirement: Đường burndown
Đường burndown SHALL dựng lại từ lịch sử của từng issue: với mỗi ngày, phạm vi là các task thuộc sprint vào cuối ngày đó, điểm là label điểm của task vào cuối ngày đó, và điểm còn lại là tổng điểm của các task trong phạm vi chưa đóng với lý do hoàn thành, tính theo múi giờ cấu hình. Task đóng với lý do không làm không thuộc phạm vi. Đường lý tưởng SHALL giảm từ phạm vi của ngày đầu về 0 ở ngày cuối, chỉ giảm qua các ngày làm việc và đi ngang qua ngày nghỉ.

#### Scenario: Burndown theo ngày
- **WHEN** sprint 2014-09-22 đến 2014-09-26 có tổng 14 điểm từ ngày đầu, một task 3 điểm đóng ngày 23 và một task 7 điểm đóng ngày 25
- **THEN** điểm còn lại là 14, 11, 11, 4, 4 cho các ngày 22 đến 26

#### Scenario: Ngày trong tương lai
- **WHEN** báo cáo được tạo giữa sprint
- **THEN** đường thực tế dừng ở hôm nay và đường lý tưởng vẫn kéo tới ngày kết thúc

#### Scenario: Thêm task giữa sprint
- **WHEN** sprint bắt đầu với 10 điểm và một task 3 điểm được gán vào sprint ngày thứ ba
- **THEN** điểm còn lại của hai ngày đầu không tính task đó, từ ngày thứ ba thì có, và đường phạm vi tăng từ 10 lên 13

#### Scenario: Bỏ task khỏi sprint
- **WHEN** một task 5 điểm có từ ngày đầu được chuyển ra khỏi sprint ngày thứ hai
- **THEN** từ ngày thứ hai task đó không còn trong điểm còn lại hay phạm vi, dù hiện nó không thuộc milestone của sprint

#### Scenario: Đổi điểm giữa sprint
- **WHEN** một task đổi từ 3 điểm sang 7 điểm ngày thứ ba
- **THEN** hai ngày đầu tính 3 điểm, từ ngày thứ ba tính 7 điểm

#### Scenario: Cuối tuần
- **WHEN** sprint từ thứ 2 tới thứ 6 tuần sau với `sprint.working_days` mặc định
- **THEN** đường lý tưởng không giảm giữa thứ 7, chủ nhật và thứ 2 kế tiếp

### Requirement: Báo cáo HTML
Lệnh báo cáo SHALL ghi một file HTML tự chứa, mở được khi không có mạng, gồm biểu đồ burndown (thực tế, lý tưởng và phạm vi), số điểm thêm vào và bỏ ra sau ngày đầu, mục "Cần chú ý", bảng theo người, và velocity của tối đa 6 sprint đã đóng gần nhất, với chữ cố định theo ngôn ngữ cấu hình. Mặc định ghi vào `scrum-reports/<tên sprint dạng slug>.html` (vd. `sprint-2.html`) trong thư mục hiện tại và in đường dẫn file.

#### Scenario: Tạo báo cáo
- **WHEN** người dùng chạy `/sprint-report` trong `Sprint 2` khi đã có `Sprint 1` đóng với velocity 11
- **THEN** file `scrum-reports/sprint-2.html` được ghi, có burndown của `Sprint 2` và cột velocity 11 cho `Sprint 1`

#### Scenario: Không tải tài nguyên ngoài
- **WHEN** file báo cáo được mở trên máy không có mạng
- **THEN** biểu đồ và bảng hiển thị đầy đủ

#### Scenario: Phạm vi thay đổi
- **WHEN** sprint có 3 điểm thêm vào và 5 điểm bỏ ra sau ngày đầu
- **THEN** báo cáo ghi thêm vào 3 điểm, bỏ ra 5 điểm, và vẽ đường phạm vi

### Requirement: Digest hằng ngày
Vào mỗi ngày làm việc theo lịch cấu hình, và khi được chạy tay, hệ thống SHALL đăng một comment vào issue digest của sprint hiện tại (issue meta tạo tự động nếu chưa có), gồm task đã xong từ digest trước, task đang làm theo người, điểm còn lại, số ngày làm việc còn lại và mục "Cần chú ý" khi có, với chữ cố định theo ngôn ngữ cấu hình. Khi có biến môi trường `SCRUM_DIGEST_WEBHOOK`, hệ thống SHALL gửi thêm nội dung đó tới webhook theo `digest.webhook_format`; lỗi webhook MUST chỉ là cảnh báo và comment vẫn được đăng. Khi không có sprint mở hoặc digest bị tắt trong cấu hình, hệ thống MUST NOT đăng gì.

#### Scenario: Ngày đầu sprint
- **WHEN** digest chạy lần đầu trong `Sprint 1`
- **THEN** issue meta "Sprint 1 digest" được tạo trong `Sprint 1` và có một comment digest

#### Scenario: Ngày tiếp theo
- **WHEN** digest chạy ngày hôm sau
- **THEN** comment mới được thêm vào cùng issue đó, không tạo issue mới

#### Scenario: Không có sprint mở
- **WHEN** digest chạy khi mọi sprint đã đóng
- **THEN** không có issue hay comment nào được tạo và log của workflow ghi lý do

#### Scenario: Tắt digest
- **WHEN** cấu hình đặt `digest.enabled: false`
- **THEN** digest không đăng gì

#### Scenario: Gửi Slack
- **WHEN** `SCRUM_DIGEST_WEBHOOK` được đặt và `digest.webhook_format` là `slack`
- **THEN** một yêu cầu POST với JSON `{"text": …}` chứa nội dung digest được gửi tới webhook

#### Scenario: Gửi Telegram
- **WHEN** `SCRUM_DIGEST_WEBHOOK` là URL `sendMessage` của bot kèm `chat_id`, và `digest.webhook_format` là `telegram`
- **THEN** một yêu cầu POST với JSON có `text` chứa nội dung digest được gửi tới URL đó

#### Scenario: Webhook lỗi
- **WHEN** webhook trả lỗi
- **THEN** lệnh in cảnh báo, comment digest vẫn được đăng, và lệnh kết thúc với mã 0

### Requirement: Mục cần chú ý
Bảng tiến độ, digest và báo cáo HTML SHALL có mục "Cần chú ý" gồm các mục của bốn yêu cầu dưới đây. Khi không có mục nào, phần này MUST NOT xuất hiện.

#### Scenario: Không có gì
- **WHEN** không có task nào thoả một điều kiện cần chú ý và sprint không chậm
- **THEN** bảng, digest và báo cáo không có mục cần chú ý

### Requirement: Cần chú ý: task bị chặn
Mục cần chú ý SHALL nêu mỗi task chưa xong của sprint bị chặn bởi một task đang mở, kèm số của task chặn.

#### Scenario: Task bị chặn
- **WHEN** task #12 trong sprint bị chặn bởi #10 đang mở
- **THEN** mục cần chú ý nêu #12 bị chặn bởi #10

### Requirement: Cần chú ý: task In progress không động
Mục cần chú ý SHALL nêu mỗi task In progress không có hoạt động trong `attention.stale_days` ngày làm việc, kèm số ngày. Hoạt động là lần cập nhật gần nhất của issue, hoặc của một pull request đang mở có liên kết đóng tới nó.

#### Scenario: Task In progress không động
- **WHEN** `attention.stale_days` là 2, task #14 In progress cập nhật lần cuối 4 ngày làm việc trước, và không có PR mở nào liên kết tới #14
- **THEN** mục cần chú ý nêu #14 không có hoạt động 4 ngày làm việc

#### Scenario: PR vừa có commit
- **WHEN** task #14 cập nhật lần cuối 4 ngày làm việc trước nhưng PR đang mở có "Closes #14" cập nhật hôm qua
- **THEN** #14 không nằm trong mục cần chú ý vì không động

### Requirement: Cần chú ý: task thiếu người nhận hoặc điểm
Mục cần chú ý SHALL nêu các task chưa xong của sprint chưa có người nhận, và các task chưa xong chưa có điểm.

#### Scenario: Thiếu người nhận
- **WHEN** task #15 New trong sprint không giao cho ai
- **THEN** mục cần chú ý nêu #15 chưa có người nhận

### Requirement: Cần chú ý: sprint chậm
Mục cần chú ý SHALL nêu sprint chậm khi điểm còn lại hôm nay vượt đường lý tưởng của hôm nay quá `attention.behind_percent` phần trăm phạm vi, kèm số điểm chậm.

#### Scenario: Chậm hơn lý tưởng
- **WHEN** `attention.behind_percent` là 15, phạm vi 20 điểm, đường lý tưởng hôm nay 10, và còn lại 14 điểm
- **THEN** mục cần chú ý nói sprint chậm 4 điểm so với đường lý tưởng

### Requirement: Báo cáo khi bật In review
Khi `statuses.in_review` đặt, bảng tiến độ và báo cáo HTML SHALL có cột In review giữa In progress và Done, digest SHALL có mục task đang chờ review, và mục cần chú ý SHALL nêu task ở In review không có hoạt động trong `attention.review_days` ngày làm việc. Điểm của task In review tính là chưa xong. Khi không đặt, không có cột hay mục nào trong số này.

#### Scenario: Bảng có cột In review
- **WHEN** In review bật và `david` có một task In review
- **THEN** bảng có cột In review và dòng của `david` có 1 task ở cột đó

#### Scenario: Chờ review quá lâu
- **WHEN** `attention.review_days` là 2 và task #12 In review không có hoạt động 3 ngày làm việc
- **THEN** mục cần chú ý nêu #12 đang chờ review 3 ngày làm việc

#### Scenario: Tắt
- **WHEN** In review không bật
- **THEN** bảng, digest và báo cáo giống hệt khi chưa có tính năng
