# Version files and changelog of a release (spec release-pr "Version files and changelog",
# design 7). Pure text changes; the shell reads the files (contents API or working tree) and
# writes the result. -n with, for the file's text, either --arg content TEXT (or --rawfile
# content FILE) or --arg b64 BASE64 (as the contents API returns it), and:
#
#   --arg step json  --arg content TEXT --arg version X.Y.Z
#     A .json file listed with only a path: its top-level "version" is set.
#     {status: changed | current | missing, object}   (object: the new JSON value, when changed)
#
#   --arg step pattern  --arg content TEXT --arg pattern 'version = "{version}"'
#                       --arg prev X.Y.Z|"" --arg version X.Y.Z
#     The first match of the pattern with the previous version is replaced by the pattern with
#     the new version. Without a previous version (first release) {version} matches any X.Y.Z.
#     {status: changed | current | missing, content}
#     current: the pattern already holds the new version (a run that already wrote it).
#
#   --arg step changelog  --arg content TEXT --arg tag TAG --arg date YYYY-MM-DD --arg notes MD
#     The notes at the top, under "## TAG (DATE)", after a leading "# ..." title line when there
#     is one; the headings of the notes go one level down. {status: changed | current, content}
#     current: the changelog already has the section of TAG.
def esc: gsub("(?<c>[.*+?^${}()|\\[\\]\\\\/])"; "\\\(.c)");
($ARGS.named.step // "") as $step
| (if $ARGS.named.b64 != null then $ARGS.named.b64 | gsub("\\s"; "") | if . == "" then "" else @base64d end
   else $ARGS.named.content // "" end) as $content
| ($ARGS.named.version // "") as $version
| ($ARGS.named.prev // "") as $prev
| ($ARGS.named.pattern // "{version}") as $pattern
| ($ARGS.named.tag // "") as $tag
| ($ARGS.named.date // "") as $date
| ($ARGS.named.notes // "") as $notes
| if $step == "json" then
    ($content | try fromjson catch null) as $j
    | if ($j | type) != "object" or ($j.version | type) != "string" then {status: "missing"}
      elif $j.version == $version then {status: "current"}
      else {status: "changed", object: ($j | .version = $version)} end
  elif $step == "pattern" then
    ($pattern | split("{version}")) as $parts
    | ($parts | map(esc)) as $eparts
    | (if $prev == "" then "[0-9]+\\.[0-9]+\\.[0-9]+" else ($prev | esc) end) as $vre
    | ([$content | match($eparts | join($vre))] | .[0]) as $m
    | ([$content | match($eparts | join($version | esc))] | .[0]) as $now
    | if $m != null and ($prev != $version) then
        {status: "changed",
         content: ($content[0:$m.offset] + ($parts | join($version)) + $content[($m.offset + $m.length):])}
      elif $now != null then {status: "current", content: $content}
      else {status: "missing"} end
  elif $step == "changelog" then
    "## \($tag) (\($date))" as $head
    | if ($content | split("\n") | any(.[]; . == $head or startswith($head + " ") or . == "## \($tag)")) then
        {status: "current", content: $content}
      else
        ($notes | split("\n") | map(if startswith("#") then "#" + . else . end) | join("\n")) as $body
        | "\($head)\n\n\($body | sub("\\s+$"; ""))\n" as $section
        | ($content | split("\n")) as $lines
        | if ($lines[0] // "" | test("^# ")) then
            ($lines[1:] | join("\n") | sub("^\\n+"; "")) as $rest
            | {status: "changed", content: ($lines[0] + "\n\n" + $section + (if $rest == "" then "" else "\n" + $rest end))}
          elif $content == "" then {status: "changed", content: $section}
          else {status: "changed", content: ($section + "\n" + $content)} end
      end
  else error("unknown step \($step)") end
