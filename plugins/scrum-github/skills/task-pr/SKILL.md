---
name: task-pr
description: Write the pull request description for the Scrum task of the current branch - a summary as the smallest visual that shows the change, before/after evidence, the merge danger, and the "Closes #N" line that links the task - then, after the user approves it, open the pull request or update the one already open. Use when the user wants to open, create, write or describe a pull request for a task.
argument-hint: "[task number]"
---

# Write the pull request for a task

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.

Run the commands from the root of the target repository. Nothing is created or changed on GitHub
before the user approves the description.

## 1. Find the task and the change

1. The task number: the argument if given. Otherwise read `branch.pattern` from
   `scrum config` and take the number at the place of
   `{number}` in the current branch name (`git branch --show-current`); `feat/12-comments` is
   task 12. If the branch name has no task number, ask the user for it. If they say the pull
   request belongs to no task, leave out the "Closes" line and tell them to add the `no_task`
   label from the config (default `no-task`), or the PR check fails.
2. The base: the default branch, `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`.
   Read `git log <base>..HEAD --oneline` and `git diff <base>...HEAD`. If there is no commit
   ahead of the base, say there is nothing to open a pull request for, and stop.
3. The task: `gh issue view <N> --json title,body,state`. Its acceptance criteria are what the
   evidence has to show.
4. An open pull request for this branch: `gh pr view --json number,url,body` (an error means
   there is none).

## 2. Write the description

Read `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/pr/SKILL.md` and follow it, with this adapter.
**Where they differ, the adapter wins.**

**Adapter for `pr`:**

- After its three sections, add a fourth:

  ```markdown
  ## Task

  Closes #<N>
  ```

  One `Closes #<n>` line per task when the pull request finishes several. Write "Closes", never
  "Solve": GitHub does not read "Solve" as a link.
- Evidence comes from what was run: a test or a command and its output, before and after. Run
  the project's tests for the change if you have not. When nothing was run and nothing can be,
  write that under "Evidence" in plain words. An invented result is worse than "none".
- Under "Evidence", say which acceptance criteria of the task the evidence covers and which it
  does not.
- For domain language, use the "Glossary" section of the project context (`planning.context_file`
  in the config) when the repository has no `GLOSSARY.md`.
- The title of the pull request is the task title, unless the user gives another.

## 3. Review with the user, then publish

Show the title and the full description. Ask the user to approve or change it; edit and show it
again until they approve.

Only after an approval:

- No pull request yet: write the description to a temporary file, then
  `gh pr create --base <base> --title "<title>" --body-file <file>`. The branch has to be on the
  remote first: if it is not, tell the user to push it (`git push -u origin <branch>`) and stop;
  pushing is theirs to do.
- A pull request is already open: say so, show what will replace its current description, and
  after the user agrees run `gh pr edit <number> --body-file <file>`.

Report the pull request URL. The check `scrum-pr-link-check` passes when the description has the
"Closes" line; opening the pull request moves the task to In progress, and merging it moves the
task to Done.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
