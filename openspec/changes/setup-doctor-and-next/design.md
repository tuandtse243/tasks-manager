# Design

## Context

Động cơ: xem proposal.md, mục Why. Yêu cầu: các spec delta của change này. Trạng thái hiện tại cần biết:

- Mọi lệnh đi qua `runtime/bin/scrum`; skill gọi nó bằng `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" …`. `require_tools` dừng ở lỗi đầu tiên.
- `scrum init` (`runtime/lib/cmd_init.sh`) render từng template rồi so từng byte với file trong repo: khác là `conflict`, trừ khi có `--force`/`--force-file`. Nó không biết file khác vì người dùng sửa hay vì cấu hình hoặc template đổi. `.github/scrum/` bị xoá và chép lại mỗi lần chạy.
- Theo tài liệu Claude Code (plugins/components, mục Executables): file trong `bin/` ở gốc plugin nằm trên PATH của Bash tool khi plugin bật, **sau** các mục PATH của người dùng; claude.ai và Cowork không cài plugin có `bin/`; `${CLAUDE_PLUGIN_ROOT}` không được export vào Bash tool.
- Bên trong sandbox của Claude Code có biến môi trường `SANDBOX_RUNTIME=1` (quan sát được, không có trong tài liệu); ngoài sandbox không có. Trong sandbox, `gh auth status` báo "The token in default is invalid" dù người dùng đã đăng nhập.
- Runtime phải chạy trên Bash 3.2 và `ubuntu-latest`; test offline dùng `tests/fake-gh`.

## Goals / Non-Goals

**Goals:**

- `doctor`, `next`, `uninstall` và phần ghi lại file của `init` dùng chung một danh sách file được quản lý và một cách render, để ba lệnh không lệch nhau.
- Mọi quyết định (kết quả kiểm tra, bước kế tiếp, file nào cập nhật hay giữ) là jq thuần hoặc hàm shell nhỏ test được offline.

**Non-Goals:**

- `doctor` không tự sửa gì (không có `--fix`).
- `next` không đọc pull request hay nhánh git; "đang làm dở" chỉ dựa vào label trạng thái và người được giao.
- Không quản lý `.github/scrum.yml` bằng bản ghi file: đó là file của người dùng.

## Decisions

### 1. `bin/scrum` là một wrapper nhỏ

`plugins/scrum-github/bin/scrum` tự tìm đường dẫn thật của mình (đi theo symlink bằng vòng `readlink` không cờ, vì `readlink -f` không có trên macOS) rồi `exec bash "<plugin>/runtime/bin/scrum" "$@"`. Không dùng `${CLAUDE_PLUGIN_ROOT}` vì biến đó không có trong môi trường của Bash tool. `runtime/bin/scrum` giữ nguyên vị trí vì workflow trong repo đích gọi bản chép của nó dưới `.github/scrum/bin/scrum`.

Skill gọi `scrum …`. Mỗi skill giữ một dòng dự phòng: nếu không tìm thấy `scrum`, hoặc `scrum --version` không in phiên bản plugin, dùng `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"`. Dòng này phủ cả Claude Code cũ chưa đưa `bin/` vào PATH.

Phương án khác: chỉ ghi đường dẫn dài trong skill như hiện nay. Đúng nhưng không đạt mục tiêu của proposal và không cho người dùng gõ `scrum` trong phiên.

### 2. Bản ghi file đã sinh: `.github/scrum/files.json`

```json
{"version": 1, "files": {".github/pull_request_template.md": "<git blob hash>", "...": "..."}}
```

- Hash là `git hash-object FILE`: có sẵn ở mọi nơi có git, giống nhau trên macOS và Linux (khác `shasum`/`sha256sum`).
- Nằm trong `.github/scrum/` vì thư mục này đã là "sinh ra, đừng sửa" và được commit cùng workflow, nên cả team dùng chung. `init` đọc bản ghi **trước** khi xoá thư mục và ghi lại **sau** khi chép runtime; chế độ xem trước chỉ đọc.
- `uninstall` xoá luôn bản ghi cùng thư mục.

Phương án khác: một file riêng như `.github/scrum-files.json`. Thêm một file lạ ở `.github/` của người dùng mà không lợi gì.

Quy tắc cho mỗi file được quản lý (bản mới = template render theo cấu hình hiện tại):

| File trong repo | Bản ghi | Kết quả |
|---|---|---|
| không có | – | tạo, ghi hash |
| giống bản mới | – | `unchanged`, ghi hash |
| khác, hash = bản ghi | có | cập nhật (`updated`), ghi hash mới |
| khác, hash ≠ bản ghi hoặc không có bản ghi | – | `conflict`, giữ bản ghi cũ nếu có; với `--force`/`--force-file` thì ghi đè và ghi hash |

Repo cài bằng bản cũ chưa có bản ghi nên file khác bản mới vẫn là `conflict` lần đầu, đúng như spec "Repo đã cài bản cũ".

### 3. Một danh sách file được quản lý

Hàm `managed_files` in từng dòng `template<TAB>đường dẫn` (Issue Form, PR template, ba workflow, thêm workflow board khi `project.enabled`). `init`, `doctor` (file cũ so với cấu hình) và `uninstall` đều đọc danh sách này và dùng chung `render_template`. `uninstall` xét thêm workflow board kể cả khi board đã tắt, vì nó có thể còn từ lúc bật.

### 4. `doctor`: ghi từng mục, render một lần

Mỗi kiểm tra là một hàm shell gọi `check GROUP ID STATUS MESSAGE [FIX]`, nối một dòng JSON vào file tạm. Không dùng `require_tools` hay `load_config` vì chúng dừng ở lỗi đầu tiên: cấu hình được nạp trong một subshell và lỗi của nó thành thông báo của mục. Cuối cùng một chương trình jq (`doctor-report.jq`) in bản cho người đọc hoặc JSON, và mã thoát là 1 khi có mục `error`.

Phụ thuộc giữa các mục: thiếu `jq` thì chỉ in được bản thô và dừng; `gh` chưa dùng được thì mọi mục cần GitHub là `skip` với lý do; không có cấu hình thì mục label và file sinh ra là `skip`.

Lời gọi GitHub, đều là GET:

- `gh auth status` (scope đọc từ dòng "Token scopes" của tài khoản đang dùng; không có dòng đó, ví dụ token fine-grained, thì mục scope là `warn` "không đọc được scope");
- `repos/{repo}/labels`;
- `repos/{repo}/contents/.github/workflows` (không truyền `ref` là nhánh mặc định; 404 nghĩa là chưa có gì);
- `repos/{repo}/actions/secrets` khi board bật (403/404 là `warn` không kiểm tra được).

### 5. Nhận ra sandbox

Khi `gh auth status` thất bại hoặc báo token không hợp lệ và `SANDBOX_RUNTIME=1`, `doctor` báo sandbox và cách chạy ngoài sandbox. `require_tools` cũng thêm một câu tương tự vào lỗi "gh is not logged in" trong trường hợp đó và dẫn tới `/scrum-github:doctor`. Biến không có trong tài liệu, nên khi thiếu biến, thông báo quay về lời khuyên `gh auth login` như cũ: sai chỉ làm lời khuyên kém đi, không làm hỏng lệnh.

Phương án khác: dò `CLAUDECODE=1`. Biến này có cả ngoài sandbox, nên sẽ báo sandbox nhầm.

### 6. `next`: shell thu trạng thái, jq quyết định

Shell dừng sớm theo thứ tự ưu tiên để không gọi GitHub khi chưa cần: chưa có `.github/scrum.yml` thì trả bước khởi tạo ngay. Sau đó lấy danh sách workflow trên nhánh mặc định (như `doctor`), milestone, issue của sprint hiện tại và login của người dùng (`gh api user`), rồi đưa một đối tượng trạng thái vào `next-step.jq`. Chương trình jq dùng lại `current_sprint`, `sprint_info`, `report_tasks` của `scrum.jq` và trả `{step, message, command, issues}`.

"Đã push" nghĩa là `scrum-status-sync.yml` có trên nhánh mặc định của remote: đó là workflow mọi cài đặt đều có, và nó là thứ làm trạng thái tự đổi.

### 7. `uninstall`

Chỉ cục bộ: `require_tools nogh`, nạp cấu hình nếu có (không có thì dùng mặc định để render). Một file được quản lý là "chưa sửa" khi hash của nó bằng bản ghi hoặc nó giống bản render hiện tại; còn lại là "đã sửa" và được giữ. Theo mẫu của `sprint close`: không có `--yes` thì chỉ in kế hoạch; `--dry-run` không bao giờ ghi.

### 8. Đổi tên skill

`skills/init/` là skill chính. `skills/scrum-init/` còn lại trong 0.5.x với `disable-model-invocation: true`, để Claude không tự chọn nó thay cho `init`, nhưng người dùng gõ tên cũ vẫn chạy được; nội dung của nó báo tên mới rồi làm theo `skills/init/SKILL.md`. Xoá ở 0.6.0.

### 9. Dòng sandbox trong skill

Dòng cảnh báo sandbox ở từng skill được thay bằng một dòng chung: "Nếu một lệnh `scrum` hoặc `gh` báo lỗi đăng nhập hay mạng, chạy `/scrum-github:doctor`." Chi tiết về sandbox chỉ còn ở `doctor` và trong phần xử lý sự cố của tài liệu.

## Risks / Trade-offs

- [Người dùng đã có một lệnh khác tên `scrum` trên PATH, và nó đứng trước `bin/` của plugin] → skill gọi nhầm lệnh. Dòng dự phòng trong mỗi skill nói: nếu `scrum --version` không in phiên bản plugin thì dùng đường dẫn đầy đủ; ghi thêm trong phần xử lý sự cố.
- [`SANDBOX_RUNTIME` đổi tên hoặc biến mất ở bản Claude Code sau] → chỉ mất lời khuyên đúng về sandbox, như hiện nay.
- [Người dùng sửa file rồi sửa ngược lại đúng bản đã sinh] → hash trùng, file được coi là chưa sửa và sẽ được cập nhật. Đúng vì nội dung không khác gì bản đã sinh.
- [Hai người chạy `init` ở hai nhánh và commit hai bản ghi khác nhau] → xung đột merge ở `files.json`. Chạy lại `init` sau khi merge sẽ ghi lại bản đúng; ghi điều này trong tài liệu xử lý sự cố.
- [`doctor` gọi GitHub bốn lần] → chậm vài giây; chấp nhận vì người dùng gọi nó khi có vấn đề.

## Migration Plan

- Nâng lên 0.5.0 rồi chạy `/scrum-github:init`: file giống bản mới được ghi vào bản ghi; file khác bản mới vẫn là `conflict` như 0.4.0. Sau khi người dùng ghi đè (hoặc giữ) các file đó, từ lần sau mọi file chưa sửa tự cập nhật.
- Quay lại 0.4.0: cài lại bản cũ và chạy `scrum init`. Bản cũ xoá và chép lại `.github/scrum/`, nên `files.json` tự mất; không có gì khác phải dọn.
