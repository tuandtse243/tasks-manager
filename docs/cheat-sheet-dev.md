# Cheat sheet: Dev

Ba lệnh cho một task, theo thứ tự. Gõ trong Claude Code, ở thư mục gốc của repo dự án.
Chi tiết: [README của plugin](../plugins/scrum-github/README.md).

## Một task

| Bước | Lệnh | Ví dụ |
|---|---|---|
| 1. Chọn việc | `/scrum-github:next` | `/scrum-github:next` |
| 2. Nhận task: giao cho bạn, In progress, tạo branch | `/scrum-github:task-start` | `/scrum-github:task-start 12` |
| 3. Viết code, commit, push branch | (git như thường) | `git push -u origin feat/12-login` |
| 4. Viết mô tả PR và mở PR | `/scrum-github:task-pr` | `/scrum-github:task-pr` |
| 5. Merge PR | (trên GitHub) | Task tự chuyển Done và đóng |

Mô tả PR luôn có `Closes #12`. Không có dòng đó thì check `scrum-pr-link-check` đỏ; PR không gắn
task nào thì gắn label `no-task`.

## Nếu repo bật trạng thái In review

| PR của bạn | Task |
|---|---|
| Nháp | In progress |
| Sẵn sàng review | In review |
| Chuyển về nháp, hoặc đóng không merge | In progress |
| Merge | Done |

## Khi cần

| Việc | Lệnh | Ví dụ |
|---|---|---|
| Xem task của mình | `/scrum-github:task` | `/scrum-github:task task của tôi đang làm` |
| Báo một bug | `/scrum-github:task-new` | `/scrum-github:task-new bug: lỗi đăng nhập trên Safari` |
| Lệnh báo lỗi đăng nhập hay mạng | `/scrum-github:doctor` | `/scrum-github:doctor` |

Không sửa label `status:` hay `points:` bằng tay; dùng `/scrum-github:task`.
