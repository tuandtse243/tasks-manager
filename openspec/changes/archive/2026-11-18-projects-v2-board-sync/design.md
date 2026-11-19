# Design

## Context

Động cơ: xem `proposal.md`. Yêu cầu hành vi: xem `specs/project-board-sync` và `specs/pr-task-linking`.

Hiện trạng và ràng buộc:

- Kiến trúc hiện có gồm ba bước: lấy JSON bằng `gh api`, tính toán bằng hàm jq thuần, áp kết quả bằng `gh api`. Test offline dùng `tests/fake-gh` qua biến `SCRUM_GH`. Phần mới giữ nguyên mô hình này.
- `set_status` trong `runtime/lib/common.sh` là điểm duy nhất đổi label trạng thái từ CLI. Workflow status-sync đi qua `apply_decision` trong `cmd_event.sh`.
- GitHub Actions **không có** trigger cho sự kiện `projects_v2_item`. Webhook loại này chỉ đến được GitHub App hoặc webhook cấp org, nên muốn biết thay đổi trên board thì phải poll.
- `GITHUB_TOKEN` không truy cập được Projects v2 thuộc user hoặc org. Cần PAT hoặc token GitHub App.
- Thay đổi do `GITHUB_TOKEN` gây ra không kích hoạt workflow khác. Thay đổi do PAT gây ra **có** kích hoạt.
- Projects v2 chỉ ghi được qua GraphQL. Field single-select phải đặt bằng `optionId`, không đặt bằng tên.
- Project tạo từ template mặc định của GitHub có Status với option `Todo`, `In Progress`, `Done`, kèm các built-in workflow như "Item closed → Done" và "Item reopened → Todo".

## Goals / Non-Goals

**Goals:**

- Mọi quyết định đồng bộ là một hàm jq thuần, nhận dữ liệu (label, board, S) và trả về danh sách thao tác, test được bằng fixture.
- Không có trạng thái nào lưu ngoài GitHub. S nằm ngay trên Project.
- Lỗi khi cập nhật board không bao giờ làm hỏng luồng lõi (PR → label).

**Non-Goals:**

- Realtime từ board về label (độ trễ bằng `poll_cron`).
- Tự sửa option của field Status, hoặc tự tắt built-in workflow của Project.
- Project chứa item của nhiều repo được nhiều cấu hình khác nhau quản lý.

## Decisions

### 1. Nguồn sự thật và field `Synced status` (S)

Label là nguồn sự thật. S là field text trên Project, lưu tên vai trò (`new`, `in_progress`, `done`) của lần sync gần nhất. Lưu tên vai trò thay vì tên option để không phụ thuộc vào việc đổi tên option.

Bảng quyết định (L = vai trò của label, B = vai trò của option trên board, hoặc `null` nếu option rỗng hoặc không ánh xạ được):

| Điều kiện | Thao tác |
|---|---|
| S rỗng | Đặt B := L, S := L |
| B không ánh xạ được (option lạ) | Không làm gì, ghi cảnh báo |
| L = B = S | Không làm gì |
| B ≠ S, L = S | Áp B vào label (đóng/mở issue nếu cần), S := B |
| L ≠ S, B = S | Đặt B := L, S := L |
| L ≠ S, B ≠ S, L = B | Chỉ đặt S := L |
| L ≠ S, B ≠ S, L ≠ B | Label thắng: B := L, S := L, comment lên issue |
| Task không có label status | Coi L = New khi issue mở, Done khi đóng completed (giống `task_role` hiện có) |

**Phương án bỏ qua:**

- So sánh `updatedAt` của item với thời điểm label đổi. Cách này phải đọc timeline của issue (nhiều lời gọi API), và không phân biệt được ai đổi field nào.
- Lưu trạng thái lần sync trong một file hoặc artifact của Actions. Sẽ có trạng thái nằm ngoài GitHub data, và mất khi cache hết hạn.

### 2. Hàm jq thuần

- `project-sync-plan.jq`: input là cấu hình, danh sách item (đã chuẩn hoá: số issue, repo, state, `state_reason`, labels, option Status, S, Points) và ID của field/option. Output là `{ops: [...], warnings: [...]}`, với mỗi op là một trong `set_labels`, `close`, `reopen`, `set_board_status`, `set_synced`, `set_points`, `clear_points`, `comment`.
- `project-items.jq`: chuẩn hoá kết quả GraphQL về dạng trên.
- Thứ tự op cho một issue khi áp thay đổi từ board: `set_labels` → `close`/`reopen` → `set_synced`. Đặt label trước giúp sự kiện `issues.reopened` mà PAT kích hoạt thấy label New và giữ nguyên (xem delta `pr-task-linking`).

### 3. Lời gọi GraphQL

Thêm vào `common.sh` hàm `gh_graphql QUERY_FILE [-f k=v ...]` gọi `ghx api graphql`, để `fake-gh` thay được như các lời gọi REST. Câu query đặt trong `runtime/share/graphql/*.graphql`.

- Tìm Project: `organization(login).projectV2(number)`. Nếu không thấy thì thử `user(login).projectV2(number)`.
- Đọc item: `projectV2.items(first: 100, after:)`, lấy `content { ... on Issue { number repository { nameWithOwner } state stateReason labels } }` và `fieldValues` của ba field cấu hình. Phân trang đến hết. Item không phải Issue của repo hiện tại bị bỏ qua (spec "Item bị bỏ qua").
- Ghi: `updateProjectV2ItemFieldValue` (single-select / text / number), `clearProjectV2ItemFieldValue`, `addProjectV2ItemById` (dùng `node_id` của issue), `createProjectV2Field`.

Nhiều mutation cho cùng một lần chạy được gom thành một request GraphQL dùng alias, tối đa 20 mutation mỗi request, để giảm số lần gọi và rate limit.

**Phương án bỏ qua:** dùng `gh project item-edit` / `item-list`. Các lệnh này cần ID nội bộ, giới hạn số item khi list, và đầu ra khó giả lập trong test.

### 4. Token

- Workflow: `GH_TOKEN` cho phần REST vẫn là `github.token`. Phần Project dùng biến `SCRUM_PROJECT_TOKEN`; `gh_graphql` chạy `GH_TOKEN=$SCRUM_PROJECT_TOKEN gh api graphql`.
- Riêng `project sync` cũng dùng `SCRUM_PROJECT_TOKEN` cho phần REST (đổi label, đóng/mở). Thay đổi do PAT gây ra kích hoạt status-sync, nhờ đó hành vi "Done → đóng" luôn đi qua cùng một luồng. Kết quả là idempotent nên không lặp.
- CLI trên máy: không có `SCRUM_PROJECT_TOKEN` thì dùng token của `gh`. Người dùng cần `gh auth refresh -s project`.
- Hàm `project_enabled` trả về true chỉ khi `project.enabled` và có token dùng được. Nếu không, các hook best-effort bỏ qua và in một cảnh báo.

### 5. Hook best-effort

`set_status` (CLI) và `apply_decision` (workflow) gọi thêm `project_mirror ISSUE_NUMBER ROLE` sau khi đổi label. Hàm này tìm item (thêm vào Project nếu chưa có), đặt Status và S. Mọi lỗi trong hàm đều được bắt lại và in `warn`. `task new` và `plan apply` gọi `project_add` cho task mới.

Lần poll luôn là bảo đảm cuối cùng: kể cả khi hook bị bỏ qua, bảng quyết định ở mục 1 vẫn đưa board về đúng.

### 6. Workflow `scrum-project-sync.yml`

```yaml
on:
  schedule: [{cron: "<project.poll_cron>"}]
  workflow_dispatch:
  issues: {types: [labeled, unlabeled, milestoned, demilestoned]}
concurrency: {group: scrum-project-sync, cancel-in-progress: false}
permissions: {issues: write, contents: read}
```

- Job chạy `scrum project sync` với `SCRUM_PROJECT_TOKEN: ${{ secrets.SCRUM_PROJECT_TOKEN }}`. Thiếu secret thì job in `::error` nêu tên secret và quyền cần cấp, rồi exit 1.
- Với sự kiện `issues`, lệnh chỉ đồng bộ issue đó (`project sync --issue N`). Với `schedule` và `workflow_dispatch`, lệnh đồng bộ toàn bộ.
- Cài có điều kiện trong `cmd_init.sh`: chỉ khi `project.enabled`. Cron được ghi vào file lúc init, giống digest.
- Mặc định 15 phút để tiết kiệm phút Actions trên repo private (khoảng 3.000 lần chạy mỗi tháng nếu chạy 24/7). Doc gợi ý giới hạn giờ hành chính, ví dụ `*/15 1-11 * * 1-5`.
- `scrum-status-sync.yml` thêm `SCRUM_PROJECT_TOKEN: ${{ secrets.SCRUM_PROJECT_TOKEN }}` vào env. Khi không có secret thì giá trị rỗng và hook bị bỏ qua.

### 7. Built-in workflow của Project

Các built-in workflow "Item added to project", "Item closed", "Item reopened", "Pull request linked to issue", "Pull request merged" tự đổi Status mà không cập nhật S. Ví dụ:
- Khi issue mở lại, "Item reopened" đặt Todo trong lúc label là In progress. Lần sync kế tiếp sẽ thấy B ≠ S và L = S, rồi áp Todo vào label, tức là sai.
- "Item added to project" đặt Todo **sau** khi sync vừa thêm item và đặt cột theo label. Lỗi xảy ra theo cùng cơ chế. Lỗi này phát hiện được trong lúc làm, nên danh sách đã được mở rộng từ 3 lên 5 workflow.

Quyết định: `project init` đọc `projectV2.workflows { name enabled }` và **dừng với lỗi** nếu còn bật một trong các workflow trên (danh sách nằm trong `conflicting_workflows`, file `lib/jq/project.jq`). Thông báo hướng dẫn tắt chúng trong Settings → Workflows của Project. Có tuỳ chọn `--allow-builtin-workflows` cho người chấp nhận rủi ro.

Hai workflow sau không xung đột nên được giữ:
- "Auto-add to project": chỉ thêm item. Status do sync đặt.
- "Auto-close issue": đóng issue khi kéo sang Done, cùng chiều với quy tắc của sync.

**Phương án bỏ qua:** tự tắt built-in workflow qua API. API không có mutation công khai ổn định cho việc này.

### 8. Thay đổi `event-decide.jq`

`issue_reopened`: nếu `task_role` hiện tại là `new` thì `keep("already new")`, ngược lại `move("in_progress")`. Thêm fixture test cho cả hai nhánh.

### 9. Cấu hình

Thêm vào `defaults.json`:

```json
"project": {
  "enabled": false, "owner": null, "number": null,
  "status_field": "Status",
  "status_options": {"new": "Todo", "in_progress": "In Progress", "done": "Done"},
  "synced_field": "Synced status", "points_field": "Points",
  "poll_cron": "*/15 * * * *"
}
```

`validate-config.jq` kiểm tra các khoá này chỉ khi `enabled`: `owner` là chuỗi khác rỗng, `number` là số nguyên dương, ba option khác rỗng và không trùng nhau, `poll_cron` có 5 trường.

## Risks / Trade-offs

- [Board → label trễ tới `poll_cron`] → Ghi rõ trong doc. Nút "Run workflow" (`workflow_dispatch`) dùng để sync ngay khi cần.
- [PAT hết hạn hoặc bị thu hồi] → Workflow thất bại rõ ràng, và GitHub gửi email thông báo job lỗi cho người kích hoạt. Hiển thị thêm trong digest là Open Question.
- [Người dùng xoá hoặc sửa S bằng tay] → S rỗng thì đặt theo label (an toàn). S bị sửa thành giá trị khác thì có thể áp nhầm board vào label một lần. Doc khuyên ẩn cột S trong mọi view.
- [*Auto-close issue* đóng issue ngay khi thẻ vào Done, trước khi sync kịp chạy] → Với cột Done, board luôn thắng, kể cả khi label vừa đổi. Trạng thái cuối vẫn nhất quán hai bên. Chạy end-to-end ngày 2026-11-18 xác nhận điều này; quy tắc "label thắng" chỉ áp dụng được với các cột khác Done, và được kiểm chứng bằng test offline.
- [Người dùng đổi tên option trên board] → `project sync` báo lỗi cấu hình (option không tìm thấy) thay vì đoán.
- [Tiêu tốn phút Actions và rate limit GraphQL] → Một query phân trang 100 item. Mutation gom theo alias. Workflow theo sự kiện chỉ sync một issue.
- [Hai sự kiện sinh ra từ cùng một thay đổi (PAT đổi label → status-sync và project-sync cùng chạy)] → Mọi thao tác idempotent. `concurrency` xếp hàng project-sync.
- [Rủi ro bảo mật của PAT trong secret] → Khuyên dùng fine-grained PAT chỉ cấp cho repo đó, quyền Issues RW và Projects RW, có hạn dùng. Hoặc dùng GitHub App. Workflow không checkout code PR (giữ nguyên nguyên tắc của design cũ).

## Migration Plan

- Repo chưa bật: không đổi gì. Cập nhật runtime bằng `scrum init` như thường.
- Bật tính năng:
  1. Tạo Project (template Board).
  2. Tắt 3 built-in workflow.
  3. Tạo secret `SCRUM_PROJECT_TOKEN`.
  4. Thêm khối `project:` vào `scrum.yml`.
  5. `scrum init --force-file .github/workflows/scrum-status-sync.yml`.
  6. `scrum project init --dry-run`, rồi chạy thật.
  7. Commit và push.
- Rollback: đặt `project.enabled: false` và xoá `scrum-project-sync.yml`. Field S và Points trên Project có thể để nguyên hoặc xoá tay. Label không bị ảnh hưởng.

## Open Questions

- Có hiển thị trạng thái của lần sync gần nhất trong digest không. Việc này cần quyền `actions: read`; nếu không có quyền thì bỏ, không ảnh hưởng tới spec chính.
