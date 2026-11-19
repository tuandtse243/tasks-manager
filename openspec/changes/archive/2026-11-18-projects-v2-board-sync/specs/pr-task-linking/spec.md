# Spec Delta

## MODIFIED Requirements

### Requirement: Trạng thái theo vòng đời issue
Khi một task được đóng với lý do hoàn thành, hệ thống SHALL đặt trạng thái Done. Khi một task đã đóng được mở lại, hệ thống SHALL đặt trạng thái In progress, trừ khi task đang có trạng thái New thì giữ nguyên New. Issue feature và issue meta MUST NOT bị đổi trạng thái.

#### Scenario: Đóng tay
- **WHEN** sprint master đóng task #3 với lý do hoàn thành mà không qua PR
- **THEN** task #3 có `status: Done`

#### Scenario: Mở lại
- **WHEN** task #3 đã Done được mở lại
- **THEN** task #3 có `status: In progress`

#### Scenario: Mở lại sau khi kéo về Todo trên board
- **WHEN** đồng bộ Project đặt `status: New` cho task #3 rồi mở lại issue
- **THEN** task #3 giữ `status: New`

### Requirement: Quyền tối thiểu cho workflow
Workflow đồng bộ trạng thái, kiểm tra PR và digest SHALL chỉ dùng token tự cấp của GitHub Actions với quyền `issues: write`, `pull-requests: read`, `contents: read`, và MUST chạy được khi repo không có secret riêng. Chỉ workflow đồng bộ Project (tuỳ chọn) được yêu cầu secret `SCRUM_PROJECT_TOKEN`. Khi secret này có, workflow đồng bộ trạng thái SHALL dùng nó để cập nhật board.

#### Scenario: Cài vào repo mới
- **WHEN** workflow được cài vào một repo chưa cấu hình secret nào
- **THEN** đồng bộ trạng thái và kiểm tra PR chạy được

#### Scenario: Bật Project mà chưa có secret
- **WHEN** `project.enabled: true` nhưng repo chưa có `SCRUM_PROJECT_TOKEN`
- **THEN** đồng bộ trạng thái và kiểm tra PR vẫn chạy thành công, chỉ workflow đồng bộ Project thất bại
