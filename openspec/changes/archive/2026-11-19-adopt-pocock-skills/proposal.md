# Proposal

## Why

Plugin `scrum-github` đã dùng bốn skill của [mattpocock/skills](https://github.com/mattpocock/skills) (`grilling`, `to-spec`, `domain-modeling`, `to-tickets`), nhưng lấy chúng gián tiếp qua plugin `aidw`, nên không thể thêm skill mà `aidw` không có và commit ghi trong `UPSTREAM.md` không phải commit thật sự đã sao chép. Trong khi đó flow còn bốn chỗ đang tự viết hoặc để trống mà upstream đã có skill tốt hơn: câu hỏi mà người đang ngồi phỏng vấn không trả lời được, mô tả task dễ lỗi thời, mô tả pull request, và các bước thủ công khi bật Project board.

## What Changes

- `scripts/vendor-sync.sh` lấy skill thẳng từ một bản clone của `mattpocock/skills` (đường dẫn local, hoặc tự clone khi không truyền đường dẫn), đọc commit bằng git, và không còn nhắc tới `aidw`. **BREAKING** cho người bảo trì: tham số `SRC` giờ là gốc của repo upstream, không phải thư mục `vendor/pocock` của `aidw`.
- Vendor nguyên văn thêm bốn mục: `to-questionnaire`, `pr`, `wizard` (kèm `template.sh`) và file `triage/AGENT-BRIEF.md`. Bốn skill cũ giữ nguyên.
- `/scrum-github:discover`:
  - đối chiếu thuật ngữ của người dùng với mục Glossary của project context (`domain-modeling`, đã vendor);
  - khi một quyết định thuộc về người không có mặt, soạn bảng câu hỏi cho người đó (`to-questionnaire`) trong thư mục plan, và brief giữ `Status: draft` với mục "Open questions".
- `/scrum-github:plan`, agent `plan-critic` và `/scrum-github:task-new` viết mô tả task theo nguyên tắc của `AGENT-BRIEF.md`: mô tả hành vi, không dẫn đường dẫn file hay số dòng, tiêu chí kiểm tra được, nêu phần ngoài phạm vi. `plan-critic` có thêm loại phát hiện cho mô tả dễ lỗi thời.
- Skill mới `/scrum-github:task-pr`: soạn mô tả pull request cho task của nhánh hiện tại theo `pr` (Summary, Evidence, Merge Danger), luôn có `Closes #N`, và chỉ tạo hoặc sửa PR sau khi người dùng duyệt.
- PR template cài vào repo đích có thêm mục Evidence và Merge Danger; mục Task với `Closes #` giữ nguyên.
- Skill mới `/scrum-github:project-setup` và một wizard dựng trên `template.sh` dẫn người dùng qua các bước chỉ con người làm được khi bật Project board (tạo project, tắt built-in workflow, tạo token, đặt secret `SCRUM_PROJECT_TOKEN`).
- README và `UPSTREAM.md` cập nhật; phiên bản plugin lên 0.4.0.

Ngoài phạm vi: `research`, `triage` đầy đủ (state machine và `.out-of-scope/`), `wayfinder`, và các skill phía viết mã (`implement`, `implement-spec`, `tdd`, `code-review`, `prototype`, `diagnosing-bugs`).

## Capabilities

### New Capabilities

- `vendored-skills`: sao chép nguyên văn một danh sách skill cố định từ `mattpocock/skills` vào plugin, ghi nguồn gốc, và quy tắc dùng chúng qua adapter.

### Modified Capabilities

- `requirement-discovery`: thêm đối chiếu thuật ngữ với glossary và bảng câu hỏi cho người vắng mặt; brief không còn là file duy nhất `/discover` có thể ghi trong thư mục plan.
- `task-management`: thêm yêu cầu mô tả task bền; agent soát có thêm một loại phát hiện.
- `pr-task-linking`: thêm việc soạn mô tả PR cho task.
- `repo-bootstrap`: PR template cài vào repo có thêm mục Evidence và Merge Danger.
- `project-board-sync`: thêm trình hướng dẫn tương tác cho các bước thủ công khi bật board.

## Impact

- Mã: `plugins/scrum-github/scripts/vendor-sync.sh`, `vendor/pocock/` (thêm bốn mục, `UPSTREAM.md`), `skills/discover`, `skills/plan`, `skills/task-new`, `agents/plan-critic.md`, skill mới `skills/task-pr` và `skills/project-setup`, wizard mới `wizards/project-board.sh`, `templates/github/pull_request_template.md`, `reference/brief-template.md`, `runtime/share/doc-sections.json`, `.claude-plugin/plugin.json`, `runtime/VERSION`.
- Test: `tests/test_vendor.sh` viết lại cho nguồn là một repo git; thêm test cho wizard (phần thư viện trùng `template.sh`), cho mục tuỳ chọn mới của brief và cho PR template.
- Repo đích đã cài: PR template cũ không bị ghi đè (hành vi sẵn có của `scrum init`); muốn có mục mới thì chạy `scrum init --force-file .github/pull_request_template.md`.
- Không có phụ thuộc mới lúc chạy. `vendor-sync.sh` cần `git` (và mạng khi tự clone); đây là công cụ của người bảo trì, không chạy ở repo đích.
- Không đổi định dạng `plan.json`, không đổi workflow, không đổi quy tắc "không ghi gì lên GitHub trước khi người dùng duyệt".
