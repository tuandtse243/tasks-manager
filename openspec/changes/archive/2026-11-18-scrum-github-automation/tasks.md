# Tasks

## 0. Chuẩn bị môi trường

- [x] 0.1 Cài `yq` (mikefarah v4) trên máy dev và đăng nhập lại `gh` (`gh auth login`, scope `repo`, `workflow`); kiểm tra bằng `yq --version` có chữ "mikefarah" và `gh auth status` báo đăng nhập hợp lệ
- [x] 0.2 Tạo (hoặc được người dùng chỉ định) repo sandbox private trên GitHub cho kiểm thử end-to-end; kiểm tra bằng `gh repo view <owner>/<sandbox>` (đã tạo: `tuandtse243/scrum-sandbox`, private, branch `main`)

## 1. Khung plugin và bộ test

- [x] 1.1 Tạo `.claude-plugin/marketplace.json` ở gốc repo và `plugins/scrum-github/.claude-plugin/plugin.json` theo bố cục trong design; kiểm tra `/plugin marketplace add ./` nhận plugin `scrum-github`
- [x] 1.2 Tạo `runtime/bin/scrum` (dispatcher, in trợ giúp khi không có lệnh, lỗi khi lệnh lạ) và `tests/run.sh` với `assert_eq`, `assert_json_eq`, `gh` giả qua biến `SCRUM_GH`; kiểm tra `tests/run.sh` chạy được một test mẫu trên Bash 3.2 của macOS
- [x] 1.3 Viết `plugins/scrum-github/README.md` phần cài đặt, yêu cầu công cụ và bảng tên lệnh (`/scrum-github:<lệnh>`); kiểm tra các lệnh cài đặt trong README chạy đúng như ghi

## 2. Cấu hình (spec scrum-config)

- [x] 2.1 Viết `templates/defaults.json` và `lib/config.sh`: đọc `.github/scrum.yml` bằng `yq -o=json`, gộp mặc định bằng jq; test: file một phần, file rỗng ra đúng JSON gộp
- [x] 2.2 Viết `lib/jq/validate-config.jq` cho các lỗi trong spec (điểm âm, trùng, độ dài không dương, trạng thái rỗng/trùng) và thông báo nêu tên khoá; test mỗi lỗi với fixture
- [x] 2.3 Viết kiểm tra công cụ (`gh`, `jq`, `yq` mikefarah, `gh auth status`) và thông báo thiếu file cấu hình; test bằng PATH giả thiếu từng công cụ, kiểm tra lệnh dừng trước khi gọi `gh api`

## 3. Khởi tạo repo (spec repo-bootstrap)

- [x] 3.1 Viết `lib/jq/label-plan.jq` (cấu hình + label hiện có → create/update/unchanged/obsolete); test các scenario lần đầu, chạy lại, sửa màu, bỏ điểm 7
- [x] 3.2 Viết các template: `scrum.yml` có chú thích, Issue Form task (dropdown điểm sinh từ thang điểm), PR template có `Closes #`; test Issue Form sinh ra khớp thang 0/1/3/7 và 1/2/3/5/8
- [x] 3.3 Viết lệnh `scrum init` (tạo cấu hình nếu thiếu, đồng bộ label, vendor `runtime/` vào `.github/scrum/`, cài template theo quy tắc xung đột, tuỳ chọn `--force` và `--dry-run`); test với `gh` giả: dry-run không ghi gì, file đã sửa không bị ghi đè, chạy lại không phát sinh lời gọi ghi
- [x] 3.4 Viết skill `skills/scrum-init/SKILL.md` (chạy dry-run, trình bày, xác nhận, chạy thật, nhắc commit/push); kiểm tra bằng cách chạy skill trên một thư mục repo tạm

## 4. Vòng đời sprint (spec sprint-lifecycle)

- [x] 4.1 Viết `lib/jq/sprint.jq`: đọc/ghi marker trong mô tả milestone, tính số sprint kế tiếp, ngày kết thúc, chồng lấn, sprint hiện tại theo múi giờ; test các scenario Sprint 1 (2014-09-22 → 26), Sprint 3, hôm nay 2014-09-24, milestone không có marker
- [x] 4.2 Viết lệnh `scrum sprint new` (từ chối trùng tên, cảnh báo chồng lấn) và skill `sprint-new`; test với `gh` giả kiểm tra payload tạo milestone
- [x] 4.3 Viết `lib/jq/velocity.jq` và `lib/jq/close-plan.jq` (velocity, task xong, task chuyển, task chưa ước lượng; loại PR, feature, meta, not_planned); test với fixture sprint mẫu cho velocity 11
- [x] 4.4 Viết lệnh `scrum sprint close` (in kế hoạch, cần `--yes` để ghi, đề xuất tạo sprint kế tiếp, chuyển task kèm comment, ghi marker velocity, đóng milestone, báo sprint đã đóng) và skill `sprint-close` (hỏi xác nhận trước khi chạy `--yes`); test với `gh` giả: không `--yes` thì không có lời gọi ghi

## 5. Quản lý task (spec task-management)

- [x] 5.1 Viết `lib/jq/status.jq` (tập label mới khi đặt trạng thái) và hàm `set_status` gọi `PUT /issues/{n}/labels` một lần; test scenario chuyển In progress và label trạng thái trùng
- [x] 5.2 Viết lệnh `scrum task new` (kiểm tra điểm, bug, sprint mặc định là sprint hiện tại, dừng khi không có sprint mở) và skill `task-new`; test điểm 5 bị từ chối, payload issue đầy đủ cho ví dụ "Sign up" 7 điểm giao `ruby`
- [x] 5.3 Viết lệnh `scrum task start` (từ chối issue đóng, giao người dùng hiện tại nếu chưa giao, đặt In progress, slug branch, tạo hoặc checkout branch từ branch mặc định) và skill `task-start`; test sinh tên `feat/2-login`, test trong repo git tạm cho trường hợp branch đã tồn tại
- [x] 5.4 Viết `templates/plan.schema.json` và lệnh `scrum plan apply` (kiểm tra điểm, tạo issue feature, tạo task, gắn sub-issue, dự phòng bằng checkbox); test với `gh` giả cho cả hai nhánh sub-issue thành công và bị từ chối
- [x] 5.5 Viết skill `sprint-plan` (soạn đề xuất theo schema, bảng trình bày, vòng sửa, chỉ apply khi được duyệt); kiểm tra bằng một lần chạy thử trên repo sandbox với feature "Blog post comments" và huỷ, xác nhận không có issue mới

## 6. Liên kết PR và đồng bộ trạng thái (spec pr-task-linking)

- [x] 6.1 Viết `lib/jq/links.jq` (closing keyword, nhiều task, bỏ qua repo khác, phát hiện "Solve #n" để gợi ý); test đủ các scenario trong spec
- [x] 6.2 Viết lệnh `scrum event` đọc `$GITHUB_EVENT_PATH` và áp quy tắc đổi trạng thái cho PR (opened/reopened/ready/edited/merged/closed) và issue (closed completed, reopened), bỏ qua feature/meta; test bằng file sự kiện mẫu và `gh` giả cho từng scenario, gồm merge vào branch không mặc định và không lùi trạng thái
- [x] 6.3 Viết lệnh `scrum pr-check` (thoát khác 0 kèm thông báo khi thiếu liên kết và không có `no-task`); test bằng file sự kiện mẫu
- [x] 6.4 Viết `templates/workflows/scrum-status-sync.yml` và `scrum-pr-link-check.yml` (`pull_request_target`, chỉ checkout base, quyền tối thiểu, không secret); kiểm tra bằng đọc YAML: không có `ref: ${{ github.event.pull_request.head... }}`, khối `permissions` đúng ba quyền

## 7. Báo cáo (spec sprint-reporting)

- [x] 7.1 Viết `lib/jq/progress.jq` (bảng theo người, Unassigned, task hai người tính một lần ở dòng tổng, % điểm xong, chưa ước lượng, ngày còn lại) và lệnh `scrum status`, skill `sprint-status`; test ví dụ `david` 1/1/1 và chọn sprint khác
- [x] 7.2 Viết `lib/jq/burndown.jq`; test chuỗi 14, 11, 11, 4, 4 và trường hợp giữa sprint dừng ở hôm nay
- [x] 7.3 Viết `templates/report.html` (SVG inline, không tài nguyên ngoài, escape `</`) và lệnh `scrum report`, skill `sprint-report`; test file sinh ra không chứa `http://` hay `https://` trong `src`/`href`, và dữ liệu JSON nhúng parse được
- [x] 7.4 Viết `lib/jq/digest.jq` và lệnh `scrum digest` (tìm/tạo issue "<Sprint> digest" nhãn meta, mốc từ comment digest trước, bỏ qua khi tắt hoặc không có sprint mở); test với `gh` giả cho ngày đầu, ngày sau, không sprint, tắt
- [x] 7.5 Viết `templates/workflows/scrum-daily-digest.yml` (cron sinh từ cấu hình lúc init, `workflow_dispatch`); test `scrum init` sinh cron khớp `digest.cron`

## 8. Kiểm thử tích hợp trên sandbox

- [x] 8.1 Chạy `/scrum-github:scrum-init` trên repo sandbox, commit, push; kiểm tra label và file `.github/` có trên GitHub và lần chạy thứ hai báo không đổi
- [x] 8.2 Chạy lại ví dụ của tài liệu: Sprint 1 (5 ngày), 4 task (register, login, post, comment) giao `david`/`ruby`, `/task-start`, mở PR "Closes #n", merge; kiểm tra trạng thái tự chuyển New → In progress → Done và check PR thất bại với "Solve #n"
- [x] 8.3 Chạy `/sprint-status`, `/sprint-report`, kích hoạt digest bằng `workflow_dispatch`, rồi `/sprint-close` với một task dở; kiểm tra velocity ghi vào milestone, task dở sang Sprint 2 kèm comment, file báo cáo mở được khi tắt mạng
- [x] 8.4 Ghi kịch bản end-to-end và kết quả vào README phần "Kiểm thử trên sandbox"; kiểm tra người khác làm theo README tái hiện được bước 8.1

## Workflow follow-up

- Review các artifact và kết quả kiểm thử sandbox trước khi archive.
- Archive change bằng `/opsx:archive` để đưa 6 spec vào `openspec/specs/`.
