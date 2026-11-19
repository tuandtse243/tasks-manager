# requirement-discovery Specification

## Purpose

Biến một ý tưởng hoặc yêu cầu chưa rõ thành một brief đã chốt scope, bằng cách tìm hiểu, phỏng vấn người dùng và kiểm tra độ phù hợp với dự án có sẵn, trước khi chia thành task.

## Requirements

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

### Requirement: Nội dung brief
Brief SHALL có các mục: vấn đề, giải pháp, người dùng và user story, trong scope, ngoài scope, quyết định đã chốt, giả định, rủi ro, và phụ lục hỏi đáp. Brief của một repo đã có mã SHALL có thêm mục độ phù hợp với dự án. Brief có nghiên cứu web SHALL có mục nguồn tham khảo.

#### Scenario: Brief đầy đủ
- **WHEN** `/discover` kết thúc cho một ý tưởng trong repo chưa có mã, không dùng nghiên cứu web
- **THEN** brief có đủ chín mục bắt buộc và không có mục độ phù hợp hay nguồn tham khảo

### Requirement: Phỏng vấn theo vòng
`/discover` SHALL hỏi người dùng theo vòng: mỗi vòng gồm các câu hỏi có thể trả lời ngay mà không phụ thuộc câu hỏi còn mở khác, đánh số, mỗi câu kèm câu trả lời đề xuất. Lệnh MUST chờ người dùng trả lời trước vòng kế tiếp, và MUST ghi mọi câu hỏi, đề xuất và câu trả lời vào phụ lục của brief.

#### Scenario: Một vòng
- **WHEN** còn ba quyết định mở, trong đó quyết định thứ ba phụ thuộc quyết định thứ nhất
- **THEN** vòng này hỏi hai câu đầu, mỗi câu có đề xuất, và câu thứ ba được hỏi ở vòng sau

#### Scenario: Ghi lại
- **WHEN** người dùng trả lời khác với đề xuất ở câu 2
- **THEN** phụ lục của brief ghi câu hỏi, đề xuất và câu trả lời của người dùng

### Requirement: Các nhóm phải làm rõ
Trước khi kết thúc, `/discover` SHALL bảo đảm các nhóm sau đã được trả lời hoặc được ghi là ngoài scope: người dùng và vai trò, luồng chính, dữ liệu và vòng đời của nó, trường hợp biên và lỗi, yêu cầu phi chức năng, tích hợp, ràng buộc (hạn, ngân sách, hạ tầng), và phần ngoài scope.

#### Scenario: Thiếu một nhóm
- **WHEN** người dùng chưa nói gì về trường hợp biên và lệnh sắp kết thúc
- **THEN** lệnh hỏi thêm một vòng về trường hợp biên trước khi ghi brief

#### Scenario: Chủ động bỏ qua
- **WHEN** người dùng nói tích hợp không liên quan tới yêu cầu này
- **THEN** brief ghi tích hợp trong mục ngoài scope và lệnh không hỏi lại

### Requirement: Sự thật và quyết định
`/discover` MUST NOT hỏi người dùng điều có thể tìm trong repo hay trên web; lệnh SHALL tự tìm. Mọi quyết định về scope, ưu tiên và lựa chọn giải pháp SHALL được đưa cho người dùng quyết. Điều lệnh phải đoán vì không ai trả lời được MUST được ghi vào mục giả định của brief.

#### Scenario: Sự thật trong mã
- **WHEN** cần biết dự án dùng cơ sở dữ liệu nào và repo có file cấu hình trả lời được
- **THEN** lệnh đọc repo và không hỏi người dùng

#### Scenario: Giả định
- **WHEN** người dùng không biết số lượng người dùng đồng thời dự kiến
- **THEN** brief ghi một giả định có con số cụ thể trong mục giả định

### Requirement: Nghiên cứu bên ngoài
Khi yêu cầu cần thông tin ngoài repo, `/discover` SHALL giao việc tìm kiếm cho một agent chỉ đọc và nhận về các phát hiện kèm nguồn. Phát hiện không có nguồn MUST NOT được ghi vào brief như sự thật. Khi không có công cụ tìm kiếm web, lệnh SHALL bỏ bước này và nói rõ với người dùng.

#### Scenario: Có nghiên cứu
- **WHEN** ý tưởng cần so sánh hai dịch vụ thanh toán
- **THEN** brief có mục nguồn tham khảo với đường dẫn cho từng phát hiện được dùng

#### Scenario: Không có web
- **WHEN** phiên làm việc không có công cụ tìm kiếm web
- **THEN** lệnh báo đã bỏ nghiên cứu web và tiếp tục với phần còn lại

### Requirement: Độ sâu
`/discover` SHALL có ba mức: `quick` (không dùng agent, một vòng hỏi), `standard` (mặc định), và `deep` (thêm nghiên cứu web và soát độc lập). Người dùng chọn mức bằng tham số; khi không chọn, lệnh dùng `standard`.

#### Scenario: Mức nhanh
- **WHEN** người dùng chạy `/discover --quick` với một yêu cầu nhỏ
- **THEN** lệnh không khởi chạy agent nào và hỏi tối đa một vòng

### Requirement: Kiểm tra độ phù hợp với dự án
Trong repo đã có mã, `/discover` SHALL đọc tài liệu ngữ cảnh dự án và nêu trong brief: kết luận (phù hợp, phù hợp nếu có thay đổi, hoặc xung đột), các vùng của dự án bị ảnh hưởng, quy ước phải theo, và những gì không được phá. Kết luận xung đột MUST được đưa cho người dùng quyết định trước khi tiếp tục.

#### Scenario: Phù hợp
- **WHEN** feature mới dùng lại mô hình dữ liệu và luồng xác thực đang có
- **THEN** brief ghi kết luận phù hợp và liệt kê các vùng bị ảnh hưởng

#### Scenario: Xung đột
- **WHEN** feature cần lưu trạng thái trên máy chủ trong khi dự án được thiết kế không trạng thái
- **THEN** lệnh nêu xung đột, đưa các phương án, và chờ người dùng chọn trước khi ghi brief

#### Scenario: Chưa có tài liệu ngữ cảnh
- **WHEN** repo có mã nhưng chưa có tài liệu ngữ cảnh dự án
- **THEN** lệnh đề nghị chạy `/project-scan` trước, và nếu người dùng từ chối thì chỉ đọc các phần mã liên quan tới feature

### Requirement: Ước lượng độ phức tạp
Brief SHALL nêu cỡ của yêu cầu: một task, một feature (nhiều task), hoặc một epic (nhiều feature), kèm lý do. `/plan` SHALL dùng cỡ này làm điểm xuất phát cho cấu trúc plan.

#### Scenario: Yêu cầu nhỏ
- **WHEN** yêu cầu chỉ chạm một màn hình và không đổi dữ liệu
- **THEN** brief ghi cỡ là một task và đề nghị dùng `/task-new` thay cho một plan

#### Scenario: Yêu cầu lớn
- **WHEN** yêu cầu gồm ba luồng người dùng độc lập
- **THEN** brief ghi cỡ là epic và nêu ba feature dự kiến

### Requirement: Xác nhận trước khi kết thúc
`/discover` SHALL trình bày tóm tắt scope, giả định và rủi ro, và chỉ coi brief là xong khi người dùng xác nhận. Sau khi xác nhận, lệnh SHALL nêu bước kế tiếp là `/plan` với đường dẫn brief.

#### Scenario: Xác nhận
- **WHEN** người dùng xác nhận tóm tắt
- **THEN** brief được ghi và lệnh in `/scrum-github:plan docs/plans/<slug>/brief.md` làm bước kế tiếp

#### Scenario: Còn sửa
- **WHEN** người dùng muốn bỏ một mục khỏi scope
- **THEN** lệnh sửa brief, trình bày lại tóm tắt và chờ xác nhận

### Requirement: Kiểm tra cấu trúc brief
`scrum doc check FILE` SHALL kiểm tra brief có đủ các mục bắt buộc, in tên từng mục thiếu, và kết thúc với mã khác 0 khi thiếu. Lệnh MUST chạy không cần mạng. `/discover` SHALL chạy kiểm tra này trước khi trình bày tóm tắt cho người dùng.

#### Scenario: Brief đủ mục
- **WHEN** brief có đủ chín mục bắt buộc
- **THEN** lệnh kết thúc với mã 0

#### Scenario: Brief thiếu mục
- **WHEN** brief không có mục rủi ro
- **THEN** lệnh nêu mục rủi ro còn thiếu và kết thúc với mã khác 0

#### Scenario: Mục tuỳ chọn
- **WHEN** brief không có mục độ phù hợp với dự án và mục nguồn tham khảo
- **THEN** lệnh không coi đó là lỗi

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
