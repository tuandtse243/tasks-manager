# Which tasks a run works, in which waves (spec ai-run "Chọn task để chạy", "Chia đợt và xem
# trước"; design 3). Pure: no network.
# -n --argjson cfg CONFIG --arg login LOGIN
#    --argjson issues [issues]: without numbers, the open issues assigned to LOGIN (like scrum
#                     mine); with numbers, the issue of each number, or {number, _unreadable: true}
#    --argjson sprint MILESTONE|null (the open sprint)
#    --argjson blocked {"N": [open blocking numbers] | null (not read)}; a number missing = not read
#    --argjson numbers [N...] | null (null: the default choice)
# Output: {login, sprint: {number, title}|null, mode: "default"|"numbers",
#          candidates: [numbers that pass every check but the blockers],
#          tasks: [{number, title, wave, deps (blocking tasks of the run), points, estimate, role, assignees}],
#          waves: [[numbers]], excluded: [{number, title, reason}],
#          eta: {work_minutes, review_minutes, estimated, missing, missing_numbers, waves}}
# The default choice: open tasks assigned to LOGIN in the open sprint, status New, labelled
# labels.ai_ready. A task blocked by an open task outside the run is left out with the reason,
# and so, in turn, is what it blocks.
include "scrum";

($cfg.labels.ai_ready) as $ai
| ($sprint.number // null) as $cur
| ($numbers != null) as $explicit
| def brief: {number, title: (.title // null)};
  def reason_not_runnable:
    if ._unreadable then "could not be read from GitHub"
    elif is_pr then "is a pull request, not a task"
    elif .state != "open" then "is closed"
    elif (is_task($cfg) | not) then "is a feature, epic or meta issue, not a task"
    elif task_role($cfg) == "done" then "is already \($cfg.statuses.done)"
    elif task_role($cfg) == "in_review" then "is already \($cfg.statuses.in_review)"
    else null end;

  ( if $explicit then
      [ ($numbers | reduce .[] as $n ([]; if index($n) then . else . + [$n] end))[] as $n
        | ([$issues[] | select(.number == $n)] | .[0] // {number: $n, _unreadable: true}) ]
      | {cand: [.[] | select(reason_not_runnable == null)],
         out: [.[] | reason_not_runnable as $r | select($r != null) | brief + {reason: $r}]}
    else
      [ $issues[] | select(.state == "open" and is_task($cfg))
        | select(any(.assignees[]?; same_login(.login; $login)))
        | select($cur != null and (.milestone.number // null) == $cur and task_role($cfg) == "new") ]
      | {cand: [.[] | select(has_label_ci($ai))],
         out: [.[] | select(has_label_ci($ai) | not) | brief + {reason: "has no \($ai) label"}]}
    end ) as $first

# Blockers: drop, until nothing changes, every task that an open task outside the run blocks.
| ($first.cand | sort_by(.number)) as $cand
| (reduce range(0; ($cand | length) + 1) as $_
     ({keep: [$cand[].number], out: []};
      . as $s
      | reduce $cand[] as $t ($s;
          ($t.number | tostring) as $k
          | if (.keep | index($t.number)) == null then .
            elif ($blocked | has($k) | not) or $blocked[$k] == null then
              .keep -= [$t.number] | .out += [$t | brief + {reason: "what blocks it could not be read from GitHub"}]
            else
              ([$blocked[$k][] | select(. as $b | ($s.keep | index($b)) == null)]) as $outside
              | if ($outside | length) > 0 then
                  .keep -= [$t.number]
                  | .out += [$t | brief + {reason: "blocked by \($outside | map("#\(.)") | join(", ")), which is open and not in this run", blocked_by: $outside}]
                else . end
            end))
  ) as $sel
| [$cand[] | select(. as $t | $sel.keep | index($t.number))] as $chosen
| ([$chosen[].number]) as $set
| ([$chosen[] | {number, deps: [($blocked[.number | tostring] // [])[] | select(. as $b | $set | index($b))]}] | wave_map) as $wave
| [ $chosen[] | {number, title, wave: $wave[.number | tostring],
                 deps: [($blocked[.number | tostring] // [])[] | select(. as $b | $set | index($b))],
                 points: task_points($cfg),
                 estimate: issue_estimate, role: task_role($cfg), assignees: assignee_logins} ]
  | sort_by(.wave, .number) as $tasks
| ($tasks | eta_by_waves($cfg.planning.merge_minutes // 5)) as $eta
| { login: $login,
    sprint: (if $sprint == null then null else {number: $sprint.number, title: $sprint.title} end),
    mode: (if $explicit then "numbers" else "default" end),
    candidates: [$cand[].number],
    tasks: $tasks,
    waves: [$tasks | group_by(.wave)[] | map(.number)],
    excluded: (($first.out + $sel.out) | sort_by(.number)),
    eta: { work_minutes: $eta.work_minutes, review_minutes: $eta.review_minutes,
           estimated: $eta.estimated,
           missing: (($tasks | length) - $eta.estimated),
           missing_numbers: [$tasks[] | select(.estimate == null) | .number],
           waves: ($tasks | map(.wave) | unique | length) } }
