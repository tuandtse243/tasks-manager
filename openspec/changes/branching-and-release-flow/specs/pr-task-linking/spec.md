# Spec Delta

## MODIFIED Requirements

### Requirement: Vòng đời PR khi bật In review
Khi `statuses.in_review` đặt, hệ thống SHALL chuyển task liên kết đang mở theo PR: PR nháp được mở, mở lại hoặc chuyển về nháp → In progress (từ New hoặc In review); PR không nháp được mở, mở lại, hoặc chuyển sang sẵn sàng review → In review (từ New hoặc In progress); PR đóng không merge → In progress (chỉ từ In review). Khi PR merge: ở preset `trunk` → Done và đóng task; ở preset `standard` và `environments` → theo requirement "Task location after merge". Task đã Done MUST NOT bị lùi trạng thái.

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
- **WHEN** preset là `trunk` và PR của #1 đang In review được merge
- **THEN** #1 có `status: Done` và đóng với lý do hoàn thành

#### Scenario: Merge ở preset standard
- **WHEN** preset là `standard` và PR của #1 được merge vào `develop`
- **THEN** #1 vẫn mở, giữ `status: In review` và có nhãn `on: develop`

### Requirement: Soạn mô tả PR cho task
Lệnh `/task-pr` SHALL soạn mô tả pull request cho task của nhánh hiện tại gồm bốn phần: tóm tắt thay đổi bằng hình thức ngắn nhất làm rõ ý chính, bằng chứng trước và sau, mức nguy hiểm khi merge (đảo ngược được hay không, phạm vi ảnh hưởng), và dòng `Closes #n` của task. Nhánh đích của PR SHALL là nhánh làm việc của preset, hoặc nhánh phát hành khi nhánh hiện tại là `hotfix/*`. Lệnh SHALL đề xuất tiêu đề theo Conventional Commits và MUST đưa mô tả cho người dùng duyệt trước khi tạo hoặc sửa PR.

#### Scenario: Nhánh của một task
- **WHEN** người dùng chạy `/task-pr` trên nhánh `feat/12-binh-luan` có commit so với nhánh đích
- **THEN** mô tả được soạn có đủ bốn phần và chứa "Closes #12", và chưa có PR nào được tạo

#### Scenario: Người dùng duyệt
- **WHEN** người dùng duyệt mô tả
- **THEN** PR được tạo với mô tả đó, và check liên kết task của PR thành công

#### Scenario: PR đã có
- **WHEN** nhánh hiện tại đã có một PR đang mở
- **THEN** lệnh đề nghị sửa mô tả của PR đó thay vì tạo PR mới, và chỉ sửa sau khi người dùng duyệt

#### Scenario: Không xác định được task
- **WHEN** tên nhánh không chứa số task và người dùng không đưa số
- **THEN** lệnh hỏi số task, hoặc đề nghị dùng label `no-task` nếu PR không thuộc task nào

#### Scenario: Không có bằng chứng chạy được
- **WHEN** thay đổi không có test hay kết quả chạy nào để dẫn
- **THEN** phần bằng chứng nói rõ là chưa có, và lệnh không bịa kết quả

#### Scenario: Nhánh chưa có thay đổi
- **WHEN** nhánh hiện tại không có commit nào so với nhánh đích
- **THEN** lệnh báo chưa có gì để mở PR và dừng

#### Scenario: Nhánh đích theo preset
- **WHEN** preset là `standard` và người dùng duyệt mô tả trên nhánh `feat/12-binh-luan`
- **THEN** PR được tạo với nhánh đích `develop` và tiêu đề dạng `feat: …`

#### Scenario: Nhánh chậm so với nhánh đích
- **WHEN** nhánh hiện tại thiếu commit của nhánh đích
- **THEN** lệnh cảnh báo và gợi ý `/scrum-github:sync` trước khi mở PR

## ADDED Requirements

### Requirement: Task location after merge
In `standard` and `environments`, when a linked pull request is merged into the working branch, the system SHALL keep the linked tasks open and In review and give each the location label of that branch (`<branching.location_prefix><branch>`, by default `on: develop`). When a promotion pull request is merged into the staging branch, the tasks it contains SHALL get the staging location label in place of the previous one. A task has at most one location label.

#### Scenario: Merged into the working branch
- **WHEN** the preset is `standard` and a pull request with "Closes #1" is merged into `develop`
- **THEN** #1 is open, `status: In review`, with the label `on: develop`

#### Scenario: Promoted to staging
- **WHEN** the preset is `environments`, #1 is `on: develop` and a pull request from `develop` into `staging` that contains it is merged
- **THEN** #1 has the label `on: staging` and no longer `on: develop`

#### Scenario: Not in the promotion
- **WHEN** #2 was merged into `develop` after the promoted commit
- **THEN** #2 keeps `on: develop`

### Requirement: Done only on the release branch
In `standard` and `environments`, a task SHALL become Done and be closed as completed only when its code is merged into the release branch, through a release or hotfix pull request. A merge into any other branch MUST NOT set Done or close the task.

#### Scenario: Hotfix merged into main
- **WHEN** a pull request from `hotfix/31-payment-fails` with "Closes #31" is merged into `main`
- **THEN** #31 is `status: Done` and closed as completed

#### Scenario: Merged into a task branch
- **WHEN** a pull request with "Closes #1" is merged into another task branch
- **THEN** #1 keeps its status and stays open
