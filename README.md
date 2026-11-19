# tasks-manager

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

## Đọc gì tiếp

| Bạn là | Đọc |
|---|---|
| Thành viên team (PO, Scrum Master, Dev) | [Hướng dẫn áp dụng](docs/huong-dan-ap-dung.md): cài đặt, quy trình một sprint, quy ước, xử lý sự cố |
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
openspec/                         spec (specs/) và lịch sử thay đổi (changes/archive/)
```

## Phát triển

```bash
bash plugins/scrum-github/tests/run.sh          # toàn bộ test, offline, khoảng 2 phút
bash plugins/scrum-github/tests/run.sh plan     # chỉ chạy tests/test_plan.sh
```

Mỗi thay đổi lớn đi qua OpenSpec: đề xuất bằng `/opsx:propose`, làm bằng `/opsx:apply`, xong thì
`/opsx:archive` để gộp spec vào `openspec/specs/`.
