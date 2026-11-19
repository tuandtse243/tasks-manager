## MODIFIED Requirements

### Requirement: Kiểm tra công cụ và đăng nhập
Hệ thống MUST kiểm tra `gh`, `jq`, `yq` có trong PATH và `gh` đã đăng nhập trước khi chạy một lệnh, và dừng với thông báo nêu đúng công cụ thiếu cùng cách cài. Khi `gh` báo chưa đăng nhập trong lúc lệnh chạy bên trong sandbox của Claude Code, thông báo SHALL nói rằng sandbox có thể là nguyên nhân và dẫn tới `/scrum-github:doctor`.

#### Scenario: Thiếu yq
- **WHEN** người dùng chạy một lệnh trên máy không có `yq`
- **THEN** lệnh dừng trước mọi thao tác GitHub và thông báo cần cài `yq` (mikefarah v4)

#### Scenario: gh chưa đăng nhập
- **WHEN** `gh auth status` báo token không hợp lệ
- **THEN** lệnh dừng và hướng dẫn chạy `gh auth login`

#### Scenario: gh báo lỗi trong sandbox
- **WHEN** lệnh chạy bên trong sandbox của Claude Code và `gh auth status` báo token không hợp lệ
- **THEN** lệnh dừng, nói sandbox có thể chặn `gh` đọc token, gợi ý chạy ngoài sandbox, và dẫn tới `/scrum-github:doctor`
