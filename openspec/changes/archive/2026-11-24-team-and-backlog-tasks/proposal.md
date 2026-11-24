# Proposal

Thứ tự trong lộ trình: **1 trên 3**. Change 2 (`time-estimates`) thêm ước lượng thời gian AI và thời gian review vào cùng các màn hình này. Change 3 (`ai-run`) chạy task bằng agent trong worktree. Cả hai dựa vào danh sách team và trang xác nhận plan của change này.

## Why

Plugin tạo được task nhưng chưa trả lời được hai câu hỏi hằng ngày: ai làm task nào, và tôi đang có những task gì. `scrum.yml` không biết team gồm những ai, nên `plan` chỉ điền người làm khi người dùng tự nêu tên, và không ai thấy được tải của từng người. Sau khi duyệt plan, người dùng còn phải tự đưa task vào sprint bằng `/sprint-fill` và tự assign từng task, tức là ba bước rời nhau. `task new` từ chối tạo task khi không có sprint nào đang mở, trong khi `plan`, `task move --backlog` và `backlog` đều coi backlog là chỗ bình thường của task. `task list --mine` chỉ đọc một sprint hoặc backlog, nên không có lệnh nào cho một người xem hết việc của mình. Cuối cùng, bản xem `plan.md` là bảng chữ, khó dùng để duyệt một plan có nhiều task và nhiều phụ thuộc.

## What Changes

- Khối `team` mới trong `scrum.yml`: danh sách thành viên, mỗi người có `login`, và tuỳ chọn `areas` (lĩnh vực) và `capacity` (điểm mỗi sprint). Khi để trống, plugin dùng danh sách người được giao việc của repo trên GitHub.
- Lệnh mới `scrum team [--json]`: in thành viên, lĩnh vực, capacity, và tải hiện tại trong sprint đang mở. Lệnh chỉ đọc.
- Login không có trong `team` (khi `team` được khai báo) gây cảnh báo ở `task new`, `task assign` và `plan check`. Đây là cảnh báo, không chặn.
- **Đổi hành vi** `scrum task new`: không có `--sprint` và không có sprint đang mở thì task vào backlog, thay vì báo lỗi. Có sprint đang mở thì vẫn vào sprint đó như trước. Thêm `--backlog` để đưa vào backlog khi đang có sprint. Lệnh luôn in task đã vào đâu.
- Lệnh mới `scrum mine [--user LOGIN] [--json]` và skill `/scrum-github:my-tasks`: mọi task đang mở được giao cho một người, ở mọi sprint và backlog, nhóm theo trạng thái và nơi chứa, kèm task đang chặn chúng, các PR đang chờ người đó review, và thứ tự nên làm theo phụ thuộc.
- `/plan` chỉ còn **một lần xác nhận**. Trước khi trình bày, skill điền đề xuất người làm (theo `areas` và tải) và sprint (phần vừa capacity vào sprint đang mở, phần dư để backlog) vào `plan.json`. Người dùng duyệt hoặc sửa trên cùng một bảng, rồi `plan apply` tạo issue với đủ milestone và assignee. Không còn bước assign hay `sprint-fill` sau apply.
- `scrum plan check` tính thêm tải từng người, mức vừa capacity của sprint, và các đợt chạy song song theo phụ thuộc, rồi in chúng cùng các thao tác sẽ làm.
- Bản xem mới `plan.html` cạnh `plan.md`, do `plan check`, `plan render` và `plan apply` sinh từ `plan.json` theo template, không cần mạng. Trang gồm: tóm tắt, thay đổi so với lần xem trước, sơ đồ phụ thuộc theo đợt (có chuyển động, rê chuột để xem chuỗi phụ thuộc), tải từng người và capacity của sprint, chi tiết từng task, góp ý của plan-critic, những gì sẽ được tạo trên GitHub, giả định và ngoài phạm vi. Chữ cố định theo khoá `language` hiện có. Skill `/plan` mở trang này để người dùng xem trước khi xác nhận trong chat.
- `plan init` ghi một `.gitignore` trong thư mục plan để bỏ qua `plan.html` và bản chụp dùng cho phần thay đổi.
- Phiên bản plugin lên 0.9.0.

Ngoài phạm vi: ước lượng theo thời gian (change 2); chạy task bằng agent, worktree và PR gộp (change 3); bàn giao task (`task handoff`), assign theo cả feature, và bước "task New chưa ai nhận" trong `next`; trả lời xác nhận ngay trên trang HTML (trang chỉ để xem).

## Capabilities

### New Capabilities

- `team`: danh sách thành viên dùng chung cho mọi lệnh: nguồn (cấu hình hoặc GitHub), lệnh `scrum team`, tải của từng người, và cảnh báo login lạ.
- `my-work`: góc nhìn của một người về toàn bộ việc của mình: task ở mọi sprint và backlog, PR chờ review, thứ tự nên làm.

### Modified Capabilities

- `scrum-config`: thêm yêu cầu cho khối `team` và cách kiểm tra nó.
- `task-management`: "Tạo task" đổi sang về backlog khi không có sprint đang mở và thêm `--backlog`; "Giao task" cảnh báo login lạ; "AI đề xuất tách feature thành task" đề xuất người làm và sprint, và chỉ còn một lần duyệt.
- `work-plan`: thêm bản xem HTML, phần thay đổi so với lần xem trước, phần tải và capacity trong `plan check`; `plan init` ghi `.gitignore` của thư mục plan.

## Impact

- Mã (tính từ `plugins/scrum-github/`): `runtime/bin/scrum`; `runtime/lib/cmd_task.sh` (`task new`, `task assign`); `runtime/lib/cmd_plan.sh` (`check`, `render`, `apply`, `init`); file mới `runtime/lib/cmd_team.sh` và `runtime/lib/cmd_mine.sh`; jq mới cho team, tải, đợt, dữ liệu trang HTML và phần thay đổi; `validate-config.jq` và `defaults.json`; template mới `runtime/share/plan.html`; chuỗi mới trong `runtime/share/strings.json` (en, vi); `templates/scrum.yml` có ví dụ khối `team`.
- Skill: mới `my-tasks`; sửa `plan`, `task-new`, `task`, `init` (giới thiệu `team`).
- API GitHub: `GET repos/{r}/assignees` khi `team` trống; `GET repos/{r}/issues?assignee=…&state=open` cho `scrum mine`; tìm PR chờ review bằng `search/issues`; đọc quan hệ "blocked by" như `backlog` đang làm, có giới hạn số lời gọi.
- Tương thích: người đang chạy `task new` trong repo không có sprint mở trước đây nhận lỗi, nay task được tạo ở backlog. CHANGELOG ghi rõ. `plan.json` không đổi định dạng: `assignees` và `sprint` đã có sẵn.
- Phiên bản: working tree đang có 0.8.3 chưa commit. Change này lên 0.9.0 sau khi 0.8.3 vào `main`.
- Test: `tests/test_team.sh`, `tests/test_mine.sh` mới; mở rộng `test_task.sh`, `test_plan.sh`, `test_config.sh`, `test_cli.sh`, `test_init.sh`.
