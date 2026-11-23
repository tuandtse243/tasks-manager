# Release notes in Markdown (spec release "Release notes", design 5). Raw output (jq -r).
# -n --argjson plan RELEASE_PLAN (release-plan.jq)
#    --argjson prs {"N": [pull request numbers] | null}   null or missing: not read
#    --argjson parents {"N": "title"}                     titles of the parent features
#    --argjson strings STRINGS_OF_THE_LANGUAGE --arg repo OWNER/NAME
# Groups in order: breaking changes, features (tasks without a parent first, then one heading per
# parent feature), bug fixes; an empty group is left out. Each line: "- Title (#12, PR #40)".
# Text from issues is inserted as it is: GitHub renders the Markdown.
include "scrum";
# "@name" (or "@org/team") in a title would notify that person when the release is published:
# put it in backticks. An e-mail address (a@b.c) is left alone.
def quiet: gsub("(?<![A-Za-z0-9_`])@(?<n>[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:/[A-Za-z0-9_.-]+)?)"; "`@\(.n)`");
def line:
  (($prs[.number | tostring] // []) | map("#\(.)")) as $p
  | "- \(.title | quiet) (#\(.number)\(if ($p | length) > 0 then ", PR " + ($p | join(", ")) else "" end))";
def lines: map(line) | join("\n");
def group($key; $body): "## " + tr($strings; $key) + "\n\n" + $body;

$plan.tasks as $t
| [$t[] | select(.kind == "breaking")] as $breaking
| [$t[] | select(.kind == "feature")] as $features
| [$t[] | select(.kind == "bug")] as $bugs
| ([$features[] | select(.parent == null)]) as $loose
| ([$features[] | select(.parent != null)] | group_by(.parent)) as $by_parent
| [ (if ($breaking | length) > 0 then group("release_breaking"; $breaking | lines) else empty end),
    (if ($features | length) > 0 then
       group("release_features";
         [ (if ($loose | length) > 0 then $loose | lines else empty end),
           ($by_parent[] | (.[0].parent | tostring) as $k
            | "### \($parents[$k] // "#\($k)" | quiet)\n\n" + lines) ] | join("\n\n"))
     else empty end),
    (if ($bugs | length) > 0 then group("release_fixes"; $bugs | lines) else empty end),
    (if $plan.previous != null
     then "**\(tr($strings; "release_full_changelog"))**: https://github.com/\($repo)/compare/\($plan.previous.tag)...\($plan.tag)"
     else empty end)
  ] | join("\n\n")
