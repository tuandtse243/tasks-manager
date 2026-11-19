# Spec Delta

## Purpose

Đưa một repo GitHub bất kỳ về trạng thái sẵn sàng chạy Scrum: có file cấu hình, bộ label chuẩn, Issue Form, PR template và các workflow tự động, và chạy lại bao nhiêu lần cũng cho cùng kết quả.

## ADDED Requirements

### Requirement: Tạo file cấu hình mặc định
Lệnh khởi tạo SHALL tạo `.github/scrum.yml` với giá trị mặc định khi file chưa có, và MUST NOT ghi đè file đã có.

#### Scenario: Repo mới
- **WHEN** người dùng chạy `/scrum-init` trong repo chưa có `.github/scrum.yml`
- **THEN** file được tạo với giá trị mặc định có chú thích từng khoá

#### Scenario: Đã có cấu hình
- **WHEN** người dùng chạy `/scrum-init` trong repo đã có `.github/scrum.yml` đã chỉnh sửa
- **THEN** file giữ nguyên nội dung và lệnh dùng cấu hình đó để đồng bộ label

### Requirement: Đồng bộ bộ label idempotent
Lệnh khởi tạo SHALL đảm bảo repo có đúng một label cho mỗi trạng thái, mỗi giá trị điểm, `bug`, nhãn feature, nhãn meta và nhãn bỏ qua kiểm tra PR, với màu và mô tả theo cấu hình. Lệnh MUST NOT xoá label không do plugin quản lý.

#### Scenario: Lần chạy đầu
- **WHEN** repo chỉ có các label mặc định của GitHub
- **THEN** các label còn thiếu được tạo, `bug` có sẵn được giữ lại, và lệnh in danh sách label đã tạo, đã cập nhật, không đổi

#### Scenario: Chạy lại không có thay đổi
- **WHEN** người dùng chạy `/scrum-init` lần thứ hai mà không sửa cấu hình
- **THEN** không có label nào bị tạo hoặc sửa và lệnh báo mọi label không đổi

#### Scenario: Label bị sửa màu bằng tay
- **WHEN** label `status: Done` trên GitHub có màu khác cấu hình
- **THEN** lệnh cập nhật màu về giá trị cấu hình và báo label đó đã cập nhật

#### Scenario: Bỏ một giá trị điểm khỏi thang
- **WHEN** cấu hình bỏ điểm `7` khỏi thang điểm trong khi repo đang có label `points: 7`
- **THEN** label `points: 7` không bị xoá và lệnh báo nó là label lỗi thời

### Requirement: Cài template vào repo
Lệnh khởi tạo SHALL ghi vào working tree của repo đích: Issue Form cho task (dropdown điểm lấy từ thang điểm), PR template có dòng `Closes #`, và các workflow đồng bộ trạng thái, kiểm tra liên kết PR, digest. Lệnh MUST NOT tự commit hoặc push, và MUST NOT ghi đè file đã khác nội dung template trừ khi người dùng yêu cầu ghi đè.

#### Scenario: Cài lần đầu
- **WHEN** repo chưa có các file template
- **THEN** các file được tạo trong `.github/`, lệnh liệt kê chúng và nhắc người dùng commit và push

#### Scenario: File đã bị sửa
- **WHEN** `.github/pull_request_template.md` đã tồn tại với nội dung khác
- **THEN** file giữ nguyên, lệnh báo xung đột và cách ghi đè

#### Scenario: Thang điểm đổi sau khi cài
- **WHEN** người dùng đổi thang điểm rồi chạy lại `/scrum-init` với tuỳ chọn ghi đè Issue Form
- **THEN** dropdown điểm trong Issue Form khớp thang điểm mới

### Requirement: Chế độ xem trước
Lệnh khởi tạo SHALL có chế độ xem trước liệt kê mọi thay đổi sẽ làm mà không ghi lên GitHub hay ổ đĩa.

#### Scenario: Xem trước
- **WHEN** người dùng chạy `/scrum-init` ở chế độ xem trước
- **THEN** lệnh in danh sách label và file sẽ tạo hoặc cập nhật, và repo không thay đổi
