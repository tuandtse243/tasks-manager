# Spec Delta

## ADDED Requirements

### Requirement: Task sẵn sàng cho agent
Task trong plan SHALL có thể có `ai_ready` là `true` hoặc `false`. `plan validate` MUST báo lỗi với giá trị khác. Khi áp plan, task có `ai_ready: true` SHALL được tạo với label `labels.ai_ready`. Với `--update`, label này SHALL được thêm hoặc gỡ cho khớp plan trên issue đang mở.

#### Scenario: Áp plan
- **WHEN** T1 có `ai_ready: true` và T2 không có trường này
- **THEN** issue của T1 có label `ai-ready` và issue của T2 không có

#### Scenario: Gỡ khi cập nhật
- **WHEN** T1 đã có issue mang `ai-ready`, plan đổi T1 thành `ai_ready: false`, và người dùng chạy `plan apply --update`
- **THEN** issue của T1 không còn label `ai-ready`
