# Spec Delta

## MODIFIED Requirements

### Requirement: Cài template vào repo
Lệnh khởi tạo SHALL ghi vào working tree của repo đích: Issue Form cho task (dropdown điểm lấy từ thang điểm), PR template có các mục tóm tắt, bằng chứng, mức nguy hiểm khi merge và dòng `Closes #`, và các workflow đồng bộ trạng thái, kiểm tra liên kết PR, digest. Lệnh MUST NOT tự commit hoặc push, và MUST NOT ghi đè file đã khác nội dung template trừ khi người dùng yêu cầu ghi đè.

#### Scenario: Cài lần đầu
- **WHEN** repo chưa có các file template
- **THEN** các file được tạo trong `.github/`, lệnh liệt kê chúng và nhắc người dùng commit và push

#### Scenario: File đã bị sửa
- **WHEN** `.github/pull_request_template.md` đã tồn tại với nội dung khác
- **THEN** file giữ nguyên, lệnh báo xung đột và cách ghi đè

#### Scenario: Thang điểm đổi sau khi cài
- **WHEN** người dùng đổi thang điểm rồi chạy lại `/scrum-init` với tuỳ chọn ghi đè Issue Form
- **THEN** dropdown điểm trong Issue Form khớp thang điểm mới

#### Scenario: PR template mới
- **WHEN** lệnh khởi tạo chạy trong repo chưa có PR template
- **THEN** PR template được tạo có các mục tóm tắt, bằng chứng, mức nguy hiểm khi merge, và mục task với dòng `Closes #`

#### Scenario: Repo đã cài bản cũ
- **WHEN** repo có PR template của phiên bản trước và người dùng chạy lại lệnh khởi tạo không có tuỳ chọn ghi đè
- **THEN** PR template cũ giữ nguyên và lệnh báo cách ghi đè để nhận các mục mới
