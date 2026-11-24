# Spec Delta

## ADDED Requirements

### Requirement: Thời gian trong việc của một người
`scrum mine` SHALL hiện thời gian làm và thời gian review của mỗi task có ước lượng, và cho các task chưa xong của người đó trong sprint đang mở: tổng thời gian review, và ước tính thời gian làm theo đợt như bản xem plan. Task chưa có ước lượng SHALL được đếm và nêu riêng.

#### Scenario: Có ước lượng
- **WHEN** người dùng có #102 (làm 20, review 15) và #103 (làm 15, review 15, bị chặn bởi #102) chưa xong trong sprint đang mở, và `merge_minutes` là 5
- **THEN** `scrum mine` hiện ước tính làm 20 + 5 + 15 + 5 = 45 phút và review 30 phút

#### Scenario: Có task chưa ước lượng
- **WHEN** một task của người dùng trong sprint đang mở không có khối ước lượng
- **THEN** `scrum mine` nêu 1 task chưa có ước lượng thời gian
