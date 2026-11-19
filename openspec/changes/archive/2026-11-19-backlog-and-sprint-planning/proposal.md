# Proposal

Thứ tự trong lộ trình: **3 trên 6**. Nên làm sau change 2 để `scrum next` gợi ý được bước lập kế hoạch sprint.

## Why

Plugin phủ tốt phần giữa của sprint nhưng bỏ trống hai đầu. Issue không có milestone (backlog) không hiện ở `status`, `report`, `digest` hay board, và cách duy nhất để đưa nó vào sprint là gán milestone trên web hoặc sửa `plan.json`. `sprint-new` tạo ra một sprint rỗng: buổi Sprint Planning không có lệnh nào hỗ trợ, dù velocity trung bình đã được tính sẵn cho `plan.md`. Về task, quy ước team ghi "không sửa label bằng tay" nhưng CLI chỉ có `task new` và `task start`, nên đổi điểm, đổi sprint, giao người hay bỏ task đều phải làm tay trên GitHub.

## What Changes

- Lệnh mới `scrum backlog [--json]` và skill `/scrum-github:backlog`: liệt kê task đang mở không có milestone, kèm điểm, người nhận, feature cha, và task nào đang bị chặn bởi task chưa xong; tổng số task và tổng điểm; đếm task chưa có điểm. Epic, feature và issue meta không tính.
- Lệnh mới `scrum sprint plan [SPRINT] [--capacity N] [--add N,N,…] [--yes]` và skill `/scrum-github:sprint-plan`:
  - không có `--add`: in sức chứa (mặc định là velocity trung bình của tối đa ba sprint đã đóng gần nhất; chưa có sprint đóng thì nói rõ là chưa có số liệu), điểm đã có trong sprint, điểm còn trống, và danh sách backlog để chọn;
  - có `--add`: xem trước việc đưa các task đó vào sprint, cảnh báo khi vượt sức chứa, khi task chưa có điểm, hoặc khi task bị chặn bởi task nằm ngoài sprint; chỉ ghi khi có `--yes`.
  Skill đề xuất một tập task vừa sức chứa và theo thứ tự phụ thuộc, người dùng sửa rồi duyệt.
- Thêm lệnh cho task, mỗi lệnh có skill hoặc được skill `task` chung gọi (chốt ở design):
  - `scrum task list [--mine] [--sprint S | --backlog] [--status ROLE] [--json]`;
  - `scrum task move N… --sprint S | --backlog`: đổi milestone, kèm comment ghi nguồn và đích;
  - `scrum task estimate N POINTS`: thay label điểm, kiểm tra theo thang;
  - `scrum task assign N LOGIN…` và `--unassign`;
  - `scrum task drop N [--reason TEXT]`: đóng với lý do "not planned" để không tính velocity.
  Các lệnh ghi đều cập nhật board khi board bật, giống `task start`.
- `sprint-new` gợi ý `/scrum-github:sprint-plan` làm bước kế tiếp khi backlog có task.
- Phiên bản plugin lên 0.6.0.

Ngoài phạm vi: thứ tự ưu tiên của backlog (label priority hay xếp hạng), sức chứa theo từng người và ngày nghỉ, tự gán milestone cho issue tạo từ form trên web, và sprint goal theo từng task.

## Capabilities

### New Capabilities

- `backlog`: xác định task nào thuộc backlog và trình bày chúng để chọn cho sprint.

### Modified Capabilities

- `sprint-lifecycle`: thêm yêu cầu lập kế hoạch sprint (sức chứa từ velocity, xem trước, cảnh báo, chỉ ghi sau khi xác nhận).
- `task-management`: thêm các yêu cầu liệt kê, chuyển sprint, ước lượng lại, giao việc và bỏ task.
- `project-board-sync`: "Thêm task vào Project" và "Cập nhật board ngay khi đổi trạng thái" áp dụng cho các lệnh ghi mới.
- `next-step-guidance`: `scrum next` gợi ý chọn task cho sprint khi sprint hiện tại rỗng mà backlog có task.

## Impact

- Mã: `runtime/bin/scrum`, `runtime/lib/cmd_task.sh`, `runtime/lib/cmd_sprint.sh`, file mới `runtime/lib/cmd_backlog.sh`, chương trình jq mới cho backlog và cho kế hoạch sprint, dùng lại phần tính velocity của `plan-render`.
- Skill mới: `backlog`, `sprint-plan`, và skill cho các lệnh task; sửa `sprint-new`, `sprint-status`.
- API GitHub: đọc issue mở không có milestone (`milestone=none`) và quan hệ "blocked by" của từng task trong backlog; với backlog lớn cần giới hạn số lời gọi (chốt ở design).
- Tên `sprint-plan` từng là tên cũ của skill `plan` (đổi ở 0.3.0). Dùng lại tên này với nghĩa khác có thể gây nhầm cho người dùng cũ; design phải chọn giữa `sprint-plan` và một tên khác như `sprint-fill`.
- Test: `tests/test_backlog.sh`, mở rộng `tests/test_task.sh`, `tests/test_sprint.sh`, fixture issue không có milestone.
- Không đổi định dạng `plan.json`. `plan apply --update` vẫn là một cách khác để đổi sprint của task.
