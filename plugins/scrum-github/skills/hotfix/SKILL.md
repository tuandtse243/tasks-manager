---
name: hotfix
description: Fix production in Scrum on GitHub without waiting for the next release (presets standard and environments) - start a hotfix branch hotfix/N-slug from the release branch for an open task, then before the pull request choose the version it publishes and update the version files and changelog on the branch. Use when the user says hotfix, production is broken, an urgent fix must ship from main, or asks to prepare a hotfix pull request.
argument-hint: "N | prepare"
---

# Hotfix

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository (it creates a local branch there).

A hotfix is a task branch that starts from the release branch (`main`) instead of the working
branch, and whose pull request targets the release branch. Merging it publishes a version like a
release pull request: the release workflow tags the merge commit, creates the GitHub Release, sets
the task Done and opens the back-merge pull requests.

## Start

1. Get the task number from the user's request. The task must exist and be open; for a new
   problem, create it first with `/scrum-github:task-new` (with `--bug`).
2. Run `scrum hotfix N`. It fetches the release branch and creates (or checks out)
   `hotfix/N-<slug>` from `origin/<release branch>`, assigns the task to the user when nobody has
   it and sets it In progress.
   - In `trunk` it stops: `/scrum-github:task-start N` already branches from the release branch.
   - A closed issue is refused and nothing changes: tell the user to reopen it if the fix is still
     needed.
   - If git refuses to switch branches because of uncommitted changes, tell the user; nothing was
     changed on GitHub then.
3. Report the branch and the status change.

## Prepare the pull request

When the fix is committed on the hotfix branch:

1. **Preview.** Run `scrum hotfix prepare --json`. It changes nothing and returns `{tag, version,
   previous, task, marker, files, notes}`: the version this hotfix publishes (from the labels of the
   task, a patch for a bug, after the highest version tag on the release branch), the `marker`
   line and the `files` that `--yes` would commit (`release.version_files` and `release.changelog`
   of `.github/scrum.yml`; empty when neither is set).
2. **Show.** Tell the user the previous and the new version, and the `files` that will change (or
   that there are none). Without `--json` the preview prints the same as "Committed on it with
   --yes: ...".
3. **Wait for the user's answer** before writing. Do not go on without a clear yes in this
   conversation.
4. **Write.** Only after the yes, run `scrum hotfix prepare --json --yes`. It writes the version
   files and the changelog in the working tree and commits them on the hotfix branch (one local
   commit, `committed` lists the files); it never pushes.
5. **Open the pull request** with `/scrum-github:task-pr`: base the release branch, `Closes #N`,
   and the `marker` line (`<!-- scrum-release-tag: vX.Y.Z -->`) in the description, unchanged.
   Without that line the release workflow sets the task Done but creates no tag and no release.

Never pass `--yes` without the user's confirmation in this conversation.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
