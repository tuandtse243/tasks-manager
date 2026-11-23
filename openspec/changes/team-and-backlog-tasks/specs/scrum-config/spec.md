# Spec Delta

## ADDED Requirements

### Requirement: Khối team
Khoá `team` SHALL là danh sách thành viên, mặc định rỗng. Mỗi thành viên có `login` (bắt buộc), `areas` (danh sách lĩnh vực, tuỳ chọn) và `capacity` (số điểm mỗi sprint, tuỳ chọn). Kiểm tra cấu hình MUST từ chối: `login` rỗng, có ký tự không hợp lệ với login GitHub, hoặc trùng nhau (không phân biệt hoa thường); `areas` không phải danh sách chuỗi không rỗng; `capacity` không phải số dương.

#### Scenario: Không khai báo
- **WHEN** `scrum.yml` không có khoá `team`
- **THEN** `scrum config` in `team` là danh sách rỗng

#### Scenario: Khai báo đầy đủ
- **WHEN** `team` có `login: tuandt`, `areas: [backend]`, `capacity: 10`
- **THEN** cấu hình hợp lệ và `scrum config` in đúng các giá trị đó

#### Scenario: Login trùng
- **WHEN** `team` có hai thành viên `TuanDT` và `tuandt`
- **THEN** kiểm tra cấu hình báo lỗi nêu `team` và login bị trùng

#### Scenario: Capacity sai
- **WHEN** một thành viên có `capacity: 0`
- **THEN** kiểm tra cấu hình báo lỗi nêu `team` và `capacity`

#### Scenario: Login có @
- **WHEN** một thành viên có `login: "@tuandt"`
- **THEN** login được hiểu là `tuandt`
