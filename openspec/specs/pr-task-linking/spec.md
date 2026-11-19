# pr-task-linking Specification

## Purpose

Nối pull request với task và để trạng thái task tự chạy theo vòng đời PR và issue, thay cho việc dev tự ghi `Solve #n` và tự đổi label như trong quy trình thủ công.

## Requirements

### Requirement: Nhận diện liên kết PR với task
Một PR SHALL được coi là liên kết với task #n khi mô tả PR chứa một closing keyword của GitHub (`close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`, `resolved`, không phân biệt hoa thường) theo sau là `#n` hoặc `owner/repo#n` của chính repo đó. Các từ khác như `Solve` MUST NOT tạo liên kết.

#### Scenario: Closes
- **WHEN** mô tả PR chứa "Closes #1"
- **THEN** PR liên kết với task #1

#### Scenario: Nhiều task
- **WHEN** mô tả PR chứa "fixes #2, resolves #3"
- **THEN** PR liên kết với task #2 và #3

#### Scenario: Từ khoá Solve của tài liệu cũ
- **WHEN** mô tả PR chỉ chứa "Solve #1"
- **THEN** PR không liên kết với task nào

#### Scenario: Repo khác
- **WHEN** mô tả PR chứa "Closes other-org/other-repo#5"
- **THEN** liên kết đó bị bỏ qua

### Requirement: Kiểm tra PR có liên kết task
Mỗi khi PR được mở, sửa, mở lại, đổi label hoặc chuyển sang ready for review, hệ thống SHALL chạy một check báo thất bại nếu PR không liên kết task nào và không có label bỏ qua (`no-task`), và báo thành công trong các trường hợp còn lại.

#### Scenario: Thiếu liên kết
- **WHEN** PR được mở với mô tả không có closing keyword
- **THEN** check thất bại với thông báo hướng dẫn thêm "Closes #<số task>" hoặc label `no-task`

#### Scenario: Dùng Solve
- **WHEN** mô tả PR chứa "Solve #1"
- **THEN** check thất bại và thông báo gợi ý đổi thành "Closes #1"

#### Scenario: Sửa mô tả
- **WHEN** check đã thất bại và người dùng sửa mô tả thêm "Closes #1"
- **THEN** check chạy lại và thành công

#### Scenario: Label bỏ qua
- **WHEN** PR không có liên kết nhưng có label `no-task`
- **THEN** check thành công

### Requirement: Trạng thái theo vòng đời PR
Khi một PR liên kết được mở, mở lại hoặc chuyển sang ready for review, hệ thống SHALL chuyển các task liên kết đang mở có trạng thái New hoặc chưa có trạng thái sang In progress. Khi PR được merge, hệ thống SHALL chuyển các task liên kết sang Done và đóng chúng với lý do hoàn thành nếu còn mở. PR đóng mà không merge MUST NOT đổi trạng thái task.

#### Scenario: Mở PR
- **WHEN** PR với "Closes #1" được mở và task #1 đang `status: New`
- **THEN** task #1 chuyển sang `status: In progress`

#### Scenario: Merge PR
- **WHEN** PR với "Closes #1" được merge
- **THEN** task #1 có `status: Done` và đã đóng với lý do hoàn thành

#### Scenario: Merge vào branch không phải mặc định
- **WHEN** PR với "Closes #1" được merge vào một branch khác branch mặc định
- **THEN** task #1 vẫn được chuyển sang Done và đóng

#### Scenario: Không lùi trạng thái
- **WHEN** PR được mở lại cho task #1 đang `status: Done` và đã đóng
- **THEN** trạng thái task #1 không đổi

#### Scenario: Đóng PR không merge
- **WHEN** PR với "Closes #1" bị đóng mà không merge
- **THEN** trạng thái task #1 giữ nguyên

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

### Requirement: Soạn mô tả PR cho task
Lệnh `/task-pr` SHALL soạn mô tả pull request cho task của nhánh hiện tại gồm bốn phần: tóm tắt thay đổi bằng hình thức ngắn nhất làm rõ ý chính, bằng chứng trước và sau, mức nguy hiểm khi merge (đảo ngược được hay không, phạm vi ảnh hưởng), và dòng `Closes #n` của task. Lệnh MUST đưa mô tả cho người dùng duyệt trước khi tạo hoặc sửa PR.

#### Scenario: Nhánh của một task
- **WHEN** người dùng chạy `/task-pr` trên nhánh `feat/12-binh-luan` có commit so với nhánh mặc định
- **THEN** mô tả được soạn có đủ bốn phần và chứa "Closes #12", và chưa có PR nào được tạo

#### Scenario: Người dùng duyệt
- **WHEN** người dùng duyệt mô tả
- **THEN** PR được tạo với mô tả đó, và check liên kết task của PR thành công

#### Scenario: PR đã có
- **WHEN** nhánh hiện tại đã có một PR đang mở
- **THEN** lệnh đề nghị sửa mô tả của PR đó thay vì tạo PR mới, và chỉ sửa sau khi người dùng duyệt

#### Scenario: Không xác định được task
- **WHEN** tên nhánh không chứa số task và người dùng không đưa số
- **THEN** lệnh hỏi số task, hoặc đề nghị dùng label `no-task` nếu PR không thuộc task nào

#### Scenario: Không có bằng chứng chạy được
- **WHEN** thay đổi không có test hay kết quả chạy nào để dẫn
- **THEN** phần bằng chứng nói rõ là chưa có, và lệnh không bịa kết quả

#### Scenario: Nhánh chưa có thay đổi
- **WHEN** nhánh hiện tại không có commit nào so với nhánh mặc định
- **THEN** lệnh báo chưa có gì để mở PR và dừng
