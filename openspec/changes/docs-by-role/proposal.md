# Proposal

Thứ tự trong lộ trình: **6 trên 6**. Làm cuối, khi các lệnh và cấu hình của change 2 đến 5 đã ổn định, để chỉ viết lại tài liệu một lần.

## Why

Hai tài liệu chính nói cùng một nội dung bằng hai thứ tiếng: README của plugin (tiếng Anh, 378 dòng) và hướng dẫn áp dụng (tiếng Việt, 584 dòng) đều mô tả bảng lệnh, cấu hình, plan và board. Mỗi change phải sửa cả hai, và chúng đã từng lệch nhau. Người đọc cũng không có đường ngắn: một Dev chỉ cần ba lệnh vẫn phải lướt qua phần thiết lập board, và không tài liệu nào vừa một trang.

## What Changes

- Chia vai rõ cho hai tài liệu:
  - README của plugin là **tài liệu tra cứu**: mọi lệnh và tuỳ chọn, mọi khoá cấu hình, quy tắc đổi trạng thái, cách lưu dữ liệu, phát triển.
  - Hướng dẫn áp dụng là **tài liệu theo việc**: cài đặt, flow theo vai trò, quy ước team, xử lý sự cố. Nó không lặp lại bảng tuỳ chọn hay bảng cấu hình mà dẫn sang README.
- Thêm ba trang cheat sheet, mỗi trang vừa một màn hình: Product Owner, Scrum Master, Dev. Mỗi trang gồm các lệnh của vai đó theo thứ tự dùng trong một sprint và một ví dụ cho mỗi lệnh.
- README gốc của repo rút còn: plugin là gì, cài trong ba bước, một ví dụ chạy trọn một task, và bảng "bạn là ai thì đọc gì" dẫn tới cheat sheet.
- Mục "Xử lý sự cố" rút gọn: các lỗi môi trường được thay bằng "chạy `/scrum-github:doctor`" (change 2); chỉ giữ các lỗi về cách dùng.
- Mục "Giới hạn hiện tại" cập nhật theo những gì change 2, 4, 5 đã gỡ.
- Thêm test offline giữ tài liệu khớp với mã:
  - mọi lệnh trong `scrum help` có trong bảng lệnh của README, và ngược lại;
  - mọi khoá trong `share/defaults.json` có trong mục cấu hình của README;
  - mọi skill trong `skills/` có trong bảng lệnh của hướng dẫn;
  - mọi liên kết tương đối trong các file tài liệu trỏ tới file tồn tại.
- Cập nhật sơ đồ `docs/diagrams/sprint-flow` cho các lệnh mới (backlog, sprint plan, trạng thái In review nếu đã có).

Ngoài phạm vi: bản dịch tiếng Anh của hướng dẫn, trang web tài liệu, video hay ảnh động, và sinh tài liệu tự động từ mã.

## Capabilities

### New Capabilities

Không có.

### Modified Capabilities

Không có. Change này chỉ sắp xếp lại tài liệu và thêm test cho tài liệu, không đổi hành vi nào đã có spec, nên đặt `skip_specs: true` trong `.openspec.yaml`.

## Impact

- File sửa: `README.md`, `plugins/scrum-github/README.md`, `docs/huong-dan-ap-dung.md`, `docs/diagrams/sprint-flow.*`.
- File mới: `docs/cheat-sheet-po.md`, `docs/cheat-sheet-sm.md`, `docs/cheat-sheet-dev.md`, `plugins/scrum-github/tests/test_docs.sh`.
- `docs/huong-dan-ap-dung.md` và `README.md` đang có thay đổi chưa commit trong cây làm việc (viết lại lớn, cộng `docs/diagrams/` chưa được theo dõi). Cần commit hoặc bỏ chúng trước khi bắt đầu change này, vì nó viết lại chính các file đó.
- Liên kết tới các mục đánh số của hướng dẫn (ví dụ `#5-các-flow-sử-dụng` trong README gốc) sẽ đổi; test liên kết ở trên bắt các chỗ gãy trong repo, liên kết từ bên ngoài thì không.
- Không đổi mã runtime, không đổi repo đích.
