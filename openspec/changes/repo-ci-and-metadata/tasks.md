# Tasks

Đường dẫn tính từ gốc repo. Chạy test bằng `bash plugins/scrum-github/tests/run.sh` (một file: thêm tên, ví dụ `manifest`). Nhóm 1 cần quyết định của người dùng; nhóm 2 đến 4 độc lập với nhau; nhóm 5 cần nhóm 2 và 3.

## 1. Giấy phép và metadata (proposal mục Impact)

- [x] 1.1 Hỏi người dùng loại giấy phép (đề xuất MIT) và tên chủ bản quyền, rồi tạo `LICENSE` ở gốc repo. Kiểm tra: file tồn tại, năm và tên đúng như người dùng trả lời
- [x] 1.2 Thêm `repository` (`https://github.com/tuandtse243/tasks-manager`), `homepage` (URL tới README của plugin trên GitHub) và `license` (mã SPDX của giấy phép ở 1.1) vào `plugins/scrum-github/.claude-plugin/plugin.json`. Kiểm tra: `jq -e '.repository and .homepage and .license' plugins/scrum-github/.claude-plugin/plugin.json` trả mã 0

## 2. Kiểm tra manifest trong bộ test (design mục 2)

- [x] 2.1 Tạo `plugins/scrum-github/tests/test_manifest.sh` với các test: hai file manifest là JSON hợp lệ; `plugin.json` có đủ `name`, `version`, `description`, `repository`, `homepage`, `license`; `version` trùng `runtime/VERSION`; `source` của plugin trong `.claude-plugin/marketplace.json` trỏ tới thư mục có `plugin.json`. Kiểm tra: `bash plugins/scrum-github/tests/run.sh manifest` xanh; tạm sửa `runtime/VERSION` thành `9.9.9` thì test phiên bản đỏ, rồi hoàn lại

## 3. Lint shell (design mục 3)

- [x] 3.1 Cài `shellcheck` ở máy (`brew install shellcheck`) và chạy với `--severity=warning` trên danh sách file của design mục 3; ghi lại số lỗi theo từng file. Kiểm tra: có danh sách lỗi ban đầu để đối chiếu ở 3.2
- [x] 3.2 Xử lý từng lỗi: sửa khi không đổi hành vi, nếu không thì thêm `# shellcheck disable=SCxxxx` kèm một dòng lý do; phần đầu của `wizards/project-board.sh` trùng với `vendor/pocock/wizard/template.sh` thì loại trừ bằng cấu hình, không sửa mã. Kiểm tra: lệnh `shellcheck` ở 3.1 trả mã 0, và `bash plugins/scrum-github/tests/run.sh` vẫn xanh toàn bộ (gồm `test_wizard.sh` so từng byte)
- [x] 3.3 Ghi lệnh `shellcheck` đầy đủ vào mục "Development" của `plugins/scrum-github/README.md` và mục "Phát triển" của `README.md`, cùng lệnh `claude plugin validate plugins/scrum-github` để chạy tay. Kiểm tra: chép lệnh `shellcheck` từ README ra chạy, kết quả mã 0

## 4. CHANGELOG và dọn dẹp (design mục 5, 6)

- [x] 4.1 Tạo `plugins/scrum-github/CHANGELOG.md` theo "Keep a Changelog", các mục 0.4.0 về 0.1.0, nội dung lấy từ bốn change trong `openspec/changes/archive/` và hai ghi chú "New in 0.4.0", "Renamed in 0.3.0" của README. Kiểm tra: mỗi phiên bản có ít nhất một dòng; mục trên cùng trùng `runtime/VERSION`; thêm vào `test_manifest.sh` một test rằng CHANGELOG có tiêu đề cho phiên bản hiện tại
- [x] 4.2 Thay hai ghi chú phiên bản trong `plugins/scrum-github/README.md` bằng một dòng dẫn tới `CHANGELOG.md`; giữ lại câu hướng dẫn `scrum init --force-file .github/pull_request_template.md` ở chỗ nói về PR template. Kiểm tra: `grep -n "New in 0.4.0\|Renamed in 0.3.0" plugins/scrum-github/README.md` không in gì, và liên kết tới CHANGELOG mở được
- [x] 4.3 Xoá `openspec/changes/.claude/`, thêm dòng `openspec/changes/.claude/` vào `.gitignore`, và ghi một dòng về thư mục này trong mục "Phát triển" của `README.md`. Kiểm tra: `git status --short` không liệt kê thư mục đó sau khi một file dưới `openspec/changes/` được ghi lại

## 5. Workflow CI (design mục 1, 4)

- [x] 5.1 Tạo `.github/workflows/ci.yml`: kích hoạt `pull_request` và `push` vào `main`, `permissions: contents: read`, `concurrency` theo ref; job `test` trên ma trận `ubuntu-latest` và `macos-latest` (cài `yq` bằng brew trên macOS) chạy `bash plugins/scrum-github/tests/run.sh`; job `lint` trên `ubuntu-latest` chạy đúng lệnh `shellcheck` đã ghi ở 3.3. Kiểm tra: `yq '.jobs | keys' .github/workflows/ci.yml` in `lint` và `test`; file không chứa `pull_request_target` hay `secrets.`
- [x] 5.2 Đẩy nhánh và mở pull request cho change này. Kiểm tra: cả ba lần chạy (test Ubuntu, test macOS, lint) xanh trên GitHub; nếu job macOS lộ lỗi thật trong mã hiện có thì xử lý theo design mục Risks và ghi lại trong mô tả PR
- [ ] 5.3 Thêm huy hiệu trạng thái CI vào đầu `README.md` và một câu trong mục "Phát triển" rằng CI chạy cùng hai lệnh đó. Kiểm tra: huy hiệu hiện trạng thái của `main` sau khi merge

## Workflow follow-up

- Sau khi merge: cân nhắc bật branch protection bắt buộc check `test` và `lint` cho `main` (design mục Open Questions).
- Archive change bằng `/opsx:archive`. Change này đặt `skip_specs: true` nên không có spec nào để gộp.
