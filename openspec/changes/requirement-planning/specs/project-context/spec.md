# Spec Delta

## Purpose

Giữ một tài liệu mô tả dự án có sẵn trong repo đích, để các lệnh làm rõ yêu cầu và chia task dựa vào hiện trạng thật của mã mà không phải quét lại toàn bộ repo mỗi lần.

## ADDED Requirements

### Requirement: Tạo tài liệu ngữ cảnh dự án
Lệnh `/project-scan` SHALL đọc repo đích và ghi tài liệu ngữ cảnh tại đường dẫn `planning.context_file`. Lệnh MUST NOT sửa file nào khác, MUST NOT chạy ứng dụng, và MUST NOT ghi gì lên GitHub.

#### Scenario: Quét lần đầu
- **WHEN** người dùng chạy `/project-scan` trong repo có mã và `planning.context_file` là `docs/project-context.md`
- **THEN** `docs/project-context.md` được tạo và không file nào khác thay đổi

#### Scenario: Repo chưa có mã
- **WHEN** repo chỉ có README và cấu hình Scrum
- **THEN** lệnh báo chưa có gì để quét và không tạo file

### Requirement: Nội dung tài liệu ngữ cảnh
Tài liệu SHALL có các mục: tổng quan, công nghệ, cấu trúc thư mục, các luồng chính, mô hình dữ liệu, tích hợp bên ngoài, quy ước (đặt tên, kiểm thử, kiểu mã), cách chạy và kiểm thử, và bảng thuật ngữ. Mỗi nhận định về mã SHALL nêu file hoặc thư mục làm căn cứ. Điều lệnh không xác định được MUST được ghi là chưa rõ, không được đoán.

#### Scenario: Có căn cứ
- **WHEN** tài liệu ghi dự án dùng một thư viện xác thực
- **THEN** dòng đó nêu file khai báo phụ thuộc hoặc file cấu hình làm căn cứ

#### Scenario: Không xác định được
- **WHEN** repo không có thông tin về môi trường triển khai
- **THEN** mục liên quan ghi "chưa rõ" thay vì một phỏng đoán

### Requirement: Dấu thời điểm quét
Tài liệu SHALL có một dấu ghi commit và ngày của lần quét. Các lệnh dùng tài liệu SHALL so dấu này với commit hiện tại và báo cho người dùng khi tài liệu đã cũ, kèm số commit chênh lệch. Tài liệu cũ MUST vẫn được dùng nếu người dùng không làm mới.

#### Scenario: Tài liệu còn mới
- **WHEN** commit trong dấu là commit hiện tại
- **THEN** lệnh dùng tài liệu và không cảnh báo

#### Scenario: Tài liệu đã cũ
- **WHEN** nhánh hiện tại có 80 commit sau commit trong dấu
- **THEN** lệnh báo tài liệu cũ 80 commit, đề nghị chạy `/project-scan`, và tiếp tục với tài liệu hiện có nếu người dùng không làm mới

#### Scenario: Không so được
- **WHEN** commit trong dấu không còn trong lịch sử của repo
- **THEN** lệnh báo không xác định được độ cũ và đề nghị quét lại

### Requirement: Làm mới tài liệu
Khi tài liệu đã tồn tại, `/project-scan` SHALL chỉ đọc lại các vùng có thay đổi từ commit trong dấu, cập nhật các mục liên quan và dấu. Lệnh SHALL giữ nguyên phần người dùng viết trong mục "Ghi chú của team". Với `--full`, lệnh SHALL quét lại toàn bộ.

#### Scenario: Làm mới theo thay đổi
- **WHEN** từ lần quét trước chỉ thư mục `api/` thay đổi
- **THEN** lệnh đọc lại `api/`, cập nhật các mục liên quan, và dấu ghi commit hiện tại

#### Scenario: Giữ ghi chú của team
- **WHEN** mục "Ghi chú của team" có nội dung do người dùng viết và người dùng chạy `/project-scan --full`
- **THEN** nội dung mục đó không đổi

### Requirement: Đọc mã qua agent chỉ đọc
`/project-scan` SHALL giao việc đọc mã cho một agent chỉ đọc và chỉ nhận về bản tóm tắt có căn cứ. Agent MUST NOT có quyền sửa file hay ghi lên GitHub.

#### Scenario: Repo lớn
- **WHEN** repo có nhiều thư mục độc lập
- **THEN** lệnh chia việc đọc theo thư mục cho các agent chạy song song và gộp kết quả thành một tài liệu

### Requirement: Bản kê repo
`scrum context inventory` SHALL in dạng JSON một bản kê của repo đích lấy từ các file git đang theo dõi: số file theo thư mục gốc và theo đuôi file, các file khai báo phụ thuộc, các lệnh khai báo trong `package.json`, file CI, thư mục kiểm thử, file tài liệu, và repo có mã hay không. Lệnh MUST chạy không cần mạng, MUST NOT sửa file nào, và cùng một commit MUST cho cùng một kết quả.

#### Scenario: Repo có mã
- **WHEN** repo có `package.json`, thư mục `src/` với 40 file `.ts` và `tests/` với 10 file
- **THEN** bản kê có `has_code` đúng, `package.json` trong danh sách file khai báo phụ thuộc, `src` với 40 file, và `tests` trong danh sách thư mục kiểm thử

#### Scenario: Repo chưa có mã
- **WHEN** repo chỉ có `README.md` và các file dưới `.github/`
- **THEN** bản kê có `has_code` sai

#### Scenario: Ngoài repo git
- **WHEN** lệnh chạy trong thư mục không phải repo git
- **THEN** lệnh dừng với mã khác 0 và thông báo cần chạy trong một repo git

### Requirement: Trạng thái tài liệu ngữ cảnh
`scrum context status` SHALL in dạng JSON: tài liệu ngữ cảnh có tồn tại không, commit và ngày trong dấu, số commit từ commit đó tới commit hiện tại, các thư mục gốc có thay đổi trong khoảng đó, và tài liệu có cũ không. Tài liệu là cũ khi số commit chênh vượt `planning.context_stale_commits`. Lệnh MUST chạy không cần mạng và MUST kết thúc với mã 0 trong mọi trạng thái dưới đây.

#### Scenario: Chưa có tài liệu
- **WHEN** file `planning.context_file` không tồn tại
- **THEN** kết quả ghi tài liệu chưa tồn tại

#### Scenario: Còn mới
- **WHEN** commit trong dấu là commit hiện tại
- **THEN** kết quả ghi 0 commit chênh, không có thư mục đã đổi, và không cũ

#### Scenario: Đã cũ
- **WHEN** ngưỡng là 50, có 80 commit sau commit trong dấu, và các commit đó chỉ đổi file dưới `api/`
- **THEN** kết quả ghi 80 commit chênh, thư mục đã đổi là `api`, và là cũ

#### Scenario: Commit không còn trong lịch sử
- **WHEN** commit trong dấu không còn trong lịch sử của repo
- **THEN** kết quả ghi không xác định được độ cũ

### Requirement: Ghi dấu thời điểm quét
`scrum context stamp` SHALL ghi vào tài liệu ngữ cảnh một dấu có commit hiện tại và ngày hôm nay theo múi giờ cấu hình, thay dấu cũ nếu đã có. Lệnh MUST NOT đổi phần nào khác của tài liệu, và MUST dừng với mã khác 0 khi tài liệu chưa tồn tại.

#### Scenario: Ghi dấu lần đầu
- **WHEN** tài liệu chưa có dấu và người dùng chạy `scrum context stamp`
- **THEN** tài liệu có đúng một dấu với commit hiện tại

#### Scenario: Thay dấu cũ
- **WHEN** tài liệu đã có dấu của một commit cũ
- **THEN** tài liệu có đúng một dấu, với commit hiện tại, và các dòng khác không đổi

### Requirement: Kiểm tra cấu trúc tài liệu ngữ cảnh
`scrum doc check FILE` SHALL kiểm tra tài liệu ngữ cảnh có đủ các mục bắt buộc và có dấu thời điểm quét, in tên từng mục thiếu, và kết thúc với mã khác 0 khi thiếu. Lệnh MUST chạy không cần mạng.

#### Scenario: Đủ mục
- **WHEN** tài liệu có đủ mục bắt buộc và có dấu
- **THEN** lệnh kết thúc với mã 0

#### Scenario: Thiếu mục
- **WHEN** tài liệu không có mục mô hình dữ liệu
- **THEN** lệnh nêu mục mô hình dữ liệu còn thiếu và kết thúc với mã khác 0

#### Scenario: Thiếu dấu
- **WHEN** tài liệu có đủ mục nhưng không có dấu thời điểm quét
- **THEN** lệnh nêu thiếu dấu và kết thúc với mã khác 0
