# Spec Delta

## Purpose

Quản lý vòng đời một sprint trên GitHub (mỗi sprint là một milestone): tạo sprint với khoảng ngày rõ ràng, xác định sprint hiện tại, và đóng sprint kèm ghi velocity và chuyển task chưa xong.

## ADDED Requirements

### Requirement: Tạo sprint
Hệ thống SHALL tạo sprint thành một milestone mở có tiêu đề theo mẫu tên sprint, hạn chót là ngày kết thúc, và mô tả chứa mục tiêu sprint cùng ngày bắt đầu và kết thúc ở dạng đọc được bằng máy. Nếu không chỉ định, số sprint là số lớn nhất hiện có cộng một, ngày bắt đầu là hôm nay, ngày kết thúc là ngày bắt đầu cộng độ dài sprint trừ một.

#### Scenario: Sprint đầu tiên
- **WHEN** repo chưa có sprint nào và người dùng chạy `/sprint-new` với ngày bắt đầu 2014-09-22, độ dài 5 ngày, mục tiêu "Register, login, post, comment"
- **THEN** milestone `Sprint 1` được tạo với hạn 2014-09-26 và mô tả chứa mục tiêu cùng khoảng ngày 2014-09-22 đến 2014-09-26

#### Scenario: Sprint kế tiếp
- **WHEN** repo đã có `Sprint 1` và `Sprint 2` và người dùng chạy `/sprint-new` không kèm tên
- **THEN** milestone `Sprint 3` được tạo

#### Scenario: Trùng tên
- **WHEN** người dùng tạo sprint với tên đã có milestone
- **THEN** lệnh từ chối, không tạo milestone, và báo tên đã tồn tại

#### Scenario: Chồng lấn khoảng ngày
- **WHEN** khoảng ngày của sprint mới chồng lên một sprint đang mở
- **THEN** sprint vẫn được tạo và lệnh in cảnh báo nêu tên sprint bị chồng lấn

### Requirement: Xác định sprint hiện tại
Hệ thống SHALL coi sprint hiện tại là sprint đang mở có khoảng ngày chứa ngày hôm nay theo múi giờ cấu hình; nếu không có, là sprint đang mở có hạn chót sớm nhất. Lệnh nào cần sprint mà không có sprint đang mở MUST dừng và hướng dẫn tạo sprint.

#### Scenario: Hôm nay nằm trong sprint
- **WHEN** hôm nay là 2014-09-24 và `Sprint 1` chạy từ 2014-09-22 đến 2014-09-26
- **THEN** sprint hiện tại là `Sprint 1`

#### Scenario: Không có sprint mở
- **WHEN** mọi milestone đã đóng và người dùng chạy `/task-new` không chỉ định sprint
- **THEN** lệnh dừng và hướng dẫn chạy `/sprint-new`

### Requirement: Đóng sprint
Lệnh đóng sprint SHALL hiển thị kế hoạch (velocity, task đã xong, task chuyển sang sprint sau) và chỉ ghi lên GitHub sau khi người dùng xác nhận. Khi ghi, hệ thống ghi velocity vào mô tả milestone rồi đóng milestone.

#### Scenario: Xác nhận đóng sprint
- **WHEN** `Sprint 1` có 3 task xong tổng 11 điểm và 1 task chưa xong, người dùng chạy `/sprint-close` và xác nhận
- **THEN** mô tả milestone ghi velocity 11, milestone được đóng, và lệnh in tóm tắt sprint

#### Scenario: Huỷ
- **WHEN** người dùng xem kế hoạch đóng sprint và không xác nhận
- **THEN** không có gì trên GitHub thay đổi

#### Scenario: Sprint đã đóng
- **WHEN** người dùng chạy `/sprint-close` cho một sprint đã đóng
- **THEN** lệnh báo sprint đã đóng và không ghi gì

### Requirement: Cách tính velocity
Velocity của một sprint SHALL là tổng điểm của các task thuộc sprint đó được đóng với lý do hoàn thành. Task đóng với lý do không làm, issue feature, issue meta và pull request MUST NOT được tính.

#### Scenario: Task đóng vì không làm
- **WHEN** một task 3 điểm trong sprint được đóng với lý do "not planned"
- **THEN** 3 điểm đó không được tính vào velocity

#### Scenario: Task chưa ước lượng
- **WHEN** một task đã xong không có label điểm
- **THEN** task đó góp 0 điểm và tóm tắt sprint nêu số task chưa ước lượng

### Requirement: Chuyển task chưa xong
Khi đóng sprint, hệ thống SHALL chuyển mọi task còn mở sang sprint kế tiếp và thêm comment vào từng task nêu sprint cũ. Nếu chưa có sprint kế tiếp, lệnh MUST đề xuất tạo sprint đó theo giá trị mặc định và chỉ tạo khi người dùng xác nhận.

#### Scenario: Có sprint kế tiếp
- **WHEN** `Sprint 1` đóng với task #4 còn mở và `Sprint 2` đã tồn tại
- **THEN** task #4 thuộc `Sprint 2`, giữ nguyên trạng thái, và có comment "Carried over from Sprint 1"

#### Scenario: Chưa có sprint kế tiếp
- **WHEN** `Sprint 1` đóng với task còn mở và chưa có sprint nào khác
- **THEN** lệnh đề xuất tạo `Sprint 2` bắt đầu ngày sau hạn `Sprint 1`, và chỉ chuyển task sau khi người dùng xác nhận
