---
name: sprint-fill
description: Sprint Planning on GitHub - work out the sprint's capacity from recent velocity, show what is already planned and the backlog, propose a set of tasks that fits the capacity in dependency order, and after the user approves move them into the sprint. Use when the user wants to plan or fill a sprint, choose tasks for the next sprint, or check how much fits.
argument-hint: "[sprint name] [capacity]"
---

# Fill a sprint from the backlog

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository.

1. **Look.** Run `scrum sprint fill [SPRINT] [--capacity N]` (no sprint = the current one). It
   changes nothing. It prints the capacity (the average velocity of up to three recent closed
   sprints, or `--capacity`), the points already planned, the points free, and the backlog.
   When tasks have time estimates, it also prints the minutes of review per person in the sprint
   ("@an-nguyen 1h30m of 2h": the second number is `review_hours` from `team` in
   `.github/scrum.yml`), and each backlog task's time ("[AI 20m, review 15m]").
   If it says the capacity is unknown, ask the user for one and run it again with `--capacity N`.
2. **Propose.** Pick tasks from the backlog that fit the free points:
   - a task that blocks others comes before them; never propose a task without its open
     blockers unless the user says so;
   - leave out tasks without points, and say which ones need an estimate
     (`/scrum-github:task` can set it);
   - follow any priority the user gave; otherwise prefer tasks of the same feature together;
   - when people have `review_hours`, keep each person's review minutes under it: when AI does
     the work, review is the bottleneck, not points.
   Show the proposal as a short table (number, points, title, why) with the total against the
   capacity. Let the user add, remove or swap tasks.
3. **Preview.** Run `scrum sprint fill [SPRINT] --add N,N,…` and show its warnings (over
   capacity, no points, blocked by a task outside the sprint, a person over their review hours).
   Warnings never stop the command. An error means nothing will be changed: fix the list first.
4. **Apply.** Only after the user agrees to that preview, run the same command with `--yes`.
   Each task gets the sprint's milestone and a comment. Report what was added.

Never pass `--yes` without the user's confirmation in this conversation.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
