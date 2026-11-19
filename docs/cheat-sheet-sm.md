# Cheat sheet: Scrum Master

Các lệnh của Scrum Master theo thứ tự dùng trong một sprint. Gõ trong Claude Code, ở thư mục gốc của
repo dự án. Chi tiết từng tuỳ chọn: [README của plugin](../plugins/scrum-github/README.md).

## Một lần cho mỗi repo

| Việc | Lệnh | Ví dụ |
|---|---|---|
| Thiết lập repo: cấu hình, label, workflow | `/scrum-github:init` | `/scrum-github:init`, rồi commit và push `.github/` |
| Kiểm tra cả bộ cài đặt | `/scrum-github:doctor` | `/scrum-github:doctor` |
| (Tuỳ chọn) Bật board kanban | `/scrum-github:project-setup` | `/scrum-github:project-setup` |

Đổi `.github/scrum.yml` (thang điểm, giờ digest, ngôn ngữ, In review) thì chạy lại `init`.

## Đầu sprint

| Việc | Lệnh | Ví dụ |
|---|---|---|
| Tạo sprint | `/scrum-github:sprint-new` | `/scrum-github:sprint-new bắt đầu thứ 2 tới, mục tiêu "Đăng ký, đăng nhập"` |
| Chọn task cho sprint theo sức chứa | `/scrum-github:sprint-fill` | `/scrum-github:sprint-fill` |

## Hằng ngày

| Việc | Lệnh | Ví dụ |
|---|---|---|
| Tiến độ theo người, mục "Cần chú ý" | `/scrum-github:sprint-status` | `/scrum-github:sprint-status ai đang bị chặn?` |
| Sửa task: điểm, người nhận, sprint, bỏ | `/scrum-github:task` | `/scrum-github:task giao #15 cho an-nguyen` |
| Việc kế tiếp của chính mình | `/scrum-github:next` | `/scrum-github:next` |

"Cần chú ý" nêu task bị chặn, task In progress không động, task thiếu người nhận hoặc điểm, và
sprint chậm hơn đường lý tưởng. Digest mỗi sáng có cùng mục này.

## Cuối sprint

| Việc | Lệnh | Ví dụ |
|---|---|---|
| Báo cáo burndown và velocity | `/scrum-github:sprint-report` | `/scrum-github:sprint-report` |
| Đóng sprint, ghi velocity, chuyển task dở | `/scrum-github:sprint-close` | `/scrum-github:sprint-close` |

Đóng sprint đăng bản tổng kết lên issue `Sprint N digest` để dùng ở buổi review.

Lệnh báo lỗi đăng nhập hay mạng: `/scrum-github:doctor`.
