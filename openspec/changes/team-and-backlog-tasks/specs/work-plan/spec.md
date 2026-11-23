# Spec Delta

## ADDED Requirements

### Requirement: Bản xem HTML
`plan check`, `plan render` và `plan apply` SHALL ghi `plan.html` cạnh `plan.md`, sinh từ plan file theo một template cố định. Trang gồm: tóm tắt, thay đổi so với lần xem trước, sơ đồ phụ thuộc theo đợt, tải từng người và capacity của sprint, chi tiết từng task, góp ý của agent soát nếu có, các thao tác sẽ làm trên GitHub, giả định và ngoài phạm vi. Mọi số trong trang MUST khớp plan file.

#### Scenario: Sinh trang khi kiểm tra
- **WHEN** người dùng chạy `scrum plan check docs/plans/comments/plan.json`
- **THEN** `docs/plans/comments/plan.html` được ghi cạnh `plan.md`

#### Scenario: Plan đã áp
- **WHEN** `plan apply` tạo xong issue #12 cho T1
- **THEN** `plan.html` được sinh lại và thẻ của T1 hiện `#12`

#### Scenario: Không có mạng
- **WHEN** người dùng chạy `scrum plan check FILE --offline`
- **THEN** `plan.html` được ghi, không có phần thao tác GitHub và phần tải theo sprint, và trang nói hai phần này cần mạng

### Requirement: Trang tự chứa và an toàn
`plan.html` MUST mở được khi không có mạng và MUST NOT tải script, font, ảnh hay dữ liệu từ bất kỳ máy chủ nào. Văn bản lấy từ plan file MUST được hiển thị như văn bản, không như mã HTML. Trang SHALL theo chế độ sáng hoặc tối của máy, và chuyển động MUST tắt khi máy bật giảm chuyển động.

#### Scenario: Tiêu đề task có thẻ HTML
- **WHEN** một task có tiêu đề `Fix <script>alert(1)</script> in comments`
- **THEN** trang hiện nguyên chuỗi đó như chữ và không chạy script nào

#### Scenario: Không có mạng
- **WHEN** người dùng mở `plan.html` trên máy không có mạng
- **THEN** trang hiện đầy đủ nội dung và sơ đồ

### Requirement: Ngôn ngữ của bản xem HTML
Chữ cố định của `plan.html` SHALL theo khoá `language`. Nội dung lấy từ plan file SHALL được giữ nguyên ngôn ngữ người viết.

#### Scenario: Tiếng Việt
- **WHEN** `language` là `vi`
- **THEN** tiêu đề các phần của trang bằng tiếng Việt, còn tiêu đề task giữ như trong plan

### Requirement: Thay đổi so với lần xem trước
Mỗi lần sinh `plan.html`, hệ thống SHALL so plan hiện tại với lần sinh trước của cùng thư mục plan và liệt kê task được thêm, bị bỏ, và task đổi tiêu đề, điểm, phụ thuộc, người làm hoặc sprint, kèm số lần sửa. Lần sinh đầu tiên MUST NOT có phần thay đổi. Plan không đổi thì số lần sửa giữ nguyên.

#### Scenario: Đổi người làm
- **WHEN** lần trước T4 giao cho `an-nguyen`, lần này giao cho `minh-ho`
- **THEN** phần thay đổi nêu T4 đổi người làm từ `an-nguyen` sang `minh-ho`

#### Scenario: Bỏ task
- **WHEN** lần trước có T7, lần này không có
- **THEN** phần thay đổi nêu T7 bị bỏ

#### Scenario: Sinh lại khi không đổi
- **WHEN** plan không đổi và người dùng chạy `plan check` hai lần
- **THEN** lần thứ hai không có thay đổi nào và số lần sửa giữ nguyên

### Requirement: Đợt theo phụ thuộc
Bản xem SHALL xếp task thành các đợt: đợt 1 gồm task không phụ thuộc task nào của plan, mỗi đợt sau gồm task chỉ phụ thuộc task của các đợt trước. Task trong cùng một đợt SHALL được coi là làm song song được.

#### Scenario: Ba đợt
- **WHEN** T2 và T3 phụ thuộc T1, T4 phụ thuộc T2, và T5 không phụ thuộc task nào
- **THEN** đợt 1 gồm T1 và T5, đợt 2 gồm T2 và T3, đợt 3 gồm T4

### Requirement: Tải và capacity khi kiểm tra plan
Khi đọc được GitHub, `plan check` SHALL tính cho sprint đang mở: tải của mỗi thành viên team gồm task đang có trong sprint cộng task của plan được giao cho họ vào sprint đó, so với capacity của họ; và tổng điểm của sprint sau khi áp plan so với capacity của sprint, tức velocity trung bình như `sprint-fill`. Lệnh SHALL cảnh báo người hoặc sprint vượt capacity.

#### Scenario: Một người vượt capacity
- **WHEN** `an-nguyen` có capacity 5, đang có 4 điểm trong Sprint 5, và plan giao thêm cho họ một task 2 điểm vào Sprint 5
- **THEN** `plan check` cảnh báo `an-nguyen` có 6 trên 5 điểm

#### Scenario: Chưa có velocity
- **WHEN** repo chưa có sprint nào đã đóng
- **THEN** `plan check` nói capacity của sprint chưa biết và vẫn tính tải từng người

### Requirement: Bỏ qua file sinh ra trong thư mục plan
`plan init` SHALL ghi `.gitignore` trong thư mục plan, bỏ qua `plan.html` và bản chụp dùng cho phần thay đổi. `.gitignore` đã có MUST NOT bị ghi đè. `plan.json` và `plan.md` MUST NOT bị bỏ qua.

#### Scenario: Thư mục plan mới
- **WHEN** người dùng chạy `scrum plan init "Blog post comments"`
- **THEN** `docs/plans/blog-post-comments/.gitignore` có `plan.html` và tên file bản chụp

#### Scenario: Đã có .gitignore
- **WHEN** thư mục plan đã có `.gitignore` do người dùng viết
- **THEN** file đó không đổi
