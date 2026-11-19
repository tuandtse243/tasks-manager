# Cheat sheet: Product Owner

Các lệnh của PO theo thứ tự dùng trong một sprint. Gõ trong Claude Code, ở thư mục gốc của repo dự án.
Chi tiết từng tuỳ chọn: [README của plugin](../plugins/scrum-github/README.md).

## Trước Sprint Planning

| Việc | Lệnh | Ví dụ |
|---|---|---|
| Làm rõ một ý tưởng còn mơ hồ | `/scrum-github:discover` | `/scrum-github:discover cho người dùng bình luận dưới bài viết` |
| Chia yêu cầu thành epic, feature, task | `/scrum-github:plan` | `/scrum-github:plan docs/plans/blog-comments/brief.md` |
| Xem việc chưa vào sprint nào | `/scrum-github:backlog` | `/scrum-github:backlog còn task nào chưa ước lượng?` |
| Thêm một task lẻ hoặc bug | `/scrum-github:task-new` | `/scrum-github:task-new bug: nút Lưu không phản hồi trên Safari, 3 điểm` |

`discover` và `plan` ghi file vào `docs/plans/<slug>/` để bạn đọc và sửa; chỉ khi bạn duyệt thì issue
mới được tạo trên GitHub.

## Trong Sprint Planning

| Việc | Lệnh | Ví dụ |
|---|---|---|
| Chọn task vừa sức chứa của sprint | `/scrum-github:sprint-fill` | `/scrum-github:sprint-fill sức chứa 20 điểm` |
| Đổi điểm, đưa task về backlog, bỏ task | `/scrum-github:task` | `/scrum-github:task đưa #12 về backlog` |

Sức chứa mặc định là velocity trung bình của tối đa ba sprint đã đóng gần nhất.

## Trong sprint

| Việc | Lệnh | Ví dụ |
|---|---|---|
| Xem tiến độ và mục "Cần chú ý" | `/scrum-github:sprint-status` | `/scrum-github:sprint-status còn bao nhiêu điểm?` |
| Báo cáo HTML gửi stakeholder | `/scrum-github:sprint-report` | `/scrum-github:sprint-report` |

Digest đăng mỗi sáng vào issue `Sprint N digest` (và kênh chat nếu repo có secret
`SCRUM_DIGEST_WEBHOOK`).

## Cuối sprint

Sprint Review dùng bản tổng kết mà Scrum Master đăng khi đóng sprint (comment trên issue
`Sprint N digest`): velocity, task xong, task chuyển tiếp, phạm vi thay đổi.

Không biết làm gì tiếp: `/scrum-github:next`. Lệnh báo lỗi: `/scrum-github:doctor`.
