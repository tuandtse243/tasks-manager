# Design

## Context

Động cơ và phạm vi: xem `proposal.md`. Yêu cầu hành vi: xem `specs/`.

Hiện trạng và ràng buộc:

- `scrum plan apply` (`runtime/lib/cmd_plan.sh`) đọc một plan JSON, tạo issue feature rồi từng task, gắn sub-issue, và chỉ biết tạo mới. `resolve_sprint` dừng khi không có sprint đang mở.
- Kiến trúc hiện có: mỗi lệnh lấy JSON thô bằng `gh api`, tính kế hoạch bằng một file jq thuần, rồi áp kế hoạch. Test offline bằng fixture và `tests/fake-gh`. Change này giữ đúng cách đó.
- Skill không chứa logic; chỉ `sprint-plan` có hướng dẫn cho Claude soạn đề xuất.
- Plugin chưa có thư mục `agents/` hay `vendor/`.
- `scrum-init` chỉ chép `runtime/` sang repo đích. Workflow Actions không dùng lệnh plan.
- Plugin `aidw` (cài tại `~/.claude/plugins/cache/aidw/aidw/0.1.0/`) vendor `mattpocock/skills` tại commit `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d`, giấy phép MIT, và không sửa các file đó.
- Agent con không hỏi được người dùng. Mọi phỏng vấn và mọi bước duyệt phải nằm trong skill chạy ở phiên chính.
- Máy dev là macOS, Bash 3.2. Sandbox của Claude Code chặn `gh` đọc token trong keychain.

## Goals / Non-Goals

**Goals:**

- Một plan file là hợp đồng duy nhất giữa phần "nghĩ" (skill, agent) và phần "ghi lên GitHub" (CLI).
- Mọi phép tính trên plan là jq thuần, test được offline.
- Người dùng chỉ cần nhớ `/scrum-github:plan`; lệnh tự chỉ sang `discover` hay `project-scan` khi cần.
- Ba đợt trong `tasks.md` dùng được độc lập: xong đợt 1 là có ích ngay.

**Non-Goals:**

- Đồng bộ ngược từ GitHub về plan file. Sau khi áp, GitHub là nguồn sự thật, giống quyết định "label là nguồn sự thật" đã có.
- Tích hợp với `aidw`. Chỉ giữ plan file trung lập để sau này viết adapter.
- Agent đóng vai PM, BA, architect. Các góc nhìn đó là danh sách nhóm phải làm rõ trong skill `discover`.
- Tự commit các file dưới `docs/`. Người dùng tự commit.
- Lưu lịch sử phiên bản plan ngoài git.

## Decisions

### 1. Bố cục mới trong plugin

```
plugins/scrum-github/
  agents/
    plan-critic.md            # đợt 1
    researcher.md             # đợt 2
    codebase-scout.md         # đợt 3
  reference/
    planning-rules.md         # quy tắc dùng chung cho plan, discover, project-scan
    brief-template.md         # đợt 2
    project-context-template.md   # đợt 3
  vendor/pocock/
    grilling/  to-spec/  domain-modeling/  to-tickets/
    LICENSE  UPSTREAM.md
  skills/
    plan/SKILL.md             # thay sprint-plan
    discover/SKILL.md
    project-scan/SKILL.md
  scripts/
    vendor-sync.sh            # phía dev, không chép sang repo đích
  runtime/lib/
    cmd_context.sh  cmd_doc.sh
  runtime/lib/jq/
    plan-normalize.jq  plan-validate.jq (viết lại)  plan-actions.jq
    plan-render.jq  plan-writeback.jq
    context-inventory.jq  context-status.jq  doc-check.jq
  runtime/share/
    doc-sections.json         # tên mục bắt buộc của brief và tài liệu ngữ cảnh
```

`vendor/` và `reference/` đặt ngoài `skills/` để chúng không thành lệnh của plugin. Nếu `to-tickets` nằm trong `skills/`, nó sẽ xuất hiện như một lệnh và tự đi publish ticket.

### 2. Plan file là JSON, bản xem là Markdown sinh ra

Nguồn là `plan.json`; `plan.md` do `scrum plan render` sinh, có dòng đầu "generated, do not edit".

Lý do chọn JSON thay vì YAML hay Markdown có front matter: toàn bộ runtime đã xử lý JSON bằng jq, đã có `plan.schema.json`, và việc ghi lại số issue bằng jq không làm mất gì. YAML dễ sửa tay hơn nhưng ghi lại bằng `yq` có thể đổi định dạng và comment. Người dùng sửa plan qua skill `plan` hoặc sửa thẳng JSON; `plan validate` bắt lỗi.

Ví dụ phiên bản 2:

```json
{
  "version": 2,
  "title": "Blog post comments",
  "sprint": null,
  "epic": null,
  "features": [
    {
      "id": "F1", "title": "Bình luận dưới bài viết", "body": "…", "issue": null,
      "tasks": [
        { "id": "T1", "title": "Lưu bình luận", "body": "…",
          "acceptance": ["…"], "subtasks": ["Migration", "API"],
          "points": 3, "depends_on": [], "assignees": [], "bug": false, "issue": null },
        { "id": "T2", "title": "Hiển thị bình luận", "points": 3, "depends_on": ["T1"], "issue": null }
      ]
    }
  ],
  "assumptions": ["…"],
  "out_of_scope": ["…"]
}
```

`id` duy nhất trong cả plan (epic không cần `id`). Không có trường nào riêng của GitHub ngoài `issue`.

### 3. Chuẩn hoá phiên bản 1 trong bộ nhớ

`plan-normalize.jq` đổi plan không có `version` thành dạng phiên bản 2: một feature `F1`, task `T1…Tn`, và `sprint: "current"` khi `sprint` bỏ trống (giữ hành vi cũ). Mọi bước sau chỉ nhận dạng phiên bản 2, nên chỉ có một đường mã. Khi `apply` ghi lại số issue, file được ghi ở dạng phiên bản 2.

Phương án bỏ qua: giữ hai đường mã cho hai phiên bản. Bị loại vì gấp đôi test mà không ai cần.

### 4. `plan apply` theo ba bước: đọc trạng thái, tính thao tác, áp

1. **Kiểm tra** bằng `plan-validate.jq` (offline). Vòng phụ thuộc được tìm bằng cách gỡ dần các task không còn phụ thuộc; còn lại gì thì đó là vòng.
2. **Đọc trạng thái** (chỉ khi cần):
   - Milestone, khi plan có `sprint` nào khác rỗng.
   - Với mỗi mục cha đã có `issue`: `GET /issues/{n}/sub_issues`.
   - Với mỗi task đã có `issue` và có `depends_on`: `GET /issues/{n}/dependencies/blocked_by`.
   - Với `--update`: `GET /issues/{n}` của từng mục đã có `issue`.
3. **Tính thao tác** bằng `plan-actions.jq`: vào là plan, cấu hình, trạng thái; ra là danh sách có thứ tự `create_epic`, `create_feature`, `create_task`, `update`, `link_sub`, `link_blocked`, `skip` (kèm lý do). `--dry-run` in danh sách này rồi dừng.
4. **Áp** từng thao tác. Thứ tự: epic → feature → task (task theo thứ tự tô-pô của `depends_on`) → sub-issue → phụ thuộc → `project_touch`.

Sau mỗi `create_*`, `plan-writeback.jq` ghi số issue vào file qua file tạm cùng thư mục rồi `mv`, để file luôn là JSON hợp lệ. Vì thao tác tạo sinh ra số issue mà các thao tác `link_*` cần, bước áp giữ một bảng `id → {number, id}` trong shell và thay vào khi áp.

Lý do đọc quan hệ hiện có thay vì cứ `POST` rồi nuốt lỗi: lỗi "đã tồn tại" và lỗi "repo không hỗ trợ" không phân biệt được chắc chắn, mà hai trường hợp cần xử lý khác nhau (bỏ qua, hoặc dùng cách dự phòng).

### 5. Cách dự phòng ghi vào thân issue, trong khối có dấu

Khi sub-issue hoặc phụ thuộc bị từ chối, lệnh ghi vào thân issue một khối giữa hai dấu, ví dụ `<!-- scrum:children -->…<!-- /scrum:children -->` và `<!-- scrum:blocked-by -->…<!-- /scrum:blocked-by -->`. Chạy lại thì thay nội dung trong khối, không nối thêm. Đây là cùng kiểu marker mà mô tả milestone đang dùng.

### 6. Phụ thuộc dùng API "blocked by" của GitHub

`POST /repos/{owner}/{repo}/issues/{n}/dependencies/blocked_by` với `issue_id` là `id` của issue chặn (không phải số issue), giống cách `sub_issues` đang dùng `id`. API này chính thức từ 08/2025.

Phương án bỏ qua: chỉ ghi "Blocked by #n" vào thân issue. Bị loại làm mặc định vì GitHub không hiểu đó là quan hệ, nhưng được giữ làm cách dự phòng (mục 5).

### 7. Backlog là issue không có milestone

Task không có sprint được tạo không có milestone. Các lệnh `status`, `report`, `digest`, `sprint close` đọc theo milestone nên không thấy backlog; đó là hành vi mong muốn. Đưa task vào sprint bằng cách đặt milestone trên GitHub, hoặc sửa `sprint` trong plan rồi `plan apply --update`.

Board (Projects v2) chỉ nhận task của sprint đang mở; change này không đổi điều đó. Cần một test xác nhận `project_touch` trên issue không có milestone không thêm thẻ và không lỗi.

Phương án bỏ qua: một milestone tên "Backlog". Bị loại vì mọi lệnh đọc milestone sẽ phải loại nó ra.

### 8. `--update` chỉ đụng bốn thứ

Tiêu đề, thân, label điểm, milestone của issue đang mở. Không đụng label trạng thái (workflow quản lý), assignee (người dùng hay đổi tay), và issue đã đóng. Cập nhật label dùng một lần `PUT` trên tập label đã tính, như `set_status`.

Khi cập nhật thân, khối dự phòng ở mục 5 được giữ lại.

### 9. Ước lượng: điểm là gốc

`plan-render.jq` nhận plan, cấu hình và danh sách milestone (có thể rỗng), và trả về chuỗi Markdown. Giờ = điểm × `planning.hours_per_point`. Số sprint = tổng điểm chia velocity trung bình của tối đa ba sprint đóng gần nhất có marker velocity, làm tròn lên.

`plan render` thử đọc milestone; không có `gh`, chưa đăng nhập, hay lỗi mạng thì truyền danh sách rỗng và không báo lỗi. Có `--offline` để bỏ hẳn bước đọc. Vì vậy `render` và `validate` không gọi `require_tools` cho `gh`.

Phương án bỏ qua: thêm trường giờ riêng cho từng task. Bị loại vì sẽ có hai con số ước lượng lệch nhau; velocity của team đã là cách quy điểm ra thời gian.

### 10. Epic

Label `labels.epic`, mặc định `type: epic`, màu và mô tả trong `label-plan.jq`. `is_task` trong `scrum.jq` loại thêm label này; đó là chỗ duy nhất quyết định một issue có phải task không, nên điểm, velocity, burndown, digest và đồng bộ trạng thái đều theo. Kiểm tra lại `project-items.jq` và `event-decide.jq` có đi qua `is_task` không.

Subtask là checkbox trong thân task (mục `### Subtasks`, thêm vào `task-payload.jq` sau tiêu chí hoàn thành). Không thành issue, để điểm và velocity không bị chia nhỏ.

### 11. Vendor skill từ `aidw`

`scripts/vendor-sync.sh SRC` copy nguyên văn bốn thư mục `grilling`, `to-spec`, `domain-modeling`, `to-tickets` cùng `LICENSE` từ `vendor/pocock/` của `aidw` (`SRC`) vào `plugins/scrum-github/vendor/pocock/`, rồi sinh `UPSTREAM.md`: repo gốc, commit (đọc từ `UPSTREAM.md` của nguồn), ngày sync, danh sách bốn skill, và ghi rõ bản này lấy qua `aidw`. Chạy lại script khi upstream hoặc `aidw` cập nhật, rồi xem `git diff`. Nếu repo nguồn của `aidw` có bản vendor mới hơn bản cache 0.1.0 thì lấy từ đó và ghi commit tương ứng.

Không sửa file vendored. Skill của plugin đọc chúng bằng đường dẫn `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/<skill>/SKILL.md` rồi áp phần **adapter** của mình:

| Skill vendored | Dùng trong | Adapter ghi đè |
|---|---|---|
| `grilling` | `discover` | Thêm danh sách nhóm phải làm rõ; ghi mọi vòng vào phụ lục brief |
| `to-spec` | `discover` | Ghi vào `brief.md` theo `reference/brief-template.md`; không publish lên tracker |
| `domain-modeling` | `discover`, `project-scan` | Chỉ dùng phần bảng thuật ngữ; ghi vào tài liệu ngữ cảnh dự án; không tạo ADR |
| `to-tickets` | `plan` | Cỡ task theo thang điểm và sprint, không theo "một context window"; dừng sau bước duyệt và ghi `plan.json`; không publish, không label `ready-for-agent`, không `/setup-matt-pocock-skills` |

Phương án bỏ qua: tự viết lại hướng dẫn phỏng vấn và chia task. Người dùng đã chọn mượn bản của `aidw`.

### 12. Ba skill

**`plan`** (thay `sprint-plan`; tham số: brief, đường dẫn, hoặc mô tả; `--quick`):

1. Đọc `scrum config`, `reference/planning-rules.md`; chạy `scrum context status` và đọc tài liệu ngữ cảnh dự án nếu có.
2. Chạy `scrum plan init` để có thư mục plan. Đã có `plan.json` thì đọc và sửa tiếp, giữ `id` và `issue`.
3. Kiểm tra độ rõ; thiếu thì đề nghị `discover`.
4. Chia task theo `to-tickets` với adapter.
5. Trừ `--quick`: gọi agent `plan-critic` với brief và bản nháp.
6. Ghi `plan.json`; chạy `scrum plan check` (kiểm tra, sinh bản xem, in thao tác sẽ làm, trong một lần gọi).
7. Trình bày bảng, phát hiện của critic, phần ước lượng và danh sách thao tác. Lặp bước 6–7 tới khi duyệt hoặc huỷ.
8. Sau khi duyệt: `scrum plan apply`. Lệnh tự sinh lại bản xem để có số issue.

**`discover`** (tham số: ý tưởng hoặc đường dẫn; `--quick`, `--deep`):

1. Đọc quy tắc dùng chung; chạy `scrum plan init` và `scrum context status`; đọc tài liệu ngữ cảnh dự án.
2. Song song: `researcher` (mức `deep`, hoặc khi yêu cầu cần thông tin bên ngoài) và `codebase-scout` cho các vùng liên quan (repo có mã, từ đợt 3).
3. Phỏng vấn theo `grilling` với adapter.
4. Kiểm tra độ phù hợp và cỡ (repo có mã).
5. Tổng hợp brief theo `to-spec` với adapter; chạy `scrum doc check` trên brief; trình bày tóm tắt; chờ xác nhận.

**`project-scan`** (tham số: `--full`):

1. Chạy `scrum context status` (tài liệu có chưa, cũ bao nhiêu commit, thư mục nào đã đổi) và `scrum context inventory` (bản kê repo).
2. Giao `codebase-scout` đọc, kèm bản kê; chia theo thư mục gốc khi repo lớn; khi làm mới thì chỉ giao các thư mục đã đổi.
3. Ghi tài liệu theo `reference/project-context-template.md`, giữ mục "Ghi chú của team".
4. Chạy `scrum context stamp` để ghi dấu, rồi `scrum doc check` trên tài liệu.

### 13. Ba agent, đều chỉ đọc

| Agent | Công cụ | Trả về |
|---|---|---|
| `plan-critic` | Read, Grep, Glob | Danh sách phát hiện theo loại: thiếu, ngoài scope, quá lớn, phụ thuộc, tiêu chí không kiểm tra được |
| `researcher` | WebSearch, WebFetch, Read | Phát hiện kèm URL; phần không tìm được nguồn ghi riêng |
| `codebase-scout` | Read, Grep, Glob, Bash | Tóm tắt có đường dẫn file làm căn cứ; điều không xác định được ghi "chưa rõ" |

Không agent nào có Write hay Edit. Agent trả kết quả cho skill; skill là nơi duy nhất ghi file và hỏi người dùng. `plan-critic` không nhận kết luận của skill, chỉ nhận brief và bản nháp, để bản soát không bị neo theo.

### 14. Quy tắc dùng chung

`reference/planning-rules.md`, được cả ba skill đọc ở bước đầu:

1. Không ghi gì lên GitHub trước khi người dùng duyệt. Chỉ CLI `scrum` chạm GitHub.
2. Agent chỉ đọc. Chỉ skill ghi file, và chỉ dưới `planning.dir` hoặc vào `planning.context_file`.
3. Sự thật lấy từ mã và web; quyết định thuộc về người dùng.
4. Điều phải đoán thì ghi thành giả định, có nội dung cụ thể.
5. Task là lát cắt dọc; vượt điểm lớn nhất của thang thì tách.
6. Nói chuyện với người dùng bằng ngôn ngữ của họ; tiêu đề mục trong brief, plan và tài liệu ngữ cảnh giữ đúng như template.

### 15. Việc lặp lại và xác định được thì thành script

Skill gọi script cho mọi bước mà cùng đầu vào luôn cho cùng kết quả; skill chỉ giữ phần phán đoán (độ rõ, phỏng vấn, chia task, soát, kết luận độ phù hợp). Script nằm trong `runtime/` nên test offline được và chạy được từ `.github/scrum/` của repo đích.

| Lệnh | Việc | Mạng |
|---|---|---|
| `scrum plan init "<tiêu đề>" [--slug S]` | Tính slug, tạo thư mục plan, in JSON đường dẫn `dir`, `plan`, `view`, `brief` và file nào đã có | Không |
| `scrum plan check FILE [--offline]` | `validate`, rồi `render`, rồi in thao tác của `apply --dry-run`. Dừng ở bước đầu tiên lỗi | Chỉ bước cuối |
| `scrum context inventory` | In JSON bản kê repo từ `git ls-files`: số file theo thư mục gốc và theo đuôi file, file manifest, script trong `package.json`, file CI, thư mục test, tài liệu; `has_code` | Không |
| `scrum context status` | In JSON: tài liệu có chưa, `sha` và ngày trong dấu, số commit chênh, thư mục gốc đã đổi, `stale` | Không |
| `scrum context stamp` | Ghi hoặc thay dòng dấu trong tài liệu bằng `HEAD` và ngày hôm nay | Không |
| `scrum doc check FILE [--type brief\|context]` | Kiểm tra file có đủ mục bắt buộc theo `doc-sections.json`; tài liệu ngữ cảnh còn phải có dấu | Không |

Chi tiết:

- **Slug.** Hàm `slug` trong `branch-name.jq` chuyển sang `scrum.jq` để dùng chung. Nó chỉ giữ ký tự ASCII, nên tiêu đề tiếng Việt cho slug xấu; vì vậy skill truyền `--slug` đã bỏ dấu, và lệnh từ chối slug không khớp `^[a-z0-9]+(-[a-z0-9]+)*$`.
- **Bản kê.** `context-inventory.jq` nhận danh sách đường dẫn và trả JSON, nên test bằng fixture. `has_code` là sai khi mọi file đều là tài liệu hoặc nằm dưới `.github/`.
- **Độ cũ.** `stale` là đúng khi số commit chênh vượt `planning.context_stale_commits` (mặc định 50). Khi `sha` không còn trong lịch sử, số commit chênh là rỗng và `unknown` là đúng.
- **Tên mục.** `runtime/share/doc-sections.json` là nguồn duy nhất cho tên mục bắt buộc. Hai template trong `reference/` phải khớp nó; một test so sánh hai bên.
- **`plan apply` tự sinh lại bản xem** sau khi chạy xong, kể cả khi lỗi giữa chừng, để `plan.md` luôn khớp số issue trong `plan.json`.

Phương án bỏ qua: để skill tự chạy `git` và tự soát mục. Bị loại vì ba skill lặp cùng một việc ở mỗi lần chạy, tốn token và không test được.

Chưa làm: `scrum plan status FILE` (đọc GitHub và in tiến độ của plan). Để sau khi có nhu cầu thật.

## Risks / Trade-offs

- [Người dùng sửa issue trên GitHub rồi chạy `--update` làm mất phần sửa] → `--update` không phải mặc định; `--dry-run` in từng issue sẽ bị ghi đè; skill `plan` luôn chạy `--dry-run` trước.
- [Plan file và GitHub lệch nhau theo thời gian] → Chấp nhận. Bản xem ghi rõ plan là ảnh chụp lúc lập; trạng thái thật nằm trên GitHub.
- [Người dùng xoá trường `issue` hoặc đổi `id` rồi áp lại, tạo trùng] → CLI không phát hiện được việc này. `--dry-run` in rõ mọi thao tác tạo, và skill `plan` trình bày danh sách đó cho người dùng trước khi áp.
- [API phụ thuộc hoặc sub-issue không có ở repo đích] → Cách dự phòng ở mục 5, có test với `fake-gh` trả lỗi.
- [Skill vendored viết cho ngữ cảnh khác, Claude theo nhầm phần bị ghi đè] → Adapter đặt sau lệnh đọc file vendored và nói rõ "adapter thắng"; test tay trong sandbox cho từng skill.
- [Nghiên cứu web và nhiều agent tốn token] → Ba mức độ sâu; `standard` chỉ gọi `researcher` khi yêu cầu cần thông tin bên ngoài.
- [Tài liệu ngữ cảnh dự án sai hoặc cũ dẫn tới kết luận phù hợp sai] → Mỗi nhận định có file làm căn cứ; dấu commit và cảnh báo độ cũ; `discover` vẫn cho `codebase-scout` đọc lại vùng liên quan.
- [Đổi tên `sprint-plan` làm gãy thói quen] → Ghi trong README và hướng dẫn; plugin mới ở 0.2.0 và chưa có người dùng ngoài.

## Migration Plan

1. Cài phiên bản 0.3.0 của plugin.
2. Trong repo đích: chạy `/scrum-github:scrum-init` để có label `type: epic` và runtime mới, rồi commit `.github/`.
3. Dùng `/scrum-github:plan` thay `/scrum-github:sprint-plan`. Plan JSON cũ vẫn áp được.

Quay lại: cài lại 0.2.0 và chạy `scrum-init`. Label `type: epic`, các issue đã tạo và file dưới `docs/` giữ nguyên; không có gì phải dọn.

## Open Questions

Không còn câu hỏi mở. Kết quả đối chiếu (task 1.2):

- Tài liệu GitHub REST và chạy thử trên `tuandtse243/scrum-sandbox` (2026-11-19) khớp nhau. Response thật (đã lược còn `id`, `number`, `title`, `state`, `html_url`) nằm trong `tests/fixtures/github-*.json`.
  - `GET …/issues/{n}/dependencies/blocked_by`: 200, mảng issue (`[]` khi chưa có).
  - `POST …/dependencies/blocked_by` với `{"issue_id": <id>}`: 201, trả về issue bị chặn.
  - Quan hệ đã có: 422 "Target issue has already been taken". Tự chặn chính nó: 422. Gắn sub-issue đã có: 422 "may not contain duplicate sub-issues and Sub issue may only have one parent".
  - `DELETE …/dependencies/blocked_by/{issue_id}`: 200.
- Vì "đã tồn tại" và "bị từ chối" cùng là 422, quyết định ở mục 4 (đọc quan hệ hiện có trước, coi mọi lỗi `POST` là bị từ chối) được giữ.

Đã trả lời: gợi ý `planning.hours_per_point: 4` được ghi trong `docs/huong-dan-ap-dung.md` (mục 3.2), kèm lưu ý chỉnh theo thực tế sau vài sprint; mặc định vẫn là không đặt.
