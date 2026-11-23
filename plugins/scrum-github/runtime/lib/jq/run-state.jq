# The state of one run (.scrum/run/<id>.json) and how it changes (spec ai-run, design 4). Pure.
# --arg op OP plus the arguments of that op; --argjson strings STRINGS (texts posted on GitHub).
# Input: the state; for op "new", the output of run-select.jq.
# Output: {state, effects} or {error}. effects (what the shell then does on GitHub):
#   {comment: {number, body}|null, to_new: [numbers], dropped: [{number, title, body}]}
#
# State: {version: 1, id, repo, login, branch, base, sprint, created_at, finished_at,
#         max_parallel, pr_per_wave, test_command, waves: [[numbers]], excluded: [{number, title, reason}],
#         tasks: {"N": {number, title, wave, deps, estimate, state, branch, started_at, ended_at,
#                       minutes, reason, notes, merge_commit, conflict_files}},
#         prs: [{wave, number, url, base, head}]}
# Task states: pending -> running -> done -> merged; failed; conflict (merge aborted, may be merged
# again); excluded (blocked by a task that failed or was left out).
#
# ops: new ($id $branch $base $base_sha $now $max_parallel $pr_per_wave $test_command $repo)
#      started ($n $now) | done ($n $now $branch $notes) | failed ($n $now $reason $notes)
#      merged ($n $now $sha) | conflict ($n $now $files $reason) | pr ($wave $pr $now)
#      | wave_closed ($wave $now) | finish ($now) | view
# done and failed take the agent's own started_at and ended_at from $notes when they are valid
# timestamps (ended not before started), so the time does not depend on when the result is recorded.
include "scrum";

def args: $ARGS.named;
def num: args.n | tonumber;
def epoch: if . == null then null else fromdateiso8601 end;
def minutes_between($a; $b): if $a == null or $b == null then null else ((($b | epoch) - ($a | epoch)) / 60 | round) end;
def task_ref($n): .tasks[$n | tostring];
def s: args.strings // {};
def iso_ok: type == "string" and ((try fromdateiso8601 catch null) != null);
# [started, ended] of a task that ends now: the agent's own times when it gave valid ones.
def times($t):
  (args.notes // {}) as $n
  | if ($n | type) == "object" and ($n.started_at | iso_ok) and ($n.ended_at | iso_ok)
       and ($n.ended_at | fromdateiso8601) >= ($n.started_at | fromdateiso8601)
    then [$n.started_at, $n.ended_at] else [$t.started_at, args.now] end;

# Comment with the actual time (spec ai-run "Thời gian thật"): the line, the estimate when there
# is one, and the data in a hidden HTML comment, between scrum:actual markers.
def actual_body($t; $result; $run):
  ($t.minutes) as $m
  | ($t.estimate | clean_estimate) as $e
  | "<!-- scrum:actual -->\n"
    + tr(s; "run_actual"; {d: (if $m == null then tr(s; "run_pr_unknown") else $m | fmt_duration end), result: tr(s; "run_result_\($result)")})
    + (if $e == null then "" else "\n" + tr(s; "run_actual_estimate"; {e: estimate_line($e; s)}) end)
    + "\n<!-- " + ({minutes: $m, result: $result, run: $run, started_at: $t.started_at, ended_at: $t.ended_at} | tojson) + " -->"
    + "\n<!-- /scrum:actual -->";

def no_effects: {comment: null, to_new: [], dropped: []};

# Tasks pending or running that a failed or left-out task blocks, directly or not, become excluded.
def drop_dependents:
  . as $st
  | reduce range(0; (.tasks | length) + 1) as $_ ({st: $st, dropped: []};
      .st as $cur
      | reduce ($cur.tasks[] | select(.state == "pending" or .state == "running")) as $t (.;
          [$t.deps[] | select($cur.tasks[tostring].state as $d | $d == "failed" or $d == "excluded")] as $bad
          | if ($bad | length) == 0 then .
            else .st.tasks[$t.number | tostring] += {state: "excluded",
                   reason: "blocked by \($bad | map("#\(.)") | join(", ")), which \(if ($bad | length) == 1 then "was" else "were" end) not finished"}
                 | .dropped += [{number: $t.number, title: $t.title, blockers: $bad}]
            end));

def check_state($t; $allowed; $what):
  if $t == null then {error: "#\(args.n) is not a task of run \(.id)"}
  elif ($allowed | index($t.state)) == null then {error: "#\($t.number) is \($t.state); it cannot be \($what)"}
  else null end;

if args.op == "new" then
  . as $sel
  | { state: {
        version: 1, id: args.id, repo: args.repo, login: $sel.login, branch: args.branch, base: args.base,
        base_sha: (args.base_sha // null),
        sprint: $sel.sprint, created_at: args.now, finished_at: null, waves_closed: [],
        max_parallel: (args.max_parallel | tonumber), pr_per_wave: (args.pr_per_wave == "true"),
        test_command: (args.test_command // ""),
        waves: $sel.waves, excluded: $sel.excluded,
        tasks: ([$sel.tasks[] | {key: (.number | tostring), value: {
                   number, title, wave, deps: (.deps // []), estimate, state: "pending", branch: null,
                   started_at: null, ended_at: null, minutes: null, reason: null, notes: null,
                   merge_commit: null, conflict_files: []}}] | from_entries),
        prs: [] },
      effects: no_effects }

elif args.op == "started" then
  task_ref(num) as $t
  | (check_state($t; ["pending", "running"]; "started")) as $err
  | if $err then $err
    else .tasks[num | tostring] += {state: "running", started_at: args.now, ended_at: null, minutes: null, reason: null}
         | {state: ., effects: no_effects} end

elif args.op == "done" then
  task_ref(num) as $t
  | (check_state($t; ["pending", "running"]; "recorded as done")) as $err
  | if $err then $err
    else .id as $run
      | times($t) as $tm
      | .tasks[num | tostring] += {state: "done", branch: args.branch, started_at: $tm[0], ended_at: $tm[1],
                                   minutes: minutes_between($tm[0]; $tm[1]), reason: null,
                                   notes: (args.notes // null)}
      | . as $st
      | {state: $st, effects: (no_effects + {comment: {number: num, body: actual_body($st.tasks[num | tostring]; "done"; $run)}})} end

elif args.op == "failed" then
  task_ref(num) as $t
  | (check_state($t; ["pending", "running", "done", "conflict"]; "recorded as failed")) as $err
  | if $err then $err
    else .id as $run
      | (if $t.state == "pending" or $t.state == "running" then times($t) else [$t.started_at, $t.ended_at] end) as $tm
      | .tasks[num | tostring] += {state: "failed", started_at: $tm[0], ended_at: $tm[1],
                                   minutes: minutes_between($tm[0]; $tm[1]),
                                   reason: args.reason,
                                   notes: (args.notes // $t.notes)}
      | . as $st
      | ($st | drop_dependents) as $d
      | ($st.tasks[num | tostring]) as $ft
      | {state: $d.st,
         effects: {comment: {number: num,
                             body: (tr(s; "run_failed_comment"; {run: $run, reason: args.reason, status: (args.status_new // "New")})
                                    + "\n\n" + actual_body($ft; "failed"; $run))},
                   to_new: [num],
                   dropped: [$d.dropped[] | {number, title,
                             body: tr(s; "run_dropped_comment"; {run: $run, blockers: (.blockers | map("#\(.)") | join(", ")), status: (args.status_new // "New")})}]}} end

elif args.op == "merged" then
  task_ref(num) as $t
  | (check_state($t; ["done", "conflict"]; "merged")) as $err
  | if $err then $err
    else .tasks[num | tostring] += {state: "merged", merge_commit: args.sha, conflict_files: [], reason: null}
         | {state: ., effects: no_effects} end

elif args.op == "conflict" then
  task_ref(num) as $t
  | (check_state($t; ["done", "conflict"]; "merged")) as $err
  | if $err then $err
    else .tasks[num | tostring] += {state: "conflict", conflict_files: (args.files | split("\n") | map(select(. != ""))),
                                    reason: (args.reason // "merge conflict")}
         | {state: ., effects: no_effects} end

elif args.op == "pr" then
  (args.pr | fromjson) as $pr
  | (args.wave | if . == "" or . == null then null else tonumber end) as $w
  | .prs += [$pr + {wave: $w}]
  | (if $w == null then . else .waves_closed = ((.waves_closed // []) + [$w] | unique) end)
  | (if $w == null or $w >= (.waves | length) then .finished_at = args.now else . end)
  | {state: ., effects: no_effects}

elif args.op == "wave_closed" then
  # --pr-per-wave: a wave with nothing merged is closed without a pull request.
  (args.wave | tonumber) as $w
  | .waves_closed = ((.waves_closed // []) + [$w] | unique)
  | (if $w >= (.waves | length) then .finished_at = args.now else . end)
  | {state: ., effects: no_effects}

elif args.op == "finish" then
  .finished_at = args.now | {state: ., effects: no_effects}

elif args.op == "view" then
  # For status and the skill: each wave with its tasks, the first wave not settled, and counts.
  . as $st
  | ([.tasks[]] | sort_by(.wave, .number)) as $all
  | def settled: .state == "merged" or .state == "failed" or .state == "excluded";
    { id, branch, base, sprint, finished: (.finished_at != null), pr_per_wave, max_parallel, test_command,
      waves: [$all | group_by(.wave)[] | {wave: .[0].wave,
               to_run: [.[] | select(.state == "pending" or .state == "running") | .number],
               to_merge: [.[] | select(.state == "done" or .state == "conflict") | .number],
               tasks: map({number, title, state, branch, minutes, reason, conflict_files})}],
      next_wave: ([$all[] | select(settled | not) | .wave] | min),
      # --pr-per-wave: settled waves whose pull request is not opened yet (scrum run finish --wave W),
      # to do before the next wave starts.
      pr_due: (if .pr_per_wave | not then []
               else [range(1; (.waves | length) + 1) as $w
                     | select(($st.waves_closed // []) | index($w) | not)
                     | select(all($all[] | select(.wave == $w); settled)) | $w] end),
      counts: ($all | group_by(.state) | map({key: .[0].state, value: length}) | from_entries),
      excluded: $st.excluded, prs: $st.prs }
else
  {error: "unknown op \(args.op)"}
end
