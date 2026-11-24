# shellcheck shell=bash
# scrum protect: long-lived branches, branch and tag rules and merge settings of the preset
# (spec repo-governance, design 9). Preview by default, writes with --yes; --json prints the plan.
# Rulesets are matched by name ("scrum: working|staging|release|tags"); every item that GitHub
# refuses is reported and the others are still applied; the exit status is 1 when one failed.

# The plugin's own required check: the job of templates/github/workflows/scrum-pr-link-check.yml.
PROTECT_CHECK_NAME="pr-check"
PROTECT_RULESET_PREFIX="scrum: "

# protect_reason ERRFILE WHAT  One sentence for a refused GitHub call (WHAT: rules | settings | branch).
protect_reason() {
  local err="$1" what="$2"
  if grep -q 'HTTP 403' "$err"; then
    case "$what" in
      rules) printf '%s' "GitHub refused (HTTP 403): rules are not available for this repository on its plan (a private repository needs GitHub Pro, Team or Enterprise), or the token has no admin rights on it" ;;
      *) printf '%s' "GitHub refused (HTTP 403): the token has no admin rights on the repository" ;;
    esac
  elif grep -q 'HTTP 404' "$err"; then
    case "$what" in
      rules) printf '%s' "GitHub answered 404: the token has no admin rights on the repository, or rules are not available for it on its plan" ;;
      *) printf '%s' "GitHub answered 404: the token has no admin rights on the repository" ;;
    esac
  else
    printf '%s' "$(sed 's/^gh: //' "$err" | head -1)"
  fi
}

# protect_plan REPO  The plan of protect-plan.jq for REPO, read from GitHub (read-only).
protect_plan() {
  local repo="$1" name branches='{}' sha rulesets rules_error="" list id one settings err tpl templates
  err="$(mktemp "${TMPDIR:-/tmp}/scrum-protect.XXXXXX")"

  for name in $(branch_role chain); do
    if branch_exists "$repo" "$name"; then
      sha="$(branch_sha "$repo" "$name" 2>/dev/null || true)"
      branches="$(printf '%s' "$branches" | jq -c --arg n "$name" --arg s "$sha" '.[$n] = {exists: true, sha: (if $s == "" then null else $s end)}')"
    else
      branches="$(printf '%s' "$branches" | jq -c --arg n "$name" '.[$n] = {exists: false, sha: null}')"
    fi
  done

  rulesets='[]'
  if list="$(gh_get_all "repos/$repo/rulesets?includes_parents=false&per_page=100" 2>"$err")"; then
    for id in $(printf '%s' "$list" | jq -r --arg p "$PROTECT_RULESET_PREFIX" '.[] | select((.name // "") | startswith($p)) | .id'); do
      if one="$(gh_get "repos/$repo/rulesets/$id" 2>/dev/null)" && [ -n "$one" ]; then
        rulesets="$(printf '%s' "$rulesets" | jq -c --argjson r "$one" '. + [$r]')"
      else
        rulesets="$(printf '%s' "$rulesets" | jq -c --argjson l "$list" --argjson id "$id" '. + [$l[] | select(.id == $id)]')"
      fi
    done
  else
    rules_error="$(protect_reason "$err" rules)"
    rulesets=null
  fi

  settings="$(gh_get "repos/$repo" 2>/dev/null)" || settings=""
  printf '%s' "$settings" | jq -e 'type == "object"' >/dev/null 2>&1 || settings=null
  rm -f "$err"

  tpl="$SCRUM_ROOT/../templates/rulesets"
  [ -d "$tpl" ] || tpl="$SCRUM_ROOT/templates/rulesets"
  [ -f "$tpl/working.json" ] || die "ruleset templates not found. Run protect from the plugin (scrum-github/bin/scrum protect), not from .github/scrum"
  templates="$(jq -n --rawfile w "$tpl/working.json" --rawfile s "$tpl/staging.json" \
    --rawfile r "$tpl/release.json" --rawfile t "$tpl/tags.json" '{working: $w, staging: $s, release: $r, tags: $t}')"

  jqlib protect-plan -n --argjson cfg "$CONFIG_JSON" --argjson templates "$templates" \
    --argjson branches "$branches" --argjson rulesets "$rulesets" --arg rules_error "$rules_error" \
    --argjson settings "$settings" --arg check "$PROTECT_CHECK_NAME" --arg step plan
}

# protect_send ITEM WHAT METHOD PATH BODY  One write; appends {item, status, message} to RESULTS.
protect_send() {
  local item="$1" what="$2" method="$3" path="$4" body="$5" err status=done msg=""
  err="$(mktemp "${TMPDIR:-/tmp}/scrum-protect.XXXXXX")"
  if ! printf '%s' "$body" | gh_send "$method" "$path" >/dev/null 2>"$err"; then
    status=failed; msg="$(protect_reason "$err" "$what")"
  fi
  rm -f "$err"
  RESULTS="$(printf '%s' "$RESULTS" | jq -c --arg i "$item" --arg s "$status" --arg m "$msg" '. + [{item: $i, status: $s, message: $m}]')"
}

# protect_apply REPO PLAN  Applies every item of the plan that needs a change; sets RESULTS.
protect_apply() {
  local repo="$1" plan="$2" item key
  RESULTS='[]'
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    case "$(printf '%s' "$item" | jq -r .action)" in
      create)
        protect_send "branch:$(printf '%s' "$item" | jq -r .name)" branch POST "repos/$repo/git/refs" \
          "$(printf '%s' "$item" | jq -c '{ref: "refs/heads/\(.name)", sha}')" ;;
      missing)
        RESULTS="$(printf '%s' "$RESULTS" | jq -c --argjson i "$item" '. + [{item: "branch:\($i.name)", status: "failed", message: $i.reason}]')" ;;
    esac
  done <<EOF
$(printf '%s' "$plan" | jq -c '.branches[]')
EOF
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    key="$(printf '%s' "$item" | jq -r .key)"
    case "$(printf '%s' "$item" | jq -r .action)" in
      create) protect_send "ruleset:$key" rules POST "repos/$repo/rulesets" "$(printf '%s' "$item" | jq -c .body)" ;;
      update) protect_send "ruleset:$key" rules PUT "repos/$repo/rulesets/$(printf '%s' "$item" | jq -r .id)" "$(printf '%s' "$item" | jq -c .body)" ;;
    esac
  done <<EOF
$(printf '%s' "$plan" | jq -c '.rulesets[]')
EOF
  if [ "$(printf '%s' "$plan" | jq -r .settings.action)" = update ]; then
    protect_send settings settings PATCH "repos/$repo" "$(printf '%s' "$plan" | jq -c .settings.desired)"
  fi
}

cmd_protect() {
  local json=0 yes=0 repo plan
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --yes|-y) yes=1 ;;
      *) die "unknown option for protect: $1" ;;
    esac
    shift
  done
  require_tools
  load_config
  repo="$(repo_slug)"
  plan="$(protect_plan "$repo")"
  plan="$(printf '%s' "$plan" | jq -c --arg r "$repo" '{repo: $r} + .')"

  if [ "$yes" = 1 ]; then
    protect_apply "$repo" "$plan"
    plan="$(printf '%s' "$plan" | jq -c --argjson r "$RESULTS" '. + {results: $r}')"
  fi

  if [ "$json" = 1 ]; then
    printf '%s\n' "$plan" | jq .
  else
    info "Repository: $repo"
    printf '%s' "$plan" | jqlib protect-plan -r --arg step text
  fi
  if [ "$yes" = 1 ] && [ "$(printf '%s' "$plan" | jq '[.results[] | select(.status == "failed")] | length')" != 0 ]; then
    exit 1
  fi
  return 0
}
