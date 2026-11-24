# Input: the output of doctor-report.jq. Output: the report for a person (raw lines).
def title: {tools: "Tools", repo: "Repository and configuration", install: "Installed files", governance: "Branches and governance", board: "Project board"}[.] // .;
def mark: {ok: "ok   ", warn: "warn ", error: "error", skip: "skip ", info: "info "}[.] // .;
( .checks | group_by(.group) | sort_by(.[0].group as $g | ["tools", "repo", "install", "governance", "board"] | index($g) // 99)
  | .[] | ( (.[0].group | title),
            (.[] | "  \(.status | mark)  \(if .status == "skip" then "\(.id): not checked, " else "" end)\(.message)", (if .fix then "         fix: \(.fix)" else empty end)),
            "" ) ),
( if .errors == 0 and .warnings == 0 then "Everything looks fine."
  else "\(.errors) error\(if .errors == 1 then "" else "s" end), \(.warnings) warning\(if .warnings == 1 then "" else "s" end)."
       + (if .errors > 0 then " Fix the errors first; each line above says how." else "" end) end )
