# vendored-skills Specification

## Purpose

Giữ trong plugin một bản sao nguyên văn của các skill lấy từ `mattpocock/skills`, biết rõ chúng đến từ commit nào, và quy định cách các skill của plugin dùng chúng mà không sửa chúng.

## Requirements

### Requirement: Lấy thẳng từ repo upstream
Công cụ đồng bộ SHALL sao chép skill từ một bản clone của `mattpocock/skills`: đường dẫn local do người bảo trì đưa vào, hoặc một bản clone công cụ tự tạo khi không có đường dẫn. Công cụ MUST NOT cần plugin nào khác làm nguồn trung gian.

#### Scenario: Nguồn là bản clone local
- **WHEN** người bảo trì chạy công cụ với đường dẫn tới một bản clone của repo upstream
- **THEN** các mục trong danh sách được sao chép từ bản clone đó và không có lời gọi mạng nào

#### Scenario: Không đưa đường dẫn
- **WHEN** người bảo trì chạy công cụ không có tham số
- **THEN** công cụ clone repo upstream vào một thư mục tạm, sao chép từ đó, rồi xoá thư mục tạm

#### Scenario: Nguồn không phải repo upstream
- **WHEN** đường dẫn đưa vào không phải một repo git hoặc không có thư mục `skills/`
- **THEN** công cụ dừng với lỗi nêu đường dẫn đó và không ghi gì

### Requirement: Danh sách cố định, sao chép nguyên văn
Công cụ SHALL sao chép đúng các mục sau và không mục nào khác: `grilling`, `to-spec`, `domain-modeling`, `to-tickets`, `to-questionnaire`, `pr`, `wizard`, và file `AGENT-BRIEF.md` của `triage`. Nội dung sao chép MUST giống nguồn từng byte, kèm file `LICENSE` của upstream.

#### Scenario: Sao chép đủ
- **WHEN** công cụ chạy xong với một nguồn hợp lệ
- **THEN** mỗi mục trong danh sách có mặt ở đích và so với nguồn không khác gì, và `LICENSE` có mặt

#### Scenario: Skill ngoài danh sách
- **WHEN** nguồn có thêm skill `grill-me`
- **THEN** `grill-me` không có ở đích

#### Scenario: Chỉ một file của một skill
- **WHEN** công cụ chạy xong
- **THEN** đích có `triage/AGENT-BRIEF.md` và không có `triage/SKILL.md`

#### Scenario: Nguồn thiếu một mục
- **WHEN** nguồn không có `to-spec`
- **THEN** công cụ dừng với lỗi nêu `to-spec` và đích không đổi

### Requirement: Ghi nguồn gốc
Mỗi lần đồng bộ SHALL ghi một file nguồn gốc nêu: địa chỉ repo upstream, commit đầy đủ của bản clone đã dùng, ngày đồng bộ, giấy phép, và đường dẫn upstream của từng mục. File này MUST NOT nhắc tới nguồn trung gian nào.

#### Scenario: Commit thật
- **WHEN** bản clone nguồn đang ở commit `abc123`
- **THEN** file nguồn gốc ghi commit `abc123` và đường dẫn upstream của từng mục

#### Scenario: Chạy lại không đổi gì
- **WHEN** công cụ chạy lần hai với cùng nguồn vào một ngày khác
- **THEN** không file nào ở đích thay đổi, kể cả ngày đồng bộ

#### Scenario: Upstream có commit mới
- **WHEN** công cụ chạy lại sau khi bản clone nguồn chuyển sang commit khác
- **THEN** file nguồn gốc ghi commit mới và ngày đồng bộ mới

### Requirement: Dùng qua adapter
Các skill của plugin SHALL đọc skill đã vendor rồi áp một phần "adapter" nằm trong chính skill của plugin; khi hai bên khác nhau, adapter thắng. Plugin MUST NOT sửa file đã vendor, và các skill đã vendor MUST NOT xuất hiện thành lệnh của plugin hay được cài vào repo đích.

#### Scenario: Skill vendor không thành lệnh
- **WHEN** người dùng cài plugin và xem danh sách lệnh
- **THEN** không có lệnh nào tên `to-questionnaire`, `pr`, `wizard` hay `grilling` thuộc plugin

#### Scenario: Repo đích sau khi khởi tạo
- **WHEN** `scrum init` chạy xong trong một repo đích
- **THEN** repo đích không có file nào của thư mục vendor
