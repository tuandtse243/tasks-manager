# Design

Đường dẫn tính từ `plugins/scrum-github/`. Change này nằm trên `time-estimates`: `scrum mine`, đợt theo phụ thuộc, `eta_by_waves`, khối `estimate` và `blocked_map` đã có.

## Context

Plugin là skill của Claude Code cộng runtime Bash và jq. Runtime không gọi được Claude, chỉ skill (tức Claude trong phiên của người dùng) mới khởi chạy được agent. Tool Agent của Claude Code có `isolation: "worktree"`: agent nhận một worktree mới, tách từ `HEAD` hiện tại của repo, trên một nhánh riêng, và báo lại tên nhánh khi có thay đổi. Workflow trạng thái hiện có đã chuyển task sang In review hoặc In progress khi PR được mở, và sang Done khi PR có `Closes #N` được merge.

## Goals / Non-Goals

**Goals:**
- Phần có thể sai về git và GitHub (chọn task, chia đợt, nhánh, merge, conflict, trạng thái, PR) nằm trong runtime và có test.
- Skill chỉ điều phối: hỏi xác nhận, khởi chạy agent, gọi `scrum run …` theo thứ tự.

**Non-Goals:** runtime tự gọi model; chạy trên CI; giới hạn token.

## Decisions

### 1. Chia việc giữa runtime và skill

```
skill /run                          runtime scrum run
----------                          -----------------
                                    plan     -> đợt, task bị loại, ETA (chỉ đọc)
hỏi xác nhận
                                    start    -> nhánh tích hợp, state, In progress
mỗi đợt:
  git checkout nhánh tích hợp
  Agent(implementer, worktree) x K  record --started N
  ...agent xong...                  record N --done --branch B --notes F | --failed --reason R
                                    merge N  -> merge --no-ff, conflict thì abort
  chạy test_command trên nhánh tích hợp
                                    finish   -> push nhánh tích hợp, mở PR (gói review)
```

Mỗi bước của runtime đọc và ghi `.scrum/run/<id>.json` bằng `run-state.jq`, nên skill có thể dừng ở bất kỳ đâu rồi chạy tiếp.

### 2. Worktree do Agent tool tạo

Skill checkout nhánh tích hợp trước mỗi đợt, rồi khởi chạy agent `implementer` với `isolation: "worktree"`. Worktree vì vậy tách từ trạng thái mới nhất của nhánh tích hợp. Nhánh mà Agent tool báo về được ghi qua `record --branch`. `merge` chỉ dùng git ở local. Không có lệnh nào push nhánh này.

Phương án khác: runtime tự `git worktree add`. Bị loại vì agent của Claude Code vẫn phải được chỉ vào đường dẫn đó, mà sandbox chỉ cho ghi trong các thư mục được phép. Để Agent tool tự quản worktree đơn giản và an toàn hơn.

### 3. Chọn và chia đợt

`run-select.jq`: đầu vào là issue của người dùng (như `scrum mine`), sprint đang mở, `blocked_map`, danh sách số task (tuỳ chọn), và cfg. Đầu ra là `{waves, excluded: [{number, reason}], eta}`. Đợt tính trên đồ thị chặn giữa các task được chọn. Chặn bởi task ngoài lần chạy thì task bị loại. `eta` dùng `eta_by_waves`.

### 4. State file

`.scrum/run/<id>.json` với `id = YYYYMMDD-HHMM-<login>`: `{id, branch, base, sprint, waves, tasks: {N: {state: pending|running|done|failed|conflict|merged|excluded, branch, started_at, ended_at, reason, notes}}, prs}`. `start` thêm `.scrum/` vào `.git/info/exclude` để không sửa `.gitignore` của repo.

### 5. Merge

`git merge --no-ff -m "Merge #N <title>" <branch>` trên nhánh tích hợp. Thất bại thì `git merge --abort`, state ghi `conflict`, lệnh trả mã khác 0 với thông báo. Skill hỏi người dùng: bỏ task đó, hoặc tự sửa rồi `scrum run merge N` lại.

### 6. Trạng thái trên GitHub

`start` đặt In progress bằng `set_status` và tự giao task cho mình nếu chưa có ai, giống `task start`. Task lỗi về New kèm comment. In review và Done để workflow hiện có lo khi PR mở và khi merge, không làm lại.

### 7. Mô tả PR

`run-pr-body.jq` dựng từ state và issue: mỗi task có acceptance (dòng checkbox trong thân issue), ước lượng (khối `estimate`) so với thời gian thật, `notes` của agent (cách test tay, chỗ cần nhìn kỹ), và `Closes #N`; thêm mục task lỗi và bị loại. Ghi ra file tạm rồi tạo PR bằng `gh pr create --body-file`. `--pr-per-wave`: `finish --wave W` nhắm vào nhánh của PR đợt trước.

### 8. Agent `implementer`

`agents/implementer.md`, tools: Read, Write, Edit, Glob, Grep, Bash. Đầu vào: số, tiêu đề, thân issue, `run.test_command`, đường dẫn `docs/project-context.md` nếu có. Nó làm theo acceptance, viết và chạy test, commit một hoặc vài commit có `#N`, không push, không sửa ngoài phạm vi task. Trả về JSON: `{result: done|failed, reason, manual_test, look_closely}`. Skill ghi phần này vào file notes cho `record`.

### 9. ai-ready

Label `labels.ai_ready` (mặc định `ai-ready`) do `init` tạo qua `label-plan.jq`. Plan có `ai_ready`. `plan apply` gắn label, `--update` thêm hoặc gỡ.

## Risks / Trade-offs

- [Agent chạy mã tuỳ ý trên máy] → mỗi lần chạy cần người dùng xác nhận; worktree riêng; không push gì ngoài nhánh tích hợp sau khi test qua.
- [Hai task cùng đợt sửa cùng chỗ] → merge từng task, conflict thì dừng và hỏi. Chưa có đoán trước conflict (ghi nhận để làm sau).
- [Máy yếu khi chạy nhiều worktree] → `max_parallel` mặc định 3.
- [Một PR lớn khó review] → mỗi task một commit merge, mô tả chia theo task, có `--pr-per-wave`.
- [Agent tool không trả nhánh khi không có thay đổi] → `record --failed --reason "no changes"`.

## Migration Plan

Không chuyển đổi. Khối `run` và `labels.ai_ready` có mặc định. Chạy `init` lại để tạo label. Phiên bản 0.11.0.
