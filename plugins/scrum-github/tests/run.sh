#!/usr/bin/env bash
# Minimal test runner. Usage: tests/run.sh [test_file_pattern]
# Each tests/test_*.sh defines functions named test_*; every function runs in its own
# subshell with a fresh temporary directory in $T. Runs on Bash 3.2 and later.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SCRUM="$PLUGIN_DIR/runtime/bin/scrum"
FIXTURES="$TESTS_DIR/fixtures"
export TESTS_DIR PLUGIN_DIR SCRUM FIXTURES

pattern="${1:-}"
pass=0; fail=0; failed_names=""

# ---------- assertions ----------
_fail() { printf '    FAIL: %s\n' "$*" >&2; exit 1; }

assert_eq() { # expected actual [message]
  [ "$1" = "$2" ] || _fail "${3:-values differ}"$'\n'"      expected: $1"$'\n'"      actual:   $2"
}
assert_json_eq() { # expected_json actual_json [message]
  local e a
  e="$(printf '%s' "$1" | jq -S . 2>/dev/null)" || _fail "expected is not JSON: $1"
  a="$(printf '%s' "$2" | jq -S . 2>/dev/null)" || _fail "actual is not JSON: $2"
  [ "$e" = "$a" ] || _fail "${3:-JSON differs}"$'\n'"      expected: $(printf '%s' "$e" | jq -c .)"$'\n'"      actual:   $(printf '%s' "$a" | jq -c .)"
}
assert_contains() { # haystack needle [message]
  case "$1" in *"$2"*) ;; *) _fail "${3:-text not found}"$'\n'"      looking for: $2"$'\n'"      in: $1" ;; esac
}
assert_not_contains() {
  case "$1" in *"$2"*) _fail "${3:-unexpected text found}: $2" ;; *) ;; esac
}
assert_status() { # expected_code actual_code [message]
  [ "$1" = "$2" ] || _fail "${3:-exit status} expected $1, got $2"
}

# ---------- fake gh ----------
# setup_fake_gh: routes are added with `route 'GLOB' fixture-file` (or '!fail' to exit 1).
# Every call is appended to $FAKE_GH_LOG; JSON sent with --input - is logged as "STDIN {...}".
setup_fake_gh() {
  export FAKE_GH_DIR="$T/fakegh"
  export FAKE_GH_LOG="$T/gh.log"
  mkdir -p "$FAKE_GH_DIR"; : > "$FAKE_GH_DIR/routes"; : > "$FAKE_GH_LOG"
  export SCRUM_GH="$TESTS_DIR/fake-gh"
  export SCRUM_REPO="acme/blog"
}
route() { printf '%s\t%s\n' "$1" "$2" >> "$FAKE_GH_DIR/routes"; }
route_first() { # route_first 'GLOB' FILE  Like route, but ahead of every earlier route.
  { printf '%s\t%s\n' "$1" "$2"; cat "$FAKE_GH_DIR/routes"; } > "$FAKE_GH_DIR/routes.new"
  mv "$FAKE_GH_DIR/routes.new" "$FAKE_GH_DIR/routes"
}
route_json() { # route_json 'GLOB' 'json text'
  local f="r$(wc -l < "$FAKE_GH_DIR/routes" | tr -d ' ').json"
  printf '%s' "$2" > "$FAKE_GH_DIR/$f"
  route "$1" "$f"
}
gh_calls() { cat "$FAKE_GH_LOG"; }
gh_writes() { grep -E -- '-X (POST|PATCH|PUT|DELETE)' "$FAKE_GH_LOG" || true; }

# A target repo working tree with a config file.
setup_repo() { # setup_repo [yaml-content]
  export SCRUM_REPO_DIR="$T/repo"
  mkdir -p "$SCRUM_REPO_DIR/.github"
  if [ $# -gt 0 ]; then printf '%s\n' "$1" > "$SCRUM_REPO_DIR/.github/scrum.yml"; fi
}

run_scrum() { # run_scrum args...  -> sets OUT, ERR, STATUS
  set +e
  OUT="$("$BASH" "$SCRUM" "$@" 2>"$T/stderr")"; STATUS=$?
  ERR="$(cat "$T/stderr")"
  set -e
}

# jq program from runtime/lib/jq
jqt() { local prog="$1"; shift; jq -L "$PLUGIN_DIR/runtime/lib/jq" "$@" -f "$PLUGIN_DIR/runtime/lib/jq/$prog.jq"; }

export -f assert_eq assert_json_eq assert_contains assert_not_contains assert_status _fail 2>/dev/null || true

# ---------- run ----------
for file in "$TESTS_DIR"/test_*.sh; do
  [ -n "$pattern" ] && case "$file" in *"$pattern"*) ;; *) continue ;; esac
  names="$(grep -E '^test_[A-Za-z0-9_]+\(\)' "$file" | sed 's/().*//')"
  printf '%s\n' "$(basename "$file")"
  for name in $names; do
    T="$(mktemp -d "${TMPDIR:-/tmp}/scrumtest.XXXXXX")"
    export T
    # Not inside `if`: errexit must stay active in the subshell.
    ( set -e; cd "$T"; . "$file"; "$name" ) 2>"$T/.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      pass=$((pass + 1)); printf '  ok   %s\n' "$name"
    else
      fail=$((fail + 1)); failed_names="$failed_names $name"
      printf '  FAIL %s\n' "$name"; sed 's/^/    /' "$T/.err"
    fi
    rm -rf "$T"
  done
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { printf 'Failed:%s\n' "$failed_names"; exit 1; }
