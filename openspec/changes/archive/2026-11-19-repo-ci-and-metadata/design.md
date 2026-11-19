# Design

## Context

Động cơ: xem proposal.md, mục Why. Trạng thái hiện tại cần biết:

- Test chạy bằng `bash plugins/scrum-github/tests/run.sh`, không cần mạng; `gh` được thay bằng `tests/fake-gh`. Test cần `jq` và `yq` bản mikefarah; một số test tự bỏ qua khi thiếu `yq`.
- Runtime phải chạy trên Bash 3.2 (macOS) và trên `ubuntu-latest` (nơi các workflow của repo đích chạy).
- Repo chưa có thư mục `.github/` ở gốc. Các file dưới `plugins/scrum-github/templates/github/` là template cho repo đích, không phải workflow của repo này.
- Máy phát triển hiện không có `shellcheck`.
- `openspec/changes/.claude/` chỉ chứa `.cc-writes/`, do Claude Code tạo ra khi ghi file dưới `openspec/changes/`.

## Goals / Non-Goals

**Goals:**

- Mỗi pull request và mỗi push vào `main` chạy cùng bộ kiểm tra mà người phát triển chạy được ở máy.
- Mọi kiểm tra không cần công cụ ngoài (JSON hợp lệ, phiên bản khớp) nằm trong bộ test offline, để CI và máy cá nhân cho cùng kết quả.

**Non-Goals:**

- Bắt buộc check CI bằng branch protection (là thiết lập của chủ repo, làm tay).
- Chạy test end-to-end với GitHub thật trong CI.
- Tự động phát hành hay gắn tag phiên bản.

## Decisions

### 1. Một workflow, hai job

`ci.yml` có job `test` và job `lint`, chạy song song. Tách ra để lỗi `shellcheck` không che kết quả test và ngược lại.

- `test`: chạy trên ma trận `ubuntu-latest` và `macos-latest`. macOS bắt được lỗi tương thích Bash 3.2 và khác biệt của `date`, `sed`, `mktemp` bản BSD, là loại lỗi mà test trên Linux không thấy. Trên macOS cần `brew install yq` (jq có sẵn); trên Ubuntu cả hai có sẵn.
- `lint`: chỉ `ubuntu-latest`, nơi `shellcheck` có sẵn.

Phương án khác: chỉ Ubuntu. Rẻ hơn, nhưng bỏ đúng môi trường mà người dùng plugin chạy nhiều nhất.

### 2. Kiểm tra manifest nằm trong bộ test, không nằm trong YAML

File mới `tests/test_manifest.sh` chứa: `plugin.json` và `marketplace.json` phân tích được; `plugin.json` có `name`, `version`, `description`, `repository`, `homepage`, `license`; `version` trùng `runtime/VERSION`; mục plugin trong `marketplace.json` trỏ tới thư mục có thật.

Lý do: workflow YAML không chạy được ở máy; test thì chạy được và đã có khung sẵn.

Không thêm bước kiểm tra cú pháp riêng cho `runtime/lib/jq/*.jq`: jq coi biến `$tên` chưa được truyền là lỗi biên dịch, nên không biên dịch được một chương trình mà không biết đủ đối số của nó. Các chương trình này đã được chạy thật trong các test hiện có.

### 3. `shellcheck` với danh sách file tường minh

Lint: `runtime/bin/scrum`, `runtime/lib/*.sh`, `scripts/*.sh`, `wizards/*.sh`, `tests/run.sh`, `tests/test_*.sh`, `tests/fake-gh`. Không lint `vendor/`. Riêng `wizards/project-board.sh` có phần đầu phải trùng từng byte với `vendor/pocock/wizard/template.sh` (test `test_wizard.sh` kiểm tra điều đó), nên lỗi `shellcheck` ở phần đó được tắt bằng một file `.shellcheckrc` hoặc tuỳ chọn `--exclude` cho riêng file này, không sửa mã.

Mức độ: `--severity=warning`. Mức `style` và `info` sinh nhiều gợi ý về trích dẫn mà mã hiện tại cố ý không theo để giữ Bash 3.2.

Các lỗi mức warning trong mã hiện có: sửa khi việc sửa không đổi hành vi; nếu không thì thêm `# shellcheck disable=SCxxxx` kèm một dòng lý do ngay trên dòng đó.

### 4. Quyền và kích hoạt của workflow

`on: pull_request` và `push` vào `main`; `permissions: contents: read`; `concurrency` theo ref để huỷ lần chạy cũ của cùng nhánh. Không dùng `pull_request_target`: CI chạy mã của PR, nên không được có quyền ghi hay secret.

### 5. CHANGELOG theo "Keep a Changelog"

`plugins/scrum-github/CHANGELOG.md`, mỗi phiên bản một mục, mới nhất ở trên. Viết lại lịch sử 0.1.0 đến 0.4.0 từ bốn change đã archive trong `openspec/changes/archive/` và hai ghi chú trong README. Viết bằng tiếng Anh, cùng ngôn ngữ với README của plugin.

### 6. Thư mục lạc

Xoá `openspec/changes/.claude/` và thêm `openspec/changes/.claude/` vào `.gitignore`. Thêm vào `.gitignore` không ngăn Claude Code tạo lại thư mục, nên `openspec list` vẫn có thể hiện nó ở máy đang dùng Claude Code; đây là hành vi của công cụ, không sửa được trong repo này. Ghi một dòng về điều đó trong mục Phát triển của README gốc.

## Risks / Trade-offs

- [Runner macOS chậm và tốn phút hơn Linux] → bộ test khoảng 2 phút; repo công khai không tính phút. Nếu repo chuyển sang riêng tư thì bỏ macOS khỏi ma trận là thay đổi một dòng.
- [`shellcheck` trên runner được nâng phiên bản và báo lỗi mới] → chấp nhận; lỗi mới là tín hiệu có ích, và sửa là việc nhỏ.
- [Test trên macOS của CI lộ ra lỗi thật trong mã hiện có] → sửa trong change này nếu nhỏ; nếu lớn thì ghi lại thành task riêng và tạm đánh dấu job macOS `continue-on-error` cho tới khi sửa xong.

## Open Questions

- Sau khi CI chạy ổn, có bật branch protection bắt buộc check này cho `main` không. Không ảnh hưởng tới việc cần làm trong change này.
