# Spec Delta

## Purpose

Định nghĩa file cấu hình `scrum.yml` của một repo đích: nơi duy nhất khai báo thang điểm, tên trạng thái, nhịp sprint và các nhãn đặc biệt mà mọi lệnh và workflow của plugin cùng đọc.

## ADDED Requirements

### Requirement: Vị trí file cấu hình
Hệ thống SHALL đọc cấu hình từ `.github/scrum.yml` trong repo đích. Mọi lệnh trừ lệnh khởi tạo MUST dừng với thông báo hướng dẫn chạy khởi tạo khi file không tồn tại.

#### Scenario: Thiếu file cấu hình
- **WHEN** người dùng chạy lệnh tạo sprint trong repo chưa có `.github/scrum.yml`
- **THEN** lệnh kết thúc với mã lỗi khác 0, thông báo chạy `/scrum-init` trước, và không ghi gì lên GitHub

#### Scenario: Có file cấu hình
- **WHEN** repo có `.github/scrum.yml` hợp lệ và người dùng chạy một lệnh bất kỳ
- **THEN** lệnh dùng các giá trị trong file đó

### Requirement: Giá trị mặc định
Hệ thống SHALL áp giá trị mặc định cho mọi khoá không khai báo: thang điểm `0, 1, 3, 7`; trạng thái `New`, `In progress`, `Done`; độ dài sprint 5 ngày; tên sprint `Sprint {n}`; múi giờ `UTC`; mẫu branch `feat/{number}-{slug}`; digest bật.

#### Scenario: File chỉ khai báo một phần
- **WHEN** `scrum.yml` chỉ khai báo `points.scale: [1, 2, 3, 5, 8]`
- **THEN** thang điểm là 1, 2, 3, 5, 8 và mọi khoá khác nhận giá trị mặc định

#### Scenario: File rỗng
- **WHEN** `scrum.yml` tồn tại nhưng rỗng
- **THEN** hệ thống dùng toàn bộ giá trị mặc định

### Requirement: Kiểm tra hợp lệ trước khi ghi
Hệ thống MUST kiểm tra cấu hình trước mọi thao tác ghi lên GitHub và từ chối cấu hình sai, với thông báo nêu tên khoá và lý do. Cấu hình sai gồm: điểm không phải số nguyên không âm hoặc trùng nhau, độ dài sprint không dương, tên trạng thái rỗng hoặc trùng nhau, YAML không đọc được.

#### Scenario: Thang điểm có giá trị âm
- **WHEN** `points.scale` chứa `-1`
- **THEN** lệnh dừng với mã lỗi khác 0, thông báo nêu `points.scale`, và không ghi gì lên GitHub

#### Scenario: YAML hỏng
- **WHEN** `scrum.yml` có lỗi cú pháp YAML
- **THEN** lệnh dừng và báo file không đọc được kèm vị trí lỗi do bộ đọc YAML trả về

### Requirement: Kiểm tra công cụ và đăng nhập
Hệ thống MUST kiểm tra `gh`, `jq`, `yq` có trong PATH và `gh` đã đăng nhập trước khi chạy một lệnh, và dừng với thông báo nêu đúng công cụ thiếu cùng cách cài.

#### Scenario: Thiếu yq
- **WHEN** người dùng chạy một lệnh trên máy không có `yq`
- **THEN** lệnh dừng trước mọi thao tác GitHub và thông báo cần cài `yq` (mikefarah v4)

#### Scenario: gh chưa đăng nhập
- **WHEN** `gh auth status` báo token không hợp lệ
- **THEN** lệnh dừng và hướng dẫn chạy `gh auth login`
