# Design

Đường dẫn tính từ `plugins/scrum-github/`.

## Context

Mọi quyết định của runtime là jq thuần trong `runtime/lib/jq/`. Các file `cmd_*.sh` chỉ đọc GitHub, chạy jq và ghi kết quả. Test giả GitHub bằng `tests/fake-gh`. Change này dựa vào những phần đã có:

- `sprint-resolve.jq` và `resolve_sprint` (`common.sh`) chọn sprint. `resolve_sprint` báo lỗi khi không có sprint mở. Đây là chỗ `task new` đang dừng.
- `recent_velocity` trong `scrum.jq` đã được `plan-render` và `sprint-fill` dùng để tính capacity của sprint.
- `blocked_map` trong `cmd_backlog.sh` đọc quan hệ "blocked by", tối đa 50 task.
- `report.html` là template tự chứa. `cmd_report.sh` thay `__SCRUM_DATA__` bằng JSON đã thoát `<`. Chữ cố định lấy từ `strings.json` (en, vi) qua `tr`/`trn`.
- `plan.json` đã có `assignees` và `sprint` cho từng task. `plan apply` đã tạo issue với hai trường này.

## Goals / Non-Goals

**Goals:**
- Danh sách team chỉ được tính ở một chỗ, mọi lệnh dùng chung.
- `plan.html` sinh ra một cách tất định từ `plan.json` cộng dữ liệu GitHub đã đọc. AI không viết HTML.
- Các phần tính toán (đợt, tải, mức vừa capacity, phần thay đổi) là jq thuần, test được không cần mạng.

**Non-Goals:**
- Chọn người làm bằng thuật toán trong runtime. Việc đề xuất người làm là phán đoán của skill `/plan` (đọc mô tả task, lĩnh vực, tải). Runtime chỉ cung cấp số liệu và kiểm tra.
- Trang HTML gửi xác nhận ngược về Claude.
- Đồng bộ `team` với GitHub Teams hay tổ chức.

## Decisions

### 1. `team` trong cấu hình, GitHub `assignees` làm dự phòng

`jq` mới `team.jq`: đầu vào là `cfg.team` và danh sách login từ `GET repos/{r}/assignees`. Đầu ra là `{source: "config"|"github", members: [{login, areas, capacity}]}`. Hàm shell `team_members` chỉ gọi GitHub khi `cfg.team` rỗng.

Dùng `assignees` thay vì `collaborators`, vì `collaborators` cần quyền push. `assignees` trả đúng những người có thể được giao issue, đúng thứ ta cần.

Login được chuẩn hoá: bỏ `@`, so khớp không phân biệt hoa thường, vì GitHub không phân biệt hoa thường với login.

### 2. `scrum team`

Lệnh `scrum team` lấy `team_members` cộng các issue của sprint đang mở (`fetch_milestone_issues`), rồi tính tải bằng `report_tasks` hiện có (đã bỏ epic, feature, not planned). Không có sprint mở thì không tính tải. Ở đây gọi `sprint-resolve` trực tiếp, không qua `resolve_sprint`, để không dừng khi thiếu sprint.

### 3. `task new`: về backlog thay vì báo lỗi

Trong `cmd_task_new`:

- Có `--backlog`: milestone `null`.
- Có `--sprint S`: giữ `resolve_sprint` như cũ. Sprint sai vẫn là lỗi.
- Không có cả hai: gọi `sprint-resolve`. Kết quả `null` thì milestone `null`.

`task-payload.jq` đã nhận `milestone`. Cần cho phép giá trị `null` (bỏ trường `milestone` khỏi payload). Dòng in ra đổi thành "in Sprint 5" hoặc "in the backlog".

Phương án khác: luôn vào backlog. Bị loại vì đổi hành vi với người đang có sprint mở, đã chốt khi khám phá.

### 4. Cảnh báo login ngoài team

Hàm `warn_unknown_logins LOGIN…` dùng `team.jq`, chỉ đọc cấu hình, không gọi GitHub khi `team` trống, vì khi đó không cảnh báo. `task new`, `task assign` gọi trước khi ghi. `plan check` đưa cảnh báo vào phần kiểm tra.

### 5. `scrum mine`

- Task: `GET repos/{r}/issues?assignee=LOGIN&state=open` (`gh_get_all`), một lần đọc cho mọi milestone. Lọc bằng `is_task`.
- Phân nhóm, sắp xếp và đề xuất nằm trong `mine.jq`. Đầu vào: issues, milestones, sprint đang mở, map chặn, cfg. Thứ tự nhóm theo spec `my-work`. Sprint khác sắp theo `due_on`.
- Quan hệ chặn: dùng lại `blocked_map` (tối đa 50 task, như `backlog`). Task vượt giới hạn hiện "blocked-by not checked".
- PR chờ review: `search/issues?q=repo:R is:pr is:open review-requested:LOGIN`. Lỗi thì `null`, và jq in "chưa đọc được".
- Đề xuất: task In progress đầu tiên. Không có thì task New của sprint đang mở không bị chặn bởi task đang mở, chọn task có số nhỏ nhất trong đợt sớm nhất. Đợt tính trên đồ thị chặn của chính các task đó.

Tên lệnh là `scrum mine` chứ không phải `task list --all`, vì đầu ra khác hẳn (nhóm, PR, đề xuất). `task list` vẫn giữ cho việc lọc đơn giản.

### 6. Đợt, tải và mức vừa capacity: jq thuần dùng chung

`plan.jq` (hoặc file mới `plan-insights.jq`) có ba hàm:

- `plan_waves`: gán `wave` cho mỗi task theo `depends_on`, với đợt bằng 1 cộng đợt lớn nhất của các task nó phụ thuộc. Plan đã được kiểm tra không có vòng nên luôn dừng.
- `plan_load($members; $sprint_issues; $target_sprint)`: tải mỗi người bằng điểm đang có trong sprint cộng điểm task của plan giao cho họ vào sprint đó, so với `capacity`.
- `plan_fit($capacity)`: đi các task theo đợt rồi theo `id`, cộng dồn điểm. Task làm vượt capacity, và task phụ thuộc task đã ở backlog, được đánh dấu "nên để backlog". Đây là số liệu cho skill đề xuất. Runtime không tự sửa `sprint` trong `plan.json`.

`plan check` in ba phần này dạng chữ, và đưa chúng vào dữ liệu của `plan.html`. Skill `/plan` đọc chúng (thêm `--json` cho `plan check`) để điền đề xuất vào `plan.json` trước khi trình bày.

### 7. Một lần duyệt nằm ở skill, không ở runtime

Thứ tự mới trong `skills/plan/SKILL.md`:

1. Viết plan.
2. Chạy `scrum team --json` và `plan check --json`.
3. Điền `assignees` và `sprint` đề xuất cho task chưa có, giữ nguyên giá trị người dùng đã nêu.
4. Chạy lại `plan check` để HTML và số liệu khớp.
5. Mở `plan.html`, trình bày bảng trong chat, hỏi một câu duyệt.
6. Duyệt thì `plan apply`.

Đề xuất sprint dùng `"current"` để nếu sprint đổi tên giữa chừng thì vẫn đúng. Bỏ câu gợi ý `sprint-fill` sau apply.

Phương án khác: thêm cờ `plan apply --auto-assign`. Bị loại, vì người dùng phải thấy người làm trước khi duyệt, không phải sau.

### 8. `plan.html`: template + dữ liệu, vẽ bằng JS trong trang

- Template `runtime/share/plan.html`, cùng cách làm với `report.html`: một chỗ `__SCRUM_DATA__`, thoát `<` thành `<`, chỉ dùng font hệ thống.
- Dữ liệu do `plan-html-data.jq` sinh: plan đã chuẩn hoá cùng `wave`, tải, mức vừa capacity, các thao tác (khi online), phần thay đổi, chuỗi đã dịch, và `generated_at`.
- Sơ đồ phụ thuộc theo đợt và các thanh tải được vẽ bằng JS trong trang (SVG dựng bằng `createElementNS`, chữ đặt qua `textContent`). Bố cục cột theo đợt đơn giản, không cần thư viện layout.
- Chuyển động bằng CSS (dòng chảy trên cạnh, chấm trạng thái), tắt dưới `prefers-reduced-motion`. Rê chuột hoặc focus một task thì làm sáng chuỗi tổ tiên và hậu duệ của nó.
- Góp ý của plan-critic: thêm trường tuỳ chọn `review` vào plan (`[{kind, text, status: fixed|kept}]`), do skill ghi sau bước soát. Trường này phải được thêm vào `plan.schema.json`. `plan apply` bỏ qua trường này.

Phương án khác: để Claude viết HTML mỗi lần. Bị loại vì tốn token, bố cục mỗi lần một kiểu, và số liệu có thể lệch `plan.json`. Phương án Mermaid cũng bị loại vì cần tải thư viện từ mạng.

### 9. Phần thay đổi: bản chụp cạnh plan

Mỗi lần sinh `plan.html`, hệ thống ghi `.plan-snapshot.json` cùng thư mục, gồm `{revision, tasks: [{id, title, points, depends_on, assignees, sprint}]}`. Lần sau so với bản chụp này bằng `plan-diff.jq`. Có khác biệt thì `revision + 1`. `plan apply` ghi số issue nhưng không tính là sửa, vì số issue không nằm trong các trường được so.

Phương án khác: so với `git HEAD`. Bị loại vì trong lúc sửa plan, file thường chưa được commit.

### 10. `.gitignore` của thư mục plan

`plan init` ghi `.gitignore` gồm `plan.html` và `.plan-snapshot.json` khi file chưa có. Thư mục plan tạo trước phiên bản này: `plan check` không tự ghi `.gitignore`, nhưng in một dòng nhắc thêm hai file đó vào `.gitignore`. Giải pháp này đơn giản hơn tự sửa `.gitignore` gốc của repo.

### 11. Mở trang

Skill `/plan` in đường dẫn tuyệt đối của `plan.html` và đề nghị mở bằng `open` (macOS) hoặc `xdg-open`. Sandbox của Claude Code chặn `open`, nên lệnh này chạy ngoài sandbox sau khi người dùng cho phép. Runtime không tự mở trình duyệt, để test và CI không bị ảnh hưởng.

## Risks / Trade-offs

- [Đổi hành vi `task new`] Người quen nhận lỗi khi không có sprint nay thấy task vào backlog → dòng in ra luôn nói rõ "in the backlog", và CHANGELOG có mục "Changed".
- [Đề xuất người làm sai] Skill đoán lĩnh vực từ mô tả task → luôn hiện trong một lần duyệt. Người dùng sửa bằng một câu, và login ngoài team vẫn bị cảnh báo.
- [`assignees` lớn ở repo của tổ chức] Danh sách dự phòng có thể rất dài → `scrum team` in nguồn "github" và gợi ý khai báo `team`. Skill `/plan` không đề xuất người làm khi nguồn là GitHub mà danh sách dài hơn 15 người.
- [Tìm PR chờ review bị giới hạn tốc độ của search API] Mỗi lần `scrum mine` chỉ tốn một lời gọi search. Lỗi thì bỏ phần này, không dừng lệnh.
- [Template HTML có lỗi JS] Nội dung phải đọc được ngay cả khi JS lỗi → bảng task và các thao tác được render sẵn bằng HTML từ dữ liệu ở phía jq, JS chỉ vẽ sơ đồ và hiệu ứng. Test kiểm tra file có đủ các phần và không có URL ngoài.
- [Bản chụp bị xoá] Lần sinh kế tiếp coi như lần đầu, không có phần thay đổi. Không mất dữ liệu.

## Migration Plan

- Không cần chuyển đổi dữ liệu. `team` mặc định rỗng, `plan.json` cũ vẫn hợp lệ (trường `review` là tuỳ chọn).
- `init` thêm ví dụ khối `team` đã comment trong `templates/scrum.yml`. Repo đã có `scrum.yml` không bị sửa.
- Phiên bản 0.9.0. Rollback bằng cách cài lại 0.8.x. Các file `plan.html` và bản chụp còn lại chỉ là file thừa.
