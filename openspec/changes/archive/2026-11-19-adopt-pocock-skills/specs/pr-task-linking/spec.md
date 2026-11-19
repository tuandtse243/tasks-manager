# Spec Delta

## ADDED Requirements

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
