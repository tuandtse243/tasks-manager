## MODIFIED Requirements

### Requirement: Cài template vào repo
Lệnh khởi tạo SHALL ghi vào working tree của repo đích: Issue Form cho task (dropdown điểm lấy từ thang điểm), PR template có các mục tóm tắt, bằng chứng, mức nguy hiểm khi merge và dòng `Closes #`, và các workflow đồng bộ trạng thái, kiểm tra liên kết PR, digest. Lệnh MUST NOT tự commit hoặc push. Lệnh SHALL ghi lại nội dung của từng file nó sinh ra; ở lần chạy sau, file người dùng không sửa kể từ lần ghi đó được cập nhật theo bản mới, còn file người dùng đã sửa MUST NOT bị ghi đè trừ khi người dùng yêu cầu ghi đè.

#### Scenario: Cài lần đầu
- **WHEN** repo chưa có các file template
- **THEN** các file được tạo trong `.github/`, lệnh liệt kê chúng và nhắc người dùng commit và push

#### Scenario: File đã bị sửa
- **WHEN** `.github/pull_request_template.md` đã tồn tại với nội dung khác bản lệnh khởi tạo đã ghi
- **THEN** file giữ nguyên, lệnh báo xung đột và cách ghi đè

#### Scenario: Thang điểm đổi sau khi cài
- **WHEN** người dùng đổi thang điểm rồi chạy lại `/scrum-github:init`, và chưa sửa tay Issue Form
- **THEN** Issue Form được cập nhật, dropdown điểm khớp thang điểm mới, và lệnh báo file đã cập nhật, không cần tuỳ chọn ghi đè

#### Scenario: Lịch digest đổi sau khi cài
- **WHEN** người dùng đổi `digest.cron` rồi chạy lại `/scrum-github:init`, và chưa sửa tay workflow digest
- **THEN** workflow digest được cập nhật theo lịch mới mà không cần tuỳ chọn ghi đè

#### Scenario: PR template mới
- **WHEN** lệnh khởi tạo chạy trong repo chưa có PR template
- **THEN** PR template được tạo có các mục tóm tắt, bằng chứng, mức nguy hiểm khi merge, và mục task với dòng `Closes #`

#### Scenario: Nâng plugin, file chưa sửa
- **WHEN** repo đã được khởi tạo bằng phiên bản có ghi lại file, người dùng không sửa PR template, và phiên bản mới đổi PR template
- **THEN** chạy lại lệnh khởi tạo cập nhật PR template mà không cần tuỳ chọn ghi đè

#### Scenario: Repo đã cài bản cũ
- **WHEN** repo có PR template của một phiên bản chưa ghi lại file, khác bản mới, và người dùng chạy lại lệnh khởi tạo không có tuỳ chọn ghi đè
- **THEN** PR template cũ giữ nguyên, lệnh báo xung đột và cách ghi đè, vì không biết người dùng đã sửa file hay chưa

#### Scenario: Ghi lại sau khi ghi đè
- **WHEN** người dùng ghi đè một file đang xung đột bằng tuỳ chọn ghi đè
- **THEN** từ lần chạy sau, file đó được cập nhật tự động như mọi file chưa sửa

### Requirement: Chế độ xem trước
Lệnh khởi tạo SHALL có chế độ xem trước liệt kê mọi thay đổi sẽ làm, gồm cả file sẽ được cập nhật vì cấu hình hoặc phiên bản đổi, mà không ghi lên GitHub hay ổ đĩa.

#### Scenario: Xem trước
- **WHEN** người dùng chạy `/scrum-github:init` ở chế độ xem trước
- **THEN** lệnh in danh sách label và file sẽ tạo hoặc cập nhật, và repo không thay đổi

#### Scenario: Xem trước một file sẽ cập nhật
- **WHEN** người dùng đổi `digest.cron` rồi chạy lệnh khởi tạo ở chế độ xem trước
- **THEN** lệnh báo workflow digest sẽ được cập nhật, và file trên ổ đĩa không đổi

## ADDED Requirements

### Requirement: Tên lệnh khởi tạo
Skill khởi tạo SHALL có tên `/scrum-github:init`. Trong phiên bản 0.5.x, tên cũ `/scrum-github:scrum-init` SHALL vẫn dùng được: nó báo người dùng tên mới rồi làm đúng như `/scrum-github:init`. Mọi thông báo của plugin nhắc tới lệnh khởi tạo MUST dùng tên mới.

#### Scenario: Dùng tên cũ
- **WHEN** người dùng chạy `/scrum-github:scrum-init`
- **THEN** người dùng được báo lệnh đã đổi tên thành `/scrum-github:init`, và việc khởi tạo vẫn diễn ra như với tên mới

#### Scenario: Thông báo thiếu cấu hình
- **WHEN** một lệnh cần cấu hình chạy trong repo chưa có `.github/scrum.yml`
- **THEN** thông báo lỗi nhắc chạy `/scrum-github:init`

### Requirement: Gỡ cài đặt
Lệnh `scrum uninstall` SHALL xoá khỏi working tree `.github/scrum/` và mọi file lệnh khởi tạo sinh ra mà người dùng chưa sửa, và giữ lại file người dùng đã sửa. Lệnh MUST giữ `.github/scrum.yml`, label, milestone và issue, MUST NOT ghi lên GitHub, MUST NOT tự commit, và SHALL in những gì được giữ lại cùng lý do.

#### Scenario: Gỡ một repo chưa sửa gì
- **WHEN** người dùng chạy `scrum uninstall --yes` trong repo đã khởi tạo và chưa sửa file nào
- **THEN** `.github/scrum/`, Issue Form, PR template và các workflow `scrum-*` bị xoá, `.github/scrum.yml` còn nguyên, và lệnh nhắc commit và push việc xoá

#### Scenario: File đã sửa được giữ
- **WHEN** người dùng đã sửa tay PR template rồi chạy `scrum uninstall --yes`
- **THEN** PR template được giữ, và lệnh nói nó được giữ vì đã bị sửa

#### Scenario: Không có --yes
- **WHEN** người dùng chạy `scrum uninstall` không có `--yes`
- **THEN** lệnh in những gì sẽ xoá và giữ, không xoá gì, và nói cần chạy lại với `--yes`

#### Scenario: Xem trước
- **WHEN** người dùng chạy `scrum uninstall --dry-run --yes`
- **THEN** lệnh in những gì sẽ xoá và giữ, và working tree không đổi

#### Scenario: Không động tới GitHub
- **WHEN** lệnh gỡ cài đặt chạy xong
- **THEN** không có lời gọi nào lên GitHub, label, milestone và issue còn nguyên
