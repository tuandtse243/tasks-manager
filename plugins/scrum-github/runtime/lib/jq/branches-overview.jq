# The pure steps of scrum branches and scrum cleanup (cmd_branch.sh, spec branch-collaboration).
#
#   --arg step stale  Input: [{branch, date, author}] of the branches of origin.
#     --argjson cfg CONFIG --arg today YYYY-MM-DD
#     The task branches (not long-lived) whose last commit is at least branching.stale_days
#     working days old, oldest first: [{branch, last_commit, author, working_days}].
#
#   --arg step text  Input: the overview of scrum branches --json. The text to print.
#
#   --arg step cleanup  Input: {locals: [{name, sha}], remotes: [{name, sha}],
#       contained_local: {long-lived: [names]}, contained_remote: {...},
#       merged: [{head, sha, number}], open_heads: [names], long_lived: [names], current}
#     A branch side (local or on origin) is deletable when it is contained in a long-lived
#     branch, or its tip is the head of a merged pull request (a squash merge). Long-lived
#     branches, the current branch and branches with an open pull request are never listed.
#     [{branch, local, remote, reason: "contained" | "merged", into, pr}]
#
#   --arg step cleanup_text  Input: the list of the cleanup step. The text to print.
include "scrum";
($ARGS.named.step // "") as $step

| def prs($l): if $l == null then ["  (could not be read)"]
                elif ($l | length) == 0 then ["  none"]
                else [$l[] | "  #\(.number) \(.head) → \(.base)  \(.title)"] end;
  def commits($n): if $n == null then "? commits" elif $n == 1 then "1 commit" else "\($n) commits" end;

if $step == "stale" then
  ($ARGS.named.cfg) as $cfg
  | ($ARGS.named.today) as $today
  | ($cfg.branching.stale_days // 5) as $days
  | [ .[] | select(is_long_lived($cfg; .branch) | not) | select(.date | is_date)
      | . + {working_days: (if .date >= $today then 0 else working_days_between($cfg; (.date | add_days(1)); $today) end)}
      | select(.working_days >= $days)
      | {branch, last_commit: .date, author, working_days} ]
  | sort_by(.last_commit, .branch)

elif $step == "text" then
  . as $o
  | ( if $o.preset == "trunk" then
        ["Preset trunk: \($o.release) only.", "", "Open pull requests"] + prs($o.pull_requests.open)
      else
        ["Preset \($o.preset): \($o.chain | join(" → "))."]
        + ([ $o.pairs[]
             | "", "\(.lower) → \(.upper): \(commits(.commits)) and \(.tasks | length) task\(if (.tasks | length) == 1 then "" else "s" end) on \(.lower) that \(.upper) lacks"
             , (.tasks[] | "  #\(.number) \(.title)")
             , (if (.unknown | length) > 0 then "  not checked (GitHub did not say): \(.unknown | map("#\(.)") | join(", "))" else empty end)
             , (if .truncated then "  only the first tasks were checked; the list may be incomplete" else empty end) ])
        + ["", "Drift (commits of \($o.release) a lower branch lacks)"]
        + [ $o.drift[]
            | if .missing_commits == 0 then "  \(.branch) has every commit of \($o.release)."
              else "  \(.branch) lacks \(commits(.missing_commits)) of \($o.release). Back-merge: "
                   + (if .back_merge == null then "could not be read"
                      elif (.back_merge | length) == 0 then "none open"
                      else (.back_merge | map("#\(.number) \(.html_url // "")") | join(", ")) end)
              end ]
        + ["", "Open release and hotfix pull requests"] + prs($o.pull_requests.release)
        + (if $o.chain | length > 2 then ["", "Open promotion pull requests"] + prs($o.pull_requests.promotion) else [] end)
        + ["", "Open back-merge pull requests"] + prs($o.pull_requests.back_merge)
      end )
    + ["", "Stale task branches (no commit for \($o.stale_days) working days)"]
    + (if ($o.stale | length) == 0 then ["  none"]
       else [$o.stale[] | "  \(.branch)  \(.working_days) working days, last commit \(.last_commit) by \(.author)"] end)
  | join("\n")

elif $step == "cleanup" then
  . as $in
  | ($in.long_lived + (if $in.current == "" then [] else [$in.current] end) + $in.open_heads) as $keep
  | def why($name; $sha; $contained):
      ([$contained | to_entries[] | select(.value | index($name)) | .key][0]) as $into
      | ([$in.merged[] | select(.head == $name and .sha == $sha) | .number] | max) as $pr
      | if $into != null then {reason: "contained", into: $into, pr: null}
        elif $pr != null then {reason: "merged", into: null, pr: $pr}
        else null end;
    ([$in.locals[] | select(.name as $n | $keep | index($n) | not)
      | why(.name; .sha; $in.contained_local) as $w | select($w != null) | {branch: .name, side: "local"} + $w]
     + [$in.remotes[] | select(.name as $n | $keep | index($n) | not)
      | why(.name; .sha; $in.contained_remote) as $w | select($w != null) | {branch: .name, side: "remote"} + $w])
  | group_by(.branch)
  | map( (map(select(.reason == "contained"))[0] // .[0]) as $w
         | {branch: .[0].branch, local: any(.[]; .side == "local"), remote: any(.[]; .side == "remote"),
            reason: $w.reason, into: $w.into, pr: $w.pr} )

elif $step == "cleanup_text" then
  ["Branches already merged (\(length)):"]
  + [ .[] | "  \(.branch)  \([if .local then "local" else empty end, if .remote then "origin" else empty end] | join(" and "))  "
            + (if .reason == "contained" then "contained in \(.into)" else "pull request #\(.pr) merged" end) ]
  | join("\n")

else error("unknown step \($step)") end
