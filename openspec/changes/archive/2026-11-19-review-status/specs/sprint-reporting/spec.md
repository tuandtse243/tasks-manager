## ADDED Requirements

### Requirement: Báo cáo khi bật In review
Khi `statuses.in_review` đặt, bảng tiến độ và báo cáo HTML SHALL có cột In review giữa In progress và Done, digest SHALL có mục task đang chờ review, và mục cần chú ý SHALL nêu task ở In review không có hoạt động trong `attention.review_days` ngày làm việc. Điểm của task In review tính là chưa xong. Khi không đặt, không có cột hay mục nào trong số này.

#### Scenario: Bảng có cột In review
- **WHEN** In review bật và `david` có một task In review
- **THEN** bảng có cột In review và dòng của `david` có 1 task ở cột đó

#### Scenario: Chờ review quá lâu
- **WHEN** `attention.review_days` là 2 và task #12 In review không có hoạt động 3 ngày làm việc
- **THEN** mục cần chú ý nêu #12 đang chờ review 3 ngày làm việc

#### Scenario: Tắt
- **WHEN** In review không bật
- **THEN** bảng, digest và báo cáo giống hệt khi chưa có tính năng
