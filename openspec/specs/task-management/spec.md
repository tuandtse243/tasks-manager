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
Lệnh lập kế hoạch SHALL nhận mô tả một feature và trình bày danh sách task đề xuất, mỗi task có tiêu đề, mô tả, tiêu chí hoàn thành và điểm trong thang điểm. Hệ thống MUST NOT tạo issue nào trước khi người dùng duyệt, và người dùng MUST sửa được, bỏ được hoặc thêm được task trước khi duyệt.

#### Scenario: Duyệt đề xuất
- **WHEN** người dùng chạy `/sprint-plan` với feature "Blog post comments", sửa điểm một task rồi duyệt
- **THEN** một issue feature có label `type: feature` được tạo, các task được tạo với điểm đã sửa trong sprint hiện tại, và mỗi task được gắn làm sub-issue của issue feature

#### Scenario: Không duyệt
- **WHEN** người dùng xem đề xuất rồi huỷ
- **THEN** không có issue nào được tạo

#### Scenario: Điểm đề xuất nằm trong thang
- **WHEN** thang điểm là 0, 1, 3, 7
- **THEN** mọi điểm trong đề xuất thuộc tập 0, 1, 3, 7

#### Scenario: Repo không hỗ trợ sub-issue
- **WHEN** gắn sub-issue bị GitHub từ chối
- **THEN** issue feature được cập nhật với danh sách checkbox tham chiếu tới từng task và lệnh báo đã dùng cách dự phòng

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
