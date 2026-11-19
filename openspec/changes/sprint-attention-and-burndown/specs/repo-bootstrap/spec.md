## ADDED Requirements

### Requirement: Secret webhook cho workflow digest
Workflow digest do lệnh khởi tạo cài SHALL truyền secret `SCRUM_DIGEST_WEBHOOK` của repo vào biến môi trường cùng tên khi chạy `scrum digest`. Repo không đặt secret thì biến rỗng và digest chỉ đăng comment.

#### Scenario: Cài workflow digest
- **WHEN** lệnh khởi tạo cài `.github/workflows/scrum-daily-digest.yml`
- **THEN** bước chạy digest có `SCRUM_DIGEST_WEBHOOK: ${{ secrets.SCRUM_DIGEST_WEBHOOK }}` trong `env`

#### Scenario: Repo đã cài, chưa sửa workflow
- **WHEN** repo đã cài workflow digest của phiên bản trước, chưa sửa tay, và người dùng chạy lại lệnh khởi tạo
- **THEN** workflow digest được cập nhật để có secret webhook
