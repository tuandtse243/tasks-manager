#!/usr/bin/env bash
# vendor-sync.sh SRC  Copy four mattpocock/skills skills (MIT) verbatim from the vendor/pocock
# directory of the aidw plugin (SRC) into vendor/pocock/ of this plugin, and write UPSTREAM.md.
# Developer tool: not copied into target repos. Re-run after aidw or upstream changes, then
# review `git diff`. A re-run with unchanged sources changes nothing (the sync date is kept).
# Environment: VENDOR_SYNC_DATE (YYYY-MM-DD) overrides today's date; VENDOR_DEST overrides
# the destination (tests).
set -euo pipefail

SKILLS="grilling to-spec domain-modeling to-tickets"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${VENDOR_DEST:-$PLUGIN_DIR/vendor/pocock}"

die() { printf 'vendor-sync: error: %s\n' "$*" >&2; exit 1; }

src="${1:-}"
[ -n "$src" ] || die "usage: scripts/vendor-sync.sh SRC (the vendor/pocock directory of aidw)"
[ -d "$src" ] || die "$src is not a directory"
src="$(cd "$src" && pwd)"

missing=""
for s in $SKILLS; do [ -d "$src/$s" ] || missing="$missing $s"; done
[ -z "$missing" ] || die "$src is missing:$missing"
[ -f "$src/LICENSE" ] || die "$src has no LICENSE"

# Upstream commit and per-skill upstream paths, read from the source's UPSTREAM.md when present.
commit="unknown"; upstream_md=""
if [ -f "$src/UPSTREAM.md" ]; then
  upstream_md="$(cat "$src/UPSTREAM.md")"
  c="$(printf '%s\n' "$upstream_md" | sed -n 's/^- Commit: `\([0-9a-f]*\)`.*/\1/p' | head -1)"
  [ -z "$c" ] || commit="$c"
fi
upstream_path() { # upstream_path SKILL -> skills/.../SKILL or empty
  printf '%s\n' "$upstream_md" | sed -n "s/^- \`$1\` <- \`\\(.*\\)\`.*/\\1/p" | head -1
}

mkdir -p "$DEST"
for s in $SKILLS; do
  rm -rf "${DEST:?}/$s"
  cp -R "$src/$s" "$DEST/$s"
done
cp "$src/LICENSE" "$DEST/LICENSE"

render_upstream() { # render_upstream DATE
  printf '# Upstream: mattpocock/skills\n\n'
  printf -- '- Repository: https://github.com/mattpocock/skills\n'
  printf -- '- Commit: `%s`\n' "$commit"
  printf -- '- Synced: %s\n' "$1"
  printf -- '- License: MIT, see `LICENSE` (copied verbatim from upstream)\n'
  printf -- '- Obtained through: the `aidw` plugin (`%s`)\n\n' "vendor/pocock"
  printf 'Vendored verbatim; scrum-github never edits these files. Plugin-specific behavior lives\n'
  printf 'in the adapter section of the scrum-github skills that load them. Re-sync with\n'
  printf '`scripts/vendor-sync.sh <aidw>/vendor/pocock` and review `git diff`.\n\n'
  printf '## Skills\n\n'
  local s p
  for s in $SKILLS; do
    p="$(upstream_path "$s")"
    if [ -n "$p" ]; then printf -- '- `%s` <- `%s`\n' "$s" "$p"; else printf -- '- `%s`\n' "$s"; fi
  done
}

today="${VENDOR_SYNC_DATE:-$(date +%Y-%m-%d)}"
new="$(render_upstream "$today")"
if [ -f "$DEST/UPSTREAM.md" ]; then
  old="$(cat "$DEST/UPSTREAM.md")"
  old_date="$(printf '%s\n' "$old" | sed -n 's/^- Synced: //p' | head -1)"
  # Same sources as last time: keep the earlier sync date so a re-run changes nothing.
  if [ -n "$old_date" ] && [ "$(render_upstream "$old_date")" = "$old" ]; then new="$old"; fi
fi
printf '%s\n' "$new" > "$DEST/UPSTREAM.md"
printf 'Synced %s from %s (commit %s) into %s\n' "$SKILLS" "$src" "$commit" "$DEST"
