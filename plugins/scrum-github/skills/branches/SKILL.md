---
name: branches
description: Show the state of the repository's branches - for each long-lived branch what it holds that the next one lacks (commits and tasks), drift (commits of main a lower branch lacks, and its back-merge pull request), open release, promotion and back-merge pull requests, and stale task branches with their last author. Read-only. Use when the user asks what is waiting on develop, what is not released yet, whether develop is behind main, or which branches are stale.
---

# Branch overview

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository. It only reads (it fetches from origin to see the
remote branches).

1. Run `scrum branches` (add `--json` when you need the data for further analysis).
2. Show the overview as it is, then a short reading:
   - tasks waiting on a lower branch: release them with `/scrum-github:release`, or promote them
     to staging with `/scrum-github:promote` in the `environments` preset;
   - drift: a lower branch lacks commits of the release branch. When no back-merge pull request is
     open, say so; the release and hotfix flow opens one. A back-merge is merged with a merge
     commit, never squashed;
   - stale task branches: name the last author so the team can ask them; finished branches can be
     removed with `/scrum-github:cleanup`.
3. In the `trunk` preset the overview has only the open pull requests and the stale branches.

"not checked" means GitHub did not say whether a task's merge commit is on the branch; it does not
mean the task is there or missing.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
