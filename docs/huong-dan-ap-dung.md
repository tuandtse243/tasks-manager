# Hướng dẫn áp dụng scrum-github vào dự án thực tế

Tài liệu này dành cho cả team (PO, Scrum Master, Dev). Phần kỹ thuật của plugin (cấu trúc mã,
test, chạy end-to-end) nằm trong [`plugins/scrum-github/README.md`](../plugins/scrum-github/README.md).

---

## 1. Tổng quan

Plugin cho phép chạy Scrum ngay trên GitHub, không cần Jira hay Trello. Không có cơ sở dữ liệu
riêng: **mọi thứ là issue, label và milestone của GitHub**.

| Khái niệm Scrum | Trên GitHub | Ghi chú |
|---|---|---|
| Sprint | Milestone `Sprint {n}` | Ngày bắt đầu, kết thúc, velocity lưu trong marker ẩn ở mô tả milestone |
| Task | Issue | Có đúng một label `status: …` và tối đa một label `points: N` |
| Trạng thái | Label `status: New` / `status: In progress` / `status: Done` | Tự đổi theo PR, không sửa tay |
| Hoàn thành | Issue **đóng với lý do "completed"** | Đóng với lý do "not planned" thì không tính điểm |
| Feature / user story | Issue có label `type: feature`, các task là sub-issue | Không tính điểm |
| Epic (yêu cầu lớn) | Issue có label `type: epic`, các feature là sub-issue | Không tính điểm |
| Backlog | Issue **không có milestone** | Không hiện trong báo cáo sprint cho tới khi được đưa vào sprint |
| Plan của một yêu cầu | File `docs/plans/<slug>/plan.json` trong repo, kèm bản xem `plan.md` | Ảnh chụp lúc lập plan; sau khi áp, GitHub là nguồn sự thật |
| Velocity | Tổng điểm task Done trong sprint | Ghi lại khi đóng sprint |

Vòng đời của một task:

```
task-new / plan ──► New ──(mở PR "Closes #n" hoặc task-start)──► In progress ──(merge PR)──► Done + đóng issue
```

---

## 2. Chuẩn bị (mỗi người trong team làm một lần)

| Công cụ | Cài đặt | Kiểm tra |
|---|---|---|
| GitHub CLI | `brew install gh` rồi `gh auth login -h github.com -s repo,workflow` | `gh auth status` |
| jq 1.6+ | `brew install jq` | `jq --version` |
| yq v4 (bản của **mikefarah**) | `brew install yq` | `yq --version` phải có chữ `mikefarah` |
| Claude Code | (không bắt buộc nếu chỉ dùng CLI) | |

> `pip install yq` cài một công cụ **khác** cùng tên. Plugin sẽ từ chối bản này.

Cài plugin trong Claude Code, chạy từ thư mục gốc của repo này:

```
/plugin marketplace add ./
/plugin install scrum-github@task-manageer
```

Không dùng Claude Code thì gọi thẳng script: `bash <đường-dẫn>/plugins/scrum-github/runtime/bin/scrum <lệnh>`.
Sau khi chạy `scrum-init`, repo dự án cũng có bản sao tại `.github/scrum/bin/scrum`.

---

## 3. Đưa vào repo dự án

Chỉ một người (thường là Scrum Master hoặc tech lead) làm bước này, trong một bản clone của repo dự án.

### 3.1 Khởi tạo

```
/scrum-github:scrum-init
```

Lệnh này chạy `scrum init --dry-run` để xem trước, hỏi xác nhận rồi mới ghi:

- `.github/scrum.yml`: cấu hình.
- Label: status, points, `type: feature`, `type: epic`, `scrum: meta`, `no-task`. Label cũ không bao giờ bị xoá.
- `.github/ISSUE_TEMPLATE/task.yml`: form tạo task có ô Points.
- `.github/pull_request_template.md`: có sẵn dòng `Closes #`.
- 3 workflow: `scrum-status-sync`, `scrum-pr-link-check`, `scrum-daily-digest`.
- `.github/scrum/`: bản runtime mà workflow gọi tới. Không sửa thư mục này bằng tay.

Sau đó **commit và push `.github/` lên nhánh mặc định**. Nếu chưa push, workflow sẽ không chạy.

Lệnh này idempotent: chạy lại khi không đổi gì thì sẽ báo `unchanged`. Nếu bạn đã sửa một file
template, lệnh báo `conflict` và giữ nguyên bản của bạn. Muốn ghi đè thì dùng `--force-file <path>`.

### 3.2 Cấu hình gợi ý cho team Việt Nam

Sửa `.github/scrum.yml`. Mọi khoá đều tuỳ chọn, khoá nào thiếu thì dùng giá trị mặc định.

```yaml
version: 1
timezone: Asia/Ho_Chi_Minh        # "hôm nay", burndown và digest tính theo giờ VN
sprint:
  length_days: 12                 # số ngày lịch, tính cả ngày đầu: thứ 2 tuần 1 → thứ 6 tuần 2
  name_pattern: "Sprint {n}"
points:
  scale: [1, 2, 3, 5, 8]          # Fibonacci; task lớn hơn 8 thì nên chia nhỏ
branch:
  pattern: "feat/{number}-{slug}"
digest:
  enabled: true
  cron: "0 1 * * 1-5"             # giờ UTC = 8:00 sáng giờ VN, từ thứ 2 đến thứ 6
planning:
  dir: docs/plans                 # nơi lưu plan và brief
  hours_per_point: 4              # tuỳ chọn: plan.md hiện thêm số giờ (ở đây 1 điểm = 4 giờ)
```

`hours_per_point` mặc định không đặt (chỉ hiện điểm). Con số 4 ở trên chỉ là gợi ý ban đầu; sau
vài sprint, hãy chỉnh theo thực tế của team.

Sau khi đổi cấu hình, chạy lại `/scrum-github:scrum-init` để đồng bộ label. Có hai trường hợp đặc biệt:

| Đổi khoá | Phải chạy thêm |
|---|---|
| `points.scale` | `scrum init --force-file .github/ISSUE_TEMPLATE/task.yml` |
| `digest.cron` | `scrum init --force-file .github/workflows/scrum-daily-digest.yml` |

Kiểm tra cấu hình mà không gọi mạng: `scrum config` in ra cấu hình đã gộp với mặc định, hoặc báo lỗi nếu sai.

### 3.3 Cài đặt GitHub nên bật

- **Branch protection** cho nhánh chính: bắt buộc check `scrum-pr-link-check` phải pass. Nhờ vậy
  không ai merge được PR không gắn task.
- Settings → Actions → Workflow permissions: để mặc định là được. Các workflow tự khai báo quyền
  `issues: write` mà chúng cần.

---

## 4. Một sprint theo vai trò

### PO / Scrum Master: đầu sprint (Sprint Planning)

| Việc | Lệnh | Ghi chú |
|---|---|---|
| Tạo sprint | `/scrum-github:sprint-new` hoặc `scrum sprint new --start 2026-11-23 --goal "Đăng ký, đăng nhập"` | Tên tự tăng `Sprint {n}` |
| Hiểu dự án có sẵn (một lần, làm mới khi mã đổi nhiều) | `/scrum-github:project-scan` | Ghi `docs/project-context.md`. Xem mục 4.1 |
| Làm rõ một ý tưởng còn mơ hồ | `/scrum-github:discover <ý tưởng>` | Phỏng vấn theo vòng, ghi `brief.md`. Xem mục 4.1 |
| Chia yêu cầu thành task | `/scrum-github:plan <brief hoặc mô tả>` | Claude lập plan (epic, feature, task, điểm, phụ thuộc) trong `docs/plans/<slug>/`. Bạn sửa đến khi duyệt, **chưa duyệt thì chưa tạo gì trên GitHub** |
| Thêm task lẻ | `/scrum-github:task-new` hoặc `scrum task new --title "Login" --points 3 --assignee <login>` | Thêm `--bug` để gắn label bug |

Task cũng tạo được từ giao diện GitHub (New issue → mẫu Task). Ô Points sẽ được workflow chuyển
thành label `points: N`, nhưng **phải tự gán milestone** cho task đó.

### 4.1 Từ yêu cầu tới task: `project-scan` → `discover` → `plan`

> **Đổi tên từ 0.3.0:** `/scrum-github:sprint-plan` nay là `/scrum-github:plan`. File plan JSON cũ vẫn áp được.

Ba lệnh nối thành một đường ống. Thường chỉ cần nhớ `/scrum-github:plan`: khi đầu vào chưa rõ,
nó đề nghị chạy `discover`; khi dự án có mã mà chưa có tài liệu ngữ cảnh, nó đề nghị `project-scan`.
Không lệnh nào ghi lên GitHub trước khi bạn duyệt plan. Các file dưới `docs/` bạn tự commit.

| Khi nào | Lệnh | Kết quả |
|---|---|---|
| Dự án đã có mã, chưa có (hoặc đã cũ) tài liệu mô tả | `/scrum-github:project-scan` (`--full` để quét lại toàn bộ) | `docs/project-context.md`: công nghệ, cấu trúc, luồng chính, mô hình dữ liệu, quy ước, bảng thuật ngữ. Mỗi nhận định có file làm căn cứ, điều không rõ ghi "chưa rõ". Mục "Team notes" do team viết và không bao giờ bị ghi đè |
| Ý tưởng còn mơ hồ ("cho người dùng bình luận", "làm app nhanh hơn") | `/scrum-github:discover <ý tưởng>` | `docs/plans/<slug>/brief.md`: vấn đề, giải pháp, user story, trong/ngoài scope, quyết định, giả định, rủi ro, cỡ yêu cầu, độ phù hợp với dự án |
| Đã rõ cần làm gì | `/scrum-github:plan <brief hoặc mô tả>` | `docs/plans/<slug>/plan.json` và bản xem `plan.md`; sau khi duyệt thì tạo issue |

**`discover`** tự tìm sự thật (đọc mã qua agent `codebase-scout`, tìm web qua agent `researcher`)
và chỉ hỏi bạn các quyết định. Mỗi vòng hỏi được đánh số, câu nào cũng có câu trả lời đề xuất;
trả lời "yes" là đồng ý với đề xuất. Lệnh hỏi tới khi đủ tám nhóm: người dùng và vai trò, luồng
chính, dữ liệu, trường hợp biên, yêu cầu phi chức năng, tích hợp, ràng buộc, phần ngoài scope.
Trên dự án có mã, lệnh kết luận feature *phù hợp*, *phù hợp nếu có thay đổi*, hay *xung đột*
(xung đột thì bạn chọn phương án trước khi đi tiếp), và ước lượng cỡ: một task, một feature, hay
một epic. Ba mức: `--quick` (không dùng agent, tối đa một vòng hỏi), mặc định, `--deep` (thêm
nghiên cứu web và soát brief độc lập).

**`plan`** chia task theo lát cắt dọc: mỗi task tự cho ra một hành vi kiểm tra được, có tiêu chí
nghiệm thu, điểm trong thang, subtask (thành checklist trong issue) và phụ thuộc. Trước khi trình
bày, agent `plan-critic` soát bản nháp (thiếu, ngoài scope, quá lớn, phụ thuộc, tiêu chí không
kiểm tra được); `--quick` bỏ bước này. Bạn xem bảng task, phát hiện của critic, phần ước lượng và
danh sách thao tác sẽ làm trên GitHub, rồi sửa tới khi duyệt.

**Sprint hay backlog.** Plan không ghi `sprint` thì task được tạo vào **backlog** (không có
milestone, không vào báo cáo sprint). Ghi `"sprint": "current"` để vào sprint đang mở, hoặc tên
sprint cụ thể; từng task có thể ghi đè. Muốn đưa task backlog vào sprint: đặt milestone trên
GitHub, hoặc sửa `sprint` trong plan rồi chạy `scrum plan apply <file> --update`.

**Epic.** Yêu cầu có nhiều luồng độc lập thành một epic (label `type: epic`) chứa nhiều feature.
Epic và feature không tính điểm.

**Ước lượng.** `plan.md` hiện tổng điểm từng feature và cả plan, số task chưa có điểm, số giờ nếu
có `planning.hours_per_point`, và số sprint ước tính theo velocity trung bình của tối đa ba sprint
đã đóng gần nhất.

**Áp lại an toàn.** `scrum plan apply` ghi số issue vào `plan.json` ngay sau mỗi lần tạo, nên chạy
lại chỉ tạo phần còn thiếu (sau lỗi giữa chừng, hoặc khi thêm task). `--dry-run` xem trước mà không
ghi gì. `--update` sửa tiêu đề, nội dung, điểm và sprint của issue đang mở; không đụng label trạng
thái, người được giao, và issue đã đóng. **Đừng xoá số `issue` hay đổi `id` trong plan**: áp lại
sẽ tạo issue trùng.

### Dev: hằng ngày

1. Nhận task: `/scrum-github:task-start` hoặc `scrum task start 12`. Lệnh này tự gán bạn vào task,
   đổi status sang In progress và tạo branch `feat/12-<slug>` từ nhánh mặc định.
2. Code, commit, push.
3. Mở PR với mô tả có **`Closes #12`** (PR template đã có sẵn dòng này).
   - Khi mở PR, task chuyển sang In progress (nếu đang là New).
   - Khi merge PR, task chuyển sang Done và issue tự đóng.
   - Một PR có thể đóng nhiều task: `Closes #12, closes #13`.
4. PR không có task (sửa CI, bump dependency) thì gắn label `no-task`.

### Cả team: theo dõi

| Việc | Lệnh |
|---|---|
| Bảng tiến độ theo người và trạng thái | `/scrum-github:sprint-status` hoặc `scrum status` |
| Digest hằng ngày | Tự động: workflow comment vào issue `Sprint N digest` theo lịch cron |
| Báo cáo HTML (burndown, velocity) | `/scrum-github:sprint-report` hoặc `scrum report --out sprint-3.html`. File mở được khi không có mạng, gửi thẳng cho stakeholder |

### Scrum Master: cuối sprint (Review / Retro)

```
/scrum-github:sprint-close
```

Lệnh này **mặc định chỉ hiện kế hoạch**: velocity, task Done, task sẽ chuyển sang sprint sau.
Khi xác nhận (`--yes --create-next`), plugin sẽ:

- Ghi velocity vào milestone.
- Tạo sprint kế tiếp nếu chưa có.
- Chuyển task còn mở sang sprint mới, kèm comment trên từng task.
- Đóng milestone.

Velocity của các sprint trước giúp ước lượng số điểm nhận ở sprint sau.

---

## 5. Quy ước team (nên thống nhất ở buổi kick-off)

1. **Mỗi PR đóng ít nhất một task**, hoặc có label `no-task`.
2. **Dùng `Closes #n`**, không dùng `Solve #n`. GitHub chỉ hiểu `close/closes/closed`, `fix/fixes/fixed`,
   `resolve/resolves/resolved`. PR check sẽ báo lỗi nếu thấy `Solve`.
3. **Không sửa label `status:` bằng tay.** Trạng thái đi theo PR. Nếu thật sự cần đổi, hãy
   đóng hoặc mở lại issue; workflow sẽ chuẩn hoá label.
4. **Task không làm nữa thì đóng với lý do "Close as not planned"**, để không bị tính vào velocity.
5. **Mọi task trong sprint đều có điểm**, kể cả bug. Task không có điểm sẽ hiện trong báo cáo nhưng không vào burndown.
6. **Task cần hơn giá trị điểm lớn nhất thì chia nhỏ.**
7. **Không đổi điểm giữa sprint.** Burndown dùng điểm hiện tại cho cả sprint (xem mục 7).

---

## 6. Xử lý sự cố

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| Merge PR mà task không đóng | PR viết `Solve #n`, hoặc PR không merge vào nhánh mặc định | Dùng `Closes #n`. GitHub chỉ tự đóng issue khi PR merge vào nhánh mặc định; nhánh khác thì đóng tay với lý do completed |
| Workflow không chạy | Chưa push `.github/` lên nhánh mặc định | Push rồi thử lại |
| `scrum: yq ... is not mikefarah/yq` | Cài nhầm bản yq của Python | `pip uninstall yq && brew install yq` |
| `gh` báo token invalid trong Claude Code, dù đã login | Sandbox chặn đọc keychain macOS | Chạy lệnh ngoài sandbox (Claude Code sẽ hỏi), hoặc chỉnh bằng `/sandbox` |
| `points 5 not in the scale` | Giá trị không có trong `points.scale` | Dùng giá trị trong thang, hoặc sửa cấu hình |
| Đổi giờ digest mà không có tác dụng | Cron được ghi cứng vào file workflow | `scrum init --force-file .github/workflows/scrum-daily-digest.yml`, rồi commit |
| Task có hai label status | Ai đó sửa label bằng tay | Lần đổi trạng thái kế tiếp sẽ tự chuẩn hoá. Muốn sửa ngay thì gỡ label thừa |
| `init` báo `conflict` | Bạn đã sửa template | Giữ bản của bạn, hoặc `--force-file <path>` để lấy bản mới |
| `plan apply` báo `no sprint named "…"` hoặc `… is closed` | Plan (hoặc một task) ghi tên sprint không có hoặc đã đóng | Sửa `sprint` trong plan; chưa có gì được tạo |
| `plan apply` dừng giữa chừng | Lỗi mạng hoặc GitHub | Chạy lại đúng lệnh đó: chỉ phần chưa có số issue được tạo |
| Issue báo "fallback": checklist hoặc mục "Blocked by" trong nội dung | Repo không cho dùng sub-issue hoặc phụ thuộc | Không cần làm gì; quan hệ được ghi trong nội dung issue |
| `plan`/`discover` báo tài liệu ngữ cảnh đã cũ | Nhiều commit sau lần quét trước | Chạy `/scrum-github:project-scan` (chỉ đọc lại thư mục đã đổi) |

---

## 7. Giới hạn hiện tại

- Burndown dùng **điểm hiện tại** và coi mọi task có mặt từ ngày đầu sprint. Thêm task hoặc đổi điểm giữa sprint sẽ làm đường burndown không chính xác.
- Không hỗ trợ GitHub Enterprise Server. Trên Windows chỉ chạy qua WSL.
- Board kanban dùng GitHub Projects (tuỳ chọn, xem mục 8). Kéo thẻ trên board trễ tới lần sync định kỳ.
- Không có lệnh gỡ cài đặt tự động. Muốn gỡ thì xoá `.github/scrum*` và các workflow `scrum-*`; label và milestone được giữ nguyên.

---

## 8. Mở rộng sang board kanban

GitHub đã là nơi lưu dữ liệu, nên board **không được có dữ liệu riêng** rồi sync ngược về. Các cách đã cân nhắc:

| Cách | Đánh giá |
|---|---|
| **A. GitHub Projects v2 + sync label ↔ field Status** | **Chọn.** Kéo thả miễn phí, không có nguồn dữ liệu thứ hai, giữ nguyên tự động hoá PR |
| B. Board tự làm, đọc/ghi thẳng GitHub API | Hợp lý nếu sau này cần UI riêng. Tạm hoãn |
| C. Board có DB riêng, sync 2 chiều | Loại: hai nguồn sự thật gây lệch trạng thái, sai burndown và velocity |
| D. Lưu task thành file trong git | Loại: mất liên kết `Closes #n`, dễ gặp merge conflict |

### 8.1 Board hoạt động thế nào

Label `status: …` vẫn là nguồn sự thật. Board là bản sao, nhưng **được phép kéo thả**.

| Bạn làm | Kết quả |
|---|---|
| Mở hoặc merge PR, `task-start`, đóng hoặc mở lại issue | Thẻ chuyển cột ngay trong lần chạy workflow (nếu đã có secret) |
| Kéo thẻ trên board | Label đổi ở lần sync định kỳ kế tiếp (mặc định 15 phút). Muốn sync ngay: Actions → `scrum-project-sync` → **Run workflow** |
| Kéo thẻ sang Done | Label Done, issue **đóng với lý do completed**, được tính vào velocity |
| Kéo thẻ ra khỏi Done | Issue được mở lại, label theo cột mới |
| Kéo trên board **và** PR đổi trạng thái trước cùng một lần sync | Label thắng, thẻ quay về, issue có comment giải thích |
| Kéo vào cột không có trong cấu hình (ví dụ "Review") | Không đổi gì, sync in cảnh báo |
| Gắn label `points: N` | Field Points trên board tự cập nhật, nhờ đó board cộng được điểm theo cột. Sửa Points trên board sẽ bị ghi đè |

Board dùng các cột mặc định `Todo` / `In Progress` / `Done`, ánh xạ sang `New` / `In progress` / `Done`.
Muốn đặt tên cột khác thì sửa `project.status_options`.

### 8.2 Bật board (Scrum Master làm một lần)

1. Tạo Project từ template **Board** và liên kết với repo.
2. Trong Project → **Workflows**, **tắt**: *Item added to project*, *Item closed*, *Item reopened*,
   *Pull request linked to issue*, *Pull request merged*. Các automation này tự đổi cột mà
   plugin không biết, khiến label bị đổi sai. *Auto-add to project* và *Auto-close issue* thì giữ được.
3. Tạo token và lưu vào secret `SCRUM_PROJECT_TOKEN` (Settings → Secrets and variables → Actions).
   Dùng fine-grained token, chỉ cấp cho repo này, quyền **Issues** read/write và **Projects** read/write,
   có hạn dùng. Phải dùng secret vì token mặc định của Actions không truy cập được Projects.
4. Thêm vào `.github/scrum.yml`:
   ```yaml
   project:
     enabled: true
     owner: <org-hoặc-user>
     number: <số trong URL .../projects/N>
     poll_cron: "*/15 1-11 * * 1-5"   # khoảng 8h–19h giờ VN, thứ 2–6, để tiết kiệm phút Actions
   ```
5. `scrum init --force-file .github/workflows/scrum-status-sync.yml`
   (cài workflow `scrum-project-sync` và thêm token vào workflow status cũ).
6. Trên máy cá nhân: `gh auth refresh -s project`, sau đó chạy `scrum project init --dry-run`,
   rồi `scrum project init`. Lệnh sẽ tạo field *Synced status* và *Points*, rồi thêm các task của sprint đang mở.
7. **Ẩn cột *Synced status*** trong mọi view. Đây là field sổ sách để sync biết bên nào vừa đổi; sửa tay sẽ làm sync hiểu sai.
8. Commit và push `.github/`.

Tắt board: đặt `project.enabled: false` và xoá `.github/workflows/scrum-project-sync.yml`. Label không bị ảnh hưởng.

### 8.3 Lưu ý khi dùng board

- Token: đã chạy thử thành công với **classic token** (scope `repo` + `project`) trên Project của user. Fine-grained token chưa thử.
  Lưu secret qua trang Settings của repo, hoặc chạy `gh secret set` trong terminal riêng. Đừng chạy qua `!` của Claude Code, vì cách đó lưu secret rỗng.
- Khi *Auto-close issue* đang bật, kéo thẻ sang Done sẽ đóng issue ngay lập tức. Vì vậy với cột Done, board luôn thắng, kể cả khi label vừa bị đổi.
- Board → label **không realtime**, vì GitHub Actions không nhận được sự kiện kéo thẻ. Muốn realtime thì phải có GitHub App và server riêng, ngoài phạm vi hiện tại.
- Token hết hạn thì workflow `scrum-project-sync` báo đỏ, GitHub gửi email. Thay secret là chạy lại được. Các workflow lõi (PR → label) vẫn chạy bình thường khi token hết hạn.
- Hành vi mới: issue **mở lại mà đang có label `status: New`** thì giữ New (trước đây luôn chuyển In progress). Nhờ vậy, kéo thẻ từ Done về Todo cho kết quả đúng.

---

## 9. Checklist áp dụng

**Chuẩn bị**
- [ ] Mọi thành viên đã cài `gh` (đã login), `jq`, `yq` mikefarah
- [ ] Đã cài plugin (với người dùng Claude Code)

**Thiết lập repo**
- [ ] Chạy `scrum-init`, review dry-run
- [ ] Sửa `.github/scrum.yml`: timezone, `length_days`, thang điểm, giờ digest
- [ ] Commit và push `.github/` lên nhánh mặc định
- [ ] Bật branch protection, bắt buộc check `scrum-pr-link-check`

**Thống nhất với team**
- [ ] Đọc mục 5 cùng team, thống nhất thang điểm và độ dài sprint
- [ ] Ai tạo sprint và ai đóng sprint
- [ ] Ai được duyệt plan do AI đề xuất
- [ ] Thống nhất `planning.hours_per_point` (hoặc chỉ dùng điểm)

**Sprint đầu tiên**
- [ ] Dự án có mã sẵn: chạy `project-scan`, commit `docs/project-context.md`
- [ ] `sprint-new`, rồi `plan` (hoặc `discover` trước nếu yêu cầu còn mơ hồ) hoặc `task-new`
- [ ] Mỗi dev thử `task-start` và một PR `Closes #n`
- [ ] Sáng hôm sau kiểm tra issue digest
- [ ] Cuối sprint chạy `sprint-report` và `sprint-close`, ghi velocity làm mốc cho sprint sau
