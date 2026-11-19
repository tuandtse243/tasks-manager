# Hướng dẫn áp dụng scrum-github

Tài liệu cho cả team: PO, Scrum Master và Dev. Đọc mục 1 và 2 để hiểu và cài đặt, mục 4 để biết
mỗi người làm gì trong một sprint. Tra lệnh và cấu hình đầy đủ ở
[README của plugin](../plugins/scrum-github/README.md).

**Mục lục**
1. [Plugin làm gì](#1-plugin-làm-gì)
2. [Cài đặt (mỗi người một lần)](#2-cài-đặt-mỗi-người-một-lần)
3. [Thiết lập repo dự án (một người làm)](#3-thiết-lập-repo-dự-án-một-người-làm)
4. [Một sprint từ đầu tới cuối](#4-một-sprint-từ-đầu-tới-cuối)
5. [Quy ước team](#5-quy-ước-team)
6. [Board kanban (tuỳ chọn)](#6-board-kanban-tuỳ-chọn)
7. [Xử lý sự cố](#7-xử-lý-sự-cố)
8. [Giới hạn hiện tại](#8-giới-hạn-hiện-tại)
9. [Checklist áp dụng](#9-checklist-áp-dụng)

---

## 1. Plugin làm gì

Plugin chạy Scrum ngay trên GitHub. Nó không có cơ sở dữ liệu riêng: **mọi thứ là issue, label và
milestone của GitHub**, nên ai có quyền vào repo là thấy được tiến độ.

| Scrum | Trên GitHub | Cần biết |
|---|---|---|
| Sprint | Milestone `Sprint {n}` | Ngày bắt đầu, kết thúc và velocity được ghi ẩn trong mô tả milestone |
| Task | Issue | Có đúng một label `status: …` và tối đa một label `points: N` |
| Trạng thái | Label `status: New`, `status: In progress`, `status: Done` | Tự đổi theo PR. Không sửa tay |
| Task xong | Issue **đóng với lý do "completed"** | Đóng với lý do "not planned" thì không tính điểm |
| Feature | Issue có label `type: feature`; các task là sub-issue của nó | Không tính điểm |
| Epic | Issue có label `type: epic`; các feature là sub-issue của nó | Không tính điểm |
| Backlog | Issue **không có milestone** | Không vào báo cáo sprint cho tới khi được gán vào sprint |
| Plan | File `docs/plans/<slug>/plan.json` trong repo, kèm bản xem `plan.md` | Chỉ là bản chụp lúc lập plan. Sau khi tạo issue, GitHub mới là nơi giữ trạng thái thật |
| Velocity | Tổng điểm task Done trong sprint | Ghi lại khi đóng sprint |

Vòng đời một task:

```
tạo task ──► New ──(task-start, hoặc mở PR "Closes #n")──► In progress ──(merge PR)──► Done, issue đóng
```

---

## 2. Cài đặt (mỗi người một lần)

| Công cụ | Cài | Kiểm tra |
|---|---|---|
| GitHub CLI | `brew install gh`, rồi `gh auth login -h github.com -s repo,workflow` | `gh auth status` |
| jq 1.6 trở lên | `brew install jq` | `jq --version` |
| yq v4 của **mikefarah** | `brew install yq` | `yq --version` có chữ `mikefarah` |
| Claude Code | Không bắt buộc nếu chỉ dùng CLI | |

> Đừng dùng `pip install yq`: lệnh đó cài một công cụ khác trùng tên, và plugin sẽ từ chối nó.

Cài plugin trong Claude Code:

```
/plugin marketplace add tuandtse243/tasks-manager
/plugin install scrum-github@tasks-manager
```

Không dùng Claude Code thì gọi thẳng script: `bash <đường-dẫn>/plugins/scrum-github/runtime/bin/scrum <lệnh>`.
Sau khi thiết lập (mục 3), repo dự án có sẵn một bản tại `.github/scrum/bin/scrum`.

---

## 3. Thiết lập repo dự án (một người làm)

Thường là Scrum Master hoặc tech lead, làm trong một bản clone của repo dự án.

### 3.1 Khởi tạo

```
/scrum-github:scrum-init
```

Lệnh cho xem trước những gì sẽ ghi, hỏi xác nhận rồi mới ghi:

| Tạo ra | Để làm gì |
|---|---|
| `.github/scrum.yml` | Cấu hình |
| Label status, points, `type: feature`, `type: epic`, `scrum: meta`, `no-task` | Label cũ không bao giờ bị xoá |
| `.github/ISSUE_TEMPLATE/task.yml` | Form tạo task trên GitHub, có ô Points |
| `.github/pull_request_template.md` | Có sẵn dòng `Closes #` |
| Workflow `scrum-status-sync`, `scrum-pr-link-check`, `scrum-daily-digest` | Tự đổi trạng thái, kiểm tra PR có gắn task, gửi digest |
| `.github/scrum/` | Bản runtime mà workflow gọi tới. Không sửa tay |

Sau đó **commit và push `.github/` lên nhánh mặc định**. Chưa push thì workflow chưa chạy.

Chạy lại lệnh này lúc nào cũng an toàn: file không đổi sẽ báo `unchanged`. File template bạn đã sửa
sẽ báo `conflict` và được giữ nguyên. Muốn lấy bản mới thì dùng `--force-file <path>`.

### 3.2 Cấu hình

Sửa `.github/scrum.yml`. Khoá nào không ghi thì dùng giá trị mặc định. Cấu hình gợi ý cho team ở Việt Nam:

```yaml
version: 1
timezone: Asia/Ho_Chi_Minh        # "hôm nay", burndown và digest tính theo giờ Việt Nam
sprint:
  length_days: 12                 # ngày lịch, tính cả ngày đầu: thứ 2 tuần 1 tới thứ 6 tuần 2
  name_pattern: "Sprint {n}"
points:
  scale: [1, 2, 3, 5, 8]          # Fibonacci; task lớn hơn 8 thì nên chia nhỏ
branch:
  pattern: "feat/{number}-{slug}"
digest:
  enabled: true
  cron: "0 1 * * 1-5"             # giờ UTC: 8 giờ sáng giờ Việt Nam, thứ 2 tới thứ 6
planning:
  dir: docs/plans                 # nơi lưu brief và plan
  hours_per_point: 4              # tuỳ chọn: plan.md hiện thêm số giờ (1 điểm = 4 giờ)
```

`hours_per_point` mặc định không đặt, nên plan chỉ hiện điểm. Số 4 ở trên chỉ là điểm xuất phát; sau
vài sprint, hãy chỉnh theo thực tế của team.

Đổi cấu hình xong thì chạy lại `/scrum-github:scrum-init` để đồng bộ label. Hai khoá cần thêm một bước:

| Đổi khoá | Chạy thêm |
|---|---|
| `points.scale` | `scrum init --force-file .github/ISSUE_TEMPLATE/task.yml` |
| `digest.cron` | `scrum init --force-file .github/workflows/scrum-daily-digest.yml` |

Kiểm tra cấu hình mà không gọi mạng: `scrum config`. Lệnh in cấu hình đã gộp với mặc định, hoặc báo lỗi.

### 3.3 Cài đặt GitHub nên bật

- **Branch protection** cho nhánh chính, bắt buộc check `scrum-pr-link-check` phải pass. Như vậy
  không ai merge được PR không gắn task.
- *Settings → Actions → Workflow permissions*: để mặc định. Mỗi workflow tự khai báo quyền nó cần.

---

## 4. Một sprint từ đầu tới cuối

| Thời điểm | Ai | Việc | Mục |
|---|---|---|---|
| Đầu sprint | PO, Scrum Master | Tạo sprint, biến yêu cầu thành task | 4.1, 4.2 |
| Hằng ngày | Dev | Nhận task, mở PR, merge | 4.3 |
| Hằng ngày | Cả team | Xem tiến độ, đọc digest | 4.4 |
| Cuối sprint | Scrum Master | Báo cáo, đóng sprint | 4.5 |

### 4.1 Tạo sprint

```
/scrum-github:sprint-new
```

Hoặc dùng CLI: `scrum sprint new --start 2026-11-23 --goal "Đăng ký, đăng nhập"`. Tên tự tăng theo
mẫu `Sprint {n}`.

### 4.2 Từ yêu cầu tới task

Có ba lệnh, dùng theo thứ tự khi cần. Thường bạn chỉ cần nhớ `/scrum-github:plan`: khi yêu cầu còn
mơ hồ, nó đề nghị chạy `discover`; khi dự án có mã mà chưa có tài liệu bối cảnh, nó đề nghị
`project-scan`.

```
project-scan ──► docs/project-context.md       dự án hiện có những gì (một lần, làm mới khi mã đổi nhiều)
discover     ──► docs/plans/<slug>/brief.md    cần làm gì, phạm vi đã chốt
plan         ──► docs/plans/<slug>/plan.json   epic → feature → task, điểm, phụ thuộc
                 docs/plans/<slug>/plan.md     bản xem, có ước lượng
             ──► issue trên GitHub             chỉ sau khi bạn duyệt
```

**Không lệnh nào ghi lên GitHub trước khi bạn duyệt plan.** Các file trong `docs/` thì bạn tự commit.

**`/scrum-github:project-scan`** (dùng `--full` để quét lại toàn bộ). Lệnh đọc mã rồi viết
`docs/project-context.md`: công nghệ, cấu trúc, luồng chính, mô hình dữ liệu, quy ước, cách chạy và
test, bảng thuật ngữ. Mỗi nhận định ghi rõ file làm căn cứ; điều mã không nói thì ghi "chưa rõ".
Lần quét sau chỉ đọc lại các thư mục đã đổi. Mục "Team notes" do team viết và không bao giờ bị ghi đè.

**`/scrum-github:discover <ý tưởng>`.** Dùng khi ý tưởng còn mơ hồ, ví dụ "cho người dùng bình luận"
hay "làm app nhanh hơn".
- Claude tự tìm sự thật (đọc mã, tìm trên web) và chỉ hỏi bạn các **quyết định**.
- Câu hỏi đi theo từng vòng, có đánh số, câu nào cũng kèm câu trả lời đề xuất. Trả lời "yes" là đồng ý đề xuất.
- Lệnh hỏi tới khi đủ tám nhóm: người dùng và vai trò, luồng chính, dữ liệu, trường hợp biên, yêu
  cầu phi chức năng, tích hợp, ràng buộc, phần ngoài phạm vi.
- Với dự án có mã, lệnh kết luận yêu cầu *phù hợp*, *phù hợp nếu có thay đổi*, hay *xung đột*. Khi
  xung đột, bạn chọn phương án trước khi đi tiếp.
- Lệnh ước lượng cỡ yêu cầu: một task, một feature, hay một epic.
- Ba mức: `--quick` (tối đa một vòng hỏi, không dùng agent), mặc định, và `--deep` (thêm nghiên cứu
  web và một lượt soát brief độc lập).

**`/scrum-github:plan <brief hoặc mô tả>`.**
- Chia yêu cầu thành task theo **lát cắt dọc**: mỗi task tự cho ra một hành vi kiểm tra được, không
  phải một tầng kỹ thuật đứng riêng.
- Mỗi task có tiêu chí nghiệm thu, điểm trong thang, subtask (thành checklist trong issue) và phụ thuộc.
- Trước khi đưa bạn xem, một agent soát bản nháp: thiếu việc, ngoài phạm vi, task quá lớn, phụ thuộc
  sai, tiêu chí không kiểm tra được. `--quick` bỏ bước này.
- Bạn xem bảng task, các phát hiện, phần ước lượng và danh sách việc sẽ làm trên GitHub, rồi sửa tới khi duyệt.
- Chạy lại `plan` cho cùng thư mục là sửa tiếp plan cũ; số issue đã tạo được giữ nguyên.

**Vào sprint hay vào backlog.** Plan không ghi `sprint` thì task vào **backlog** (không milestone,
không vào báo cáo sprint). Ghi `"sprint": "current"` để vào sprint đang mở, hoặc ghi tên sprint cụ
thể; từng task có thể ghi riêng. Muốn đưa task từ backlog vào sprint: gán milestone trên GitHub, hoặc
sửa `sprint` trong plan rồi chạy `scrum plan apply <file> --update`.

**Ước lượng.** `plan.md` hiện tổng điểm từng feature và cả plan, số task chưa có điểm, số giờ (nếu
có `hours_per_point`), và số sprint ước tính theo velocity trung bình của tối đa ba sprint đã đóng gần nhất.

**Tạo lại an toàn.** `scrum plan apply` ghi số issue vào `plan.json` ngay sau mỗi issue được tạo.
Vì vậy chạy lại chỉ tạo phần còn thiếu, dù trước đó bị lỗi giữa chừng hay vừa thêm task.
- `--dry-run`: xem trước, không ghi gì.
- `--update`: sửa tiêu đề, nội dung, điểm và sprint của các issue còn mở. Không đụng label trạng
  thái, người được giao, hay issue đã đóng.
- **Đừng xoá số `issue` hay đổi `id` trong plan**: lần tạo sau sẽ sinh issue trùng.

**Thêm task lẻ.** `/scrum-github:task-new`, hoặc `scrum task new --title "Login" --points 3 --assignee <login>`.
Thêm `--bug` để gắn label bug. Task cũng tạo được trên giao diện GitHub (New issue → mẫu Task): ô
Points tự thành label `points: N`, nhưng bạn **phải tự gán milestone**.

### 4.3 Dev: hằng ngày

1. **Nhận task:** `/scrum-github:task-start` (hoặc `scrum task start 12`). Lệnh gán task cho bạn,
   đổi sang In progress và tạo branch `feat/12-<slug>` từ nhánh mặc định.
2. **Code, commit, push.**
3. **Mở PR** với mô tả có **`Closes #12`** (PR template đã có sẵn dòng này).
   - Mở PR: task chuyển sang In progress, nếu đang là New.
   - Merge PR: task chuyển sang Done và issue tự đóng. Merge vào nhánh nào cũng vậy, không chỉ nhánh mặc định.
   - Đóng PR mà không merge: trạng thái task giữ nguyên.
   - Một PR đóng được nhiều task: `Closes #12, closes #13`.
4. **PR không gắn task** (sửa CI, nâng phiên bản thư viện): gắn label `no-task`.

### 4.4 Cả team: theo dõi

| Việc | Lệnh |
|---|---|
| Bảng tiến độ theo người và trạng thái | `/scrum-github:sprint-status` hoặc `scrum status` |
| Digest hằng ngày | Tự động: workflow comment vào issue `Sprint N digest` theo lịch |
| Báo cáo HTML có burndown và velocity | `/scrum-github:sprint-report` hoặc `scrum report --out sprint-3.html`. File mở được khi không có mạng, gửi thẳng cho stakeholder được |

### 4.5 Scrum Master: cuối sprint

```
/scrum-github:sprint-close
```

Mặc định lệnh **chỉ hiện kế hoạch**: velocity, các task Done, các task sẽ chuyển sang sprint sau.
Khi bạn xác nhận (`--yes --create-next`), plugin:
- ghi velocity vào milestone,
- tạo sprint kế tiếp nếu chưa có,
- chuyển các task còn mở sang sprint mới, kèm comment trên từng task,
- đóng milestone.

Velocity của các sprint trước giúp quyết định nhận bao nhiêu điểm cho sprint sau.

---

## 5. Quy ước team

Nên thống nhất ở buổi kick-off.

1. **Mỗi PR đóng ít nhất một task**, hoặc có label `no-task`.
2. **Viết `Closes #n`, không viết `Solve #n`.** GitHub chỉ hiểu `close/closes/closed`,
   `fix/fixes/fixed`, `resolve/resolves/resolved`. Check của PR sẽ báo lỗi nếu thấy `Solve`.
3. **Không sửa label `status:` bằng tay.** Trạng thái đi theo PR. Nếu thật sự cần, hãy đóng hoặc
   mở lại issue; workflow sẽ chuẩn hoá label.
4. **Task không làm nữa thì đóng với lý do "Close as not planned"**, để không bị tính vào velocity.
5. **Mọi task trong sprint đều có điểm**, kể cả bug. Task không có điểm vẫn hiện trong báo cáo nhưng không vào burndown.
6. **Task cần nhiều hơn mức điểm lớn nhất thì chia nhỏ.**
7. **Không đổi điểm giữa sprint**, vì burndown dùng điểm hiện tại cho cả sprint (xem mục 8).

---

## 6. Board kanban (tuỳ chọn)

Dùng một board GitHub Projects để xem task thành thẻ và kéo thả. Label `status: …` vẫn là nguồn sự
thật; board chỉ là bản sao được phép kéo thả. Nhờ vậy báo cáo, velocity và tự động hoá theo PR vẫn
chạy như cũ. (Board có dữ liệu riêng rồi đồng bộ hai chiều đã bị loại, vì hai nguồn dữ liệu sẽ lệch
nhau và làm sai burndown.)

### 6.1 Board hoạt động thế nào

| Bạn làm | Kết quả |
|---|---|
| Mở hoặc merge PR, `task-start`, đóng hoặc mở lại issue | Thẻ chuyển cột ngay trong lần chạy workflow (khi đã có secret) |
| Kéo thẻ trên board | Label đổi ở lần đồng bộ định kỳ kế tiếp (mặc định 15 phút). Muốn ngay: *Actions → `scrum-project-sync` → Run workflow* |
| Kéo thẻ sang Done | Label Done, issue **đóng với lý do completed**, được tính vào velocity |
| Kéo thẻ ra khỏi Done | Issue mở lại, label theo cột mới |
| Kéo thẻ, và PR cũng đổi trạng thái trước lần đồng bộ | Label thắng: thẻ quay về, issue có comment giải thích. Riêng cột Done thì board thắng khi *Auto-close issue* đang bật |
| Kéo vào cột không có trong cấu hình (ví dụ "Review") | Không đổi gì, lần đồng bộ in cảnh báo |
| Gắn label `points: N` | Field Points trên board tự cập nhật. Sửa Points trên board sẽ bị ghi đè |

Cột mặc định `Todo` / `In Progress` / `Done` ứng với `New` / `In progress` / `Done`. Muốn đặt tên
cột khác thì sửa `project.status_options`.

### 6.2 Bật board (Scrum Master làm một lần)

1. Tạo Project từ template **Board** và liên kết với repo.
2. Trong Project → **Workflows**, **tắt**: *Item added to project*, *Item closed*, *Item reopened*,
   *Pull request linked to issue*, *Pull request merged*. Các automation này tự đổi cột mà plugin
   không biết, làm label bị đổi sai. *Auto-add to project* và *Auto-close issue* thì để bật được.
3. Tạo token và lưu vào secret `SCRUM_PROJECT_TOKEN` (*Settings → Secrets and variables → Actions*).
   - Đã chạy thử thành công với **classic token** có scope `repo` và `project`.
   - Fine-grained token (chỉ cấp cho repo này, quyền **Issues** và **Projects** read/write, có hạn
     dùng) về lý thuyết cũng được nhưng chưa thử.
   - Lưu secret qua trang Settings, hoặc `gh secret set` trong một terminal riêng. **Đừng** chạy qua
     `!` của Claude Code: cách đó lưu secret rỗng.
   - Token mặc định của Actions không truy cập được Projects, nên phải có secret này.
4. Thêm vào `.github/scrum.yml`:
   ```yaml
   project:
     enabled: true
     owner: <org-hoặc-user>
     number: <số trong URL .../projects/N>
     poll_cron: "*/15 1-11 * * 1-5"   # khoảng 8h–19h giờ Việt Nam, thứ 2–6, tiết kiệm phút Actions
   ```
5. Chạy `scrum init --force-file .github/workflows/scrum-status-sync.yml`. Lệnh cài workflow
   `scrum-project-sync` và thêm token vào workflow trạng thái.
6. Trên máy mình: `gh auth refresh -s project`, rồi `scrum project init --dry-run`, rồi
   `scrum project init`. Lệnh tạo field *Synced status* và *Points*, và thêm các task của sprint đang mở.
7. **Ẩn field *Synced status*** trong mọi view. Field này để công cụ biết bên nào vừa đổi; sửa tay sẽ làm đồng bộ sai.
8. Commit và push `.github/`.

**Tắt board:** đặt `project.enabled: false` và xoá `.github/workflows/scrum-project-sync.yml`. Label không bị ảnh hưởng.

### 6.3 Lưu ý

- Từ board về label **không tức thời**, vì GitHub Actions không nhận được sự kiện kéo thẻ. Muốn tức
  thời thì cần GitHub App và server riêng, ngoài phạm vi hiện tại.
- Token hết hạn thì workflow `scrum-project-sync` báo đỏ và GitHub gửi email. Thay secret là chạy lại
  được. Các workflow chính (PR → label) vẫn chạy bình thường.
- Issue được mở lại khi đang có label `status: New` thì giữ New. Nhờ vậy kéo thẻ từ Done về Todo cho kết quả đúng.

---

## 7. Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| Merge PR mà task không đóng | PR viết `Solve #n` thay vì `Closes #n` | Sửa mô tả PR thành `Closes #n` |
| Merge PR vào một nhánh khác mà task không đóng | Nhánh đích chưa có `.github/` (workflow chạy theo file trên nhánh đích của PR) | Đưa `.github/` vào nhánh đó, hoặc đóng task tay với lý do completed |
| Workflow không chạy | Chưa push `.github/` lên nhánh mặc định | Push rồi thử lại |
| `scrum: yq ... is not mikefarah/yq` | Cài nhầm bản yq của Python | `pip uninstall yq && brew install yq` |
| `gh` báo token invalid trong Claude Code dù đã login | Sandbox của Claude Code chặn đọc keychain macOS | Chạy lệnh ngoài sandbox (Claude Code sẽ hỏi), hoặc chỉnh bằng `/sandbox` |
| `points 5 not in the scale` | Giá trị không có trong `points.scale` | Dùng giá trị trong thang, hoặc sửa cấu hình |
| Đổi giờ digest mà không có tác dụng | Giờ chạy được ghi cứng vào file workflow | `scrum init --force-file .github/workflows/scrum-daily-digest.yml`, rồi commit |
| Task có hai label status | Ai đó sửa label bằng tay | Lần đổi trạng thái kế tiếp tự chuẩn hoá. Muốn sửa ngay thì gỡ label thừa |
| `init` báo `conflict` | Bạn đã sửa một file template | Giữ bản của bạn, hoặc `--force-file <path>` để lấy bản mới |
| `plan apply` báo `no sprint named "…"` hoặc `… is closed` | Plan hoặc một task ghi tên sprint không tồn tại hoặc đã đóng | Sửa `sprint` trong plan. Chưa có gì được tạo |
| `plan apply` dừng giữa chừng | Lỗi mạng hoặc GitHub | Chạy lại đúng lệnh đó: chỉ phần chưa có số issue được tạo |
| Issue có checklist hoặc mục "Blocked by" trong nội dung | Repo không cho dùng sub-issue hoặc quan hệ phụ thuộc | Không cần làm gì; quan hệ được ghi ngay trong nội dung issue |
| `plan`/`discover` báo tài liệu bối cảnh đã cũ | Có nhiều commit sau lần quét trước | Chạy `/scrum-github:project-scan` (chỉ đọc lại thư mục đã đổi) |

---

## 8. Giới hạn hiện tại

- Burndown dùng **điểm hiện tại** và coi mọi task có mặt từ ngày đầu sprint. Thêm task hoặc đổi
  điểm giữa sprint sẽ làm đường burndown lệch.
- Không hỗ trợ GitHub Enterprise Server. Trên Windows chỉ chạy qua WSL.
- Kéo thẻ trên board chỉ đến label ở lần đồng bộ định kỳ kế tiếp.
- Chưa có lệnh gỡ cài đặt. Muốn gỡ thì xoá `.github/scrum*` và các workflow `scrum-*`; label và milestone vẫn giữ.

---

## 9. Checklist áp dụng

**Chuẩn bị**
- [ ] Mọi thành viên đã cài `gh` (đã login), `jq`, `yq` bản mikefarah
- [ ] Người dùng Claude Code đã cài plugin

**Thiết lập repo**
- [ ] Chạy `scrum-init`, xem kỹ phần xem trước
- [ ] Sửa `.github/scrum.yml`: timezone, `length_days`, thang điểm, giờ digest
- [ ] Commit và push `.github/` lên nhánh mặc định
- [ ] Bật branch protection, bắt buộc check `scrum-pr-link-check`

**Thống nhất với team**
- [ ] Đọc mục 5 cùng team, chốt thang điểm và độ dài sprint
- [ ] Ai tạo sprint, ai đóng sprint
- [ ] Ai duyệt plan do AI đề xuất
- [ ] Dùng `planning.hours_per_point` hay chỉ dùng điểm

**Sprint đầu tiên**
- [ ] Dự án có mã sẵn: chạy `project-scan`, commit `docs/project-context.md`
- [ ] `sprint-new`, rồi `plan` (chạy `discover` trước nếu yêu cầu còn mơ hồ) hoặc `task-new`
- [ ] Mỗi dev thử `task-start` và một PR `Closes #n`
- [ ] Sáng hôm sau kiểm tra issue digest
- [ ] Cuối sprint chạy `sprint-report` và `sprint-close`, lấy velocity làm mốc cho sprint sau
