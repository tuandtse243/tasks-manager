# Proposal

Thứ tự trong lộ trình: **1 trên 6**. Làm trước để năm change sau được CI kiểm tra.

## Why

Bộ test offline của plugin (khoảng 2 phút, `gh` giả) hiện chỉ chạy khi ai đó nhớ gõ lệnh, và repo không có lint cho shell hay kiểm tra manifest. Năm change tiếp theo sửa nhiều vào runtime, nên cần một lưới an toàn tự chạy trước khi bắt đầu. Repo cũng thiếu vài thứ mà người cài plugin mong thấy: giấy phép, lịch sử thay đổi, và metadata trong manifest.

## What Changes

- Thêm workflow CI ở gốc repo (`.github/workflows/ci.yml`), chạy trên pull request và trên push vào `main`:
  - `bash plugins/scrum-github/tests/run.sh` (toàn bộ test offline);
  - `shellcheck` cho `runtime/bin/scrum`, `runtime/lib/*.sh`, `scripts/*.sh`, `wizards/*.sh`, `tests/*.sh` (không lint `vendor/`);
  - kiểm tra manifest: `plugin.json` và `marketplace.json` là JSON hợp lệ, phiên bản trong `plugin.json` trùng `runtime/VERSION`.
- Thêm một test offline cho chính các kiểm tra manifest ở trên, để chạy được ở máy cá nhân mà không cần CI.
- `plugin.json` có thêm `repository`, `homepage`, `license`.
- Thêm `LICENSE` ở gốc repo và `CHANGELOG.md` cho plugin; chuyển các đoạn "New in 0.4.0" và "Renamed in 0.3.0" từ README của plugin sang CHANGELOG, README chỉ còn một dòng dẫn tới đó.
- Dọn thư mục lạc `openspec/changes/.claude/` (đang hiện thành một change tên `.claude` trong `openspec list`) và thêm vào `.gitignore` để nó không quay lại.

Ngoài phạm vi: `claude plugin validate --strict` trong CI (cần cài Claude Code trên runner; chỉ ghi lệnh vào mục Development để chạy tay), publish plugin lên thư mục của Anthropic, và mọi thay đổi hành vi của runtime.

## Capabilities

### New Capabilities

Không có.

### Modified Capabilities

Không có. Change này chỉ thêm công cụ và metadata, không đổi hành vi nào đã có spec, nên đặt `skip_specs: true` trong `.openspec.yaml`.

## Impact

- File mới: `.github/workflows/ci.yml`, `LICENSE`, `plugins/scrum-github/CHANGELOG.md`, một file test mới trong `plugins/scrum-github/tests/`.
- File sửa: `plugins/scrum-github/.claude-plugin/plugin.json`, `plugins/scrum-github/README.md`, `README.md` (mục Phát triển), `.gitignore`.
- `shellcheck` có thể báo lỗi ở mã đang có; change này sửa các lỗi đó hoặc tắt từng quy tắc kèm lý do, không đổi hành vi.
- **Cần người dùng quyết định trước khi làm**: loại giấy phép (đề xuất MIT, trùng với giấy phép của các skill vendor từ `mattpocock/skills`) và tên chủ bản quyền ghi trong `LICENSE`.
- Không có phụ thuộc mới lúc chạy. Repo đích đã cài plugin không bị ảnh hưởng.
