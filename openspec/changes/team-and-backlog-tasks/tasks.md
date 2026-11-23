# Tasks

Đường dẫn tính từ `plugins/scrum-github/`. Chạy test bằng `bash tests/run.sh` (một file: thêm tên). Lint bằng lệnh `shellcheck` trong mục Development của README plugin. Bắt đầu sau khi 0.8.3 (đang ở working tree) đã vào `main`.

## 1. Cấu hình team (design 1; spec scrum-config)

- [ ] 1.1 Thêm `team: []` vào `runtime/share/defaults.json`; kiểm tra khối `team` trong `validate-config.jq` (login rỗng, ký tự sai, trùng không phân biệt hoa thường, `areas`, `capacity`), chuẩn hoá bỏ `@`. Kiểm tra: test mới trong `tests/test_config.sh` cho mặc định, đầy đủ, trùng, capacity 0, login có `@`; `bash tests/run.sh config` xanh
- [ ] 1.2 Thêm ví dụ khối `team` đã comment vào `templates/scrum.yml` và mục `team` trong README plugin (bảng cấu hình). Kiểm tra: `bash tests/run.sh init` xanh; ví dụ bỏ comment thì `scrum config` chấp nhận

## 2. Lệnh team và cảnh báo login (design 1, 2, 4; spec team)

- [ ] 2.1 Tạo `runtime/lib/jq/team.jq` (nguồn config hoặc github, chuẩn hoá login, tải theo sprint dùng `report_tasks`, login lạ) và test jq trong `tests/test_team.sh`. Kiểm tra: `bash tests/run.sh team` xanh
- [ ] 2.2 Tạo `runtime/lib/cmd_team.sh` với `team_members` (chỉ gọi `repos/{r}/assignees` khi `team` rỗng) và lệnh `scrum team [--json]`; đăng ký trong `runtime/bin/scrum` và `--help`. Test với `fake-gh`: cấu hình, dự phòng GitHub, có sprint, không có sprint, không có lời gọi ghi. Kiểm tra: `bash tests/run.sh team` xanh
- [ ] 2.3 Thêm `warn_unknown_logins` và gọi trong `task new`, `task assign`. Test: cảnh báo khi team có thành viên và login lạ, vẫn ghi; không cảnh báo khi team rỗng. Kiểm tra: `bash tests/run.sh task` xanh

## 3. `task new` về backlog (design 3; spec task-management "Tạo task")

- [ ] 3.1 Cho `task-payload.jq` nhận milestone `null`; `cmd_task_new` thêm `--backlog`, không có sprint mở thì về backlog, `--backlog` cùng `--sprint` thì báo lỗi; dòng in "in Sprint N" hoặc "in the backlog". Test: không có sprint mở, có sprint mở, `--backlog`, cả hai cờ, sprint không tồn tại. Kiểm tra: `bash tests/run.sh task` xanh
- [ ] 3.2 Sửa `skills/task-new/SKILL.md` (cờ `--backlog`, nói task đã vào đâu) và dòng `task new` trong README. Kiểm tra: `claude plugin validate .` đạt

## 4. Việc của tôi (design 5; spec my-work)

- [ ] 4.1 Tạo `runtime/lib/jq/mine.jq`: lọc task, nhóm theo thứ tự spec, task bị chặn, đề xuất (In progress trước, rồi task New không bị chặn của sprint đang mở theo đợt), PR chờ review hoặc "chưa đọc được". Test jq trong `tests/test_mine.sh`. Kiểm tra: `bash tests/run.sh mine` xanh
- [ ] 4.2 Tạo `runtime/lib/cmd_mine.sh` và lệnh `scrum mine [--user LOGIN] [--json]`: đọc issue theo assignee, milestones, `blocked_map`, search PR chờ review (lỗi thì bỏ qua). Test với `fake-gh`: task ở nhiều sprint và backlog, không có sprint mở, `--user`, không có việc, search lỗi, không có lời gọi ghi. Kiểm tra: `bash tests/run.sh mine` xanh
- [ ] 4.3 Tạo `skills/my-tasks/SKILL.md` (trình bày, nói task nên làm, đề nghị `/scrum-github:task-start N` và chờ đồng ý); thêm vào README và `docs/huong-dan-ap-dung.md` gốc repo. Kiểm tra: `claude plugin validate .` đạt; test skill trong `test_cli.sh` xanh

## 5. Số liệu plan: đợt, tải, capacity (design 6; spec work-plan "Đợt theo phụ thuộc", "Tải và capacity khi kiểm tra plan")

- [ ] 5.1 Thêm `plan_waves`, `plan_load`, `plan_fit` vào jq của plan và test jq: ba đợt theo ví dụ spec, một người vượt capacity, sprint vượt capacity, chưa có velocity. Kiểm tra: `bash tests/run.sh plan` xanh
- [ ] 5.2 `plan check` đọc team và issue của sprint đang mở, in đợt, tải, mức vừa capacity, cảnh báo login ngoài team; thêm `plan check --json` cho skill. Test online và `--offline`. Kiểm tra: `bash tests/run.sh plan` xanh

## 6. Bản xem HTML (design 8, 9, 10; spec work-plan "Bản xem HTML", "Trang tự chứa và an toàn", "Ngôn ngữ của bản xem HTML", "Thay đổi so với lần xem trước", "Bỏ qua file sinh ra trong thư mục plan")

- [ ] 6.1 Thêm trường tuỳ chọn `review` vào `runtime/share/plan.schema.json` và `plan-validate.jq`; `plan apply` bỏ qua trường này. Kiểm tra: test plan có `review` vẫn hợp lệ và áp được; `bash tests/run.sh plan` xanh
- [ ] 6.2 Tạo `plan-diff.jq` và ghi đọc `.plan-snapshot.json`: thêm, bỏ, đổi tiêu đề, điểm, phụ thuộc, người làm, sprint; số lần sửa; lần đầu không có thay đổi; ghi số issue không tính là sửa. Kiểm tra: test jq và test lệnh trong `tests/test_plan.sh` xanh
- [ ] 6.3 Tạo `plan-html-data.jq` và chuỗi mới (en, vi) trong `runtime/share/strings.json`. Kiểm tra: test jq cho dữ liệu có đợt, tải, thao tác, thay đổi, chuỗi theo `language`; `bash tests/run.sh plan` xanh
- [ ] 6.4 Tạo template `runtime/share/plan.html` (8 phần, phần chữ render sẵn, sơ đồ đợt và tải vẽ bằng JS với `textContent`, chuyển động CSS tắt khi giảm chuyển động, sáng và tối) theo bản mẫu đã duyệt. Kiểm tra: test trong `test_plan.sh` khẳng định file sinh ra có đủ 8 phần, không có `http://` hay `https://` trong `src` hoặc `href` của tài nguyên, và tiêu đề task chứa `<script>` bị thoát
- [ ] 6.5 `plan check`, `plan render` và `plan apply` ghi `plan.html` cạnh `plan.md`; bản offline ghi chú phần cần mạng. Kiểm tra: test cho cả ba lệnh và cho `--offline`; `bash tests/run.sh plan` xanh
- [ ] 6.6 `plan init` ghi `.gitignore` (`plan.html`, `.plan-snapshot.json`) khi chưa có; `plan check` nhắc khi thư mục cũ thiếu. Kiểm tra: test thư mục mới, `.gitignore` đã có không đổi; `bash tests/run.sh plan` xanh

## 7. Skill plan một lần duyệt (design 7, 11; spec task-management "Đề xuất người làm và sprint trong plan", "Một lần duyệt plan")

- [ ] 7.1 Sửa `skills/plan/SKILL.md`: gọi `scrum team --json` và `plan check --json`, điền `assignees` và `sprint: "current"` đề xuất (giữ giá trị người dùng nêu, không đề xuất login ngoài team, không đề xuất khi nguồn GitHub dài hơn 15 người), ghi `review` từ plan-critic, mở `plan.html` (ngoài sandbox, sau khi người dùng cho phép), một câu duyệt, rồi `plan apply`; bỏ gợi ý `sprint-fill` sau apply. Kiểm tra: `claude plugin validate .` đạt; đọc lại skill thấy đúng một câu hỏi duyệt trước apply
- [ ] 7.2 Cập nhật `reference/planning-rules.md` nếu nói tới việc để trống người làm hoặc sprint. Kiểm tra: `grep` không còn quy tắc mâu thuẫn với design 7

## 8. Phiên bản và tài liệu chung

- [ ] 8.1 Phiên bản 0.9.0 (`runtime/VERSION`, `.claude-plugin/plugin.json`, test phiên bản trong `test_init.sh`); mục 0.9.0 trong `CHANGELOG.md` với "Added" (team, mine, my-tasks, plan.html, một lần duyệt) và "Changed" (`task new` về backlog khi không có sprint mở). Kiểm tra: `bash tests/run.sh manifest` và `init` xanh
- [ ] 8.2 README plugin và `docs/huong-dan-ap-dung.md`: bảng lệnh (`team`, `mine`, `my-tasks`), luồng plan một lần duyệt có `plan.html`. Kiểm tra: mọi lệnh trong bảng có trong `scrum --help`

## 9. Kiểm tra tích hợp

- [ ] 9.1 Toàn bộ `bash tests/run.sh` (jq 1.8.1 và 1.8.2), `shellcheck`, `openspec validate team-and-backlog-tasks --strict`, `claude plugin validate .`. Kiểm tra: tất cả đạt
- [ ] 9.2 Thử trên một repo thật: `/plan` một yêu cầu nhỏ, mở `plan.html`, duyệt một lần, issue có milestone và assignee; `scrum mine`; `task new` khi không có sprint mở. Kiểm tra: kết quả khớp spec, ghi lại trong mô tả PR

## Workflow follow-up

- Mở pull request, CI xanh, merge.
- Archive bằng `/opsx:archive team-and-backlog-tasks`.
- Tiếp theo: change 2 `time-estimates`.
