---
name: release
description: Publish a version on GitHub from the Scrum tasks that are done - find the previous version tag, gather the tasks completed since then (or those of named sprints) with the pull requests that closed them, suggest the next version by semver, write release notes, and after the user agrees create the tag and the GitHub Release. Use when the user wants to release, tag or publish a version, write release notes or a changelog for GitHub, or after closing a sprint.
argument-hint: "[VERSION] [--sprint \"Sprint N\"] [--since TAG] [--draft]"
---

# Release a version

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository.

Pass on what the user gave: a version (`1.5.0` or `v1.5.0`), `--sprint "Sprint 5"` (repeatable: only
the Done tasks of those sprints), `--since TAG` (start from that tag instead of the latest one) and
`--draft` (a draft release, published by hand on GitHub later).

1. **Preview.** Run `scrum release [VERSION] [--sprint S]… [--since TAG] [--draft] --json`. It
   changes nothing. It returns the previous version (`previous`, null before the first release),
   the new version (`version`, `tag`), why (`bump`: `first`, `major`, `minor`, `patch` or `given`,
   with `reasons.breaking`, `reasons.features` and `reasons.bugs` as task numbers), the tasks with
   the pull requests that closed them (`prs`, null when they could not be read), and the release
   notes (`notes`, Markdown). `nothing: true` means no task was completed since the previous
   version: say so and stop. An error (a version that is not `X.Y.Z` or not greater than the
   previous one, or a version already released) means nothing will be changed: tell the user.
2. **Show.** Tell the user the previous and the new version and why this one: a major version
   because of the tasks labelled `release.breaking_label` (name them), a minor one because of the
   tasks that are not bugs (name a few), a patch when every task is a bug, the first release
   (`release.first_version`) when there is no version tag yet. Then show the release notes as they
   will appear on GitHub. When `tag_exists` is true, say that the tag was created by an earlier
   run and only the release is missing.
3. **Edit.** Let the user change the version or the notes:
   - another version: run the preview again with that `VERSION`;
   - different notes: write the notes the user wants to a file outside the repository with the
     Write tool, and pass it with `--notes-file FILE` from then on. Never put the notes or any
     text taken from an issue on a command line.
   Show the result again after each change.
4. **Wait for the user's answer.** Ask whether to publish this version with these notes. Do not
   go on without a clear yes in this conversation.
5. **Publish.** Only after the yes, run the same command without `--json` and with `--yes`
   (keep `VERSION`, `--sprint`, `--since`, `--draft` and `--notes-file` exactly as previewed). It
   creates an annotated tag on the head commit of the default branch on GitHub, then the GitHub
   Release. Report the tag and the link to the release.

If it says the tag exists but the release was not created, run the same command again: it creates
only the release and leaves the tag as it is. A 403 when creating the tag means the token needs
`contents: write` on the repository: run `/scrum-github:doctor`.

The command does not change files in the repository (no version file, no `CHANGELOG.md`), does
not deploy and does not publish packages.

Never pass `--yes` without the user's confirmation in this conversation.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
