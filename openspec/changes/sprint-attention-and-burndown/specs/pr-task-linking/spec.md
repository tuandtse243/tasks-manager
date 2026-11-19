## MODIFIED Requirements

### Requirement: Quyền tối thiểu cho workflow
Workflow đồng bộ trạng thái, kiểm tra PR và digest SHALL chỉ dùng token tự cấp của GitHub Actions với quyền `issues: write`, `pull-requests: read`, `contents: read`, và MUST chạy được khi repo không có secret riêng. Chỉ workflow đồng bộ Project (tuỳ chọn) được yêu cầu secret `SCRUM_PROJECT_TOKEN`. Workflow digest MAY đọc thêm secret tuỳ chọn `SCRUM_DIGEST_WEBHOOK` để gửi digest ra kênh chat, và MUST chạy được khi secret đó không có. Khi secret này có, workflow đồng bộ trạng thái SHALL dùng nó để cập nhật board.

#### Scenario: Cài vào repo mới
- **WHEN** workflow được cài vào một repo chưa cấu hình secret nào
- **THEN** đồng bộ trạng thái và kiểm tra PR chạy được

#### Scenario: Bật Project mà chưa có secret
- **WHEN** `project.enabled: true` nhưng repo chưa có `SCRUM_PROJECT_TOKEN`
- **THEN** đồng bộ trạng thái và kiểm tra PR vẫn chạy thành công, chỉ workflow đồng bộ Project thất bại

#### Scenario: Digest không có webhook
- **WHEN** workflow digest chạy trong repo chưa đặt `SCRUM_DIGEST_WEBHOOK`
- **THEN** digest vẫn được đăng thành comment và job thành công
