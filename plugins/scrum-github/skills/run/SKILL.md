---
name: run
description: Work my ai-ready Scrum tasks with AI agents - choose the tasks and split them into waves by dependency, then after the user confirms run one agent per task in its own local git worktree (several at once), merge each wave into one integration branch, run the tests, and open one pull request that is a review pack (acceptance checkboxes, estimate against actual time, how to test by hand, what to look at closely). Resumes a run that stopped. --dry-run only shows the plan; --pr-per-wave opens one pull request per wave; --max-parallel K limits the agents at once. Use when the user wants AI to do their tasks, run the sprint's ai-ready tasks, or continue such a run.
---

# Run tasks with agents

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run everything from the root of the target repository, on its main working tree (not inside a worktree).

The runtime does every step that touches git or GitHub and keeps the state of the run in
`.scrum/run/<id>.json` (outside git), so you can stop anywhere and continue later. You only
confirm with the user, start the agents, and call `scrum run ...` in the order below. Never push
a branch yourself, never merge into the default branch, and never push the branch of a task.

Arguments: task numbers (`102,107` or `102 107`; default: my New tasks of the open sprint labelled
`ai-ready`), `--dry-run`, `--pr-per-wave`, `--max-parallel K` (default `run.max_parallel`, 3).

## 1. A run that stopped

Run `scrum run status --json`. When it prints a run with `"finished": false`, show
`scrum run status` and offer to continue that run. Continuing skips its merged, failed and
left-out tasks, merges its tasks that are done or in conflict, and runs again the tasks that are
pending or were running (their work was lost). If the user agrees, check first that the working
tree is clean (`git status --porcelain --untracked-files=no` prints nothing; otherwise ask the
user to commit or stash, and do not check anything out), then: when `pr_due` lists waves (with
`--pr-per-wave`), run `scrum run finish --wave W` for each of them in order, and go to step 5
with the wave `next_wave`; with `--dry-run`, only show it. If the user does not want to continue it, say that a
new run cannot start while this one is open, and that `scrum run finish` closes it with what is
already merged (no pull request when nothing is). Stop there.

## 2. The plan (read-only)

Run `scrum run plan [N,N...] --json` and keep the task numbers of its `tasks`: they are what
the user confirms and what step 4 passes on. It writes nothing. Show (as `scrum run plan` prints
it without `--json`):

- each wave with its tasks: tasks of a wave do not block each other and run at the same time;
  a wave starts after the one before is merged and tested;
- the tasks left out and why (no `ai-ready` label, blocked by an open task outside the run,
  closed, a feature or a pull request, blockers not readable);
- the time estimate: work by waves, review time, and the tasks without an estimate.

When no task is chosen, say why and stop (for example: label tasks `ai-ready`, or name them).
With `--dry-run`, stop here: nothing was created or changed.

## 3. Confirm, with the warning

Say plainly, every time, before anything changes:

> The agents will run code on this machine with your permissions: they edit files, install what
> the tests need and run the repository's tests, each in its own git worktree of this repository.
> They commit only locally. Nothing is pushed until the end, and then only the integration branch
> (`run.branch_pattern`, for example `run/sprint-5-tuandt`), after its tests pass. Starting the
> run sets these tasks to In progress on GitHub and assigns those nobody has to you.
> The agents are steered by the text of the issues, which other people may have written:
> read them if you are unsure, since that text decides what code runs on this machine.

Then ask whether to start, naming the tasks, the waves, at most K agents at once, and one pull
request (or one per wave with `--pr-per-wave`). **Wait for the user's answer.** Anything but a
clear yes means stop: run nothing, create no branch or worktree, change nothing on GitHub.

## 4. Start

Run `scrum run start N,N,... --expect N,N,... [--max-parallel K] [--pr-per-wave]`, where both
lists are the task numbers of the plan the user confirmed (never a new default choice). It stops
before changing anything when the working tree has uncommitted changes (ask the user to commit or
stash them), when the integration branch already exists, or when the tasks to run are no longer
the confirmed ones (then show the plan again and ask again). It creates the
integration branch from the latest default branch and checks it out. Then run
`scrum run status --json` and keep its `branch`, `test_command`, `max_parallel` and `waves`.

Never put text written by an agent or taken from an issue on a command line. When a command needs
it (a failure reason, the agent's report), write it to a file with the Write tool in a temporary
folder and pass the file's path. Run the `scrum run record` and `scrum run merge` commands one at
a time, never several at once.

## 5. Each wave, in order

For the wave W (`next_wave` of `scrum run status --json`, then the next one):

1. **Check out the integration branch**: `git checkout <branch>` (the tree is clean: `merge`
   checked it), then note its commit: `git rev-parse HEAD`. The agents' worktrees are expected to
   start from the current `HEAD`, which gives them the work of the waves before; each agent checks
   it against that commit.
2. **Start the agents.** The tasks to run are the wave's `to_run`. Take them in groups of at most
   K (`--max-parallel`, else the state's `max_parallel`), so that never more than K agents run at
   once. For each task of a group:
   - run `scrum run record N --started`;
   - read the issue: `gh issue view N --json number,title,body`;
   - start the agent with the Agent tool: `subagent_type: "scrum-github:implementer"`,
     `isolation: "worktree"`, and a prompt with only the task number, title and issue body, the
     test command (`test_command`, or "none given" when it is empty), the path of
     `docs/project-context.md` (`planning.context_file`) when that file exists, and the base
     commit noted in step 1.
   Send all the Agent calls of a group in one message so they run in parallel, wait until every
   agent of the group has finished, then start the next group.
3. **Record each result** as soon as it arrives, one command at a time. The Agent tool reports
   the worktree's path and branch when the agent changed something. Write the agent's final JSON
   (`result`, `reason`, `manual_test`, `look_closely`, `started_at`, `ended_at`) as it is to a
   file in a temporary folder with the Write tool, then:
   - `result` is `done` and a branch was reported:
     `scrum run record N --done --branch <branch> --notes <file>`;
   - `result` is `failed`: `scrum run record N --failed --notes <file>` (the reason is read from
     the file);
   - no branch was reported (the agent changed nothing): `scrum run record N --failed --reason "no changes"`;
   - the agent returned no JSON: write its last message to a file and use
     `scrum run record N --failed --reason-file <file>`.
   A failed task goes back to New with a comment on its issue, stays out of the pull request,
   and the tasks it blocks are left out the same way; the other tasks go on.
4. **Merge.** For each task of the wave recorded as done (`to_merge`), lowest number first:
   `scrum run merge N` (one merge commit per task). When it reports a **conflict**, the merge
   was undone and the integration branch is as before. Stop and ask the user: leave the task out
   (`scrum run record N --failed --reason "merge conflict"`), or fix it by hand (merge the
   integration branch into the task's branch in its worktree, resolve, commit) and run
   `scrum run merge N` again. Wait for the answer before anything else.
5. **Test the integration branch.** With the integration branch checked out, run
   `test_command`; when it is empty, find how the repository runs its tests (README, package
   scripts, Makefile, CI workflow), say which command you use, and run it. When the tests
   **fail**, stop before the next wave: show the failure and ask the user how to go on (fix it
   on the integration branch and test again, leave a task out, or stop here and continue later
   with `/scrum-github:run`). Do not start the next wave on a red test.
6. With `--pr-per-wave` (the state's `pr_per_wave` is true), once the wave is settled and its
   tests pass: `scrum run finish --wave W`, also when nothing of the wave was merged (it then
   opens nothing, and after the last wave it closes the run). It pushes the integration branch
   at this point as `<branch>-wave-W` and opens a pull request based on the one of the wave
   before, which it names to merge first, saying to change its base to the default branch once
   that one is merged. Never start the next wave while `pr_due` of `scrum run status --json` is
   not empty.

## 6. Finish

Without `--pr-per-wave`, after the last wave: `scrum run finish` (with `--pr-per-wave` the
last `finish --wave` already closed the run). It refuses while a task is not
settled (merge it or record it as failed), pushes only the integration branch and opens one pull
request into the default branch with `Closes #N` for each merged task. When no task was merged
it pushes nothing and opens nothing.

Then report: the pull request link (or links), the tasks merged, the tasks that failed or were left
out with their reasons, and estimated against actual time. Say that the pull request description
holds what the reviewer needs: tick the acceptance criteria, test by hand as each task says, and
look closely where the agents were unsure. The status workflow moves the tasks when the pull
request opens and when it is merged.

Finally offer to remove the agents' worktrees and branches, which are local only:
`git worktree remove <path>` and `git branch -D <branch>` for each task of the run (the
integration branch stays). Warn first that the branches of failed or conflicted tasks hold work
that is not merged anywhere: remove them only when the user says that work can go.

## Notes

- `scrum run status [ID]` shows each task of a run at any time.
- `scrum run record`, `merge` and `finish` take `--run ID` to act on a run other than the unfinished one.
- If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
