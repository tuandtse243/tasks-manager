# Spec Delta

## ADDED Requirements

### Requirement: Giờ review khi lập kế hoạch sprint
`scrum sprint fill` SHALL in tổng phút review của các task đã có trong sprint và, khi có `--add`, của sprint sau khi thêm, theo từng người được giao. Khi một thành viên có `review_hours`, lệnh SHALL cảnh báo nếu tổng phút review giao cho họ vượt `review_hours` × 60. Cảnh báo MUST NOT chặn việc thêm task.

#### Scenario: Vượt giờ review
- **WHEN** `an-nguyen` có `review_hours: 2`, đang có 90 phút review trong sprint, và người dùng xem trước việc thêm một task review 45 phút giao cho họ
- **THEN** lệnh cảnh báo `an-nguyen` có 135 trên 120 phút review

#### Scenario: Không khai báo giờ review
- **WHEN** không thành viên nào có `review_hours`
- **THEN** lệnh in tổng phút review và không cảnh báo
