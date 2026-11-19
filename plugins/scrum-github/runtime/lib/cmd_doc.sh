# shellcheck shell=bash
# scrum doc check FILE [--type brief|context]  (design 15)
# Checks the required sections of a brief or of the project context (share/doc-sections.json),
# and the scan stamp of the project context. Offline; reads only FILE.

doc_type_of() { # doc_type_of FILE -> brief | context | empty
  case "$(basename "$1")" in
    brief*.md|*-brief.md) printf brief ;;
    *context*.md) printf context ;;
  esac
}

cmd_doc_check() {
  local file="" type=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --type) type="${2:-}"; shift ;;
      -*) die "unknown option for doc check: $1" ;;
      *) file="$1" ;;
    esac
    shift
  done
  [ -n "$file" ] || die "usage: scrum doc check FILE [--type brief|context]"
  [ -f "$file" ] || die "no file at $file"
  require_tools nogh
  [ -n "$type" ] || type="$(doc_type_of "$file")"
  case "$type" in
    brief|context) ;;
    "") die "cannot tell the kind of $file from its name. Pass --type brief or --type context" ;;
    *) die "unknown document type \"$type\". Use --type brief or --type context" ;;
  esac
  local result
  result="$(jqlib doc-check -n --rawfile text "$file" --argjson spec "$(jq -c --arg t "$type" '.[$t]' "$SHARE_DIR/doc-sections.json")")"
  if [ "$(printf '%s' "$result" | jq -r .ok)" = true ]; then
    info "$file: every required section of a $type is present$(printf '%s' "$result" | jq -r 'if .stamp then " (scanned at \(.stamp.sha[0:7]) on \(.stamp.date))" else "" end')."
  else
    printf 'scrum: error: %s is not a complete %s:\n' "$file" "$type" >&2
    printf '%s' "$result" | jq -r '.errors[]' | sed 's/^/  - /' >&2
    exit 1
  fi
}
