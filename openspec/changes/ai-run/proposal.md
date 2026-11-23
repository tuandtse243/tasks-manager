# Proposal

Thứ tự trong lộ trình: **3 trên 3**. Cần `team-and-backlog-tasks` (`scrum mine`, đợt theo phụ thuộc) và `time-estimates` (ước lượng thời gian để lập lịch và so với thời gian thật).

## Why

Task của team chủ yếu do AI làm, nhưng plugin dừng ở chỗ quản lý: dev vẫn phải tự mở từng task, tự gọi agent, tự tạo branch và PR cho từng cái. Các task không phụ thuộc nhau đáng lẽ chạy song song được, và người review cần một PR có sẵn danh sách để kiểm, thay vì đọc diff mù. Ước lượng thời gian AI (change 2) cũng chỉ là dự đoán nếu không có ai đo thời gian thật.

## What Changes

- Skill mới `/scrum-github:run`: chạy các task của tôi bằng agent. Mỗi task chạy trong một git worktree riêng ở local, song song theo đợt phụ thuộc. Xong mỗi đợt thì merge vào một nhánh tích hợp và chạy test. Cuối cùng push riêng nhánh tích hợp và mở **một PR** vào nhánh mặc định, với `Closes #N` cho mọi task xong. Worktree và nhánh của từng task không bao giờ được push.
- Agent mới `scrum-github:implementer`: làm một task trong worktree của nó theo acceptance của issue, chạy test, commit ở local, rồi trả về kết quả, cách test tay, và những chỗ nó chưa chắc.
- Lệnh runtime mới `scrum run`:
  - `plan`: chọn task và chia đợt, xem trước được. Mặc định chọn task của tôi trong sprint đang mở, trạng thái New, có label `ai-ready`.
  - `start`: tạo nhánh tích hợp và chuyển task sang In progress.
  - `merge`: merge nhánh của một task vào nhánh tích hợp, dừng và báo khi conflict.
  - `record`: ghi task xong hoặc lỗi, kèm thời gian thật.
  - `finish`: push và mở PR.
  - `status`: xem lại một lần chạy.
- `--dry-run` chỉ in các đợt, task bị loại kèm lý do, và ước tính thời gian. `--pr-per-wave` mở một PR cho mỗi đợt thay vì một PR. `--max-parallel K` giới hạn số agent chạy cùng lúc (mặc định 3).
- Trạng thái của một lần chạy được lưu ở local trong `.scrum/run/<id>.json` (bỏ qua bởi git), để chạy lại thì làm tiếp từ chỗ dừng.
- Mô tả PR là gói review: mỗi task có acceptance để tích, thời gian ước lượng so với thời gian thật, cách test tay, những chỗ cần nhìn kỹ. Task lỗi bị bỏ khỏi PR, có comment lý do trên issue và trở về New.
- Thời gian thật của mỗi task được ghi thành comment trên issue (khối `actual`), cạnh ước lượng.
- Plan có trường `ai_ready` cho từng task. `plan apply` gắn label `ai-ready` cho task có trường này. Khoá mới `labels.ai_ready`; `init` tạo label này.
- Khối cấu hình mới `run`: `test_command` (lệnh test của repo; trống thì agent tự tìm), `max_parallel`, `branch_pattern` (mặc định `run/{sprint}-{login}`).
- Phiên bản plugin lên 0.11.0.

Ngoài phạm vi: giới hạn chi phí token; chạy trên máy chủ hoặc CI; tự sửa PR theo comment review; hiệu chỉnh ước lượng từ thời gian thật (chỉ ghi dữ liệu); đo thời gian review của người.

## Capabilities

### New Capabilities

- `ai-run`: chạy task bằng agent: chọn task, chia đợt, worktree local, nhánh tích hợp, merge, xử lý lỗi và conflict, PR gói review, thời gian thật, chạy tiếp.

### Modified Capabilities

- `scrum-config`: khối `run` và nhãn `labels.ai_ready`.
- `work-plan`: trường `ai_ready` của task và label khi áp plan.

## Impact

- Mã (tính từ `plugins/scrum-github/`): file mới `runtime/lib/cmd_run.sh`; jq mới `run-select.jq`, `run-state.jq`, `run-pr-body.jq`; `runtime/bin/scrum`; `defaults.json`, `validate-config.jq`, `label-plan.jq` (label `ai-ready`); `plan.schema.json`, `plan-validate.jq`, `plan-actions.jq`; `strings.json`.
- Skill mới `run`; agent mới `agents/implementer.md`; sửa `my-tasks` và `next` để gợi ý `/scrum-github:run` khi có task `ai-ready`.
- Git: tạo nhánh và worktree ở local, merge, chỉ push nhánh tích hợp. Cần git ≥ 2.20.
- API GitHub: đổi label trạng thái, comment trên issue, tạo PR. Không cần quyền mới.
- An toàn: agent chạy mã và test của repo trên máy người dùng, trong worktree riêng. Skill nói rõ điều này trước lần chạy đầu và cần người dùng xác nhận mỗi lần chạy.
- Test: `tests/test_run.sh` với `fake-gh` và một repo git tạm (nhánh, merge, conflict, state file). Phần điều phối agent nằm ở skill, được kiểm bằng review.
