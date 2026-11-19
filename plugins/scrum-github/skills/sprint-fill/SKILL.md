---
name: sprint-fill
description: Sprint Planning on GitHub - work out the sprint's capacity from recent velocity, show what is already planned and the backlog, propose a set of tasks that fits the capacity in dependency order, and after the user approves move them into the sprint. Use when the user wants to plan or fill a sprint, choose tasks for the next sprint, or check how much fits.
argument-hint: "[sprint name] [capacity]"
---

# Fill a sprint from the backlog

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.
Run it from the root of the target repository.

1. **Look.** Run `scrum sprint fill [SPRINT] [--capacity N]` (no sprint = the current one). It
   changes nothing. It prints the capacity (the average velocity of up to three recent closed
   sprints, or `--capacity`), the points already planned, the points free, and the backlog.
   If it says the capacity is unknown, ask the user for one and run it again with `--capacity N`.
2. **Propose.** Pick tasks from the backlog that fit the free points:
   - a task that blocks others comes before them; never propose a task without its open
     blockers unless the user says so;
   - leave out tasks without points, and say which ones need an estimate
     (`/scrum-github:task` can set it);
   - follow any priority the user gave; otherwise prefer tasks of the same feature together.
   Show the proposal as a short table (number, points, title, why) with the total against the
   capacity. Let the user add, remove or swap tasks.
3. **Preview.** Run `scrum sprint fill [SPRINT] --add N,N,…` and show its warnings (over
   capacity, no points, blocked by a task outside the sprint). An error means nothing will be
   changed: fix the list first.
4. **Apply.** Only after the user agrees to that preview, run the same command with `--yes`.
   Each task gets the sprint's milestone and a comment. Report what was added.

Never pass `--yes` without the user's confirmation in this conversation.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
