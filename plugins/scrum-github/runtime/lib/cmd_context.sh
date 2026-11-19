# shellcheck shell=bash
# scrum context inventory | status | stamp   (design 15, spec project-context)
# Offline helpers for /scrum-github:project-scan, discover and plan. They read git; only stamp
# writes, and only the scan stamp line of planning.context_file.

context_git_root() {
  local dir
  dir="$(repo_dir)"
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "this command must run inside a git repository (no git repository at $dir)"
  git -C "$dir" rev-parse --show-toplevel
}

cmd_context_inventory() {
  [ $# -eq 0 ] || die "usage: scrum context inventory"
  command -v jq >/dev/null 2>&1 || die "jq is required"
  local root list pkg="null"
  root="$(context_git_root)"
  list="$(mktemp "${TMPDIR:-/tmp}/scrum-files.XXXXXX")"
  git -C "$root" ls-files > "$list"
  if grep -qx 'package.json' "$list" && [ -f "$root/package.json" ]; then
    pkg="$(jq -c . "$root/package.json" 2>/dev/null)" || pkg="null"
  fi
  jqlib context-inventory -n --rawfile files "$list" --argjson pkg "$pkg"
  rm -f "$list"
}

# The stamp of a document: {"sha", "date"} or null.
context_read_stamp() {
  jq -n --rawfile t "$1" '[$t | capture("<!-- scrum:context sha=(?<sha>[0-9a-f]{7,40}) date=(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2}) -->"; "g")] | .[0]'
}

cmd_context_status() {
  [ $# -eq 0 ] || die "usage: scrum context status"
  require_tools nogh
  load_config_or_defaults
  local root rel file head stamp="null" exists=false reachable=false count=null changed="[]" sha
  root="$(context_git_root)"
  rel="$(config_get .planning.context_file)"
  file="$root/$rel"
  head="$(git -C "$root" rev-parse HEAD 2>/dev/null || true)"
  if [ -f "$file" ]; then
    exists=true
    stamp="$(context_read_stamp "$file")"
    sha="$(printf '%s' "$stamp" | jq -r '.sha // empty')"
    if [ -n "$sha" ] && [ -n "$head" ] \
       && git -C "$root" cat-file -e "$sha^{commit}" 2>/dev/null \
       && git -C "$root" merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
      reachable=true
      count="$(git -C "$root" rev-list --count "$sha..HEAD")"
      changed="$(git -C "$root" diff --name-only "$sha" HEAD | jq -R . | jq -sc .)"
    fi
  fi
  jqlib context-status -n --argjson in "$(jq -n --arg file "$rel" --argjson exists "$exists" --argjson stamp "$stamp" \
    --arg head "$head" --argjson reachable "$reachable" --argjson count "$count" --argjson changed "$changed" \
    --argjson threshold "$(config_get .planning.context_stale_commits)" \
    '{file: $file, exists: $exists, stamp: $stamp, head: (if $head == "" then null else $head end),
      reachable: $reachable, count: $count, changed: $changed, threshold: $threshold}')"
}

cmd_context_stamp() {
  [ $# -eq 0 ] || die "usage: scrum context stamp"
  require_tools nogh
  load_config_or_defaults
  local root rel file head stamp
  root="$(context_git_root)"
  rel="$(config_get .planning.context_file)"
  file="$root/$rel"
  [ -f "$file" ] || die "$rel does not exist yet. Write it first (/scrum-github:project-scan)"
  head="$(git -C "$root" rev-parse --short=12 HEAD 2>/dev/null)" || die "the repository has no commit yet"
  stamp="<!-- scrum:context sha=$head date=$(today) -->"
  # Replace the first stamp line and drop any other; with none, insert it after the title line.
  jq -nj --rawfile t "$file" --arg s "$stamp" '
    ($t | endswith("\n")) as $nl
    | ($t | rtrimstr("\n") | split("\n")) as $lines
    | def is_stamp: test("^\\s*<!-- scrum:context sha=[0-9a-f]* date=[0-9-]* -->\\s*$");
      ([$lines | to_entries[] | select(.value | is_stamp) | .key]) as $at
    | (if ($at | length) > 0 then
         [$lines | to_entries[] | if .key == $at[0] then $s elif (.value | is_stamp) then empty else .value end]
       else
         ([$lines | to_entries[] | select(.value | test("^# ")) | .key] | .[0]) as $h
         | if $h == null then [$s, ""] + $lines
           else $lines[:$h + 1] + ["", $s] + $lines[$h + 1:] end
       end)
    | join("\n") + (if $nl then "\n" else "" end)' | write_atomic "$file"
  info "Stamped $rel with $head ($(today))."
}
