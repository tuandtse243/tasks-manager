# Tasks

Đường dẫn tính từ `plugins/scrum-github/`. Chạy test bằng `bash tests/run.sh` (một file: thêm tên). Lint bằng lệnh `shellcheck` trong mục Development của README plugin.

## 1. Backlog (design mục 3; spec backlog)

- [x] 1.1 Tách `recent_velocity` vào `runtime/lib/jq/scrum.jq` và cho `plan-render.jq` dùng nó. Kiểm tra: test plan hiện có vẫn xanh (`bash tests/run.sh plan`)
- [x] 1.2 Tạo `runtime/lib/jq/backlog.jq` và test jq trong `tests/test_backlog.sh`: task thuộc backlog (bỏ PR, feature, epic, meta, task đóng), cha từ "Part of #N", tổng, chưa ước lượng, `blocked_by: null` là chưa kiểm tra. Kiểm tra: `bash tests/run.sh backlog` xanh
- [x] 1.3 Tạo `runtime/lib/cmd_backlog.sh` (đọc backlog, quan hệ chặn cho tối đa 50 task) và lệnh `scrum backlog [--json]`; test lệnh với `fake-gh` cho backlog có task, bị chặn, rỗng, 60 task (đúng 50 lời gọi chặn), không có lời gọi ghi. Kiểm tra: `bash tests/run.sh backlog` xanh
- [x] 1.4 Tạo `skills/backlog/SKILL.md`. Kiểm tra: `claude plugin validate .` đạt; test skill của `test_cli.sh` xanh

## 2. Lệnh task (design mục 2, 5; spec task-management, project-board-sync)

- [x] 2.1 `scrum task list [--mine] [--sprint S | --backlog] [--status ROLE] [--json]`, có test. Kiểm tra: `bash tests/run.sh task` xanh
- [x] 2.2 `scrum task move N… --sprint S | --backlog` (kiểm tra cả danh sách trước khi ghi, comment, `project_touch`), có test cho đưa về backlog, sprint đã đóng, feature bị từ chối. Kiểm tra: `bash tests/run.sh task` xanh
- [x] 2.3 `scrum task estimate N POINTS` với `points-labels.jq`, có test đổi điểm và ngoài thang. Kiểm tra: `bash tests/run.sh task` xanh
- [x] 2.4 `scrum task assign N LOGIN… [--unassign]` và `scrum task drop N [--reason TEXT]`, có test. Kiểm tra: `bash tests/run.sh task` xanh
- [x] 2.5 Test board: với project bật, `estimate`, `move` và `drop` gọi cập nhật board (route GraphQL của `fake-gh`). Kiểm tra: `bash tests/run.sh task` xanh
- [x] 2.6 Tạo `skills/task/SKILL.md` (nói lại thay đổi và chờ đồng ý trước lệnh ghi). Kiểm tra: `claude plugin validate .` đạt

## 3. Lập kế hoạch sprint (design mục 1, 4; spec sprint-lifecycle)

- [ ] 3.1 Tạo `runtime/lib/jq/sprint-fill.jq` và test jq: sức chứa từ velocity, chưa có velocity, `--capacity`, vượt sức chứa, chưa có điểm, bị chặn ngoài sprint, số không hợp lệ. Kiểm tra: `bash tests/run.sh sprint` xanh
- [ ] 3.2 Lệnh `scrum sprint fill [SPRINT] [--capacity N] [--add N,N,…] [--yes]`: xem trước, chỉ ghi khi `--yes`, dừng khi có lỗi; test lệnh cho xem trước không ghi, ghi (milestone, comment), số không hợp lệ không ghi gì. Kiểm tra: `bash tests/run.sh sprint` xanh
- [ ] 3.3 `scrum sprint new` gợi ý `/scrum-github:sprint-fill` khi backlog có task; test có và không có backlog. Kiểm tra: `bash tests/run.sh sprint` xanh
- [ ] 3.4 Tạo `skills/sprint-fill/SKILL.md` (đề xuất tập task vừa sức chứa theo thứ tự phụ thuộc, người dùng sửa rồi duyệt); sửa `skills/sprint-new/SKILL.md` gợi ý bước này. Kiểm tra: `claude plugin validate .` đạt

## 4. `next` (design mục 6; spec next-step-guidance)

- [ ] 4.1 `next-step.jq` thêm bước "fill"; `cmd_next.sh` đếm backlog khi sprint rỗng; test jq và test lệnh. Kiểm tra: `bash tests/run.sh next` xanh

## 5. Phiên bản, dọn dẹp và tài liệu

- [ ] 5.1 Xoá `skills/scrum-init/` (design mục 7) và sửa test tên cũ. Kiểm tra: `bash tests/run.sh cli` xanh; `claude plugin validate .` không còn `scrum-init`
- [ ] 5.2 Phiên bản 0.6.0 (`runtime/VERSION`, `plugin.json`, test phiên bản trong `test_init.sh`), mục 0.6.0 trong `CHANGELOG.md`. Kiểm tra: `bash tests/run.sh manifest` và `init` xanh
- [ ] 5.3 README plugin (bảng lệnh: backlog, sprint-fill, task; lệnh task mới) và `docs/huong-dan-ap-dung.md` gốc repo (bảng lệnh, Flow A mở sprint dùng `sprint-fill`, quy ước "không sửa label bằng tay" dẫn tới `/scrum-github:task`). Kiểm tra: mọi lệnh trong bảng có trong `scrum --help`

## 6. Kiểm tra tích hợp

- [ ] 6.1 Toàn bộ `bash tests/run.sh` (jq 1.8.1 và 1.8.2), `shellcheck`, `openspec validate backlog-and-sprint-planning --strict`, `claude plugin validate .`. Kiểm tra: tất cả đạt
- [ ] 6.2 Mở pull request, CI xanh, merge. Kiểm tra: CI trên `main` (gồm macOS) xanh

## Workflow follow-up

- Archive bằng `/opsx:archive backlog-and-sprint-planning`.
