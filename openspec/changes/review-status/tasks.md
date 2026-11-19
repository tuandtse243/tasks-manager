# Tasks

Đường dẫn tính từ `plugins/scrum-github/`. Chạy test bằng `bash tests/run.sh <tên>`. Mỗi nhóm có test cho cả chế độ tắt (không đổi gì) và bật.

## 1. Cấu hình và danh sách trạng thái (design mục 1; spec scrum-config)

- [x] 1.1 `statuses.in_review` (null), `attention.review_days` (2), `project.status_options.in_review` (`In Review`) trong `defaults.json`, `templates/scrum.yml` (có chú thích) và `validate-config.jq`; `roles($cfg)`, `review_on($cfg)`; `status_labels`, `task_role` dùng chúng; test kiểm tra hợp lệ và vai trò của task ở hai chế độ. Kiểm tra: `bash tests/run.sh test_config` và `test_task` xanh

## 2. Sự kiện PR (design mục 2; spec pr-task-linking)

- [x] 2.1 `event-decide.jq` và `cmd_event.sh` với `draft`, `pr_draft`, `pr_closed`; `converted_to_draft` trong template status-sync; test mọi scenario của spec ở chế độ bật và test chế độ tắt giữ hành vi cũ. Kiểm tra: `bash tests/run.sh test_event` và `test_init` xanh

## 3. Label và lệnh task (design mục 5; spec repo-bootstrap, task-management)

- [x] 3.1 `label-plan.jq` theo `roles($cfg)`; `task list --status in_review`; test bật, tắt lại (lỗi thời), và từ chối khi tắt. Kiểm tra: `bash tests/run.sh test_init` và `test_task` xanh

## 4. Báo cáo (design mục 1, 4; spec sprint-reporting)

- [ ] 4.1 `progress`, `progress-table.jq`, `digest.jq`, `report-data.jq`, `report.html` dựng cột và mục từ `roles($cfg)`; `attention.jq` loại `review`; chuỗi `en`, `vi`; test bật và tắt (output tắt giống hệt trước). Kiểm tra: `bash tests/run.sh test_report` xanh

## 5. Board (design mục 3; spec project-board-sync)

- [ ] 5.1 Board dùng `roles($cfg)`; test kéo thẻ vào cột In Review, `project init` thiếu option, và chế độ tắt bỏ qua cột đó. Kiểm tra: `bash tests/run.sh test_project` xanh

## 6. Phiên bản và tài liệu

- [ ] 6.1 Phiên bản 0.8.0, CHANGELOG; README plugin (khoá cấu hình, quy tắc đổi trạng thái có bảng cho chế độ bật, board) và `docs/huong-dan-ap-dung.md` gốc repo (cách bật, ghi chú bật giữa sprint). Kiểm tra: `bash tests/run.sh manifest` xanh

## 7. Kiểm tra tích hợp

- [ ] 7.1 Toàn bộ test (jq 1.8.1 và 1.8.2), `shellcheck`, `openspec validate review-status --strict`, `claude plugin validate .`. Kiểm tra: tất cả đạt
- [ ] 7.2 Mở pull request, CI xanh, merge, CI trên `main` xanh

## Workflow follow-up

- Archive bằng `/opsx:archive review-status`.
