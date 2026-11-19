# work-plan Specification

## Purpose

Lưu bản chia việc của một requirement thành một plan file trong repo đích, để người dùng xem và duyệt ở local, rồi đưa lên GitHub thành epic, feature và task mà chạy lại không tạo trùng.

## Requirements

### Requirement: Vị trí plan file
Plan của một requirement SHALL nằm tại `<planning.dir>/<slug>/plan.json` trong repo đích, với `<slug>` là tên viết thường nối bằng gạch ngang. Bản xem `plan.md` và brief (nếu có) nằm cùng thư mục. Các lệnh plan MUST nhận đường dẫn file bất kỳ, không chỉ file trong `planning.dir`.

#### Scenario: Plan mới
- **WHEN** `planning.dir` là `docs/plans` và người dùng lập plan cho "Blog post comments"
- **THEN** plan được ghi tại `docs/plans/blog-post-comments/plan.json`

#### Scenario: File ở chỗ khác
- **WHEN** người dùng chạy `scrum plan validate /tmp/x.json`
- **THEN** lệnh kiểm tra file đó

### Requirement: Khởi tạo thư mục plan
`scrum plan init "<tiêu đề>"` SHALL tính slug từ tiêu đề, hoặc dùng slug của `--slug`, tạo thư mục `<planning.dir>/<slug>/` nếu chưa có, và in dạng JSON: slug, đường dẫn thư mục, plan file, bản xem, brief, và file nào trong số đó đã tồn tại. Lệnh MUST chạy không cần mạng, MUST NOT ghi đè file đã có, và MUST từ chối slug chứa ký tự ngoài chữ thường, số và gạch ngang.

#### Scenario: Thư mục mới
- **WHEN** người dùng chạy `scrum plan init "Blog post comments"` và `planning.dir` là `docs/plans`
- **THEN** thư mục `docs/plans/blog-post-comments/` được tạo và lệnh in đường dẫn `docs/plans/blog-post-comments/plan.json`

#### Scenario: Slug cho sẵn
- **WHEN** người dùng chạy `scrum plan init "Bình luận dưới bài viết" --slug binh-luan-bai-viet`
- **THEN** thư mục là `docs/plans/binh-luan-bai-viet/`

#### Scenario: Thư mục đã có plan
- **WHEN** `docs/plans/blog-post-comments/plan.json` đã tồn tại và người dùng chạy lại lệnh
- **THEN** lệnh báo plan file đã tồn tại và không file nào thay đổi

#### Scenario: Slug không hợp lệ
- **WHEN** người dùng truyền `--slug "Blog Post"`
- **THEN** lệnh dừng với mã khác 0 và không tạo thư mục

### Requirement: Kiểm tra gộp trước khi duyệt
`scrum plan check FILE` SHALL chạy lần lượt kiểm tra plan, sinh bản xem, và in các thao tác mà `plan apply` sẽ làm, trong một lần gọi. Lệnh MUST dừng với mã khác 0 ở bước đầu tiên lỗi, MUST NOT ghi gì lên GitHub hay vào plan file, và với `--offline` SHALL bỏ bước in thao tác.

#### Scenario: Plan hợp lệ
- **WHEN** người dùng chạy `scrum plan check` với một plan hợp lệ chưa áp
- **THEN** bản xem được ghi, lệnh in các thao tác tạo sẽ làm, và GitHub không đổi

#### Scenario: Plan lỗi
- **WHEN** plan có điểm ngoài thang
- **THEN** lệnh in lỗi, kết thúc với mã khác 0, và không ghi bản xem

#### Scenario: Không có mạng
- **WHEN** người dùng chạy `scrum plan check FILE --offline`
- **THEN** lệnh kiểm tra và sinh bản xem, không gọi GitHub

### Requirement: Định dạng plan phiên bản 2
Plan phiên bản 2 SHALL có `version: 2`, `title`, và danh sách `features` không rỗng; mỗi feature có `id`, `title` và danh sách `tasks` không rỗng. Mỗi task có `id` và `title`, và có thể có `body`, `acceptance`, `subtasks`, `points`, `depends_on`, `assignees`, `bug`, `sprint`. Plan có thể có `epic`, `sprint`, `assumptions`, `out_of_scope`. Epic, feature và task có trường `issue`, rỗng cho tới khi được tạo trên GitHub.

#### Scenario: Plan tối thiểu
- **WHEN** plan có `version: 2`, `title`, một feature `F1` với một task `T1` có tiêu đề
- **THEN** plan hợp lệ

#### Scenario: Plan có epic
- **WHEN** plan có `epic.title` và hai feature
- **THEN** plan hợp lệ và được coi là một epic chứa hai feature

### Requirement: Đọc được plan phiên bản 1
Lệnh plan SHALL nhận plan không có `version` theo định dạng cũ (một `feature` và danh sách `tasks`), và coi nó là plan phiên bản 2 có một feature. Với plan phiên bản 1, `sprint` bỏ trống MUST nghĩa là sprint hiện tại, như hành vi trước đây.

#### Scenario: Áp plan cũ
- **WHEN** người dùng áp một plan phiên bản 1 có một feature và hai task, không ghi `sprint`
- **THEN** issue feature và hai task được tạo trong sprint hiện tại, và file được ghi lại ở định dạng phiên bản 2 có số issue

### Requirement: Kiểm tra plan
`scrum plan validate FILE` SHALL kiểm tra plan mà không gọi mạng và in mọi lỗi tìm thấy. Lỗi gồm: thiếu trường bắt buộc; `id` trùng nhau; điểm ngoài thang điểm; `depends_on` trỏ tới `id` không tồn tại, tới chính nó, hoặc tạo thành vòng. Lệnh MUST kết thúc với mã khác 0 khi có lỗi. `plan apply` và `plan render` MUST chạy cùng kiểm tra này trước khi làm việc khác.

#### Scenario: Plan hợp lệ
- **WHEN** người dùng kiểm tra một plan hợp lệ
- **THEN** lệnh kết thúc với mã 0 và in số feature, số task, tổng điểm

#### Scenario: Điểm ngoài thang
- **WHEN** thang điểm là 0, 1, 3, 7 và task `T2` có 5 điểm
- **THEN** lệnh báo lỗi nêu `T2`, giá trị 5 và các điểm hợp lệ

#### Scenario: Phụ thuộc vòng
- **WHEN** `T1` phụ thuộc `T2` và `T2` phụ thuộc `T1`
- **THEN** lệnh báo lỗi nêu vòng phụ thuộc giữa `T1` và `T2`

#### Scenario: Phụ thuộc không tồn tại
- **WHEN** `T1` có `depends_on: ["T9"]` và plan không có `T9`
- **THEN** lệnh báo lỗi nêu `T1` và `T9`

#### Scenario: Nhiều lỗi
- **WHEN** plan có hai `id` trùng và một điểm ngoài thang
- **THEN** lệnh in cả hai lỗi trong một lần chạy

### Requirement: Bản xem ở local
`scrum plan render FILE` SHALL ghi `plan.md` cạnh plan file, hoặc vào đường dẫn của `--out`. Bản xem gồm: tiêu đề, epic nếu có, từng feature với bảng task (id, tiêu đề, điểm, phụ thuộc, số issue nếu đã tạo), tiêu chí hoàn thành và subtask của từng task, giả định, phần ngoài scope, và phần ước lượng. Bản xem MUST có dòng đầu ghi rõ file được sinh ra và không sửa tay.

#### Scenario: Sinh bản xem
- **WHEN** người dùng chạy `scrum plan render docs/plans/comments/plan.json`
- **THEN** `docs/plans/comments/plan.md` có bảng task của từng feature và tổng điểm

#### Scenario: Plan đã áp
- **WHEN** plan có task `T1` với `issue: 12`
- **THEN** dòng của `T1` trong bản xem hiện `#12`

#### Scenario: Sinh lại
- **WHEN** plan không đổi và người dùng sinh bản xem hai lần khi không có mạng
- **THEN** hai file giống hệt nhau

### Requirement: Ước lượng
Bản xem SHALL hiện tổng điểm của plan và của từng feature, không tính task chưa có điểm, và nêu số task chưa có điểm. Khi `planning.hours_per_point` được đặt, bản xem SHALL hiện thêm số giờ của từng task, từng feature và cả plan. Khi đọc được velocity của các sprint đã đóng, bản xem SHALL hiện số sprint ước tính theo velocity trung bình của tối đa ba sprint đóng gần nhất.

#### Scenario: Chỉ có điểm
- **WHEN** `hours_per_point` không đặt và plan có các task 3, 7 và một task chưa có điểm
- **THEN** bản xem hiện tổng 10 điểm, ghi 1 task chưa ước lượng, và không hiện giờ

#### Scenario: Quy ra giờ
- **WHEN** `hours_per_point` là 4 và plan có tổng 10 điểm
- **THEN** bản xem hiện 40 giờ

#### Scenario: Quy ra sprint
- **WHEN** ba sprint đóng gần nhất có velocity 10, 12, 14 và plan có tổng 30 điểm
- **THEN** bản xem hiện velocity trung bình 12 và ước tính 3 sprint

#### Scenario: Chưa có sprint nào đóng
- **WHEN** repo chưa có sprint đã đóng, hoặc lệnh chạy không có mạng
- **THEN** bản xem bỏ phần quy ra sprint và lệnh vẫn kết thúc với mã 0

### Requirement: Áp plan lên GitHub
`scrum plan apply FILE` SHALL tạo trên GitHub mọi mục của plan chưa có `issue`: epic (nếu có) với label epic, mỗi feature với label feature, và mỗi task theo đúng quy tắc tạo task. Feature SHALL là sub-issue của epic, task SHALL là sub-issue của feature. `subtasks` của task SHALL thành danh sách checkbox trong thân issue, không thành issue riêng.

#### Scenario: Plan có một feature
- **WHEN** người dùng áp plan có feature `F1` với hai task
- **THEN** một issue có label `type: feature` và hai issue task được tạo, hai task là sub-issue của feature

#### Scenario: Plan có epic
- **WHEN** người dùng áp plan có epic và hai feature
- **THEN** một issue có label `type: epic` được tạo và hai issue feature là sub-issue của nó

#### Scenario: Task có subtask
- **WHEN** task `T1` có `subtasks: ["Viết migration", "Viết test"]`
- **THEN** thân issue của `T1` có mục "Subtasks" với hai checkbox, và không có issue nào khác được tạo cho chúng

#### Scenario: Repo không hỗ trợ sub-issue
- **WHEN** gắn sub-issue bị GitHub từ chối
- **THEN** issue cha được cập nhật với danh sách checkbox tham chiếu tới từng issue con và lệnh báo đã dùng cách dự phòng

### Requirement: Ghi lại số issue
Sau mỗi issue được tạo, `plan apply` SHALL ghi số issue vào trường `issue` của mục tương ứng trong plan file trước khi tạo issue kế tiếp. Việc ghi MUST giữ file là JSON hợp lệ kể cả khi lệnh bị ngắt giữa chừng.

#### Scenario: Áp thành công
- **WHEN** plan có ba task chưa có `issue` và lệnh chạy xong
- **THEN** cả ba task trong file có số issue

#### Scenario: Lỗi giữa chừng
- **WHEN** GitHub trả lỗi khi tạo task thứ hai trong ba task
- **THEN** file ghi số issue của task thứ nhất, hai task còn lại chưa có `issue`, và lệnh kết thúc với mã khác 0

#### Scenario: Bản xem theo kịp
- **WHEN** `plan apply` kết thúc, dù thành công hay lỗi giữa chừng
- **THEN** bản xem cạnh plan file được sinh lại và hiện số của mọi issue đã tạo

### Requirement: Chạy lại không tạo trùng
`plan apply` MUST NOT tạo issue cho mục đã có `issue`. Khi chạy lại, lệnh SHALL chỉ tạo các mục còn thiếu và bổ sung các quan hệ sub-issue và phụ thuộc còn thiếu. Lệnh MUST NOT sửa tiêu đề, thân, label hay milestone của issue đã có, trừ khi có `--update`.

#### Scenario: Chạy lần hai
- **WHEN** plan đã áp xong và người dùng chạy `plan apply` lần nữa
- **THEN** không có issue nào được tạo hay sửa, và lệnh báo mọi mục đã có

#### Scenario: Chạy lại sau lỗi
- **WHEN** lần chạy trước tạo được một trong ba task rồi lỗi, và người dùng chạy lại
- **THEN** chỉ hai task còn thiếu được tạo

#### Scenario: Thêm task vào plan đã áp
- **WHEN** người dùng thêm task `T4` vào feature đã có issue rồi áp lại
- **THEN** chỉ `T4` được tạo và thành sub-issue của feature đó

### Requirement: Cập nhật issue đã có
Với `--update`, `plan apply` SHALL cập nhật tiêu đề, thân, label điểm và milestone của các issue đang mở cho khớp plan. Lệnh MUST NOT đổi label trạng thái, MUST NOT đổi issue đã đóng, và MUST báo từng issue đã đóng mà nó bỏ qua.

#### Scenario: Chuyển từ backlog vào sprint
- **WHEN** task `T1` đã có issue #12 không có milestone, người dùng đặt `sprint: "Sprint 3"` cho `T1` rồi chạy `plan apply --update`
- **THEN** issue #12 có milestone `Sprint 3` và giữ nguyên label trạng thái

#### Scenario: Đổi điểm
- **WHEN** task `T1` đổi từ 3 sang 7 điểm trong plan và người dùng chạy `plan apply --update`
- **THEN** issue của `T1` có `points: 7` và không còn `points: 3`

#### Scenario: Issue đã đóng
- **WHEN** issue của `T2` đã đóng và plan đổi tiêu đề `T2`
- **THEN** issue không đổi và lệnh báo đã bỏ qua `T2` vì issue đã đóng

### Requirement: Sprint và backlog
Trường `sprint` của plan phiên bản 2 SHALL nhận tên một sprint, giá trị `current` (sprint hiện tại), hoặc bỏ trống (backlog). `sprint` của task ghi đè `sprint` của plan. Task backlog SHALL được tạo không có milestone. Issue epic và feature SHALL nhận sprint của plan. Lệnh MUST dừng trước khi ghi bất cứ gì khi một sprint được nêu tên không tồn tại hoặc đã đóng.

#### Scenario: Backlog
- **WHEN** plan phiên bản 2 không ghi `sprint` và repo không có sprint nào đang mở
- **THEN** mọi issue được tạo không có milestone

#### Scenario: Sprint hiện tại
- **WHEN** plan ghi `sprint: "current"` và sprint hiện tại là `Sprint 2`
- **THEN** mọi task có milestone `Sprint 2`

#### Scenario: Task ghi đè
- **WHEN** plan ghi `sprint: "Sprint 2"` và task `T3` ghi `sprint: "Sprint 3"`
- **THEN** `T3` có milestone `Sprint 3` và các task khác có `Sprint 2`

#### Scenario: Sprint không tồn tại
- **WHEN** task `T3` ghi `sprint: "Sprint 9"` và repo không có `Sprint 9`
- **THEN** lệnh dừng với lỗi nêu `Sprint 9` và không tạo issue nào

### Requirement: Phụ thuộc giữa các task
Với mỗi `depends_on`, `plan apply` SHALL đánh dấu trên GitHub rằng issue của task bị chặn bởi issue của task kia, sau khi cả hai issue tồn tại. Quan hệ đã có MUST được coi là thành công. Khi GitHub từ chối quan hệ này, lệnh SHALL ghi mục "Blocked by" tham chiếu tới issue chặn vào thân issue và báo đã dùng cách dự phòng.

#### Scenario: Có phụ thuộc
- **WHEN** `T2` có `depends_on: ["T1"]`, `T1` là issue #10 và `T2` là issue #11
- **THEN** issue #11 được đánh dấu bị chặn bởi #10

#### Scenario: Chạy lại
- **WHEN** quan hệ chặn giữa #11 và #10 đã có và người dùng áp lại plan
- **THEN** lệnh không báo lỗi và không tạo quan hệ trùng

#### Scenario: GitHub từ chối
- **WHEN** GitHub từ chối tạo quan hệ chặn
- **THEN** thân issue #11 có mục "Blocked by" với `#10`, và lệnh báo đã dùng cách dự phòng

### Requirement: Xem trước khi áp
`scrum plan apply FILE --dry-run` SHALL in từng thao tác sẽ làm (tạo, cập nhật, gắn sub-issue, gắn phụ thuộc, bỏ qua) và MUST NOT ghi gì lên GitHub hay vào plan file.

#### Scenario: Xem trước plan mới
- **WHEN** người dùng chạy `plan apply --dry-run` với plan có một feature và hai task chưa áp
- **THEN** lệnh in ba thao tác tạo và hai thao tác gắn sub-issue, GitHub và plan file không đổi

#### Scenario: Xem trước plan đã áp một phần
- **WHEN** một trong hai task đã có `issue`
- **THEN** lệnh in một thao tác tạo và ghi task kia là đã có

### Requirement: Epic không tính điểm
Issue có label epic MUST NOT được tính là task trong điểm, velocity, burndown, digest, bảng tiến độ và đồng bộ trạng thái, giống issue feature.

#### Scenario: Báo cáo sprint
- **WHEN** sprint có một issue epic, một issue feature và hai task 3 điểm
- **THEN** tổng điểm của sprint là 6 và bảng tiến độ có hai task
