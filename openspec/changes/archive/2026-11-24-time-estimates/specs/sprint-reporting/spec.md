# Spec Delta

## ADDED Requirements

### Requirement: Thời gian còn lại trong bảng tiến độ
Khi ít nhất một task của sprint có ước lượng thời gian, bảng tiến độ SHALL có thêm cho mỗi người và dòng tổng: phút làm và phút review của các task chưa Done, và câu nêu số task chưa có ước lượng thời gian. Task giao cho nhiều người SHALL được tính một lần ở dòng tổng. Khi không task nào có ước lượng, bảng MUST giống như trước.

#### Scenario: Có ước lượng
- **WHEN** `david` có hai task chưa Done với review 15 và 30 phút
- **THEN** dòng của `david` hiện 45 phút review còn lại

#### Scenario: Không có ước lượng
- **WHEN** không task nào của sprint có khối ước lượng
- **THEN** bảng tiến độ không có cột thời gian
