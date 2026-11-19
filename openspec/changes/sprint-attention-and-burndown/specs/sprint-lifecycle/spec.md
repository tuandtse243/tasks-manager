## MODIFIED Requirements

### Requirement: Đóng sprint
Lệnh đóng sprint SHALL hiển thị kế hoạch (velocity, task đã xong, task chuyển sang sprint sau) và chỉ ghi lên GitHub sau khi người dùng xác nhận. Khi ghi, hệ thống ghi velocity vào mô tả milestone, đóng milestone, rồi đăng bản tổng kết sprint (mục tiêu, velocity so với trung bình tối đa ba sprint đóng trước, task xong, task chuyển tiếp, điểm thêm vào và bỏ ra sau ngày đầu) thành một comment trên issue digest của sprint đó, tạo issue digest nếu chưa có, theo ngôn ngữ cấu hình. Lỗi khi đăng bản tổng kết MUST chỉ là cảnh báo.

#### Scenario: Xác nhận đóng sprint
- **WHEN** `Sprint 1` có 3 task xong tổng 11 điểm và 1 task chưa xong, người dùng chạy `/sprint-close` và xác nhận
- **THEN** mô tả milestone ghi velocity 11, milestone được đóng, và lệnh in tóm tắt sprint

#### Scenario: Huỷ
- **WHEN** người dùng xem kế hoạch đóng sprint và không xác nhận
- **THEN** không có gì trên GitHub thay đổi

#### Scenario: Sprint đã đóng
- **WHEN** người dùng chạy `/sprint-close` cho một sprint đã đóng
- **THEN** lệnh báo sprint đã đóng và không ghi gì

#### Scenario: Bản tổng kết
- **WHEN** `Sprint 3` có velocity 11, ba sprint trước có velocity 9, 10, 11, và người dùng xác nhận đóng
- **THEN** issue "Sprint 3 digest" có một comment tổng kết nêu velocity 11 so với trung bình 10, các task xong và các task chuyển sang sprint sau
