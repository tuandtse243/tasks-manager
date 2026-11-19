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
Lệnh tiến độ SHALL in bảng theo từng người được giao (task không giao ai gộp vào nhóm "Unassigned"), mỗi dòng có số task và tổng điểm ở từng trạng thái, cùng dòng tổng, phần trăm điểm đã xong, số task chưa ước lượng và số ngày còn lại của sprint. Lệnh MUST NOT ghi gì lên GitHub.

#### Scenario: Ví dụ trong tài liệu
- **WHEN** trong `Sprint 1`, `david` có 1 task Done, 1 task In progress, 1 task New
- **THEN** dòng của `david` hiện 1 Done, 1 In progress, 1 New kèm điểm từng nhóm

#### Scenario: Task giao cho hai người
- **WHEN** một task được giao cho cả `david` và `ruby`
- **THEN** task xuất hiện ở dòng của cả hai người nhưng chỉ được tính một lần ở dòng tổng

#### Scenario: Chọn sprint khác
- **WHEN** người dùng chạy `/sprint-status "Sprint 1"` khi sprint hiện tại là `Sprint 2`
- **THEN** bảng hiện số liệu của `Sprint 1`

### Requirement: Đường burndown
Điểm còn lại của một ngày SHALL bằng tổng điểm các task hiện thuộc sprint trừ điểm các task đóng với lý do hoàn thành trước hoặc trong ngày đó, tính theo múi giờ cấu hình. Đường lý tưởng SHALL giảm đều từ tổng điểm ở ngày bắt đầu về 0 ở ngày kết thúc.

#### Scenario: Burndown theo ngày
- **WHEN** sprint 2014-09-22 đến 2014-09-26 có tổng 14 điểm, một task 3 điểm đóng ngày 23 và một task 7 điểm đóng ngày 25
- **THEN** điểm còn lại là 14, 11, 11, 4, 4 cho các ngày 22 đến 26

#### Scenario: Ngày trong tương lai
- **WHEN** báo cáo được tạo giữa sprint
- **THEN** đường thực tế dừng ở hôm nay và đường lý tưởng vẫn kéo tới ngày kết thúc

### Requirement: Báo cáo HTML
Lệnh báo cáo SHALL ghi một file HTML tự chứa, mở được khi không có mạng, gồm biểu đồ burndown (thực tế và lý tưởng), bảng theo người, và velocity của tối đa 6 sprint đã đóng gần nhất. Mặc định ghi vào `scrum-reports/<tên sprint dạng slug>.html` (vd. `sprint-2.html`) trong thư mục hiện tại và in đường dẫn file.

#### Scenario: Tạo báo cáo
- **WHEN** người dùng chạy `/sprint-report` trong `Sprint 2` khi đã có `Sprint 1` đóng với velocity 11
- **THEN** file `scrum-reports/sprint-2.html` được ghi, có burndown của `Sprint 2` và cột velocity 11 cho `Sprint 1`

#### Scenario: Không tải tài nguyên ngoài
- **WHEN** file báo cáo được mở trên máy không có mạng
- **THEN** biểu đồ và bảng hiển thị đầy đủ

### Requirement: Digest hằng ngày
Vào mỗi ngày làm việc theo lịch cấu hình, và khi được chạy tay, hệ thống SHALL đăng một comment vào issue digest của sprint hiện tại (issue meta tạo tự động nếu chưa có), gồm task đã xong từ digest trước, task đang làm theo người, điểm còn lại và số ngày còn lại. Khi không có sprint mở hoặc digest bị tắt trong cấu hình, hệ thống MUST NOT đăng gì.

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
