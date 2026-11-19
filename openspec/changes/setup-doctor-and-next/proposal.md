# Proposal

Thứ tự trong lộ trình: **2 trên 6**. Độc lập với các change sau; `next` sẽ được mở rộng khi change 3 thêm backlog.

## Why

Người mới vấp ở cài đặt chứ không phải ở Scrum: mục "Xử lý sự cố" của hướng dẫn có 17 dòng, phần lớn là lỗi môi trường (cài nhầm `yq`, `gh` thiếu scope, chưa push `.github/`, runtime trong repo cũ hơn plugin, secret board rỗng) mà hiện mỗi lỗi chỉ lộ ra khi một lệnh khác thất bại. Sau khi cài xong, plugin có 12 lệnh và không lệnh nào trả lời câu "giờ tôi làm gì tiếp". Vài bước thủ công còn sót lại (`--force-file` sau khi đổi cấu hình, gỡ cài đặt bằng tay, gõ đường dẫn dài tới script) cũng làm việc dùng hằng ngày nặng hơn cần thiết.

## What Changes

- Lệnh mới `scrum doctor [--json]` và skill `/scrum-github:doctor`: kiểm tra một lượt và in từng mục là đạt, cảnh báo hay lỗi, kèm lệnh sửa:
  - công cụ: `jq`, `yq` đúng bản mikefarah, `gh` đã đăng nhập và có scope `repo`, `workflow` (và `project` khi board bật);
  - repo: có remote GitHub, `.github/scrum.yml` hợp lệ, đủ label theo cấu hình;
  - cài đặt: các workflow `scrum-*` có trên nhánh mặc định của remote (không chỉ ở máy), phiên bản `.github/scrum/VERSION` so với phiên bản plugin, file sinh ra đã cũ so với cấu hình;
  - board (khi bật): secret `SCRUM_PROJECT_TOKEN` tồn tại, workflow đồng bộ có mặt;
  - nhận ra trường hợp `gh` báo token sai vì sandbox của Claude Code chặn keychain và nói rõ cách chạy ngoài sandbox.
  Lệnh chỉ đọc; mã thoát khác 0 khi có lỗi.
- Lệnh mới `scrum next [--json]` và skill `/scrum-github:next`: đọc trạng thái rồi nêu một bước kế tiếp kèm lệnh, theo thứ tự ưu tiên: chưa khởi tạo → chưa push `.github/` → chưa có sprint mở → sprint đã quá ngày kết thúc → task của tôi đang In progress → task chưa có điểm hoặc chưa giao trong sprint → gợi ý nhận task New.
- `scrum init` ghi lại hash của từng file nó sinh ra. Lần chạy sau, file mà người dùng **không sửa** nhưng khác bản mới (vì đổi `points.scale`, `digest.cron`, `project.poll_cron` hoặc nâng plugin) được cập nhật luôn; chỉ file người dùng đã sửa tay mới báo `conflict`. Hết cần `--force-file` cho hai trường hợp trong tài liệu.
- Lệnh mới `scrum uninstall [--dry-run] [--yes]`: gỡ `.github/scrum/`, các workflow `scrum-*` và các template còn nguyên bản; giữ `scrum.yml`, label, milestone và issue; in những gì bị giữ lại và vì sao.
- Script `scrum` nằm trên PATH trong Claude Code qua thư mục `bin/` của plugin, nên các skill gọi `scrum …` thay cho `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" …`.
- **BREAKING**: skill `scrum-init` đổi tên thành `init` (`/scrum-github:init`). Tên cũ còn lại một phiên bản dưới dạng skill chuyển tiếp, in lời nhắc dùng tên mới.
- Dòng cảnh báo sandbox lặp ở 12 skill được thay bằng một dòng dẫn tới `/scrum-github:doctor`.
- Phiên bản plugin lên 0.5.0.

Ngoài phạm vi: bỏ phụ thuộc `yq`, hook `SessionStart` tự in tình trạng sprint (gọi `gh` mỗi lần mở phiên thì chậm và vướng sandbox), và hỗ trợ Windows ngoài WSL.

## Capabilities

### New Capabilities

- `setup-diagnostics`: kiểm tra môi trường, cấu hình và phần đã cài của một repo, báo từng mục kèm cách sửa, không ghi gì.
- `next-step-guidance`: từ trạng thái của repo, sprint và task của người đang dùng, nêu một bước kế tiếp theo thứ tự ưu tiên cố định.

### Modified Capabilities

- `repo-bootstrap`: "Cài template vào repo" phân biệt file người dùng đã sửa với file chỉ cũ so với cấu hình; thêm yêu cầu gỡ cài đặt.
- `scrum-config`: "Kiểm tra công cụ và đăng nhập" nêu thêm trường hợp sandbox và dẫn tới `doctor`.

## Impact

- Mã: `runtime/bin/scrum`, file mới `runtime/lib/cmd_doctor.sh`, `runtime/lib/cmd_next.sh`, chương trình jq tương ứng, `runtime/lib/cmd_init.sh` (hash và `uninstall`), thư mục mới `bin/` của plugin, skill mới `skills/doctor`, `skills/next`, `skills/init` (và skill chuyển tiếp `skills/scrum-init`), sửa dòng gọi script trong mọi skill.
- File mới trong repo đích: một file ghi hash các file đã sinh, dưới `.github/scrum/` hoặc cạnh nó (vị trí chốt ở design, vì `.github/scrum/` bị thay mỗi lần `init`).
- Repo đích đã cài trước đó chưa có file hash: lần `init` đầu sau khi nâng cấp phải coi file khác bản mới là `conflict` như hiện nay, rồi mới bắt đầu ghi hash.
- Plugin có thư mục `bin/` thì claude.ai và Cowork không cài được; plugin này chỉ dành cho Claude Code nên chấp nhận.
- Test: thêm `tests/test_doctor.sh`, `tests/test_next.sh`; mở rộng `tests/test_init.sh` cho hash và `uninstall`.
- Tài liệu: bảng lệnh, mục cài đặt và mục "Xử lý sự cố" của hai tài liệu (viết lại toàn bộ ở change 6).
