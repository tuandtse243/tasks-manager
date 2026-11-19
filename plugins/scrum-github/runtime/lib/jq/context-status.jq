# -n --argjson in {file, exists, stamp: {sha, date}|null, head, reachable: bool, count: N|null,
#                  changed: [paths], threshold: N}
# Output: status of the project context (spec project-context: Trạng thái tài liệu ngữ cảnh).
$in as $s
| if ($s.exists | not) then
    {file: $s.file, exists: false, sha: null, date: null, head: $s.head, commits_behind: null,
     changed_dirs: [], stale: false, unknown: false, threshold: $s.threshold}
  elif $s.stamp == null or ($s.reachable | not) or $s.count == null then
    {file: $s.file, exists: true, sha: ($s.stamp.sha // null), date: ($s.stamp.date // null), head: $s.head,
     commits_behind: null, changed_dirs: [], stale: false, unknown: true, threshold: $s.threshold,
     reason: (if $s.stamp == null then "the document has no scan stamp" else "the stamped commit is not in the history of HEAD" end)}
  else
    {file: $s.file, exists: true, sha: $s.stamp.sha, date: $s.stamp.date, head: $s.head,
     commits_behind: $s.count,
     changed_dirs: ([$s.changed[] | select(. != $s.file) | if test("/") then split("/")[0] else "." end] | unique),
     stale: ($s.count > $s.threshold), unknown: false, threshold: $s.threshold}
  end
