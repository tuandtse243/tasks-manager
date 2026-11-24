---
name: cleanup
description: Remove finished branches - list the local and remote branches whose pull request was merged (also squash merges) or whose commits are all in a long-lived branch, never the long-lived branches, the current branch or a branch with an open pull request, then after the user agrees delete them locally and on origin. Use when the user wants to clean up, prune or delete merged or old branches.
---

# Clean up merged branches

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository.

1. Run `scrum cleanup`. It deletes nothing: it lists each branch, whether it is local, on origin or
   both, and why it is finished (its pull request was merged, or a long-lived branch contains it).
   A branch with commits after its merged pull request is not listed on that side.
2. When the list is empty, say so and stop.
3. Show the list and ask the user whether to delete these branches, locally and on origin.
   **Wait for the user's answer.** Anything but a clear yes means stop: delete nothing. When the
   user wants to keep some, delete the others by hand with `git branch -D <name>` and
   `git push origin --delete <name>` after they confirm each one.
4. Run `scrum cleanup --yes` only after the user agrees. Report what was deleted and any branch
   that could not be (for example a branch checked out in another worktree).

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
