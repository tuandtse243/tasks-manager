---
name: release
description: Publish a version on GitHub from the Scrum tasks that are done - find the previous version tag, gather the tasks completed since then (or those of named sprints, or with a working branch the tasks In review on develop or staging) with the pull requests that closed them, suggest the next version by semver, write release notes, and after the user agrees create the tag and the GitHub Release (preset trunk) or open the release pull request into main (presets standard and environments). Use when the user wants to release, tag or publish a version, open a release pull request, write release notes or a changelog for GitHub, or after closing a sprint.
argument-hint: "[VERSION] [--sprint \"Sprint N\"] [--since TAG] [--from REF] [--draft]"
---

# Release a version

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository.

Pass on what the user gave: a version (`1.5.0` or `v1.5.0`), `--sprint "Sprint 5"` (repeatable: only
the Done tasks of those sprints), `--since TAG` (start from that tag instead of the latest one),
`--from REF` (release up to that branch, tag or commit) and `--draft` (a draft release, published by
hand on GitHub later).

**Which flow.** `branching.preset` in `.github/scrum.yml` decides (`scrum config` prints it):

- `trunk` (or no `branching` block): the steps below publish directly: tag and GitHub Release on the
  head of the release branch. `--from` is refused.
- `standard` or `environments`: the same steps, but `--yes` opens a **release pull request** instead
  (see "With a working branch" below). `--sprint` and `--draft` are refused there.

1. **Preview.** Run `scrum release [VERSION] [--sprint S]… [--since TAG] [--draft] --json`. It
   changes nothing. It returns the previous version (`previous`, null before the first release),
   the new version (`version`, `tag`), why (`bump`: `first`, `major`, `minor`, `patch` or `given`,
   with `reasons.breaking`, `reasons.features` and `reasons.bugs` as task numbers), the tasks with
   the pull requests that closed them (`prs`, null when they could not be read), and the release
   notes (`notes`, Markdown). `nothing: true` means no task was completed since the previous
   version: say so and stop. An error (a version that is not `X.Y.Z` or not greater than the
   previous one, a version already released, a draft release for it, or version tags none of
   which can be confirmed on the release branch (`branching.main`): then suggest `--since TAG`) means nothing will
   be changed: tell the user.
2. **Show.** Tell the user the previous and the new version and why this one: a major version
   because of the tasks labelled `release.breaking_label` (name them), a minor one because of the
   tasks that are not bugs (name a few), a patch when every task is a bug, the first release
   (`release.first_version`) when there is no version tag yet. Then show the release notes as they
   will appear on GitHub. When `tag_exists` is true, say that the tag was created by an earlier
   run and only the release is missing.
3. **Edit.** Let the user change the version or the notes:
   - another version: run the preview again with that `VERSION`;
   - different notes: write the notes the user wants to a file outside the repository with the
     Write tool, and pass it with `--notes-file FILE` from then on.
   Never put the notes or any text taken from an issue on a command line. Show the result again
   after each change.
4. **Wait for the user's answer.** Ask whether to publish this version with these notes. Do not
   go on without a clear yes in this conversation.
5. **Publish exactly what was previewed.** Only after the yes:
   - write the `notes` of the last preview, unchanged, to a file outside the repository with the
     Write tool (unless they already come from your `--notes-file`), so tasks closed since the
     preview cannot change them;
   - run `scrum release <version> [--sprint S]… [--since TAG] [--draft] --notes-file FILE --json --yes`,
     where `<version>` is the `version` of the last preview (the command refuses `--yes` without
     a version) and the other options are the previewed ones.
   In `trunk` it creates an annotated tag on the head commit of the release branch on GitHub, then
   the GitHub Release, and prints one JSON value with `published.url`. Report the tag and the link.
   With a working branch it opens the release pull request instead and prints `pull_request.url`
   (see below).

If it says the tag exists but the release was not created, run that same command again, with the
same options: it creates only the release and leaves the tag as it is. A 403 means the token needs
`contents: write` on the repository: run `/scrum-github:doctor`.

## With a working branch (`standard`, `environments`)

- **The tasks** are those In review whose merged pull request the start point contains: the head of
  `develop` (`standard`), of `staging` (`environments`), or `--from REF`. A task merged after it is
  not listed. Merged pull requests without a task are listed under `other` ("Other" in the notes);
  they never change the version, and a release with only those is a patch. `nothing: true` means
  nothing is waiting: say so and stop.
- **The preview** also has `release_branch` (`release/<tag>`), `start` (`ref`, `sha`) and `files`
  (the configured `release.version_files` and `release.changelog`). Tell the user where the release
  starts and which files will change. A pull request from a `release/*` branch that is already open
  stops the command: give its number and link.
- **`--yes`** checks the version files first (a listed file without a version to replace stops
  everything, naming the file), creates `release/<tag>` at the start point, commits the version
  files and the changelog on it (one commit, none when neither is configured), and opens the pull
  request "Release <tag>" into the release branch with the notes between
  `<!-- scrum-release-notes -->` and `<!-- /scrum-release-notes -->`. It creates no tag and no GitHub
  Release. Report the pull request link and say: merging it (with the reviews of the release branch)
  makes the release workflow `scrum-release.yml` tag the merge commit, create the GitHub Release from
  those notes, set the tasks Done and open the back-merge pull requests (merge those with a merge
  commit). Edits of the notes in the pull request description before the merge are what gets
  published.

The command does not deploy and does not publish packages. In `trunk` it does not change files in
the repository.

Never pass `--yes` without the user's confirmation in this conversation.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
