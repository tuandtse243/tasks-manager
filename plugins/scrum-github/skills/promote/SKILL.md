---
name: promote
description: Promote the working branch to the staging branch in Scrum on GitHub (preset environments) - list the tasks on develop that staging does not have yet and, after the user agrees, open the promotion pull request from develop into staging. Use when the user wants to promote, move develop to staging, send work to the test environment, or prepare a test round before a release.
---

# Promote to staging

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository.

1. **Preview.** Run `scrum promote --json`. It changes nothing. It returns the working and the
   staging branch, the tasks In review on the working branch that staging does not contain yet
   (`tasks`), the tasks that could not be checked (`unknown`), `nothing: true` when staging
   already contains the head of the working branch, and `open` when a promotion pull request is
   already open.
   - With another preset the command stops and says there is no staging branch: tell the user
     that their preset releases straight from the working branch with `/scrum-github:release`.
   - `nothing: true`: say there is nothing to promote and stop.
   - `open`: give its number and link, and stop; a second one is never opened.
2. **Show.** List the tasks that the promotion brings to staging (number and title). Say that
   commits without a task are promoted too, and that the tasks move to `on: staging` when the pull
   request is merged (computed from the commits, not from the list).
3. **Wait for the user's answer.** Ask whether to open the promotion pull request. Do not go on
   without a clear yes in this conversation.
4. **Open it.** Only after the yes, run `scrum promote --json --yes`. Report the number and the
   link of the pull request (`pull_request.url`). It is merged like any other pull request, with
   the reviews and checks of the staging branch.

Never pass `--yes` without the user's confirmation in this conversation.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
