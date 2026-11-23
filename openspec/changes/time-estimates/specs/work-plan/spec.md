# Spec Delta

## ADDED Requirements

### Requirement: Ước lượng thời gian trong plan
Task trong plan SHALL có thể có `estimate` với `work_minutes` và `review_minutes` là số nguyên dương, và `by` là `ai` hoặc `human`. `plan validate` MUST báo lỗi với giá trị khác, nêu task và trường. Khi áp plan, task có `estimate` SHALL được tạo với khối ước lượng trong thân issue. Với `--update`, khối ước lượng của issue đang mở SHALL được cập nhật theo plan.

#### Scenario: Thời gian không hợp lệ
- **WHEN** task T2 có `estimate.review_minutes: 0`
- **THEN** `plan validate` báo lỗi nêu T2 và `review_minutes`

#### Scenario: Áp plan có thời gian
- **WHEN** T1 có `estimate` làm 20 phút, review 15 phút, `by: ai`, và người dùng áp plan
- **THEN** issue của T1 có khối ước lượng với 20, 15 và `ai`

#### Scenario: Cập nhật thời gian
- **WHEN** T1 đã có issue đang mở và plan đổi review của T1 thành 25 phút, rồi người dùng chạy `plan apply --update`
- **THEN** khối ước lượng của issue T1 có review 25 phút

### Requirement: Thời gian trong bản xem
`plan.md` và `plan.html` SHALL hiện thời gian làm và thời gian review của từng task có ước lượng, tổng của từng feature và của plan, và số task chưa có ước lượng thời gian. Ước tính thời gian làm xong SHALL bằng tổng, qua các đợt, của thời gian làm lâu nhất trong đợt cộng `planning.merge_minutes`; thời gian review SHALL là tổng thời gian review.

#### Scenario: Ba đợt
- **WHEN** `merge_minutes` là 5, đợt 1 có task 20 và 8 phút, đợt 2 có task 15 và 35 phút, đợt 3 có task 20 phút
- **THEN** ước tính thời gian làm xong là 20 + 5 + 35 + 5 + 20 + 5 = 90 phút

#### Scenario: Thiếu ước lượng
- **WHEN** plan có 5 task và 1 task không có `estimate`
- **THEN** bản xem nêu 1 task chưa có ước lượng thời gian và ước tính chỉ tính 4 task

### Requirement: Dòng thời gian trong plan.html
Khi có ít nhất một task có ước lượng, `plan.html` SHALL có dòng thời gian vẽ theo đúng tỉ lệ phút: mỗi task một thanh thời gian làm đặt theo đợt của nó, khoảng merge giữa các đợt, và một thanh thời gian review bắt đầu khi thời gian làm kết thúc. Chuyển động của dòng thời gian MUST tắt khi máy bật giảm chuyển động.

#### Scenario: Có ước lượng
- **WHEN** plan có task có ước lượng
- **THEN** `plan.html` có phần dòng thời gian với thanh của từng task có ước lượng và thanh review

#### Scenario: Không có ước lượng
- **WHEN** không task nào có ước lượng
- **THEN** `plan.html` không có phần dòng thời gian
