# Spec Delta

## MODIFIED Requirements

### Requirement: Soát độc lập bản chia task
Trước khi trình bày cho người dùng, `/plan` SHALL đưa bản chia task cho một agent chỉ đọc soát: task thiếu so với scope, task ngoài scope, task quá lớn, phụ thuộc thiếu hoặc thừa, tiêu chí hoàn thành không kiểm tra được, và mô tả task dễ lỗi thời. Lệnh SHALL trình bày các phát hiện cùng bản đề xuất. Với mức `quick`, bước này được bỏ.

#### Scenario: Có phát hiện
- **WHEN** brief có luồng xoá bình luận nhưng bản chia task không có task nào cho nó
- **THEN** bản đề xuất kèm phát hiện thiếu task cho luồng xoá bình luận

#### Scenario: Mức nhanh
- **WHEN** người dùng chạy `/plan --quick`
- **THEN** lệnh không khởi chạy agent soát

#### Scenario: Mô tả dẫn số dòng
- **WHEN** mô tả một task viết "sửa hàm ở dòng 150 của file handler"
- **THEN** bản đề xuất kèm phát hiện mô tả dễ lỗi thời cho task đó, với gợi ý mô tả hành vi mong muốn

## ADDED Requirements

### Requirement: Mô tả task bền
Mô tả và tiêu chí hoàn thành của task do AI soạn SHALL nói hệ thống phải làm gì, không nói cách sửa mã: không dẫn đường dẫn file hay số dòng, được nêu tên kiểu, hàm hay dạng cấu hình cần đổi. Mỗi tiêu chí hoàn thành SHALL kiểm tra được một cách độc lập. Điều dễ bị hiểu nhầm là thuộc task SHALL được nêu là ngoài phạm vi.

#### Scenario: Task trong plan
- **WHEN** `/plan` soạn task "Lưu bình luận"
- **THEN** mô tả nêu hành vi trước và sau khi làm xong, không có đường dẫn file hay số dòng, và mỗi tiêu chí hoàn thành là một điều kiểm tra được

#### Scenario: Ranh giới phạm vi
- **WHEN** task "Lưu bình luận" không gồm việc sửa bình luận
- **THEN** mô tả task nêu sửa bình luận là ngoài phạm vi

#### Scenario: Người dùng tự viết mô tả
- **WHEN** người dùng chạy `/task-new` và tự đưa mô tả có đường dẫn file
- **THEN** lệnh giữ nguyên mô tả của người dùng

#### Scenario: Nhờ soạn mô tả
- **WHEN** người dùng chạy `/task-new` chỉ với tiêu đề và nhờ soạn mô tả
- **THEN** mô tả được soạn theo các quy tắc trên và được đưa cho người dùng xem trước khi tạo issue
