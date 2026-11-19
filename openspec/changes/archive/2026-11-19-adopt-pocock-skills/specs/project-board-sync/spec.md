# Spec Delta

## ADDED Requirements

### Requirement: Trình hướng dẫn bật board
Plugin SHALL có một trình hướng dẫn tương tác chạy trong terminal của người dùng, dẫn từng bước qua các việc chỉ con người làm được khi bật board: tạo và liên kết Project, tắt các built-in workflow xung đột, tạo token, đặt secret `SCRUM_PROJECT_TOKEN`, và khai báo khối `project:`. Token MUST được nhập ẩn và MUST NOT được ghi vào file nào trong repo.

#### Scenario: Chạy hết các bước
- **WHEN** người dùng chạy trình hướng dẫn và làm theo tới hết
- **THEN** secret `SCRUM_PROJECT_TOKEN` được đặt cho repo, `.github/scrum.yml` có khối `project:` với `enabled: true`, owner và number đã nhập, và phần tổng kết nêu các lệnh còn lại phải chạy

#### Scenario: Token không lộ
- **WHEN** người dùng dán token ở bước nhập
- **THEN** token không hiện trên màn hình và không có file nào trong repo chứa nó

#### Scenario: Không đặt được secret
- **WHEN** `gh` chưa đăng nhập ở bước đặt secret
- **THEN** trình hướng dẫn không dừng giữa chừng, và phần tổng kết nêu secret còn phải đặt bằng tay cùng lệnh để đặt

#### Scenario: Dừng trước thay đổi cấu hình
- **WHEN** người dùng trả lời không ở câu xác nhận ghi khối `project:`
- **THEN** `.github/scrum.yml` không đổi và phần tổng kết nêu việc đó còn phải làm bằng tay

#### Scenario: Gọi từ Claude Code
- **WHEN** người dùng chạy `/project-setup`
- **THEN** lệnh in câu lệnh để người dùng tự chạy trình hướng dẫn trong terminal của họ, không tự chạy nó, và sau khi người dùng báo xong thì chạy `project init --dry-run` và trình bày kết quả
