# tasks-manager

[![CI](https://github.com/tuandtse243/tasks-manager/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tuandtse243/tasks-manager/actions/workflows/ci.yml)

Chạy Scrum ngay trên GitHub, không cần Jira hay Trello. Repo này là một **marketplace plugin của
Claude Code**. Hiện marketplace có một plugin là [`scrum-github`](plugins/scrum-github/README.md).

| Scrum | Trên GitHub |
|---|---|
| Sprint | Milestone `Sprint {n}` |
| Task | Issue có label `status: …` và `points: N` |
| Trạng thái | Tự đổi khi mở hoặc merge PR có `Closes #n` |
| Lập kế hoạch | Claude chia yêu cầu thành epic → feature → task, bạn duyệt rồi mới tạo issue |
| Theo dõi | Bảng tiến độ, báo cáo HTML có burndown, digest hằng ngày |

## Bắt đầu nhanh

1. Cài công cụ: `brew install gh jq yq`, rồi `gh auth login -h github.com -s repo,workflow`.
2. Cài plugin trong Claude Code:
   ```
   /plugin marketplace add tuandtse243/tasks-manager
   /plugin install scrum-github@tasks-manager
   ```
   Nếu đã clone repo này về máy, có thể chạy `/plugin marketplace add ./` ở thư mục gốc của nó.
3. Mở Claude Code trong repo dự án của bạn, chạy `/scrum-github:scrum-init`, rồi commit và push
   thư mục `.github/` lên nhánh mặc định.
4. Tạo sprint đầu tiên bằng `/scrum-github:sprint-new`, rồi thêm task bằng `/scrum-github:plan`
   hoặc `/scrum-github:task-new`.
5. Dev nhận task bằng `/scrum-github:task-start <số>`, mở PR bằng `/scrum-github:task-pr`. Merge PR
   là task tự chuyển Done.

![Một sprint với scrum-github](docs/diagrams/sprint-flow.png)

Từng bước cụ thể của mỗi vai trò, kèm ví dụ lệnh: [Hướng dẫn áp dụng → Các flow sử dụng](docs/huong-dan-ap-dung.md#5-các-flow-sử-dụng).
Tra nhanh mọi lệnh: [Bảng lệnh](docs/huong-dan-ap-dung.md#2-bảng-lệnh).

## Đọc gì tiếp

| Bạn là | Đọc |
|---|---|
| Thành viên team (PO, Scrum Master, Dev) | [Hướng dẫn áp dụng](docs/huong-dan-ap-dung.md): bảng lệnh, cài đặt, flow từng vai trò, quy ước, xử lý sự cố |
| Người dùng cần tra lệnh và cấu hình | [README của plugin](plugins/scrum-github/README.md) (tiếng Anh) |
| Người phát triển plugin | [Bối cảnh dự án](docs/project-context.md), [kiểm thử end-to-end](plugins/scrum-github/docs/e2e-testing.md), spec trong `openspec/specs/` |

## Cấu trúc repo

```
.claude-plugin/marketplace.json   khai báo marketplace "tasks-manager"
plugins/scrum-github/             mã nguồn plugin
  skills/                         các lệnh /scrum-github:*
  agents/                         agent chỉ đọc: codebase-scout, researcher, plan-critic
  runtime/                        CLI `scrum` (bash + jq), được chép vào repo dự án khi init
  templates/                      workflow, issue form, PR template cài vào repo dự án
  tests/                          test offline với `gh` giả
docs/                             tài liệu tiếng Việt và bối cảnh dự án
  diagrams/                       sơ đồ flow (nguồn archify .json, bản .html tương tác, ảnh .png)
openspec/                         spec (specs/) và lịch sử thay đổi (changes/archive/)
```

## Phát triển

```bash
bash plugins/scrum-github/tests/run.sh          # toàn bộ test, offline, khoảng 2 phút
bash plugins/scrum-github/tests/run.sh plan     # chỉ chạy tests/test_plan.sh
```

Lint mã shell (không lint `vendor/`) và kiểm tra plugin:

```bash
(cd plugins/scrum-github && shellcheck --severity=warning runtime/bin/scrum runtime/lib/*.sh scripts/*.sh wizards/*.sh tests/run.sh tests/test_*.sh tests/fake-gh)
claude plugin validate plugins/scrum-github     # chạy tay, CI không cài Claude Code
```

CI (`.github/workflows/ci.yml`) chạy bộ test trên Ubuntu cùng lệnh `shellcheck` ở trên cho mỗi
pull request, và chạy thêm bộ test trên macOS mỗi lần push vào `main` (repo riêng tư tính phút macOS
gấp mười). Lịch sử phiên bản của plugin ở
[CHANGELOG](plugins/scrum-github/CHANGELOG.md).

Claude Code có thể tạo thư mục `openspec/changes/.claude/` khi ghi file dưới `openspec/changes/`.
Thư mục này đã nằm trong `.gitignore`, nhưng `openspec list` vẫn có thể hiện nó như một change tên
`.claude`; bỏ qua hoặc xoá đi.

Mỗi thay đổi lớn đi qua OpenSpec: đề xuất bằng `/opsx:propose`, làm bằng `/opsx:apply`, xong thì
`/opsx:archive` để gộp spec vào `openspec/specs/`.
