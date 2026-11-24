# -n --argjson cfg CONFIG --argjson existing LABELS
# Output: {create, update, unchanged, obsolete}. Never deletes anything.
include "scrum";
def norm: ascii_downcase;
def col: ltrimstr("#") | ascii_downcase;
{ new: {color: "d4c5f9", description: "Task not started"},
  in_progress: {color: "fbca04", description: "Task being worked on"},
  in_review: {color: "1d76db", description: "Task waiting for review"},
  done: {color: "0e8a16", description: "Task finished"} } as $look
| [ (roles($cfg)[] as $r | {name: status_label($cfg; $r)} + $look[$r]),
  ($cfg.points.scale[] | {name: points_label($cfg; .), color: "bfdadc", description: "Story points: \(.)"}),
  {name: $cfg.labels.bug, color: "d73a4a", description: "Something isn't working", keep_existing: true},
  {name: $cfg.labels.feature, color: "a2eeef", description: "Feature broken down into sprint tasks"},
  {name: $cfg.labels.epic, color: "5319e7", description: "Large requirement split into features"},
  {name: $cfg.labels.meta, color: "ededed", description: "Scrum bookkeeping issue, not a task"},
  {name: $cfg.labels.no_task, color: "cfd3d7", description: "Pull request with no linked task"},
  {name: $cfg.labels.ai_ready, color: "8250df", description: "Task ready for an AI agent (/scrum-github:run)"},
  # One location label per long-lived branch below the release branch (design 3); none in trunk.
  (branching($cfg).lower[] | {name: location_label($cfg; .), color: "c5def5", description: "Task merged into \(.), not released yet"})
]
| map(.override = ($cfg.colors[.name] != null) | .color = (($cfg.colors[.name] // .color) | col)) as $want
| ($existing | map({key: (.name | norm), value: .}) | from_entries) as $have
| [ $want[] | . as $w | $have[$w.name | norm] as $h
    | if $h == null then {op: "create", name, color, description}
      elif (.keep_existing and (.override | not)) then {op: "unchanged", name: $h.name}
      elif ($h.color | col) != .color or (($h.description // "") != .description and (.keep_existing | not)) or $h.name != .name then
        {op: "update", current: $h.name, name, color,
         description: (if .keep_existing then ($h.description // .description) else .description end)}
      else {op: "unchanged", name: $h.name} end ] as $ops
| { create: [$ops[] | select(.op == "create") | del(.op)],
    update: [$ops[] | select(.op == "update") | del(.op)],
    unchanged: [$ops[] | select(.op == "unchanged") | .name],
    obsolete: [ $existing[] | .name as $n
                | select(($n | startswith($cfg.points.label_prefix))
                         or ($cfg.statuses.label_prefix != "" and ($n | startswith($cfg.statuses.label_prefix)))
                         or (has_working_branch($cfg) and ($n | startswith(location_prefix($cfg)))))
                | select(any($want[]; (.name | norm) == ($n | norm)) | not) | $n ] }
