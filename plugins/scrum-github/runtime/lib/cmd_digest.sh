# shellcheck shell=bash
# scrum digest: post the daily digest comment on the "<sprint> digest" issue.

cmd_digest() {
  require_tools
  load_config
  if [ "$(config_get .digest.enabled)" != "true" ]; then
    info "The digest is turned off (digest.enabled: false). Nothing posted."
    return 0
  fi
  local repo ms sprint number title issues digest_title meta digest_issue n comments body
  repo="$(repo_slug)"
  ms="$(fetch_milestones "$repo")"
  sprint="$(jqlib sprint-resolve -n --argjson ms "$ms" --argjson cfg "$CONFIG_JSON" --arg title "" --arg today "$(today)")"
  if [ "$sprint" = "null" ]; then
    info "There is no open sprint. Nothing posted."
    return 0
  fi
  number="$(printf '%s' "$sprint" | jq -r .number)"
  title="$(printf '%s' "$sprint" | jq -r .title)"
  issues="$(fetch_milestone_issues "$repo" "$number")"
  digest_title="$title digest"
  meta="$(config_get .labels.meta)"

  digest_issue="$(printf '%s' "$issues" | jq -c --arg t "$digest_title" --arg m "$meta" \
    '[.[] | select(.title == $t and any(.labels[]?; .name == $m) and (has("pull_request") | not))] | sort_by(.number) | .[0]')"
  if [ "$digest_issue" = "null" ]; then
    digest_issue="$(jq -n --arg t "$digest_title" --arg m "$meta" --arg s "$title" --argjson n "$number" \
      '{title: $t, body: "Daily progress of \($s), posted by the scrum-daily-digest workflow. Not a task.", labels: [$m], milestone: $n}' \
      | gh_send POST "repos/$repo/issues")"
    comments="[]"
    info "Created issue #$(printf '%s' "$digest_issue" | jq -r .number) \"$digest_title\"."
  else
    comments="$(gh_get_all "repos/$repo/issues/$(printf '%s' "$digest_issue" | jq -r .number)/comments?per_page=100")"
  fi
  n="$(printf '%s' "$digest_issue" | jq -r .number)"

  . "$SCRUM_ROOT/lib/attention.sh"
  ATTENTION_LINES="$(attention_json "$repo" "$sprint" "$issues" | jq -c .lines)"
  body="$(jqlib digest -n --argjson cfg "$CONFIG_JSON" --argjson sprint "$sprint" --argjson issues "$issues" \
    --argjson comments "$comments" --arg today "$(today)" --argjson off "$(tz_offset)" \
    --argjson strings "$(strings_json)" --argjson attention "${ATTENTION_LINES:-[]}")"
  printf '%s' "$body" | jq -c '{body}' | gh_send POST "repos/$repo/issues/$n/comments" >/dev/null
  info "Posted the digest on #$n."
  send_webhook "$(printf '%s' "$body" | jq -r '.body | split("\n") | map(select(test("^<!--") | not)) | join("\n")')"
}

# send_webhook TEXT  POST the digest to SCRUM_DIGEST_WEBHOOK, if set, in digest.webhook_format.
# Best effort: a failure is a warning, the digest comment is already posted.
send_webhook() {
  local url="${SCRUM_DIGEST_WEBHOOK:-}" format payload code
  [ -n "$url" ] || return 0
  format="$(config_get '.digest.webhook_format // "slack"')"
  case "$format" in
    telegram) payload="$(jq -nc --arg t "$1" '{text: $t, disable_web_page_preview: true}')" ;;
    *) payload="$(jq -nc --arg t "$1" '{text: $t}')" ;;
  esac
  # The URL holds a secret: never print it.
  if ! code="$(printf '%s' "$payload" | "${SCRUM_CURL:-curl}" -sS -o /dev/null -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' --data-binary @- "$url" 2>/dev/null)"; then
    warn "the digest webhook could not be reached; the digest comment was posted"
    return 0
  fi
  case "$code" in
    2??) info "Sent the digest to the $format webhook." ;;
    *) warn "the digest webhook answered HTTP $code; the digest comment was posted" ;;
  esac
}
