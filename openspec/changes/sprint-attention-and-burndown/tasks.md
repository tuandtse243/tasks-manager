# Tasks

Đường dẫn tính từ `plugins/scrum-github/`. Chạy test bằng `bash tests/run.sh <tên>`. Lint bằng lệnh `shellcheck` trong mục Development của README plugin.

## 1. Cấu hình (spec scrum-config)

- [x] 1.1 Thêm `sprint.working_days`, `attention.stale_days`, `attention.behind_percent`, `language`, `digest.webhook_format` vào `runtime/share/defaults.json`, `templates/scrum.yml` (có chú thích) và quy tắc kiểm tra trong `validate-config.jq`; test cho từng giá trị sai. Kiểm tra: `bash tests/run.sh test_config` xanh

## 2. Ngày làm việc (design mục 1; spec sprint-reporting "Đường burndown", "Tóm tắt tiến độ sprint")

- [x] 2.1 `working_days`, `is_working_day`, `days_left` theo ngày làm việc và đường lý tưởng đi ngang qua ngày nghỉ trong `scrum.jq`; test thứ 6 tới thứ 3, sprint qua cuối tuần, và ví dụ 22 đến 26/9/2014 cho đúng số cũ. Kiểm tra: `bash tests/run.sh test_report` xanh

## 3. Ngôn ngữ (design mục 4; spec scrum-config "Ngôn ngữ")

- [x] 3.1 Tạo `runtime/share/strings.json` (`en`, `vi`) và hàm `tr`; `progress-table.jq` và `digest.jq` dùng nó; test hai bảng cùng khoá và bảng tiến độ tiếng Việt. Kiểm tra: `bash tests/run.sh test_report` xanh

## 4. Cần chú ý (design mục 3; spec sprint-reporting "Mục cần chú ý" và bốn yêu cầu con)

- [x] 4.1 `attention.jq` và test cho task bị chặn, không động (có và không có PR mới), thiếu người nhận, thiếu điểm, chậm, và không có gì. Kiểm tra: `bash tests/run.sh test_report` xanh
- [x] 4.2 `scrum status` và `scrum digest` đọc PR mở và quan hệ chặn rồi in mục cần chú ý; test lệnh với `fake-gh`. Kiểm tra: `bash tests/run.sh test_report` và `test_event` xanh

## 5. Burndown theo lịch sử (design mục 2; spec sprint-reporting "Đường burndown", "Báo cáo HTML")

- [x] 5.1 `history.jq` dựng trạng thái cuối ngày từ events; burndown trả `scope`, `added`, `removed`; test thêm task giữa sprint, bỏ task, đổi điểm, mở lại. Kiểm tra: `bash tests/run.sh test_report` xanh
- [x] 5.2 `scrum report` đọc events (tối đa 100 task, 30 ứng viên rời sprint) và truyền vào báo cáo; `report.html` vẽ đường phạm vi, ghi điểm thêm/bỏ, mục cần chú ý, và dùng `d.strings`; test lệnh và test số lời gọi. Kiểm tra: `bash tests/run.sh test_report` xanh

## 6. Webhook (design mục 5; spec sprint-reporting "Digest hằng ngày", repo-bootstrap)

- [x] 6.1 Gửi webhook trong `cmd_digest.sh` (slack, telegram, lỗi chỉ cảnh báo) với `curl` giả trong test; thêm secret vào `templates/github/workflows/scrum-daily-digest.yml` và test template. Kiểm tra: `bash tests/run.sh test_report` và `test_init` xanh

## 7. Tổng kết khi đóng sprint (design mục 6; spec sprint-lifecycle)

- [x] 7.1 `sprint-summary.jq` và bước đăng tổng kết trong `cmd_sprint_close` (tìm hoặc tạo issue digest, lỗi chỉ cảnh báo); test. Kiểm tra: `bash tests/run.sh test_sprint` xanh

## 8. Phiên bản và tài liệu

- [ ] 8.1 Phiên bản 0.7.0, mục CHANGELOG (ghi rõ burndown đổi số với sprint có thay đổi phạm vi); README plugin (cấu hình mới, webhook, Telegram) và `docs/huong-dan-ap-dung.md` gốc repo (cấu hình, digest webhook, bỏ dòng giới hạn về burndown). Kiểm tra: `bash tests/run.sh manifest` xanh; `grep -n 'điểm hiện tại' docs/huong-dan-ap-dung.md` không còn ở mục Giới hạn

## 9. Kiểm tra tích hợp

- [ ] 9.1 Toàn bộ test (jq 1.8.1 và 1.8.2), `shellcheck`, `openspec validate sprint-attention-and-burndown --strict`, `claude plugin validate .`. Kiểm tra: tất cả đạt
- [ ] 9.2 Mở pull request, CI xanh, merge, CI trên `main` xanh

## Workflow follow-up

- Archive bằng `/opsx:archive sprint-attention-and-burndown`.
