# Spec Delta

## MODIFIED Requirements

### Requirement: AI đề xuất tách feature thành task
Lệnh lập kế hoạch `/plan` SHALL nhận một brief, một mô tả yêu cầu, hoặc đường dẫn tới một trong hai, và trình bày danh sách task đề xuất, mỗi task có tiêu đề, mô tả, tiêu chí hoàn thành và điểm trong thang điểm. Bản đề xuất SHALL được lưu thành plan file và bản xem ở local trước khi người dùng duyệt. Hệ thống MUST NOT tạo issue nào trước khi người dùng duyệt, và người dùng MUST sửa được, bỏ được hoặc thêm được task trước khi duyệt.

#### Scenario: Duyệt đề xuất
- **WHEN** người dùng chạy `/plan` với feature "Blog post comments", sửa điểm một task rồi duyệt
- **THEN** một issue feature có label `type: feature` được tạo, các task được tạo với điểm đã sửa, mỗi task được gắn làm sub-issue của issue feature, và plan file ghi số của từng issue

#### Scenario: Không duyệt
- **WHEN** người dùng xem đề xuất rồi huỷ
- **THEN** không có issue nào được tạo, và plan file vẫn nằm ở local để dùng lại

#### Scenario: Điểm đề xuất nằm trong thang
- **WHEN** thang điểm là 0, 1, 3, 7
- **THEN** mọi điểm trong đề xuất thuộc tập 0, 1, 3, 7

#### Scenario: Repo không hỗ trợ sub-issue
- **WHEN** gắn sub-issue bị GitHub từ chối
- **THEN** issue feature được cập nhật với danh sách checkbox tham chiếu tới từng task và lệnh báo đã dùng cách dự phòng

#### Scenario: Lập plan từ brief
- **WHEN** người dùng chạy `/plan docs/plans/comments/brief.md`
- **THEN** plan được ghi tại `docs/plans/comments/plan.json`, và các task chỉ nằm trong phần "trong scope" của brief

#### Scenario: Sửa plan đã có
- **WHEN** thư mục plan đã có `plan.json` và người dùng chạy `/plan` cho cùng yêu cầu
- **THEN** lệnh đọc plan hiện có, giữ nguyên `id` và số issue của các task không đổi, và chỉ thêm, sửa hoặc bỏ theo yêu cầu của người dùng

## ADDED Requirements

### Requirement: Kiểm tra độ rõ trước khi chia task
Trước khi chia task, `/plan` SHALL kiểm tra đầu vào có nêu được: ai dùng, kết quả mong muốn, và điều kiện coi là xong. Khi thiếu, lệnh SHALL nêu phần thiếu và đề nghị chạy `/discover` trước. Người dùng MUST chọn được tiếp tục; khi đó lệnh ghi các phần thiếu thành giả định trong plan.

#### Scenario: Đầu vào đủ rõ
- **WHEN** người dùng đưa một brief đã được xác nhận
- **THEN** lệnh chia task ngay mà không đề nghị `/discover`

#### Scenario: Đầu vào mơ hồ
- **WHEN** người dùng chạy `/plan` với "làm cho app nhanh hơn"
- **THEN** lệnh nêu chưa rõ kết quả mong muốn và điều kiện xong, và đề nghị chạy `/discover`

#### Scenario: Người dùng vẫn tiếp tục
- **WHEN** lệnh đề nghị `/discover` và người dùng chọn tiếp tục
- **THEN** plan được lập và mục giả định của plan ghi các phần còn thiếu

### Requirement: Quy tắc chia task
Mỗi task trong đề xuất SHALL là một lát cắt dọc: tự nó cho ra một hành vi kiểm tra được, không phải một tầng kỹ thuật đứng riêng. Task cần nhiều hơn điểm lớn nhất của thang MUST được tách. Thứ tự bắt buộc giữa các task SHALL được ghi bằng phụ thuộc, không bằng thứ tự trong danh sách. Yêu cầu gồm nhiều luồng độc lập SHALL được chia thành nhiều feature dưới một epic.

#### Scenario: Task quá lớn
- **WHEN** thang điểm lớn nhất là 7 và một phần việc được ước lượng lớn hơn 7
- **THEN** đề xuất tách phần việc đó thành nhiều task, mỗi task có điểm trong thang

#### Scenario: Có thứ tự bắt buộc
- **WHEN** task hiển thị bình luận cần task lưu bình luận xong trước
- **THEN** task hiển thị có phụ thuộc tới task lưu

#### Scenario: Thay đổi rộng không cắt dọc được
- **WHEN** yêu cầu là đổi tên một cột dùng ở khắp mã
- **THEN** đề xuất chia theo mở rộng, chuyển dần từng phần, rồi thu gọn, và mỗi bước chuyển phụ thuộc bước mở rộng

### Requirement: Soát độc lập bản chia task
Trước khi trình bày cho người dùng, `/plan` SHALL đưa bản chia task cho một agent chỉ đọc soát: task thiếu so với scope, task ngoài scope, task quá lớn, phụ thuộc thiếu hoặc thừa, và tiêu chí hoàn thành không kiểm tra được. Lệnh SHALL trình bày các phát hiện cùng bản đề xuất. Với mức `quick`, bước này được bỏ.

#### Scenario: Có phát hiện
- **WHEN** brief có luồng xoá bình luận nhưng bản chia task không có task nào cho nó
- **THEN** bản đề xuất kèm phát hiện thiếu task cho luồng xoá bình luận

#### Scenario: Mức nhanh
- **WHEN** người dùng chạy `/plan --quick`
- **THEN** lệnh không khởi chạy agent soát
