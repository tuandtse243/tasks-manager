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

  body="$(jqlib digest -n --argjson cfg "$CONFIG_JSON" --argjson sprint "$sprint" --argjson issues "$issues" \
    --argjson comments "$comments" --arg today "$(today)" --argjson off "$(tz_offset)")"
  printf '%s' "$body" | jq -c '{body}' | gh_send POST "repos/$repo/issues/$n/comments" >/dev/null
  info "Posted the digest on #$n."
}
