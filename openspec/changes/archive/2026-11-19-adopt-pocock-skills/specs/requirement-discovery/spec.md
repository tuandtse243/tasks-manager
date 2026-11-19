# Spec Delta

## MODIFIED Requirements

### Requirement: Brief là đầu ra duy nhất
Lệnh `/discover` SHALL nhận một ý tưởng, một yêu cầu, hoặc đường dẫn tới tài liệu yêu cầu, và ghi kết quả vào `<planning.dir>/<slug>/brief.md`. Ngoài brief, lệnh chỉ được ghi các bảng câu hỏi cho người vắng mặt trong cùng thư mục plan đó. Lệnh MUST NOT ghi gì lên GitHub và MUST NOT sửa file nào ngoài thư mục plan đó.

#### Scenario: Ý tưởng mơ hồ
- **WHEN** người dùng chạy `/discover` với "cho người dùng bình luận dưới bài viết"
- **THEN** sau khi người dùng xác nhận, `docs/plans/<slug>/brief.md` được ghi, và không có issue, label hay milestone nào được tạo

#### Scenario: Người dùng dừng giữa chừng
- **WHEN** người dùng huỷ trong lúc phỏng vấn
- **THEN** lệnh hỏi có lưu bản nháp không, và chỉ ghi file khi người dùng đồng ý

#### Scenario: Có bảng câu hỏi
- **WHEN** `/discover` soạn một bảng câu hỏi cho product owner
- **THEN** file bảng câu hỏi nằm trong `docs/plans/<slug>/` cạnh `brief.md`, và không file nào ngoài thư mục đó thay đổi

## ADDED Requirements

### Requirement: Bảng câu hỏi cho người vắng mặt
Khi một quyết định thuộc về người không có mặt trong phiên, `/discover` SHALL đề nghị soạn một bảng câu hỏi gửi cho người đó thay vì ghi một giả định. Nếu người dùng đồng ý, lệnh SHALL hỏi người dùng về người nhận và điều cần nhận lại, rồi ghi bảng câu hỏi vào thư mục plan. Brief khi đó MUST giữ trạng thái nháp và liệt kê các câu hỏi còn mở kèm tên file bảng câu hỏi.

#### Scenario: Quyết định của product owner
- **WHEN** người dùng nói mức phí hoa hồng do product owner quyết và họ không biết
- **THEN** lệnh đề nghị soạn bảng câu hỏi cho product owner, và khi người dùng đồng ý thì ghi file bảng câu hỏi trong thư mục plan

#### Scenario: Brief chờ câu trả lời
- **WHEN** một bảng câu hỏi đã được ghi và chưa có câu trả lời
- **THEN** brief có trạng thái nháp, có mục câu hỏi còn mở nêu từng câu và tên file bảng câu hỏi, và lệnh không in bước kế tiếp `/plan`

#### Scenario: Người dùng không muốn gửi
- **WHEN** người dùng từ chối soạn bảng câu hỏi
- **THEN** điều chưa biết được ghi thành một giả định cụ thể trong mục giả định, như trước

#### Scenario: Câu trả lời đã về
- **WHEN** người dùng chạy lại `/discover` trên cùng thư mục plan sau khi bảng câu hỏi đã được điền
- **THEN** lệnh đọc các câu trả lời, ghi chúng vào mục quyết định, bỏ các câu đó khỏi mục câu hỏi còn mở, và tiếp tục tới bước xác nhận

### Requirement: Thuật ngữ nhất quán với glossary
Trong repo có tài liệu ngữ cảnh dự án, `/discover` SHALL đối chiếu thuật ngữ người dùng dùng với mục glossary của tài liệu đó: nêu ngay khi một từ được dùng khác nghĩa đã ghi, và đề nghị một từ chính xác khi một từ mơ hồ hoặc mang hai nghĩa. Thuật ngữ đã chốt SHALL được ghi trong brief. Lệnh MUST NOT sửa tài liệu ngữ cảnh dự án.

#### Scenario: Dùng khác nghĩa
- **WHEN** glossary định nghĩa "huỷ đơn" là huỷ toàn bộ đơn và người dùng nói về huỷ một phần đơn
- **THEN** lệnh nêu chỗ khác nhau và hỏi người dùng ý nào đúng trước khi tiếp tục

#### Scenario: Từ mơ hồ
- **WHEN** người dùng nói "tài khoản" trong khi dự án có cả khách hàng và người dùng đăng nhập
- **THEN** lệnh hỏi người dùng muốn nói khái niệm nào và brief dùng từ đã chọn

#### Scenario: Thuật ngữ mới
- **WHEN** phỏng vấn chốt một thuật ngữ chưa có trong glossary
- **THEN** brief ghi thuật ngữ đó cùng nghĩa của nó trong mục quyết định, và tài liệu ngữ cảnh dự án không đổi

#### Scenario: Chưa có tài liệu ngữ cảnh
- **WHEN** repo chưa có tài liệu ngữ cảnh dự án
- **THEN** lệnh vẫn làm rõ từ mơ hồ với người dùng và không báo lỗi vì thiếu glossary
