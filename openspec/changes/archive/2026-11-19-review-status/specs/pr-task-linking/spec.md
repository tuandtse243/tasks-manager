## MODIFIED Requirements

### Requirement: Trạng thái theo vòng đời PR
Khi `statuses.in_review` không đặt, và một PR liên kết được mở, mở lại hoặc chuyển sang ready for review, hệ thống SHALL chuyển các task liên kết đang mở có trạng thái New hoặc chưa có trạng thái sang In progress. Khi PR được merge, hệ thống SHALL chuyển các task liên kết sang Done và đóng chúng với lý do hoàn thành nếu còn mở. PR đóng mà không merge MUST NOT đổi trạng thái task.

#### Scenario: Mở PR
- **WHEN** PR với "Closes #1" được mở và task #1 đang `status: New`
- **THEN** task #1 chuyển sang `status: In progress`

#### Scenario: Merge PR
- **WHEN** PR với "Closes #1" được merge
- **THEN** task #1 có `status: Done` và đã đóng với lý do hoàn thành

#### Scenario: Merge vào branch không phải mặc định
- **WHEN** PR với "Closes #1" được merge vào một branch khác branch mặc định
- **THEN** task #1 vẫn được chuyển sang Done và đóng

#### Scenario: Không lùi trạng thái
- **WHEN** PR được mở lại cho task #1 đang `status: Done` và đã đóng
- **THEN** trạng thái task #1 không đổi

#### Scenario: Đóng PR không merge
- **WHEN** PR với "Closes #1" bị đóng mà không merge
- **THEN** trạng thái task #1 giữ nguyên

## ADDED Requirements

### Requirement: Vòng đời PR khi bật In review
Khi `statuses.in_review` đặt, hệ thống SHALL chuyển task liên kết đang mở theo PR: PR nháp được mở, mở lại hoặc chuyển về nháp → In progress (từ New hoặc In review); PR không nháp được mở, mở lại, hoặc chuyển sang sẵn sàng review → In review (từ New hoặc In progress); PR đóng không merge → In progress (chỉ từ In review); PR merge → Done và đóng task. Task đã Done MUST NOT bị lùi trạng thái.

#### Scenario: Mở PR nháp
- **WHEN** PR nháp với "Closes #1" được mở và #1 đang New
- **THEN** #1 chuyển sang In progress

#### Scenario: PR sẵn sàng review
- **WHEN** PR nháp của #1 chuyển sang sẵn sàng review
- **THEN** #1 chuyển sang In review

#### Scenario: Mở PR không nháp
- **WHEN** PR không nháp với "Closes #1" được mở và #1 đang New
- **THEN** #1 chuyển sang In review

#### Scenario: Chuyển về nháp
- **WHEN** PR của #1 đang In review được chuyển về nháp
- **THEN** #1 về In progress

#### Scenario: Đóng không merge
- **WHEN** PR của #1 đang In review bị đóng không merge
- **THEN** #1 về In progress

#### Scenario: Merge
- **WHEN** PR của #1 đang In review được merge
- **THEN** #1 có `status: Done` và đóng với lý do hoàn thành
