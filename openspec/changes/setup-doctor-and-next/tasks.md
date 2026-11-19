# Tasks

Đường dẫn tính từ `plugins/scrum-github/` trừ khi ghi khác. Chạy test bằng `bash tests/run.sh` (một file: thêm tên, ví dụ `doctor`). Lint bằng lệnh `shellcheck` trong mục Development của README plugin. Nhóm 2 cần trước nhóm 3 và 4; nhóm 6 cần nhóm 1, 4, 5.

## 1. `scrum` trên PATH (design mục 1)

- [x] 1.1 Tạo `bin/scrum` (thực thi được): tự tìm đường dẫn thật qua symlink bằng vòng `readlink` không cờ, rồi `exec bash` tới `runtime/bin/scrum`. Thêm test trong `tests/test_cli.sh`: gọi `bin/scrum --version` trực tiếp và qua một symlink ở thư mục tạm, cả hai in đúng `runtime/VERSION`. Kiểm tra: `bash tests/run.sh cli` xanh
- [x] 1.2 Thêm `bin/scrum` vào lệnh `shellcheck` ở README plugin, README gốc và `.github/workflows/ci.yml` (gốc repo). Kiểm tra: lệnh `shellcheck` chép từ README trả mã 0; `test_manifest.sh` vẫn xanh

## 2. Bản ghi file và cập nhật tự động trong `init` (design mục 2, 3; spec repo-bootstrap "Cài template vào repo", "Chế độ xem trước")

- [x] 2.1 Tách `managed_files` (template và đường dẫn, kể cả workflow board khi bật) và cho `cmd_init` dùng nó. Kiểm tra: mọi test hiện có của `tests/test_init.sh` vẫn xanh
- [x] 2.2 Ghi và đọc `.github/scrum/files.json` (hash `git hash-object`): đọc trước khi chép lại runtime, ghi sau; áp bảng quy tắc của design mục 2, với kết quả mới `updated` (xem trước: `would update`). Thêm test: đổi `points.scale` rồi chạy lại `init` không có `--force-file` thì Issue Form được cập nhật; đổi `digest.cron` tương tự; file sửa tay vẫn là `conflict`; repo không có `files.json` mà file khác bản mới là `conflict`; sau `--force-file` lần chạy sau tự cập nhật; `--dry-run` báo `would update` và không đổi file. Kiểm tra: `bash tests/run.sh init` xanh
- [x] 2.3 Đổi mọi thông báo nhắc `/scrum-github:scrum-init` trong `runtime/` sang `/scrum-github:init`. Kiểm tra: `grep -rn 'scrum-init' runtime/` không in gì; test liên quan trong `tests/` cập nhật và xanh
- [x] 2.4 `require_tools`: khi `gh auth status` thất bại và `SANDBOX_RUNTIME=1`, thêm câu về sandbox và dẫn tới `/scrum-github:doctor` (spec scrum-config). Thêm test có và không có biến. Kiểm tra: `bash tests/run.sh config` xanh

## 3. `scrum uninstall` (design mục 7; spec repo-bootstrap "Gỡ cài đặt")

- [x] 3.1 Tạo `runtime/lib/cmd_uninstall.sh` và lệnh `scrum uninstall [--dry-run] [--yes]` trong dispatcher và `usage`. Thêm `tests/test_uninstall.sh` cho năm scenario của spec (gỡ repo chưa sửa, giữ file đã sửa, không có `--yes`, `--dry-run --yes`, không có lời gọi `gh`). Kiểm tra: `bash tests/run.sh uninstall` xanh
- [x] 3.2 Ghi `scrum uninstall` vào bảng lệnh của README plugin. Kiểm tra: bảng có dòng mới và lệnh trong đó chạy được trên repo test

## 4. `scrum doctor` (design mục 4, 5; spec setup-diagnostics)

- [x] 4.1 Tạo `runtime/lib/cmd_doctor.sh` và `runtime/lib/jq/doctor-report.jq`; lệnh `scrum doctor [--json]` trong dispatcher và `usage`; các nhóm công cụ, repo và cấu hình, cài đặt, board như spec, mã thoát 1 khi có lỗi. Kiểm tra: `scrum doctor` chạy trên repo test với `fake-gh` in đủ bốn nhóm
- [x] 4.2 Thêm `tests/test_doctor.sh`, một test cho mỗi scenario của spec setup-diagnostics (gồm sandbox có và không có `SANDBOX_RUNTIME`, board bật và tắt, secret 403), và một test rằng không có lời gọi ghi nào tới `gh`. Kiểm tra: `bash tests/run.sh doctor` xanh
- [x] 4.3 Tạo `skills/doctor/SKILL.md`: chạy `scrum doctor`, giải thích từng mục không đạt và đề nghị chạy lệnh sửa (chỉ chạy khi người dùng đồng ý). Kiểm tra: `claude plugin validate .` đạt và skill có trong danh sách

## 5. `scrum next` (design mục 6; spec next-step-guidance)

- [x] 5.1 Tạo `runtime/lib/jq/next-step.jq` và test jq thuần trong `tests/test_next.sh` cho từng bậc ưu tiên và quy tắc chọn task New. Kiểm tra: `bash tests/run.sh next` xanh
- [x] 5.2 Tạo `runtime/lib/cmd_next.sh` và lệnh `scrum next [--json]` trong dispatcher và `usage`: dừng sớm khi chưa khởi tạo (không gọi GitHub), còn lại thu trạng thái rồi gọi `next-step.jq`. Thêm test lệnh với `fake-gh` cho chưa khởi tạo, chưa push, `--json`, và không có lời gọi ghi. Kiểm tra: `bash tests/run.sh next` xanh
- [x] 5.3 Tạo `skills/next/SKILL.md`: chạy `scrum next`, nói bước kế tiếp, đề nghị chạy lệnh đó. Kiểm tra: `claude plugin validate .` đạt

## 6. Skill dùng `scrum`, đổi tên `init` (design mục 1, 8, 9; spec repo-bootstrap "Tên lệnh khởi tạo")

- [ ] 6.1 Chuyển `skills/scrum-init/` thành `skills/init/` (tên `init`, nội dung dùng `scrum init`, bỏ các ghi chú `--force-file` cho `digest.cron` và `points.scale`); tạo lại `skills/scrum-init/SKILL.md` là skill chuyển tiếp với `disable-model-invocation: true`. Kiểm tra: `claude plugin validate .` đạt; hai skill có trong danh sách
- [ ] 6.2 Trong mọi skill: thay `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` bằng `scrum`, thêm dòng dự phòng của design mục 1, thay dòng cảnh báo sandbox bằng dòng chung của design mục 9; sửa các chỗ nhắc `scrum-init` trong `skills/`, `agents/` và `reference/`. Thêm test trong `tests/test_cli.sh`: mỗi `SKILL.md` gọi lệnh có dòng dự phòng, không còn dòng cảnh báo sandbox cũ, và không còn `scrum-init` ngoài skill chuyển tiếp. Kiểm tra: `bash tests/run.sh cli` xanh

## 7. Phiên bản và tài liệu

- [ ] 7.1 Nâng phiên bản lên 0.5.0 ở `runtime/VERSION` và `.claude-plugin/plugin.json`; thêm mục 0.5.0 vào `CHANGELOG.md` (Added: doctor, next, uninstall, `scrum` trên PATH, cập nhật file tự động; Changed: **Breaking** đổi tên `scrum-init` thành `init`). Kiểm tra: `bash tests/run.sh manifest` xanh
- [ ] 7.2 README plugin: bảng lệnh có `doctor`, `next`, `uninstall`, `init`; mục cài đặt nói chạy `/scrum-github:doctor` sau khi cài; bỏ hướng dẫn `--force-file` cho đổi cấu hình; mục sandbox dẫn tới `doctor`; dòng về nâng cấp từ 0.4 (lần `init` đầu vẫn báo `conflict` với file khác bản mới). Kiểm tra: `grep -n 'scrum-init' README.md` chỉ còn câu về tên cũ; mọi lệnh trong bảng có trong `scrum --help`
- [ ] 7.3 `docs/huong-dan-ap-dung.md` (gốc repo) và `README.md` gốc: bảng lệnh, mục cài đặt và mục xử lý sự cố dùng `/scrum-github:init`, `/scrum-github:doctor`, `/scrum-github:next`; mục xử lý sự cố mở đầu bằng "chạy `/scrum-github:doctor`". Kiểm tra: `grep -rn 'scrum-init' README.md docs/huong-dan-ap-dung.md` không in gì ngoài câu về tên cũ

## 8. Kiểm tra tích hợp

- [ ] 8.1 Chạy toàn bộ `bash tests/run.sh`, lệnh `shellcheck` của README, `openspec validate setup-doctor-and-next --strict` và `claude plugin validate .`. Kiểm tra: tất cả đạt
- [ ] 8.2 Trong một phiên Claude Code có plugin này (cài từ thư mục local), chạy `scrum --version` bằng Bash tool để xác nhận `bin/` nằm trên PATH, rồi `/scrum-github:doctor` và `/scrum-github:next` trên một repo đã cài. Kiểm tra: `scrum --version` in 0.5.0; ghi kết quả vào mô tả PR
- [ ] 8.3 Mở pull request. Kiểm tra: CI (`test (ubuntu-latest)`, `lint`) xanh

## Workflow follow-up

- Sau khi merge: CI trên `main` chạy thêm macOS; kiểm tra nó xanh.
- Archive bằng `/opsx:archive setup-doctor-and-next` để gộp spec vào `openspec/specs/`.
- Xoá skill chuyển tiếp `scrum-init` ở 0.6.0.
