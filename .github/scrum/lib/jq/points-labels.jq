# New label set for an estimate. Input: the issue. --argjson cfg CONFIG --argjson points N
# Output: {labels, changed} or {error}.
include "scrum";

if ($cfg.points.scale | index($points)) == null then
  {error: "\($points) is not in the point scale (\($cfg.points.scale | map(tostring) | join(", ")))"}
else
  label_names as $cur
  | ([$cur[] | select(startswith($cfg.points.label_prefix) | not)] + [points_label($cfg; $points)]) as $new
  | {labels: $new, changed: (($new | sort) != ($cur | sort))}
end
