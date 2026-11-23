# Tasks

Đường dẫn tính từ `plugins/scrum-github/`. Chạy test bằng `bash tests/run.sh`. Bắt đầu sau khi `team-and-backlog-tasks` đã cài xong trên branch nền.

## 1. Cấu hình (design 6; spec scrum-config)

- [x] 1.1 Thêm `team[].review_hours` và `planning.merge_minutes` vào `defaults.json`, `validate-config.jq`, ví dụ trong `templates/scrum.yml` và bảng cấu hình trong README. Kiểm tra: test trong `test_config.sh` cho mặc định 5 và các giá trị sai; `bash tests/run.sh config` xanh

## 2. Khối ước lượng và thời lượng (design 1, 2; spec time-estimate)

- [x] 2.1 Thêm `parse_duration`, `fmt_duration`, `issue_estimate`, `estimate_block` vào `scrum.jq`, gắn `._est` trong `report_tasks`, chuỗi en và vi. Test jq trong `tests/test_estimate.sh`: các định dạng, 0, `abc`, đọc khối, khối hỏng, ghi đè giữ phần thân còn lại. Kiểm tra: `bash tests/run.sh estimate` xanh

## 3. Lệnh task (design 3; spec time-estimate)

- [x] 3.1 `task new --work --review --by`; `task-payload.jq` ghi khối. Test với `fake-gh`. Kiểm tra: `bash tests/run.sh task` xanh
- [x] 3.2 `task estimate N [POINTS] [--work] [--review] [--by]`: gộp với ước lượng cũ, PATCH thân, lỗi khi không có gì để đổi. Test chỉ đổi thời gian, chỉ đổi điểm, cả hai, không có gì. Kiểm tra: `bash tests/run.sh task` xanh
- [x] 3.3 Sửa `skills/task-new/SKILL.md` và `skills/task/SKILL.md`. Kiểm tra: `claude plugin validate plugins/scrum-github` đạt hoặc ghi lý do môi trường

## 4. Plan (design 3, 4, 5; spec work-plan)

- [x] 4.1 `estimate` trong `plan.schema.json` và `plan-validate.jq`; `plan apply` ghi khối; `--update` cập nhật khối. Test: lỗi `review_minutes: 0`, áp có khối, update đổi review. Kiểm tra: `bash tests/run.sh plan` xanh
- [x] 4.2 `eta_by_waves`; thời gian trong `plan-render.jq` (task, feature, plan, số task thiếu, ước tính) và trong dữ liệu `plan.html`. Test ví dụ 90 phút của spec. Kiểm tra: `bash tests/run.sh plan` xanh
- [x] 4.3 Phần dòng thời gian trong `runtime/share/plan.html` (đúng tỉ lệ, đợt, merge, review, vạch chạy, tắt khi giảm chuyển động, không có phần này khi không có ước lượng), thời gian trên thẻ và KPI. Test: có hoặc không có phần dòng thời gian, không có URL ngoài. Kiểm tra: `bash tests/run.sh plan` xanh
- [x] 4.4 Sửa `skills/plan/SKILL.md` và `reference/planning-rules.md`: ước lượng `estimate` cho mỗi task. Kiểm tra: đọc lại skill thấy bước ước lượng thời gian

## 5. Việc của tôi, tiến độ, lập sprint (spec my-work, sprint-reporting, sprint-lifecycle)

- [x] 5.1 `mine.jq` và `scrum mine`: thời gian từng task, ước tính theo đợt, số task thiếu ước lượng; skill `my-tasks`. Test ví dụ 45 phút của spec. Kiểm tra: `bash tests/run.sh mine` xanh
- [x] 5.2 `progress-table.jq`: cột phút làm và phút review còn lại khi có ước lượng, câu số task thiếu ước lượng (en, vi); bảng giữ nguyên khi không có ước lượng. Kiểm tra: `bash tests/run.sh report` xanh, các test bảng cũ không đổi
- [x] 5.3 `sprint-fill.jq` và `scrum sprint fill`: phút review theo người, cảnh báo vượt `review_hours`. Test hai scenario của spec. Kiểm tra: `bash tests/run.sh sprint` xanh

## 6. Phiên bản và tài liệu

- [x] 6.1 Phiên bản 0.10.0 (`runtime/VERSION`, `plugin.json`, test phiên bản), mục CHANGELOG, README (lệnh và cấu hình mới), `docs/huong-dan-ap-dung.md`. Kiểm tra: `bash tests/run.sh manifest init` xanh

## 7. Kiểm tra tích hợp

- [ ] 7.1 Toàn bộ `bash tests/run.sh`, `shellcheck`, `openspec validate time-estimates --strict`. Kiểm tra: tất cả đạt

## Workflow follow-up

- Mở pull request xếp trên PR của `team-and-backlog-tasks`, merge sau nó.
- Archive bằng `/opsx:archive time-estimates`.
