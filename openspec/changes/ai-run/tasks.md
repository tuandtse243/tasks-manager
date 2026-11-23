# Tasks

Đường dẫn tính từ `plugins/scrum-github/`. Chạy test bằng `bash tests/run.sh`. Bắt đầu sau khi `time-estimates` đã cài xong trên branch nền.

## 1. Cấu hình và ai-ready (design 9; spec scrum-config, work-plan)

- [x] 1.1 Khối `run` và `labels.ai_ready` trong `defaults.json`, `validate-config.jq`, `templates/scrum.yml`, README. Kiểm tra: test `test_config.sh` cho mặc định và `max_parallel: 0`; `bash tests/run.sh config` xanh
- [x] 1.2 `label-plan.jq`: `init` tạo label `ai-ready`. Kiểm tra: `bash tests/run.sh init` xanh
- [x] 1.3 `ai_ready` trong `plan.schema.json`, `plan-validate.jq`, `plan-actions.jq` (gắn label khi tạo, thêm hoặc gỡ khi `--update`). Kiểm tra: test hai scenario của spec; `bash tests/run.sh plan` xanh

## 2. Chọn task và chia đợt (design 3; spec ai-run "Chọn task để chạy", "Chia đợt và xem trước")

- [x] 2.1 `run-select.jq` và test jq: mặc định, danh sách số, bị chặn bởi task ngoài lần chạy, task đóng hoặc feature hoặc PR bị loại, hai đợt, ETA. Kiểm tra: `bash tests/run.sh run` xanh
- [x] 2.2 `runtime/lib/cmd_run.sh` với `scrum run plan [N,…] [--json]`, đăng ký trong `bin/scrum` và `--help`. Test với `fake-gh`, không có lời gọi ghi. Kiểm tra: `bash tests/run.sh run` xanh

## 3. State, start, record, merge, status (design 1, 4, 5, 6; spec ai-run)

- [x] 3.1 `run-state.jq` và đọc ghi `.scrum/run/<id>.json` (ghi atomic), thêm `.scrum/` vào `.git/info/exclude`. Kiểm tra: test jq chuyển trạng thái task
- [x] 3.2 `scrum run start`: dừng khi có thay đổi chưa commit, tạo nhánh tích hợp từ nhánh mặc định, giao task chưa có người, In progress. Test trên repo git tạm cộng `fake-gh`. Kiểm tra: `bash tests/run.sh run` xanh
- [x] 3.3 `scrum run record N --started | --done --branch B [--notes FILE] | --failed --reason R`: thời gian thật, comment khối `actual`, task lỗi về New kèm comment, task phụ thuộc task lỗi bị loại. Kiểm tra: test cho xong, lỗi, phụ thuộc lỗi
- [x] 3.4 `scrum run merge N`: `--no-ff`, conflict thì `--abort` và ghi `conflict`, nhánh tích hợp không đổi. Test merge sạch và conflict trên repo tạm. Kiểm tra: `bash tests/run.sh run` xanh
- [x] 3.5 `scrum run status [ID]` và tìm lần chạy chưa xong. Kiểm tra: test in trạng thái từng task

## 4. Finish và PR (design 7; spec ai-run "Một PR gói review", "Một PR mỗi đợt")

- [x] 4.1 `run-pr-body.jq`: mục cho từng task (acceptance, ước lượng so với thực tế, test tay, chỗ cần nhìn kỹ, `Closes`), task lỗi và bị loại; test jq. Kiểm tra: `bash tests/run.sh run` xanh
- [x] 4.2 `scrum run finish [--wave W]`: push nhánh tích hợp, `gh pr create --body-file`, không có task merge thì không push; `--wave` nhắm vào nhánh của PR trước. Test với `fake-gh` và remote git tạm (bare repo). Kiểm tra: chỉ nhánh tích hợp có trên remote

## 5. Agent và skill (design 2, 8; spec ai-run "Mỗi task một worktree local", "Chạy tiếp sau khi dừng", "Xác nhận trước khi chạy")

- [ ] 5.1 `agents/implementer.md` (đầu vào, quy tắc không push và không làm ngoài phạm vi, đầu ra JSON). Kiểm tra: `claude plugin validate plugins/scrum-github` đạt hoặc ghi lý do môi trường
- [ ] 5.2 `skills/run/SKILL.md`: dry-run, xác nhận kèm cảnh báo chạy mã, start, vòng đợt (checkout nhánh tích hợp, tối đa K agent `isolation: worktree`, record, merge, test, hỏi khi conflict hoặc test đỏ), finish, chạy tiếp, `--pr-per-wave`. Kiểm tra: test skill trong `test_cli.sh`; đọc lại skill thấy đủ các bước của spec
- [ ] 5.3 `my-tasks` và `next` gợi ý `/scrum-github:run` khi có task `ai-ready`; test `next-step.jq`. Kiểm tra: `bash tests/run.sh next` xanh

## 6. Phiên bản và tài liệu

- [ ] 6.1 Phiên bản 0.11.0, CHANGELOG, README (lệnh `run`, agent, cấu hình, cảnh báo an toàn), `docs/huong-dan-ap-dung.md`. Kiểm tra: `bash tests/run.sh manifest init` xanh

## 7. Kiểm tra tích hợp

- [ ] 7.1 Toàn bộ `bash tests/run.sh`, `shellcheck`, `openspec validate ai-run --strict`. Kiểm tra: tất cả đạt

## Workflow follow-up

- Mở pull request xếp trên PR của `time-estimates`, merge sau nó.
- Thử `/scrum-github:run` trên một repo thật với hai task nhỏ trước khi dùng rộng.
- Archive bằng `/opsx:archive ai-run`.
