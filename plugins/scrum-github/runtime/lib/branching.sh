# shellcheck shell=bash
# Branching presets for shell code (spec branching-presets, design 1 and 5). Sourced by common.sh.
# The roles come from jq/scrum.jq (branching); no command reads the default branch of the
# repository for them (doctor only checks that it is the release branch).

BRANCH_CONTENTS_LIMIT=100   # tasks checked for being on a branch (one compare call per merge commit)

# branch_role ROLE  The branch of a role in the configured preset (needs CONFIG_JSON):
#   preset | main | develop | staging | working | release  -> one name, nothing when the preset
#   has no such branch; lower | chain -> one name per line (lowest first).
branch_role() {
  jq -rn -L "$JQ_LIB" --argjson cfg "$CONFIG_JSON" --arg r "$1" \
    'include "scrum"; branching($cfg)[$r] | if type == "array" then .[] elif . == null then empty else . end'
}

# has_working_branch  True when the preset has a working branch below the release branch.
has_working_branch() { [ "$(branch_role preset)" != trunk ]; }

# branch_uri TEXT  TEXT encoded for one segment of a URL path (release/v1.2.0 -> release%2Fv1.2.0).
branch_uri() { jq -rn --arg s "$1" '$s | @uri'; }

# ref_contains REPO SHA REF  Prints the compare status of REF against SHA: ahead or identical
# when REF contains SHA, behind or diverged when it does not. Returns 1 when GitHub gives none.
ref_contains() {
  local st
  st="$(gh_get "repos/$1/compare/$(branch_uri "$2")...$(branch_uri "$3")" 2>/dev/null | jq -r '.status // empty' 2>/dev/null)" || return 1
  [ -n "$st" ] || return 1
  printf '%s' "$st"
}

# task_merged_prs REPO N  [{number, sha}] of the merged pull requests of REPO that close task N
# (from its timeline, as release does), each with its merge commit. Returns 1 when unread.
task_merged_prs() {
  local repo="$1" n="$2" tl nums p sha out='[]'
  tl="$(gh_get_all "repos/$repo/issues/$n/timeline?per_page=100" 2>/dev/null)" || return 1
  nums="$(printf '%s' "$tl" | jq -r -L "$JQ_LIB" --arg r "$repo" --argjson n "$n" 'include "scrum"; timeline_prs($r; $n)[]' 2>/dev/null)" || return 1
  for p in $nums; do
    sha="$(gh_get "repos/$repo/pulls/$p" 2>/dev/null | jq -r '.merge_commit_sha // empty' 2>/dev/null)" || return 1
    [ -n "$sha" ] || return 1
    out="$(printf '%s' "$out" | jq -c --argjson p "$p" --arg s "$sha" '. + [{number: $p, sha: $s}]')"
  done
  printf '%s' "$out"
}

# branch_contents REPO REF ISSUES_JSON [LOCATIONS_JSON]  Which open tasks In review with a
# location label (of one of LOCATIONS_JSON, a JSON list of branch names, when given) REF
# contains: for each, the merged pull requests that close it and whether REF contains their
# merge commits. At most BRANCH_CONTENTS_LIMIT tasks; one compare per merge commit.
# Prints {ref, contained: [N], missing: [N], unknown: [N], prs: {"N": [{number, sha}]},
#         truncated, total, limit}.
branch_contents() {
  local repo="$1" ref="$2" issues="$3" locations="${4:-null}" cand n prs sha st checks='[]' statuses seen=''
  cand="$(printf '%s' "$issues" | jqlib branch-contents --arg step candidates --argjson cfg "$CONFIG_JSON" \
    --argjson locations "$locations" --argjson limit "$BRANCH_CONTENTS_LIMIT")"
  for n in $(printf '%s' "$cand" | jq -r '.numbers[]'); do
    if ! prs="$(task_merged_prs "$repo" "$n")"; then
      checks="$(printf '%s' "$checks" | jq -c --argjson n "$n" '. + [{number: $n, prs: null, statuses: []}]')"
      continue
    fi
    statuses='[]'
    for sha in $(printf '%s' "$prs" | jq -r '.[].sha'); do
      # Cache within this call: one compare per merge commit.
      st="$(printf '%s' "$seen" | awk -v s="$sha" '$1 == s {print $2; exit}')"
      if [ -z "$st" ]; then
        st="$(ref_contains "$repo" "$sha" "$ref")" || st="unread"
        seen="$seen$sha $st"$'\n'
      fi
      statuses="$(printf '%s' "$statuses" | jq -c --arg s "$st" '. + [if $s == "unread" then null else $s end]')"
    done
    checks="$(printf '%s' "$checks" | jq -c --argjson n "$n" --argjson p "$prs" --argjson s "$statuses" \
      '. + [{number: $n, prs: $p, statuses: $s}]')"
  done
  jqlib branch-contents -n --arg step result --argjson checks "$checks" \
    | jq -c --arg ref "$ref" --argjson c "$cand" '{ref: $ref} + . + {truncated: $c.truncated, total: $c.total, limit: $c.limit}'
}

# open_prs REPO HEAD BASE  The open pull requests from HEAD (a branch of REPO) into BASE, as JSON
# [{number, title, html_url, head, base}] (empty list when none). HEAD or BASE may be "" for any.
open_prs() {
  local q="state=open&per_page=100" owner="${1%%/*}"
  [ -z "$2" ] || q="$q&head=$(branch_uri "$owner:$2")"
  [ -z "$3" ] || q="$q&base=$(branch_uri "$3")"
  gh_get_all "repos/$1/pulls?$q" | jq -c '[.[] | {number, title, html_url, head: .head.ref, base: .base.ref, body: (.body // "")}]'
}

# open_prs_matching REPO HEAD_PREFIX BASE  Like open_prs, for every head branch starting with
# HEAD_PREFIX (release/, hotfix/).
open_prs_matching() {
  open_prs "$1" "" "$3" | jq -c --arg p "$2" '[.[] | select(.head | startswith($p))]'
}

# branch_rules REPO BRANCH  The rules that apply to BRANCH (from rulesets), as JSON; [] when none.
# Returns 1 when GitHub could not be read.
branch_rules() { gh_get_all "repos/$1/rules/branches/$(branch_uri "$2")"; }

# branch_exists REPO BRANCH  True when the branch exists on GitHub.
branch_exists() { gh_get "repos/$1/branches/$(branch_uri "$2")" >/dev/null 2>&1; }

# branch_sha REPO BRANCH  The head commit of BRANCH on GitHub.
branch_sha() { gh_get "repos/$1/git/ref/heads/$(branch_uri "$2")" | jq -r '.object.sha // empty'; }
