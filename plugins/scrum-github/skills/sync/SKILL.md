---
name: sync
description: Bring the latest working branch (develop, or main in trunk; main on a hotfix branch) into the current task branch with a merge, and list any conflicts with who last changed each file on that branch. Never resolves conflicts. Use when the user wants to update, sync or rebase their task branch, or when task-pr says the branch is behind its base.
---

# Sync the task branch

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository. `scrum sync` uses only git (it fetches from origin).

1. Run `scrum sync`. It merges `origin/<working branch>` into the current branch
   (`origin/<release branch>` on a `hotfix/*` branch) and says how many commits it brought in, or
   that the branch is already up to date.
2. When it refuses:
   - on a long-lived branch (`develop`, `staging`, `main`): it works on task branches only; ask the
     user which task branch to check out;
   - with uncommitted changes: ask the user to commit or stash them first. Do not stash for them.
3. When the merge conflicts, the command lists each conflicted file with the author and subject of
   the last commit on the base that changed it, and leaves the merge in progress. Show that list.
   Do not resolve the conflicts on your own: offer to help with each file, and only edit after the
   user agrees. When the files are fixed, the user runs `git add <files>` and `git merge --continue`;
   to give up, `git merge --abort` puts the branch back as it was.
4. The merge is local. Pushing the branch is the user's to do.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
