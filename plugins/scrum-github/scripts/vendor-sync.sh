#!/usr/bin/env bash
# vendor-sync.sh [SRC] [--ref REF]
# Copy the skills listed in ITEMS (MIT) verbatim from mattpocock/skills into vendor/pocock/
# of this plugin, and write UPSTREAM.md with the commit they came from.
#   SRC        a local clone of https://github.com/mattpocock/skills. Without it, the script
#              clones VENDOR_UPSTREAM_URL into a temporary directory and removes it afterwards.
#   --ref REF  branch or tag to clone (only without SRC).
# Developer tool: not copied into target repos. Re-run to pick up upstream changes, then
# review `git diff vendor/`. A re-run with an unchanged source changes nothing (the sync date
# is kept).
# Environment: VENDOR_UPSTREAM_URL overrides the repository to clone; VENDOR_SYNC_DATE
# (YYYY-MM-DD) overrides today's date; VENDOR_DEST overrides the destination (tests).
set -euo pipefail

UPSTREAM_WEB="https://github.com/mattpocock/skills"
UPSTREAM_URL="${VENDOR_UPSTREAM_URL:-$UPSTREAM_WEB.git}"

# "destination <- upstream path", one per line. A path is a directory (copied whole) or a
# single file. This list is the whole content of vendor/pocock/: anything else there is removed.
ITEMS="grilling skills/productivity/grilling
to-questionnaire skills/productivity/to-questionnaire
to-spec skills/engineering/to-spec
to-tickets skills/engineering/to-tickets
domain-modeling skills/engineering/domain-modeling
pr skills/engineering/pr
wizard skills/engineering/wizard
triage/AGENT-BRIEF.md skills/engineering/triage/AGENT-BRIEF.md"

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${VENDOR_DEST:-$PLUGIN_DIR/vendor/pocock}"

die() { printf 'vendor-sync: error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'vendor-sync: warning: %s\n' "$*" >&2; }

src=""; ref=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) [ $# -ge 2 ] || die "--ref needs a value"; ref="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [ -z "$src" ] || die "usage: scripts/vendor-sync.sh [SRC] [--ref REF]"; src="$1"; shift ;;
  esac
done
command -v git >/dev/null 2>&1 || die "git is required"

tmp=""
cleanup() { if [ -n "$tmp" ]; then rm -rf "$tmp"; fi; }
trap cleanup EXIT

if [ -n "$src" ]; then
  [ -z "$ref" ] || die "--ref is only for cloning; check out $ref in $src yourself"
  [ -d "$src" ] || die "$src is not a directory"
  src="$(cd "$src" && pwd)"
else
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/vendor-sync.XXXXXX")"
  if [ -n "$ref" ]; then
    git clone -q --depth 1 --branch "$ref" "$UPSTREAM_URL" "$tmp/skills" || die "could not clone $UPSTREAM_URL at $ref"
  else
    git clone -q --depth 1 "$UPSTREAM_URL" "$tmp/skills" || die "could not clone $UPSTREAM_URL"
  fi
  src="$tmp/skills"
fi

# Check the whole source before writing anything.
commit="$(git -C "$src" rev-parse --verify -q HEAD 2>/dev/null)" \
  || die "$src is not a git repository with a commit (expected a clone of $UPSTREAM_WEB)"
[ "$(cd "$(git -C "$src" rev-parse --show-toplevel)" && pwd -P)" = "$(cd "$src" && pwd -P)" ] \
  || die "$src is not the root of a git repository (expected a clone of $UPSTREAM_WEB)"
[ -d "$src/skills" ] || die "$src has no skills/ directory (expected a clone of $UPSTREAM_WEB)"
[ -f "$src/LICENSE" ] || die "$src has no LICENSE"
missing=""
while read -r dest path; do
  [ -e "$src/$path" ] || missing="$missing $path"
done <<EOF
$ITEMS
EOF
[ -z "$missing" ] || die "$src is missing:$missing"
[ -z "$(git -C "$src" status --porcelain 2>/dev/null)" ] \
  || warn "$src has uncommitted changes; the copy will not match commit $commit"

# Remove what the list no longer names, then copy.
mkdir -p "$DEST"
keep=" LICENSE UPSTREAM.md"
while read -r dest path; do keep="$keep ${dest%%/*}"; done <<EOF
$ITEMS
EOF
for entry in "$DEST"/* "$DEST"/.[!.]*; do
  [ -e "$entry" ] || continue
  case " $keep " in *" $(basename "$entry") "*) ;; *) rm -rf "$entry" ;; esac
done
while read -r dest path; do rm -rf "${DEST:?}/${dest%%/*}"; done <<EOF
$ITEMS
EOF
while read -r dest path; do
  mkdir -p "$(dirname "$DEST/$dest")"
  if [ -d "$src/$path" ]; then cp -R "$src/$path" "$DEST/$dest"; else cp "$src/$path" "$DEST/$dest"; fi
done <<EOF
$ITEMS
EOF
cp "$src/LICENSE" "$DEST/LICENSE"

render_upstream() { # render_upstream DATE
  printf '# Upstream: mattpocock/skills\n\n'
  printf -- '- Repository: %s\n' "$UPSTREAM_WEB"
  printf -- '- Commit: `%s`\n' "$commit"
  printf -- '- Synced: %s\n' "$1"
  printf -- '- License: MIT, see `LICENSE` (copied verbatim from upstream)\n\n'
  printf 'Vendored verbatim; scrum-github never edits these files. Plugin-specific behavior lives\n'
  printf 'in the adapter section of the scrum-github skills that load them. Re-sync with\n'
  printf '`scripts/vendor-sync.sh [path to a clone of the repository]` and review `git diff vendor/`.\n\n'
  printf '## Skills\n\n'
  local dest path
  while read -r dest path; do printf -- '- `%s` <- `%s`\n' "$dest" "$path"; done <<EOF
$ITEMS
EOF
}

today="${VENDOR_SYNC_DATE:-$(date +%Y-%m-%d)}"
new="$(render_upstream "$today")"
if [ -f "$DEST/UPSTREAM.md" ]; then
  old="$(cat "$DEST/UPSTREAM.md")"
  old_date="$(printf '%s\n' "$old" | sed -n 's/^- Synced: //p' | head -1)"
  # Same commit and list as last time: keep the earlier sync date so a re-run changes nothing.
  if [ -n "$old_date" ] && [ "$(render_upstream "$old_date")" = "$old" ]; then new="$old"; fi
fi
printf '%s\n' "$new" > "$DEST/UPSTREAM.md"
printf 'Synced %s item(s) from %s (commit %s) into %s\n' \
  "$(printf '%s\n' "$ITEMS" | wc -l | tr -d ' ')" "$src" "$commit" "$DEST"
