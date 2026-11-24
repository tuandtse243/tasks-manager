# Spec Delta

## MODIFIED Requirements

### Requirement: Bắt đầu task
Lệnh bắt đầu task SHALL, với một issue đang mở: giao issue cho người dùng hiện tại nếu chưa ai được giao, chuyển trạng thái sang In progress, và tạo rồi checkout branch cục bộ đặt tên theo mẫu branch tính từ nhánh làm việc của preset, lấy theo trạng thái mới nhất trên remote. Lệnh MUST từ chối với issue đã đóng.

#### Scenario: Bắt đầu task mới
- **WHEN** người dùng `david` chạy `/task-start 2` cho issue #2 "Login" chưa giao ai, với preset `trunk`
- **THEN** issue #2 được giao cho `david`, có `status: In progress`, và branch `feat/2-login` được tạo từ branch mặc định và checkout

#### Scenario: Branch đã tồn tại
- **WHEN** branch `feat/2-login` đã có cục bộ
- **THEN** lệnh checkout branch đó thay vì tạo mới

#### Scenario: Issue đã đóng
- **WHEN** người dùng chạy `/task-start` cho một issue đã đóng
- **THEN** lệnh từ chối và không đổi gì trên GitHub hay git cục bộ

#### Scenario: Đã giao cho người khác
- **WHEN** issue đã giao cho `ruby` và `david` chạy `/task-start`
- **THEN** người được giao giữ nguyên, trạng thái vẫn chuyển sang In progress, và lệnh nhắc issue đang giao cho `ruby`

#### Scenario: Preset standard
- **WHEN** preset là `standard`, `origin/develop` đi trước `develop` cục bộ hai commit, và người dùng chạy `/task-start 2`
- **THEN** branch `feat/2-login` được tạo từ `origin/develop` và chứa hai commit đó

#### Scenario: Không lấy được remote
- **WHEN** không fetch được remote
- **THEN** lệnh tạo branch từ nhánh làm việc cục bộ và cảnh báo rằng nhánh có thể đã cũ
