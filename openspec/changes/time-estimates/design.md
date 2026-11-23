# Design

Đường dẫn tính từ `plugins/scrum-github/`. Change này nằm trên `team-and-backlog-tasks`: `team.jq`, `mine.jq`, `plan_waves`, dữ liệu và template `plan.html` đã có.

## Context

`scrum.jq` đã có cơ chế khối của plugin trong thân issue: `set_scrum_block`, `scrum_blocks`, `strip_scrum_blocks`, với dạng `<!-- scrum:NAME -->…<!-- /scrum:NAME -->`. `task_issue_body` dựng thân issue từ task của plan. Points nằm trên label và được đọc qua `._pts` trong `report_tasks`.

## Goals / Non-Goals

**Goals:** một nơi duy nhất đọc và ghi ước lượng (jq), dùng chung cho plan, task, mine, status, fill.

**Non-Goals:** field thời gian trên Project board; đổi burndown hay velocity sang thời gian; đo thời gian thật.

## Decisions

### 1. Khối `estimate` trong thân issue

Nội dung khối:

```
AI ~25m · Review ~20m
<!-- {"work_minutes":25,"review_minutes":20,"by":"ai"} -->
```

Dòng đầu cho người đọc. Nhãn "AI" hoặc "Human" theo `by`, chữ theo `language`. Dòng JSON nằm trong comment HTML nên không hiện trên GitHub. `scrum.jq` có thêm `issue_estimate` (đọc từ `.body`; trả `null` khi thiếu hoặc hỏng) và `estimate_block($e; $strings)`. `report_tasks` gắn thêm `._est` để mọi báo cáo dùng chung.

Phương án khác: label `ai: 25m`. Bị loại vì mỗi giá trị phút thành một label riêng. Field trên board: board là tuỳ chọn, để sau.

### 2. Thời lượng

Hàm `parse_duration` trong jq (regex `^([0-9]+h)?([0-9]+m?)?$`, phải có ít nhất một phần, kết quả lớn hơn 0) dùng cho các cờ CLI. Hàm `fmt_duration` in `25m`, `1h30m`.

### 3. Ghi khi tạo, đổi

- `task-payload.jq`: khi task có `estimate`, thân issue gọi `set_scrum_block("estimate"; …)`.
- `task estimate`: đọc issue, gộp các trường mới vào ước lượng cũ, PATCH thân issue bằng `set_scrum_block`. Đổi điểm vẫn dùng `points-labels.jq`.
- `plan apply --update`: so khối hiện có với plan, chỉ PATCH khi khác.

### 4. Ước tính theo đợt: một hàm

`eta_by_waves($tasks; $merge)`: với các task có `wave` và `estimate`, cộng max `work_minutes` mỗi đợt cộng `$merge` cho mỗi đợt có ít nhất một task có ước lượng. Review bằng tổng `review_minutes`. Hàm dùng cho plan (đợt từ `plan_waves`) và `mine` (đợt từ đồ thị chặn của chính các task). Khớp ví dụ trong spec: ba đợt cộng ba lần merge.

### 5. `plan.html`

Thêm phần dòng thời gian vào template, đúng tỉ lệ (`x = phút × scale`, scale chọn sao cho tổng làm + review vừa chiều rộng), có vạch "bây giờ" chạy qua, tắt khi giảm chuyển động. Thẻ task và KPI có thời gian. Bản mẫu đã duyệt là tham chiếu.

### 6. Cấu hình

`team[].review_hours` (số dương, tuỳ chọn) và `planning.merge_minutes` (số nguyên ≥ 0, mặc định 5) trong `defaults.json` và `validate-config.jq`.

### 7. Skill

`plan` (`reference/planning-rules.md`): khi chia task, ước lượng `estimate` cho từng task. `by: ai` trừ khi task cần người (thiết kế, quyết định sản phẩm, thao tác trên hệ thống thật). `review_minutes` gồm cả test tay. `task-new`, `task`: thêm cờ. `sprint-status`, `sprint-fill`, `my-tasks`: đọc phần thời gian.

## Risks / Trade-offs

- [Người dùng sửa tay khối trên GitHub và làm hỏng JSON] → đọc ra `null`, coi như chưa ước lượng, không dừng lệnh. `task estimate` ghi lại khối sạch.
- [Ước lượng AI sai nhiều] → change 3 đo thời gian thật. Change này chỉ ghi dự đoán.
- [Thân issue dài thêm] → khối chỉ hai dòng, dòng dữ liệu bị ẩn.

## Migration Plan

Không chuyển đổi gì. Task cũ không có khối thì không có thời gian. Phiên bản 0.10.0.
