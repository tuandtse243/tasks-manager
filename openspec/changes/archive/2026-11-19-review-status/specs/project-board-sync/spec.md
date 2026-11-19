## ADDED Requirements

### Requirement: Cột In review trên board
Khi `statuses.in_review` đặt, option `project.status_options.in_review` SHALL là cột thứ tư của đồng bộ: kéo thẻ vào cột đó đặt label In review, và task In review nằm ở cột đó. `project init` MUST dừng mà không ghi gì khi field Status thiếu option này, và nêu tên option cần tạo. Khi `statuses.in_review` không đặt, option đó không thuộc đồng bộ và thẻ ở đó được bỏ qua kèm cảnh báo như mọi cột lạ.

#### Scenario: Kéo thẻ vào cột review
- **WHEN** In review bật, task #5 có L=In progress, S=In progress, và người dùng kéo thẻ sang `In Review`
- **THEN** sau khi sync, #5 có label In review và S=In review

#### Scenario: Thiếu cột
- **WHEN** In review bật và field Status không có option `In Review`
- **THEN** `project init` dừng, không ghi gì, và nêu option `In Review` cần tạo

#### Scenario: Tắt In review
- **WHEN** In review không bật và task #8 nằm ở cột `In Review`
- **THEN** label của #8 không đổi và lần sync in cảnh báo nêu #8 và option `In Review`
