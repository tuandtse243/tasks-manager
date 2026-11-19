# Tasks

Đường dẫn tính từ gốc repo. Change này không đổi mã runtime (`skip_specs: true`). Test tài liệu chạy trong bộ test của plugin: `bash plugins/scrum-github/tests/run.sh test_docs`.

## 1. Test giữ tài liệu khớp với mã

- [x] 1.1 Tạo `plugins/scrum-github/tests/test_docs.sh`: mọi lệnh trong `scrum --help` có trong bảng lệnh của README plugin và ngược lại; mọi khoá lá trong `runtime/share/defaults.json` có trong mục Configuration của README plugin; mọi skill trong `skills/` có trong bảng lệnh của `docs/huong-dan-ap-dung.md`; mọi liên kết tương đối trong `README.md`, `docs/*.md`, `plugins/scrum-github/README.md`, `plugins/scrum-github/CHANGELOG.md` trỏ tới file có thật. Kiểm tra: test chạy được; ghi lại các chỗ đang đỏ để sửa ở nhóm 2 và 3

## 2. Chia vai cho hai tài liệu chính

- [x] 2.1 README plugin là tài liệu tra cứu: đủ mọi lệnh và tuỳ chọn, mọi khoá cấu hình, quy tắc đổi trạng thái, cách lưu dữ liệu, phát triển; bỏ phần hướng dẫn theo việc trùng với hướng dẫn áp dụng. Kiểm tra: phần README của `test_docs.sh` xanh
- [x] 2.2 `docs/huong-dan-ap-dung.md` là tài liệu theo việc: cài đặt, flow theo vai trò, quy ước team, xử lý sự cố, giới hạn; bảng cấu hình đầy đủ và bảng tuỳ chọn được thay bằng liên kết tới README plugin; mục "Xử lý sự cố" mở đầu bằng `/scrum-github:doctor` và chỉ giữ lỗi về cách dùng; mục "Giới hạn hiện tại" cập nhật theo change 2 đến 5. Kiểm tra: phần hướng dẫn của `test_docs.sh` xanh

## 3. Cheat sheet và README gốc

- [x] 3.1 Tạo `docs/cheat-sheet-po.md`, `docs/cheat-sheet-sm.md`, `docs/cheat-sheet-dev.md`: mỗi trang các lệnh của vai đó theo thứ tự dùng trong một sprint, mỗi lệnh một ví dụ, không quá 60 dòng. Kiểm tra: `wc -l docs/cheat-sheet-*.md` mỗi file ≤ 60; liên kết trong đó qua `test_docs.sh`
- [x] 3.2 README gốc: plugin là gì, cài trong ba bước, một ví dụ chạy trọn một task, bảng "bạn là ai thì đọc gì" dẫn tới cheat sheet; giữ huy hiệu CI và mục Phát triển. Kiểm tra: liên kết qua `test_docs.sh`

## 4. Sơ đồ

- [x] 4.1 Cập nhật `docs/diagrams/sprint-flow` (nguồn `.workflow.json`, bản `.html`, ảnh `.png`) cho các lệnh mới: `init`, `doctor`, `next`, `backlog`, `sprint-fill`, `task`, và trạng thái In review tuỳ chọn. Kiểm tra: `grep -c 'scrum-init' docs/diagrams/sprint-flow.html` là 0; ảnh mở được

## 5. Kiểm tra tích hợp

- [x] 5.1 Toàn bộ test của plugin, `shellcheck`, `openspec validate docs-by-role`. Kiểm tra: tất cả đạt
- [x] 5.2 Mở pull request, CI xanh, merge

## Workflow follow-up

- Archive bằng `/opsx:archive docs-by-role` (không có spec để gộp).
