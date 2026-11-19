# Design

## Context

Xem `proposal.md` cho lý do. Hiện trạng đã kiểm tra trong mã (đường dẫn tính từ `plugins/scrum-github/`):

- `scripts/vendor-sync.sh SRC` nhận thư mục `vendor/pocock` của `aidw`, đọc commit bằng cách phân tích `UPSTREAM.md` của nguồn, và chỉ biết sao chép cả thư mục skill. `tests/test_vendor.sh` dựng nguồn giả theo dạng đó.
- Bốn skill đang vendor giống upstream HEAD (`5863806`, 2026-11-12) từng byte, dù `UPSTREAM.md` ghi commit `4ae2317`.
- `skills/discover`, `skills/plan`, `skills/project-scan` đọc skill vendor rồi áp một phần "Adapter"; `reference/planning-rules.md` thắng mọi skill vendor.
- `scrum doc check` đọc danh sách mục của brief từ `runtime/share/doc-sections.json` (mục bắt buộc và mục tuỳ chọn).
- `scrum pr-check` chỉ cần một closing keyword trong mô tả PR; nó không quan tâm các mục khác.
- `scrum init` sao chép `runtime/{bin,lib,share,VERSION}` vào repo đích; mọi thứ ngoài `runtime/` và `templates/` ở lại trong plugin.
- README mục "Project board: Turn it on" có bảy bước, trong đó `gh secret set` không chạy được qua shell không tương tác (lưu secret rỗng).
- Upstream `wizard/template.sh` dùng mảng, `[[ ]]`, `printf -v`, `read -e`: chạy được trên Bash 3.2.

## Goals / Non-Goals

**Goals:**

- Một lệnh đồng bộ lấy mọi mục vendor từ đúng một commit của upstream, kiểm tra được offline.
- Mỗi skill mới của upstream được nối vào đúng một chỗ của flow bằng adapter, không sửa file vendor.
- Giữ nguyên các bất biến: không ghi GitHub trước khi duyệt, agent chỉ đọc, định dạng `plan.json` không đổi.

**Non-Goals:**

- Không phụ thuộc lúc chạy vào plugin `mattpocock-skills`.
- Không thêm lệnh mới vào CLI `scrum` cho việc soạn PR hay chạy wizard.
- Không tự động cập nhật bản vendor (không cron, không CI).

## Decisions

### 1. Nguồn của `vendor-sync.sh` là một bản clone git của upstream

`vendor-sync.sh [SRC] [--ref REF]`. Có `SRC`: dùng thư mục đó (phải là repo git có `skills/` và `LICENSE`). Không có `SRC`: `git clone --depth 1` từ `VENDOR_UPSTREAM_URL` (mặc định `https://github.com/mattpocock/skills.git`) vào thư mục tạm, xoá khi thoát; `--ref` chọn nhánh hoặc tag. Commit lấy bằng `git -C SRC rev-parse HEAD`.

- Vì sao: commit là sự thật của git, không phải dòng chữ trong một file trung gian; test dựng được nguồn giả bằng `git init` trong thư mục tạm nên vẫn offline.
- Đã cân nhắc: tải tarball qua `curl` (không cần git nhưng mất commit chính xác khi dùng nhánh); git submodule (repo đích của người cài plugin không nên phải biết submodule; plugin marketplace sao chép cây thư mục, không khởi tạo submodule).
- Cây làm việc bẩn của `SRC` không bị chặn: người bảo trì chịu trách nhiệm; script in cảnh báo khi `git status --porcelain` không rỗng.

### 2. Danh sách vendor là một bảng "đích <- đường dẫn upstream" trong script

```
grilling          skills/productivity/grilling
to-questionnaire  skills/productivity/to-questionnaire
to-spec           skills/engineering/to-spec
to-tickets        skills/engineering/to-tickets
domain-modeling   skills/engineering/domain-modeling
pr                skills/engineering/pr
wizard            skills/engineering/wizard
triage/AGENT-BRIEF.md  skills/engineering/triage/AGENT-BRIEF.md
```

Một dòng là thư mục (sao chép cả cây, xoá đích cũ trước) hoặc một file (sao chép đúng file đó). Script kiểm tra đủ mọi nguồn trước khi ghi bất cứ thứ gì, như hiện nay. Đích nào trong `vendor/pocock/` không còn trong bảng thì bị xoá, để bảng luôn là toàn bộ nội dung.

- Vì sao chỉ lấy `AGENT-BRIEF.md` của `triage`: `triage/SKILL.md` là một state machine ghi lên tracker, ngoài phạm vi; để nó trong plugin sẽ khiến người đọc tưởng nó được dùng.
- `UPSTREAM.md` sinh từ chính bảng này, nên đường dẫn upstream luôn có (bỏ nhánh "không biết đường dẫn" của script cũ) và bỏ dòng "Obtained through".
- Giữ nguyên quy tắc "chạy lại với cùng nguồn không đổi gì": so `UPSTREAM.md` mới dựng với ngày cũ; trùng thì giữ file cũ.

### 3. `discover`: thêm hai adapter, một mục tuỳ chọn của brief

- **`domain-modeling`** (đã vendor): trong bước phỏng vấn, đọc thêm skill này với adapter: chỉ dùng ba động tác "challenge against the glossary", "sharpen fuzzy language", "cross-reference with code"; glossary là mục `## Glossary` của `planning.context_file`; thuật ngữ đã chốt ghi vào mục "Decisions" của brief; không tạo `GLOSSARY.md`, không ADR, không sửa context file. Thuật ngữ mới sẽ vào glossary ở lần `project-scan` sau khi mã có nó, hoặc người dùng tự thêm vào "Team notes".
- **`to-questionnaire`**: nhánh mới trong adapter của `grilling`. Khi người dùng nói quyết định thuộc về người khác, đề nghị bảng câu hỏi; đồng ý thì theo ba bước của skill vendor với adapter: file là `<plan folder>/questionnaire-<recipient-slug>.md` (không phải thư mục hiện tại), viết bằng ngôn ngữ của người dùng, dùng thuật ngữ của Glossary.
- **Brief**: thêm mục tuỳ chọn `## Open questions` vào `reference/brief-template.md` và `runtime/share/doc-sections.json`. Mỗi dòng: câu hỏi, người trả lời, tên file bảng câu hỏi. Còn mục này thì `Status` là `draft` và `discover` không in bước kế tiếp. Chạy lại: đọc file bảng câu hỏi, câu nào đã có trả lời thì chuyển sang "Decisions" và ghi vào phụ lục như một vòng hỏi đáp.
- `plan` bước 3: brief `draft` có "Open questions" không tự qua; nêu các câu còn mở và hỏi người dùng có tiếp tục không; tiếp tục thì mỗi câu thành một giả định cụ thể.
- Đã cân nhắc: ghi câu hỏi mở vào "Risks" (không cần đổi `doc-sections.json` nhưng `plan` không phân biệt được rủi ro với điều chưa quyết); thêm trạng thái `waiting` cho `Status` (thêm một giá trị mà không lệnh nào đọc).

### 4. Mô tả task bền: dùng nguyên tắc của `AGENT-BRIEF.md`, không dùng mẫu của nó

`plan` (adapter của `to-tickets`), `task-new` và `plan-critic` đọc `vendor/pocock/triage/AGENT-BRIEF.md` và áp bốn nguyên tắc: durability over precision, behavioral not procedural, complete acceptance criteria, explicit scope boundaries. Adapter: không đăng comment "Agent Brief", không dùng nhãn `ready-for-agent`; nội dung đi vào các trường sẵn có của `plan.json` (`body`, `acceptance`); ranh giới phạm vi của một task viết thành một câu "Out of scope: …" cuối `body`.

- Vì sao không thêm trường `out_of_scope` cho task: đổi schema và `task-payload.jq` cho một dòng chữ; plan đã có `out_of_scope` ở cấp plan.
- `plan-critic` thêm loại phát hiện thứ sáu `fragile`: `body` hoặc `acceptance` dẫn đường dẫn file, số dòng, hoặc mô tả từng bước sửa mã. Agent vẫn chỉ đọc; nó nhận thêm đường dẫn `AGENT-BRIEF.md` trong prompt.
- `task-new`: chỉ áp khi AI soạn mô tả; mô tả người dùng tự viết giữ nguyên (khớp quy tắc sẵn có "do not invent").

### 5. Skill mới `task-pr`, dùng `gh` trực tiếp

`skills/task-pr/SKILL.md` đọc `vendor/pocock/pr/SKILL.md` với adapter:

- Số task: tham số, hoặc số đầu tiên trong tên nhánh khớp `branch.pattern` (`scrum config`); không có thì hỏi.
- Nền so sánh: nhánh mặc định của repo (`gh repo view --json defaultBranchRef`), diff ba chấm.
- Thân PR: ba mục của `pr` theo đúng tên upstream (`## Summary`, `## Evidence`, `## Merge Danger`), rồi `## Task` với `Closes #N`. Tiêu chí hoàn thành của issue (`gh issue view N`) là thứ phần Evidence phải chứng minh. Không có `GLOSSARY.md`: dùng Glossary của project context nếu có.
- Không bịa bằng chứng: không có test hay kết quả chạy thì ghi rõ.
- Chỉ sau khi người dùng duyệt: `gh pr create --body-file` (hoặc `gh pr edit` khi nhánh đã có PR mở). Đẩy nhánh là việc của người dùng; nhánh chưa có trên remote thì nói và dừng.

Vì sao không thêm `scrum task pr`: soạn mô tả là việc của mô hình, phần còn lại là hai lệnh `gh` không có logic để kiểm thử bằng jq. Quy tắc "chỉ CLI `scrum` chạm GitHub" thuộc `planning-rules.md`, áp cho ba skill lập kế hoạch; `task-pr` giữ tinh thần của nó bằng bước duyệt.

PR template (`templates/github/pull_request_template.md`) có cùng bốn mục, mỗi mục một comment hướng dẫn ngắn, để PR viết tay và PR do `task-pr` soạn cùng dạng. Placeholder `{{NO_TASK_LABEL}}` giữ nguyên.

### 6. Wizard bật board: một script soạn sẵn, không sinh lúc chạy

`wizards/project-board.sh` = phần thư viện của `vendor/pocock/wizard/template.sh` (mọi thứ phía trên dòng đánh dấu `STAGES`, nguyên văn) + các stage của plugin. Một test so phần thư viện của hai file từng byte, nên khi upstream đổi `template.sh` test sẽ đỏ cho tới khi wizard được dựng lại.

Các stage:

1. Tạo Project từ template Board và liên kết với repo (mở trang projects của owner); hỏi `owner` và `number`.
2. Tắt năm built-in workflow (mở `…/projects/<number>/workflows`), nêu tên từng cái.
3. Tạo token (mở trang tạo token), nêu scope; `ask_secret`; `set_secret SCRUM_PROJECT_TOKEN`.
4. `confirm` rồi ghi khối `project:` (`enabled`, `owner`, `number`) vào `.github/scrum.yml`: chưa có khối thì nối thêm vào cuối file, có rồi thì sửa đúng ba dòng đó; `yq` kiểm tra kết quả và chỉ tự ghi lại cả file khi cách sửa theo dòng không cho ra đúng giá trị. Trả lời không thì ghi vào `SKIPPED`.
5. Hỏi rồi chạy `gh auth refresh -s project` (cần trình duyệt). Sau `finish`, in các lệnh còn lại (`scrum init --force-file …`, `scrum project init --dry-run` rồi `scrum project init`, ẩn field "Synced status", commit): in sau phần tổng kết vì `finish` xoá màn hình.

- Đặt ngoài `runtime/` để `scrum init` không sao chép vào repo đích; người dùng chạy `bash "<plugin>/wizards/project-board.sh"` từ gốc repo đích.
- Token không qua `write_env`: không có `.env` nào được ghi.
- Vì sao soạn sẵn thay vì để skill `wizard` sinh mỗi lần: quy trình này cố định và đã biết; script soạn sẵn kiểm thử được (`bash -n`, so thư viện, đếm stage) và không tốn lượt mô hình. Skill `wizard` vẫn được vendor vì nó là hướng dẫn cho người bảo trì khi sửa các stage.
- Skill `project-setup` chỉ in câu lệnh và chờ: wizard chặn ở đầu vào của người dùng và mở trình duyệt, nên không chạy được qua công cụ Bash. Sau khi người dùng báo xong, skill chạy `scrum project init --dry-run`.
- Không thêm `scrum project setup` vào CLI: CLI được sao chép vào repo đích, nơi wizard không có mặt.

### 7. Phiên bản

`plugin.json` và `runtime/VERSION` lên `0.4.0` (đổi `doc-sections.json` nằm trong runtime). README: bảng lệnh thêm `task-pr` và `project-setup`, mục "Development" viết lại đoạn vendor, mục "Turn it on" trỏ tới wizard trước danh sách bảy bước.

## Risks / Trade-offs

- [Upstream đổi hoặc xoá một skill đang vendor] → script dừng trước khi ghi và nêu tên mục thiếu; bản vendor cũ còn nguyên. Người bảo trì sửa bảng ở mục 2.
- [Adapter lệch khỏi skill vendor sau một lần đồng bộ] → adapter thắng theo quy ước; `git diff vendor/` sau mỗi lần đồng bộ là bước rà bắt buộc, ghi trong `UPSTREAM.md`.
- [Wizard hướng dẫn giao diện GitHub đã đổi] → mỗi stage mở đúng URL và nêu tên mục cần bấm; README vẫn giữ danh sách bước bằng chữ làm đường lui.
- [`yq -i` làm mất dòng trống của `scrum.yml`] → đã gặp khi chạy thử trên cấu hình thật (comment còn, mọi dòng trống mất). Wizard vì vậy sửa theo dòng và chỉ dùng `yq` để đọc và kiểm tra; `yq` ghi lại cả file chỉ còn là đường lui cho khối viết kiểu flow. Test chạy trên chính `templates/scrum.yml` và so từng dòng.
- [PR template dài hơn làm người viết tay bỏ trống] → comment hướng dẫn cho phép ghi "none"; `pr-check` vẫn chỉ đòi `Closes #`.
- [Brief `draft` nằm lâu vì bảng câu hỏi không được trả lời] → `plan` cho tiếp tục với giả định, nên không ai bị chặn.

## Migration Plan

1. Chạy `scripts/vendor-sync.sh` mới một lần; rà `git diff vendor/`.
2. Phát hành 0.4.0. Repo đích đã cài: không bắt buộc làm gì. Muốn PR template mới: `scrum init --force-file .github/pull_request_template.md`. Muốn `doc check` nhận mục "Open questions" trong workflow của repo: chạy lại `scrum init` để cập nhật runtime.
3. Quay lui: quay về 0.3.0; file trong repo đích (PR template, brief có mục mới) vẫn hợp lệ với bản cũ vì mục tuỳ chọn lạ không làm `doc check` thất bại — kiểm tra điều này bằng test ở nhóm việc tương ứng.
