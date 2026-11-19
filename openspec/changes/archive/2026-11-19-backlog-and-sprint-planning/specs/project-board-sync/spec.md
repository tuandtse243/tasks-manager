## MODIFIED Requirements

### Requirement: Thêm task vào Project
Khi tính năng bật, task tạo bởi `task new`, `plan apply`, đưa vào sprint bằng `task move` hoặc `sprint fill`, hoặc gán vào milestone của một sprint đang mở SHALL được thêm vào Project, và board cùng S được đặt theo label.

#### Scenario: Tạo task
- **WHEN** người dùng chạy `task new --title "Login" --points 3` với project bật
- **THEN** task mới xuất hiện trong Project ở cột Todo với Points 3

#### Scenario: Gán milestone từ giao diện GitHub
- **WHEN** người dùng gán milestone `Sprint 4` (đang mở) cho issue #12 tạo bằng Issue Form
- **THEN** sau khi workflow chạy, #12 nằm trong Project

#### Scenario: Đưa task từ backlog vào sprint
- **WHEN** project bật và người dùng chạy `scrum sprint fill --add 30 --yes`
- **THEN** #30 xuất hiện trong Project trong cùng lần chạy, với cột theo label trạng thái

### Requirement: Cập nhật board ngay khi đổi trạng thái
Khi một lệnh hoặc workflow đổi trạng thái, điểm hoặc sprint của task (kể cả `task estimate`, `task move`, `task drop`) và có token truy cập Project, hệ thống SHALL cập nhật Status và S trên board trong cùng lần chạy. Lỗi ở bước này MUST chỉ là cảnh báo, không làm lệnh thất bại.

#### Scenario: Merge PR
- **WHEN** PR "Closes #5" được merge và workflow status-sync có `SCRUM_PROJECT_TOKEN`
- **THEN** thẻ #5 sang Done trong cùng lần chạy workflow

#### Scenario: Thiếu token
- **WHEN** workflow status-sync chạy mà không có `SCRUM_PROJECT_TOKEN`
- **THEN** label vẫn đổi bình thường, job thành công kèm cảnh báo, và board được sửa ở lần poll kế tiếp

#### Scenario: Ước lượng lại
- **WHEN** project bật, có token, và người dùng chạy `scrum task estimate 12 7`
- **THEN** field Points của thẻ #12 là 7 sau lệnh

#### Scenario: Bỏ task
- **WHEN** project bật, có token, và người dùng chạy `scrum task drop 12`
- **THEN** board được cập nhật trong cùng lần chạy; thẻ của task đóng với lý do not planned được để nguyên như mọi task not planned
