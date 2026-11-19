# Tasks

Ba đợt dùng được độc lập. Đợt 1 (nhóm 1–7) là nền; đợt 2 (nhóm 8) và đợt 3 (nhóm 9) dựa trên nó. Mọi đường dẫn tính từ `plugins/scrum-github/` trừ khi ghi khác. Chạy test bằng `bash tests/run.sh`.

## 1. Chuẩn bị (design mục 6, 11)

- [x] 1.1 Viết `scripts/vendor-sync.sh SRC` (design mục 11): copy nguyên văn `grilling`, `to-spec`, `domain-modeling`, `to-tickets` và `LICENSE` từ `SRC` vào `vendor/pocock/`, sinh `UPSTREAM.md` (repo gốc, commit đọc từ `UPSTREAM.md` của nguồn, ngày sync, bốn skill, ghi chú lấy qua `aidw`); dừng với lỗi khi `SRC` thiếu một trong bốn thư mục. Kiểm tra: test trong `tests/test_vendor.sh` (file mới) chạy script với một thư mục nguồn giả và so kết quả; chạy lần hai không đổi gì
- [x] 1.3 Chạy `scripts/vendor-sync.sh ~/.claude/plugins/cache/aidw/aidw/0.1.0/vendor/pocock` (hoặc repo nguồn của `aidw` nếu mới hơn). Kiểm tra: `diff -r` giữa nguồn và đích cho bốn thư mục không in gì; `LICENSE` và `UPSTREAM.md` có mặt
- [x] 1.2 Đối chiếu tài liệu GitHub cho `GET/POST /repos/{owner}/{repo}/issues/{n}/dependencies/blocked_by` và `GET /issues/{n}/sub_issues`: thân request, dạng response, mã lỗi khi đã tồn tại và khi repo không hỗ trợ. Chạy thử trên repo sandbox và lưu response thật vào `tests/fixtures/`. Kiểm tra: các fixture là JSON hợp lệ; ghi kết quả đối chiếu vào mục Open Questions của `design.md` (xoá câu hỏi đã trả lời)

## 2. Cấu hình (spec scrum-config: Cấu hình planning, Nhãn epic)

- [x] 2.1 Thêm `planning` (`dir`, `context_file`, `hours_per_point`, `context_stale_commits`) và `labels.epic` vào `runtime/share/defaults.json` và `templates/scrum.yml` (có comment). Kiểm tra: `scrum config` trong repo không khai báo in đúng bốn giá trị mặc định của `planning` và `labels.epic` là `type: epic`
- [x] 2.2 Thêm kiểm tra vào `validate-config.jq`: `dir` và `context_file` rỗng, tuyệt đối hoặc chứa `..`; `hours_per_point` không phải số dương; `context_stale_commits` không phải số nguyên dương; `labels.epic` trùng nhãn feature, meta hoặc no_task. Kiểm tra: mỗi scenario lỗi trong spec có một test trong `tests/test_config.sh`
- [x] 2.3 Thêm label epic vào `label-plan.jq` và loại nó trong `is_task` (`scrum.jq`); rà `project-items.jq`, `event-decide.jq`, `report-data.jq`, `digest.jq` xem có chỗ nào tự lọc label feature mà không qua `is_task`. Kiểm tra: test `label-plan` có `type: epic`; test "Repo cài bản cũ" chỉ tạo một label; test báo cáo với một epic, một feature, hai task 3 điểm cho tổng 6 (spec work-plan: Epic không tính điểm)

## 3. Định dạng và kiểm tra plan (spec work-plan: Định dạng plan phiên bản 2, Đọc được plan phiên bản 1, Kiểm tra plan, Vị trí plan file)

- [x] 3.1 Viết lại `runtime/share/plan.schema.json` cho phiên bản 2 (giữ mô tả dạng phiên bản 1 trong `description`). Kiểm tra: ví dụ ở design mục 2 và một plan phiên bản 1 đều là JSON hợp lệ theo mô tả; file là JSON hợp lệ
- [x] 3.2 Viết `plan-normalize.jq`: plan không có `version` thành phiên bản 2 với `F1`, `T1…Tn`, `sprint: "current"` khi bỏ trống; plan phiên bản 2 đi qua không đổi. Kiểm tra: test trong `tests/test_plan.sh` (file mới) cho cả hai hướng
- [x] 3.3 Viết lại `plan-validate.jq` trên dạng đã chuẩn hoá: trường bắt buộc, `id` trùng, điểm ngoài thang, `depends_on` không tồn tại, tự trỏ, vòng. Trả về mọi lỗi cùng lúc. Kiểm tra: một test cho mỗi scenario lỗi trong spec, gồm "Nhiều lỗi"
- [x] 3.4 Thêm `scrum plan validate FILE` vào `cmd_plan.sh` và `bin/scrum` (cả phần trợ giúp): chạy offline, không cần `gh`, in số feature, số task, tổng điểm khi hợp lệ, mã khác 0 khi lỗi. Kiểm tra: test lệnh với `SCRUM_GH` trỏ tới một `gh` luôn thất bại vẫn qua
- [x] 3.5 Chuyển hàm `slug` từ `branch-name.jq` sang `scrum.jq`; thêm `scrum plan init "<tiêu đề>" [--slug S]` (spec work-plan: Khởi tạo thư mục plan; design mục 15): offline, tạo thư mục, in JSON đường dẫn và file đã có, từ chối slug sai. Kiểm tra: bốn scenario của requirement, mỗi scenario một test; test tên branch cũ vẫn qua

## 4. Bản xem và ước lượng (spec work-plan: Bản xem ở local, Ước lượng)

- [x] 4.1 Viết `plan-render.jq`: vào là plan, cấu hình, danh sách milestone; ra là Markdown gồm dòng "generated", tiêu đề, epic, bảng task theo feature (id, tiêu đề, điểm, giờ nếu có, phụ thuộc, `#issue`), tiêu chí hoàn thành và subtask, giả định, ngoài scope, phần ước lượng. Kiểm tra: test so với file mong đợi trong `tests/fixtures/` cho plan chưa áp và plan đã áp
- [x] 4.2 Thêm phần ước lượng: tổng điểm theo feature và plan, số task chưa có điểm, giờ khi có `hours_per_point`, số sprint từ velocity trung bình của tối đa ba sprint đóng gần nhất. Kiểm tra: bốn scenario của requirement "Ước lượng", mỗi scenario một test
- [x] 4.3 Thêm `scrum plan render FILE [--out PATH] [--offline]`: thử đọc milestone, lỗi thì dùng danh sách rỗng và không báo lỗi; mặc định ghi `plan.md` cạnh plan. Kiểm tra: test "Sinh lại" (hai lần chạy offline cho file giống hệt); test `gh` thất bại vẫn mã 0 và không có phần quy ra sprint

## 5. Áp plan (spec work-plan: Áp plan lên GitHub, Ghi lại số issue, Chạy lại không tạo trùng, Sprint và backlog, Phụ thuộc giữa các task, Xem trước khi áp)

- [x] 5.1 Thêm mục `### Subtasks` vào `task-payload.jq` (sau tiêu chí hoàn thành) và cho phép `milestone` rỗng (không gửi khoá `milestone`). Kiểm tra: test payload có subtask; test payload backlog không có khoá `milestone`; các test payload cũ vẫn qua
- [x] 5.2 Viết `plan-actions.jq` theo design mục 4: vào là plan, cấu hình, trạng thái (milestone, sub-issue hiện có, blocked-by hiện có); ra là danh sách thao tác có thứ tự, task theo thứ tự tô-pô. Lỗi sprint không tồn tại hoặc đã đóng trả về trước mọi thao tác. Kiểm tra: test cho plan mới, plan đã áp hết (chỉ `skip`), plan áp một phần, thêm task vào feature đã có, plan có epic, và bốn scenario của "Sprint và backlog"
- [x] 5.3 Viết `plan-writeback.jq` và hàm ghi qua file tạm cùng thư mục rồi `mv`. Kiểm tra: test ghi `issue` cho epic, feature, task theo `id`; file sau khi ghi là JSON hợp lệ và phần còn lại không đổi
- [x] 5.4 Viết lại `cmd_plan_apply` theo ba bước đọc trạng thái, tính, áp; ghi số issue sau mỗi lần tạo; mở rộng `tests/fake-gh` cho `sub_issues` (GET) và `dependencies/blocked_by` (GET, POST). Kiểm tra: test lệnh "Áp thành công", "Lỗi giữa chừng" (fake-gh lỗi ở lần tạo thứ hai; file có đúng một số issue; mã khác 0), "Chạy lần hai" (không có POST nào), "Chạy lại sau lỗi"
- [x] 5.5 Thêm cách dự phòng trong khối có dấu cho sub-issue và phụ thuộc (design mục 5), thay nội dung khối khi chạy lại. Kiểm tra: test fake-gh từ chối `sub_issues` và từ chối `blocked_by`; chạy hai lần thân issue chỉ có một khối mỗi loại
- [x] 5.6 Thêm `--dry-run`: in danh sách thao tác, không POST/PATCH/PUT, không ghi file. Kiểm tra: test đếm lời gọi ghi của fake-gh bằng 0 và checksum plan file không đổi; hai scenario của "Xem trước khi áp"
- [x] 5.7 Xác nhận `project_touch` trên issue không có milestone không thêm thẻ và không lỗi; sửa nếu cần. Kiểm tra: test trong `tests/test_project.sh` với board bật và một task backlog
- [x] 5.8 Cho `plan apply` tự sinh lại bản xem khi kết thúc, kể cả khi lỗi giữa chừng. Thêm `scrum plan check FILE [--offline]` (spec work-plan: Kiểm tra gộp trước khi duyệt): validate, render, rồi in thao tác; dừng ở bước đầu tiên lỗi. Kiểm tra: scenario "Bản xem theo kịp" cho cả hai trường hợp; ba scenario của "Kiểm tra gộp trước khi duyệt"; test đếm lời gọi ghi của fake-gh bằng 0

## 6. Cập nhật issue đã có (spec work-plan: Cập nhật issue đã có)

- [x] 6.1 Thêm `--update` vào `plan-actions.jq` và `cmd_plan_apply`: so tiêu đề, thân, label điểm, milestone của issue đang mở với plan; một `PATCH` cho tiêu đề, thân, milestone và một `PUT` cho tập label; giữ label trạng thái và khối dự phòng; bỏ qua issue đã đóng và báo. Kiểm tra: ba scenario của requirement, mỗi scenario một test; test không có `--update` thì không có lời gọi sửa nào

## 7. Skill `plan` và agent `plan-critic` (spec task-management; design mục 12, 13, 14)

- [x] 7.1 Viết `reference/planning-rules.md` với sáu quy tắc ở design mục 14. Kiểm tra: file tồn tại và được dẫn bằng `${CLAUDE_PLUGIN_ROOT}/reference/planning-rules.md` trong skill `plan`
- [x] 7.2 Viết `agents/plan-critic.md` (frontmatter `name`, `description`, `tools: Read, Grep, Glob`): nhận brief và bản nháp plan, trả phát hiện theo năm loại, không đề xuất lại cả plan. Kiểm tra: sau khi cài lại plugin, agent `scrum-github:plan-critic` có trong danh sách agent
- [x] 7.3 Viết `skills/plan/SKILL.md` theo tám bước ở design mục 12 (dùng `scrum plan init` và `scrum plan check`), với adapter cho `to-tickets` (design mục 11) và tham số `--quick`; xoá `skills/sprint-plan/`. Kiểm tra: `/scrum-github:plan` xuất hiện và `/scrum-github:sprint-plan` không còn; `grep -r sprint-plan` trong plugin và `docs/` chỉ còn ở ghi chú đổi tên
- [x] 7.4 Chạy tay trên repo sandbox: `/scrum-github:plan` với một feature rõ, sửa điểm một task, duyệt; rồi thêm một task và áp lại; rồi `/scrum-github:plan` với "làm cho app nhanh hơn". Kiểm tra: `docs/plans/<slug>/plan.json` và `plan.md` có số issue; lần áp lại chỉ tạo một issue; lần thứ ba đề nghị `discover` (lệnh chưa có thì nêu rõ phần thiếu)
- [x] 7.5 Cập nhật `README.md` (bảng lệnh, mục cấu hình, mục plan file, kịch bản end-to-end) và `docs/huong-dan-ap-dung.md` (lập plan, backlog, epic, ước lượng, đổi tên lệnh). Tăng phiên bản lên 0.3.0 trong `.claude-plugin/plugin.json` và `runtime/VERSION`. Kiểm tra: mọi lệnh ghi trong README chạy được như đã viết trên sandbox; `bash tests/run.sh` qua toàn bộ

## 8. Đợt 2: skill `discover` và agent `researcher` (spec requirement-discovery)

- [x] 8.1 Viết `runtime/share/doc-sections.json` (tên mục bắt buộc và tuỳ chọn của brief) và `reference/brief-template.md` với đúng các mục đó, gồm hai mục tuỳ chọn và mục cỡ yêu cầu. Viết `doc-check.jq`, `cmd_doc.sh` và lệnh `scrum doc check FILE [--type brief|context]` (spec requirement-discovery: Kiểm tra cấu trúc brief; design mục 15); loại file suy từ tên khi không có `--type`. Kiểm tra: `tests/test_doc.sh` (file mới) có ba scenario của requirement; một test so tên mục trong template với `doc-sections.json`; `scrum doc check reference/brief-template.md` qua
- [x] 8.2 Viết `agents/researcher.md` (`tools: WebSearch, WebFetch, Read`): nhận câu hỏi, trả phát hiện kèm URL, tách riêng phần không có nguồn. Kiểm tra: agent `scrum-github:researcher` có trong danh sách; chạy thử một câu hỏi trả về có URL
- [x] 8.3 Viết `skills/discover/SKILL.md` theo design mục 12 (dùng `scrum plan init` và `scrum doc check`): ba mức độ sâu, adapter cho `grilling` (danh sách tám nhóm phải làm rõ, ghi phụ lục) và `to-spec` (ghi brief theo template, không publish), quy tắc sự thật và quyết định, xử lý khi không có web, bước xác nhận và in lệnh `/scrum-github:plan <brief>`. Kiểm tra: `/scrum-github:discover` xuất hiện
- [x] 8.4 Nối `plan` với `discover`: `plan` nhận brief, chỉ chia task trong phần "trong scope", dùng cỡ yêu cầu làm cấu trúc ban đầu, chép giả định và ngoài scope vào plan. Kiểm tra: scenario "Lập plan từ brief" chạy tay trên sandbox cho ra plan có `assumptions` và `out_of_scope` lấy từ brief
- [x] 8.5 Chạy tay trên sandbox: `/scrum-github:discover` với một ý tưởng mơ hồ ở mức `standard` và `--quick`; huỷ giữa chừng một lần. Kiểm tra: brief có đủ mục và phụ lục hỏi đáp; `--quick` không khởi chạy agent; sau cả ba lần `gh issue list` không có issue mới
- [x] 8.6 Thêm `discover` vào `README.md` và `docs/huong-dan-ap-dung.md` (khi nào dùng, ba mức, đường đi discover → plan → apply). Kiểm tra: ví dụ trong tài liệu khớp lệnh thật

## 9. Đợt 3: skill `project-scan` và agent `codebase-scout` (spec project-context; requirement-discovery: Kiểm tra độ phù hợp, Ước lượng độ phức tạp)

Thứ tự làm: 9.1, 9.7, 9.8 (script) trước, rồi 9.2–9.6 (agent, skill, tài liệu).

- [x] 9.1 Thêm tên mục của tài liệu ngữ cảnh vào `doc-sections.json`; viết `reference/project-context-template.md` với đúng các mục đó, mục "Ghi chú của team", và dòng dấu `<!-- scrum:context sha=… date=… -->`; cho `scrum doc check` kiểm tra thêm dấu với loại `context`. Kiểm tra: ba scenario của "Kiểm tra cấu trúc tài liệu ngữ cảnh" trong `tests/test_doc.sh`; test so tên mục trong template với `doc-sections.json`
- [x] 9.7 Viết `context-inventory.jq` (vào là danh sách đường dẫn và nội dung `package.json` nếu có) và `scrum context inventory` trong `cmd_context.sh` (spec project-context: Bản kê repo). Kiểm tra: `tests/test_context.sh` (file mới) có ba scenario của requirement; chạy hai lần trên cùng commit cho kết quả giống hệt
- [x] 9.8 Viết `context-status.jq` và `scrum context status`, `scrum context stamp` (spec project-context: Trạng thái tài liệu ngữ cảnh, Ghi dấu thời điểm quét). Kiểm tra: test dựng một repo git tạm với vài commit cho bốn scenario của trạng thái và hai scenario của ghi dấu; `stamp` hai lần chỉ để lại một dấu
- [x] 9.2 Viết `agents/codebase-scout.md` (`tools: Read, Grep, Glob, Bash`, ghi rõ chỉ dùng lệnh đọc): trả tóm tắt có đường dẫn làm căn cứ, ghi "chưa rõ" khi không xác định được. Kiểm tra: agent `scrum-github:codebase-scout` có trong danh sách
- [x] 9.3 Viết `skills/project-scan/SKILL.md` theo design mục 12: quét lần đầu và làm mới dựa trên `scrum context status` và `scrum context inventory`, `--full`, ghi dấu bằng `scrum context stamp`, soát bằng `scrum doc check`, giữ "Ghi chú của team", adapter cho `domain-modeling` (chỉ bảng thuật ngữ), xử lý repo chưa có mã. Kiểm tra: chạy trên chính repo này cho ra `docs/project-context.md` có dấu commit; `git status` chỉ có một file mới
- [x] 9.4 Thêm vào `discover` và `plan`: đọc tài liệu ngữ cảnh, gọi `scrum context status` và cảnh báo khi kết quả là cũ hoặc không xác định, đề nghị `project-scan` khi chưa có. Thêm vào `discover` bước kiểm tra độ phù hợp (ba kết luận, dừng hỏi khi xung đột) và cỡ yêu cầu, dùng `codebase-scout` cho vùng liên quan. Kiểm tra: chạy tay ba scenario của "Kiểm tra độ phù hợp với dự án" và ba scenario của "Dấu thời điểm quét" trên sandbox có mã
- [x] 9.5 Chạy tay làm mới: sửa một thư mục, commit, chạy `/scrum-github:project-scan`; thêm nội dung vào "Ghi chú của team" rồi chạy `--full`. Kiểm tra: dấu ghi commit mới; ghi chú của team không đổi
- [x] 9.6 Thêm `project-scan` và luồng "feature mới trên dự án có sẵn" vào `README.md` và `docs/huong-dan-ap-dung.md`. Kiểm tra: ví dụ trong tài liệu khớp lệnh thật

## 10. Kiểm tra tích hợp

- [x] 10.1 Chạy trọn đường ống trên sandbox có mã: `project-scan` → `discover` một feature mới → `plan` → duyệt → `apply` có epic, phụ thuộc và một task backlog → `plan apply --update` đưa task backlog vào sprint. Ghi kết quả vào mục end-to-end của `README.md`. Kiểm tra: trên GitHub có epic, feature, task đúng quan hệ sub-issue và blocked-by; `scrum status` không tính epic và feature; `bash tests/run.sh` qua toàn bộ
- [x] 10.2 Chạy `openspec validate requirement-planning --strict`. Kiểm tra: không có lỗi hay cảnh báo

## Workflow follow-up

- Archive change sau khi cả ba đợt xong, hoặc tách đợt 2 và 3 thành change riêng nếu muốn archive đợt 1 sớm.
