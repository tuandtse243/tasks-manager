# What `scrum plan apply` will do (design 4, 8). Pure: no network.
# Input: a valid plan in version 2 form.
# --argjson cfg CONFIG
# --argjson state {
#     milestones: [...] | null   (null when no sprint is named anywhere)
#     today: "YYYY-MM-DD",
#     subs:    {"<parent issue number>": [child issue numbers]},
#     blocked: {"<issue number>": [issue numbers blocking it]},
#     issues:  {"<issue number>": issue JSON}   (only with --update)
#   }
# --argjson update true|false
# [--argjson strings STRINGS]   (the language of the estimate block's line)
# Output: {errors: [...]} when a sprint cannot be used, otherwise {errors: [], actions: [...]}.
# Order: create_epic, create_feature, create_task (dependency order), skip/update, link_sub, link_blocked.
# Every action has "text" (one line for the user) and "ref" ("epic", a feature id or a task id).
include "scrum";
include "plan";

. as $plan
| ($state.subs // {}) as $subs
| ($state.blocked // {}) as $blocked
| ($state.issues // {}) as $issues
| ($ARGS.named.strings // null) as $strings
| plan_tasks as $tasks

# ---------- sprints ----------
| def sprint_of_plan: ($plan.sprint // "") | tostring;
  def resolve($name):
    if $name == "" then {milestone: null, sprint: "backlog"}
    elif ($name | ascii_downcase) == "current" then
      (($state.milestones // []) | current_sprint($state.today)) as $m
      | if $m == null then {error: "there is no open sprint for \"current\". Create one first (/scrum-github:sprint-new, or scrum sprint new), or leave sprint empty for the backlog"}
        else {milestone: $m.number, sprint: $m.title} end
    else
      ([($state.milestones // [])[] | select((.title | ascii_downcase) == ($name | ascii_downcase))] | .[0]) as $m
      | if $m == null then {error: "no sprint named \"\($name)\""}
        elif $m.state != "open" then {error: "\($m.title) is closed"}
        else {milestone: $m.number, sprint: $m.title} end
    end;

  # Items that will be written (created, or updated with --update) need their sprint resolved.
  def needs_write: .issue == null or $update;
  ( [ (if $plan.epic != null and ($plan.epic | needs_write) then sprint_of_plan else empty end),
      (if any(plan_features[]; needs_write) then sprint_of_plan else empty end),
      ($tasks[] | select(needs_write) | task_sprint($plan)) ] | unique
  ) as $names
| ([$names[] | {key: ., value: resolve(.)}] | from_entries) as $res
| [$res[] | .error // empty] as $errors
| if ($errors | length) > 0 then {errors: $errors} else

# ---------- helpers ----------
  def ms_label($r): $r.sprint;
  def est_text: if . == null then "none"
    else [ (if .work_minutes != null then "work \(.work_minutes | fmt_duration)" else empty end),
           (if .review_minutes != null then "review \(.review_minutes | fmt_duration)" else empty end) ] | join(" + ") end;
  def ref_text($ref; $issue): if $issue == null then "\($ref) (new)" else "\($ref) #\($issue)" end;
  ([plan_features[] as $f | $f.tasks[] | {key: .id, value: $f.id}] | from_entries) as $parent_of
  | ([plan_features[] | {key: .id, value: .issue}] + [$tasks[] | {key: .id, value: .issue}]
     + (if $plan.epic != null then [{key: "epic", value: $plan.epic.issue}] else [] end) | from_entries) as $num
  | ([$tasks[] | {key: .id, value: .title}] | from_entries) as $title_of
  | def has_sub($p; $c): ($num[$p]) as $pn | ($num[$c]) as $cn
      | $pn != null and $cn != null and (($subs["\($pn)"] // []) | index($cn)) != null;
    def has_block($t; $b): ($num[$t]) as $tn | ($num[$b]) as $bn
      | $tn != null and $bn != null and (($blocked["\($tn)"] // []) | index($bn)) != null;

    # Desired state of an existing open issue, compared with GitHub (--update).
    def update_action($ref; $kind; $item; $want_title; $want_body; $want_points; $res):
      $issues["\($item.issue)"] as $cur
      | if $cur == null then {op: "skip", ref: $ref, issue: $item.issue, reason: "unreadable",
                              text: "skip    \(ref_text($ref; $item.issue)): could not read the issue, not updated"}
        elif $cur.state != "open" then {op: "skip", ref: $ref, issue: $item.issue, reason: "closed",
                              text: "skip    \(ref_text($ref; $item.issue)) is closed, not updated"}
        else
          (($cur.body // "") | [scrum_blocks[]] | join("\n\n")) as $blocks
          | ($want_body + (if $blocks == "" then "" else (if $want_body == "" then "" else "\n\n" end) + $blocks end)) as $kept
          # The estimate block follows the plan; it is written only when its data differ, and
          # left as it is when the plan has no estimate (spec work-plan "Cập nhật thời gian").
          | ($item.estimate | clean_estimate) as $want_est
          | ($want_est != null and $kind == "task" and ($cur | issue_estimate) != $want_est) as $est_changed
          | (if $est_changed then $kept | set_estimate($want_est; $strings) else $kept end) as $body
          | ($cur | label_names) as $labels
          | (if $kind == "task" then
               ([$labels[] | select(startswith($cfg.points.label_prefix) | not)]
                + (if $want_points != null then [points_label($cfg; $want_points)] else [] end))
             else $labels end) as $want_labels
          | ($cur.milestone.number // null) as $cur_ms
          | ( {}
              + (if $cur.title != $want_title then {title: $want_title} else {} end)
              + (if ($cur.body // "") != $body then {body: $body} else {} end)
              + (if $cur_ms != $res.milestone then {milestone: $res.milestone} else {} end) ) as $patch
          | (if ($labels | sort) != ($want_labels | sort) then $want_labels else null end) as $set_labels
          | if ($patch | length) == 0 and $set_labels == null then
              {op: "skip", ref: $ref, issue: $item.issue, reason: "up to date",
               text: "skip    \(ref_text($ref; $item.issue)) is up to date"}
            else
              {op: "update", ref: $ref, issue: $item.issue, patch: $patch, labels: $set_labels,
               text: ("update  \(ref_text($ref; $item.issue)): "
                      + ([ (if $patch.title then "title" else empty end),
                           (if $patch.body and ($cur.body // "") != $kept then "body" else empty end),
                           (if $est_changed then "time estimate \(($cur | issue_estimate) | est_text) -> \($want_est | est_text)" else empty end),
                           (if $patch | has("milestone") then "sprint \(($cur.milestone.title // "backlog")) -> \($res.sprint)" else empty end),
                           (if $set_labels then "points \($cur | task_points($cfg) // "none") -> \($want_points // "none")" else empty end)
                         ] | join(", ")))}
            end
        end;

    def existing($ref; $kind; $item; $want_title; $want_body; $want_points; $res):
      if $update then update_action($ref; $kind; $item; $want_title; $want_body; $want_points; $res)
      else {op: "skip", ref: $ref, issue: $item.issue, reason: "exists",
            text: "skip    \(ref_text($ref; $item.issue)) already exists"} end;

    $res[sprint_of_plan] as $plan_res
  | [
      # epic
      (if $plan.epic == null then empty
       elif $plan.epic.issue == null then
         {op: "create_epic", ref: "epic", kind: "epic",
          payload: ({title: $plan.epic.title, body: ($plan.epic.body // ""), labels: [$cfg.labels.epic]}
                    + (if $plan_res.milestone == null then {} else {milestone: $plan_res.milestone} end)),
          text: "create  epic \"\($plan.epic.title)\" (\(ms_label($plan_res)))"}
       else existing("epic"; "epic"; $plan.epic; $plan.epic.title; ($plan.epic.body // ""); null; $plan_res) end),

      # features
      (plan_features[] as $f
       | if $f.issue == null then
           {op: "create_feature", ref: $f.id, kind: "feature",
            payload: ({title: $f.title, body: ($f.body // ""), labels: [$cfg.labels.feature]}
                      + (if $plan_res.milestone == null then {} else {milestone: $plan_res.milestone} end)),
            text: "create  feature \($f.id) \"\($f.title)\" (\(ms_label($plan_res)))"}
         else existing($f.id; "feature"; $f; $f.title; ($f.body // ""); null; $plan_res) end),

      # tasks, dependencies first
      (($tasks | topo_order)[] as $id
       | ($tasks | map(select(.id == $id)) | .[0]) as $t
       | $res[$t | task_sprint($plan)] as $r
       | $parent_of[$id] as $fid
       | if $t.issue == null then
           {op: "create_task", ref: $id, kind: "task", parent: $fid,
            task: ($t | del(.id, .issue, .sprint, .depends_on)), milestone: $r.milestone,
            text: "create  task \($id) \"\($t.title)\" (\(if $t.points == null then "no points" elif $t.points == 1 then "1 point" else "\($t.points) points" end)\(($t.estimate | clean_estimate) as $e | if $e == null then "" else ", \($e | est_text)" end), \(ms_label($r)))"}
         else existing($id; "task"; $t; $t.title; task_issue_body($t; $num[$fid]); $t.points; $r) end),

      # sub-issues: epic -> features, feature -> tasks
      (if $plan.epic == null then empty else
         plan_features[] | select(has_sub("epic"; .id) | not)
         | {op: "link_sub", parent: "epic", child: .id,
            text: "link    \(.id) as sub-issue of \(ref_text("epic"; $plan.epic.issue))"} end),
      (plan_features[] as $f | $f.tasks[] | select(has_sub($f.id; .id) | not)
       | {op: "link_sub", parent: $f.id, child: .id,
          text: "link    \(ref_text(.id; .issue)) as sub-issue of \(ref_text($f.id; $f.issue))"}),

      # dependencies: task blocked by each task it depends on
      ($tasks[] as $t | ($t | deps | unique)[] as $d | select(has_block($t.id; $d) | not)
       | {op: "link_blocked", ref: $t.id, blocker: $d,
          text: "link    \(ref_text($t.id; $t.issue)) blocked by \(ref_text($d; $num[$d]))"})
    ] as $actions
  | {errors: [], actions: $actions}
  end
