# task-management Specification

## Purpose

Tạo và điều khiển task (mỗi task là một issue GitHub) trong sprint: tạo task đúng chuẩn label, để AI đề xuất tách một feature thành các task có điểm, bắt đầu làm một task, và giữ trạng thái task luôn duy nhất.

## Requirements

### Requirement: Tạo task
Hệ thống SHALL tạo task thành một issue mở có tiêu đề, mô tả, label `status: New`, label điểm nếu có, người được giao nếu có, và thuộc sprint hiện tại hoặc sprint chỉ định. Điểm ngoài thang điểm MUST bị từ chối trước khi ghi.

#### Scenario: Task đầy đủ
- **WHEN** người dùng chạy `/task-new` với tiêu đề "Sign up via email, Facebook, LinkedIn", 7 điểm, giao cho `ruby`, trong `Sprint 1`
- **THEN** issue mới có label `status: New` và `points: 7`, assignee `ruby`, milestone `Sprint 1`, và lệnh in số issue cùng link

#### Scenario: Điểm không hợp lệ
- **WHEN** thang điểm là 0, 1, 3, 7 và người dùng tạo task 5 điểm
- **THEN** lệnh từ chối, liệt kê điểm hợp lệ, và không tạo issue

#### Scenario: Task là bug
- **WHEN** người dùng tạo task và đánh dấu là bug
- **THEN** issue có thêm label `bug`

#### Scenario: Chưa ước lượng
- **WHEN** người dùng tạo task không có điểm
- **THEN** issue được tạo không có label điểm

### Requirement: Trạng thái task là duy nhất
Một task SHALL có nhiều nhất một label trạng thái. Mọi thao tác đặt trạng thái MUST gỡ các label trạng thái khác của task đó.

#### Scenario: Chuyển sang In progress
- **WHEN** task #1 đang có `status: New` và được chuyển sang In progress
- **THEN** task #1 có `status: In progress` và không còn `status: New`

#### Scenario: Có nhiều trạng thái do sửa tay
- **WHEN** task có cả `status: New` và `status: Done` rồi được chuyển sang In progress
- **THEN** task chỉ còn `status: In progress`

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

### Requirement: Bắt đầu task
Lệnh bắt đầu task SHALL, với một issue đang mở: giao issue cho người dùng hiện tại nếu chưa ai được giao, chuyển trạng thái sang In progress, và tạo rồi checkout branch cục bộ đặt tên theo mẫu branch tính từ branch mặc định. Lệnh MUST từ chối với issue đã đóng.

#### Scenario: Bắt đầu task mới
- **WHEN** người dùng `david` chạy `/task-start 2` cho issue #2 "Login" chưa giao ai
- **THEN** issue #2 được giao cho `david`, có `status: In progress`, và branch `feat/2-login` được tạo từ branch mặc định và checkout

#### Scenario: Branch đã tồn tại
- **WHEN** branch `feat/2-login` đã có cục bộ
- **THEN** lệnh checkout branch đó thay vì tạo mới

#### Scenario: Issue đã đóng
- **WHEN** người dùng chạy `/task-start` cho một issue đã đóng
- **THEN** lệnh từ chối và không đổi gì trên GitHub hay git cục bộ

#### Scenario: Đã giao cho người khác
- **WHEN** issue đã giao cho `ruby` và `david` chạy `/task-start`
- **THEN** người được giao giữ nguyên, trạng thái vẫn chuyển sang In progress, và lệnh nhắc issue đang giao cho `ruby`

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

### Requirement: Liệt kê task
Lệnh `scrum task list` SHALL liệt kê task của sprint hiện tại (mặc định), của một sprint (`--sprint S`) hoặc của backlog (`--backlog`), lọc được theo người dùng hiện tại (`--mine`) và theo trạng thái (`--status new|in_progress|done`). Mỗi dòng có số, trạng thái, điểm, người nhận và tiêu đề. Với `--json`, lệnh in JSON. Lệnh chỉ đọc.

#### Scenario: Task của tôi đang làm
- **WHEN** người dùng chạy `scrum task list --mine --status in_progress`
- **THEN** chỉ các task In progress giao cho người dùng trong sprint hiện tại được in

#### Scenario: Backlog
- **WHEN** người dùng chạy `scrum task list --backlog`
- **THEN** các task đang mở không có milestone được in

### Requirement: Chuyển task giữa sprint và backlog
Lệnh `scrum task move N… --sprint S` hoặc `--backlog` SHALL gán milestone của sprint S (phải đang mở) hoặc bỏ milestone cho từng task, rồi ghi một comment nêu nguồn và đích. Task đã đóng hoặc issue không phải task MUST bị từ chối trước khi ghi bất cứ gì.

#### Scenario: Đưa về backlog
- **WHEN** người dùng chạy `scrum task move 12 --backlog` cho task #12 trong Sprint 4
- **THEN** #12 không còn milestone, và có comment "Moved from Sprint 4 to the backlog"

#### Scenario: Sprint đã đóng
- **WHEN** người dùng chuyển task vào Sprint 2 đã đóng
- **THEN** lệnh dừng, nói Sprint 2 đã đóng, và không ghi gì

### Requirement: Ước lượng lại task
Lệnh `scrum task estimate N POINTS` SHALL thay label điểm của task bằng đúng một label điểm mới. Giá trị không có trong thang điểm MUST bị từ chối trước khi ghi và lệnh nêu các giá trị hợp lệ.

#### Scenario: Đổi điểm
- **WHEN** task #12 có `points: 3` và người dùng chạy `scrum task estimate 12 7`
- **THEN** #12 có `points: 7` và không còn `points: 3`

#### Scenario: Ngoài thang điểm
- **WHEN** thang điểm là 0, 1, 3, 7 và người dùng chạy `scrum task estimate 12 5`
- **THEN** lệnh dừng, nêu các giá trị hợp lệ, và không ghi gì

### Requirement: Giao task
Lệnh `scrum task assign N LOGIN…` SHALL thêm người nhận cho task; với `--unassign`, lệnh SHALL gỡ những người đó. `@` ở đầu login được bỏ qua.

#### Scenario: Giao
- **WHEN** người dùng chạy `scrum task assign 12 @alice bob`
- **THEN** alice và bob là người nhận của #12

#### Scenario: Gỡ giao
- **WHEN** người dùng chạy `scrum task assign 12 alice --unassign`
- **THEN** alice không còn là người nhận của #12

### Requirement: Bỏ task
Lệnh `scrum task drop N [--reason TEXT]` SHALL đóng task với lý do "not planned", để task không tính vào điểm hay velocity, và ghi comment kèm lý do khi có.

#### Scenario: Bỏ task có lý do
- **WHEN** người dùng chạy `scrum task drop 12 --reason "Đã có thư viện làm việc này"`
- **THEN** #12 đóng với lý do not planned, có comment chứa lý do, và không tính vào velocity của sprint

### Requirement: Skill cho các lệnh task
Skill `/scrum-github:task` SHALL nhận yêu cầu bằng lời về liệt kê, chuyển, ước lượng, giao hoặc bỏ task, chạy lệnh tương ứng, và với lệnh ghi MUST nói lại thay đổi sẽ làm và chờ người dùng đồng ý trước khi chạy.

#### Scenario: Yêu cầu bằng lời
- **WHEN** người dùng gõ `/scrum-github:task đưa #12 về backlog`
- **THEN** skill nói sẽ chuyển #12 về backlog, chờ đồng ý, rồi chạy `scrum task move 12 --backlog`

### Requirement: Lệnh task với In review
Khi `statuses.in_review` đặt, `scrum task list --status in_review` SHALL liệt kê task In review, và mọi thao tác đặt trạng thái MUST giữ đúng một label trạng thái trong bốn trạng thái. Khi không đặt, `--status in_review` MUST bị từ chối và nêu cách bật.

#### Scenario: Liệt kê task chờ review
- **WHEN** In review bật và người dùng chạy `scrum task list --status in_review`
- **THEN** chỉ task có label In review được in

#### Scenario: Tắt
- **WHEN** In review không bật và người dùng chạy `scrum task list --status in_review`
- **THEN** lệnh dừng và nói cần đặt `statuses.in_review`
