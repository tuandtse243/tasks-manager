---
name: plan
description: Break a requirement into an epic, features and Scrum tasks with acceptance criteria, story points and dependencies, suggest an assignee and a sprint for each task from the team and the sprint's capacity, and save it as a plan file in the repo (docs/plans/<slug>/plan.json, plan.md and plan.html) for the user to review once; after that one approval create the issues on GitHub with their sprint and assignees. Re-running continues the same plan without duplicates. Use when the user wants a feature, user story, requirement or brief planned, split or estimated into tasks. Replaces sprint-plan. Pass --quick to skip the independent review.
argument-hint: "<brief path | requirement text> [--quick]"
---

# Plan a requirement into tasks

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the target repository. Nothing is created on GitHub until the user approves the plan.

Input: a brief (`brief.md` from `/scrum-github:discover`), a path to a requirement, or a
description. `--quick` skips the independent review (step 5).

## 1. Read the context

1. Read `${CLAUDE_PLUGIN_ROOT}/reference/planning-rules.md` and follow it throughout.
2. `scrum config` (offline): the point scale `points.scale`, `planning.dir`,
   `planning.context_file`, `planning.hours_per_point`.
3. `scrum context status`: whether the project context exists and how old it is.
   - It exists: read `planning.context_file`. If `stale` or `unknown` is true, tell the user in one
     line that it may be out of date and suggest `/scrum-github:project-scan`; carry on.
   - It does not exist and the repository has code: suggest `/scrum-github:project-scan` once;
     carry on without it.
4. The plan format: `${CLAUDE_PLUGIN_ROOT}/runtime/share/plan.schema.json`.

## 2. Find or create the plan folder

- Input is a brief inside `planning.dir`: the plan goes in the same folder (`plan.json` next to
  `brief.md`).
- Otherwise: `scrum plan init "<title>" --slug <slug>`. Write the slug yourself in lowercase ASCII
  with dashes (drop accents: "Bình luận bài viết" -> `binh-luan-bai-viet`). The command prints the
  paths as JSON and which files already exist.
- `plan.json` already exists: read it and continue from it. Keep every `id` and every `issue`
  number of the tasks that stay; give new tasks new ids (next free `T<n>`, `F<n>`); never renumber.
  Change only what the user asks for.

## 3. Check that the input is clear enough

Before splitting, check the input says: **who** uses it, the **outcome** wanted, and **when it
counts as done**. A brief confirmed by `discover` passes. A brief with `Status: draft` and an
"Open questions" section does not pass on its own: list the open questions and who is to answer
them, and ask whether to wait for the answers or to continue. If the user continues, write each
open question as a concrete assumption in `assumptions`. If something is missing (for example
"make the app faster"), name what is missing and suggest `/scrum-github:discover` first. The user
may choose to continue: then write each missing part as a concrete assumption in `assumptions`.

## 4. Split into tasks

Read `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/to-tickets/SKILL.md` and follow its steps 1 to 4
(gather context, explore the code, draft vertical slices with blocking edges, wide refactors as
expand-migrate-contract), with this adapter. **Where they differ, the adapter wins.**

**Adapter for `to-tickets`:**

- Size tasks by the point scale and the sprint, not by "a single context window". Each task gets
  `points` from `points.scale` only; a task bigger than the largest value is split.
- Blocking edges become `depends_on` (ids of tasks of this plan).
- Each ticket becomes a task in `plan.json`: `id`, `title` (short, starts with a verb), `body`
  (the behaviour now and the behaviour once it is done, two or three sentences), `acceptance`
  (two to four criteria, each checkable on its own),
  optional `subtasks` (checklist items inside the issue, not issues), `points`, `depends_on`,
  `assignees` (the people the user named; the others are suggested in step 6), `bug` for defects.
- Several independent streams of work become several features under one `epic`; one stream is
  one feature and no epic.
- From a brief: plan only what its "In scope" section lists; the brief's size estimate gives the
  starting structure (task, feature, or epic); copy its assumptions into `assumptions` and its
  out-of-scope items into `out_of_scope`.
- `sprint`: set it now only where the user named one ("Sprint 5", "this sprint" = `"current"`,
  "backlog" = `null`); every other task gets a suggested sprint in step 6. Put the sprint on each
  task (a task's own `sprint` key) and leave the plan's `sprint` empty.
- **Stop after the user approves** (step 7): do not publish tickets, do not use the
  `ready-for-agent` label, do not run `/setup-matt-pocock-skills`, and do not write `.scratch/`
  files. The only output is `plan.json`.

A task may wait in the backlog for weeks while the code moves, so write `body` and `acceptance`
to last. Read `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/triage/AGENT-BRIEF.md` and apply its four
principles (durability over precision, behavioural not procedural, complete acceptance criteria,
explicit scope boundaries), with this adapter. **Where they differ, the adapter wins.**

**Adapter for `AGENT-BRIEF`:**

- Use the principles, not the template: the content goes into the `body` and `acceptance` fields
  of `plan.json`. Post no "Agent Brief" comment and apply no label.
- Name behaviour, and where it helps a type, a function or a config shape. Leave file paths and
  line numbers to the "Project fit" section of the brief, where they belong.
- When something could be mistaken for part of a task, end its `body` with one sentence
  "Out of scope: ...". What the whole plan leaves out stays in `out_of_scope`.

## 5. Independent review (skip with `--quick`)

Spawn the agent `scrum-github:plan-critic`. Give it only: the brief path or the requirement text,
the path of the draft `plan.json` (write it first, step 6), the point scale, and the path
`${CLAUDE_PLUGIN_ROOT}/vendor/pocock/triage/AGENT-BRIEF.md` (resolved). Do not give it
your reasoning or conclusions. Keep its findings for step 7; fix the obvious ones in the draft
and say which.

## 6. Write, suggest people and sprint, and check

1. Write `plan.json`. Record the reviewer's findings (step 5) in its `review` list, one entry
   each: `kind` (`missing`, `out_of_scope`, `too_large`, `dependency`, `untestable` or
   `fragile`), `text` (the finding and what you did about it), `status` (`fixed` when the plan
   changed, `kept` when it stays as it is, with the reason in `text`). `plan apply` ignores it.
2. Run `scrum team --json` and `scrum plan check <plan.json> --json` (with `--json` it writes
   neither `plan.html` nor the snapshot, so the page the user first sees, written in 6.5, already
   has your suggestions and no list of changes). From the second, read
   `insights`: `wave_list` (dependency waves), `sprint` (the open sprint or null), `capacity`,
   `load` (each person's points in the sprint now and from this plan, against their capacity),
   `fit` (which new tasks fit in the open sprint in dependency order, and why the others should
   stay in the backlog: `over_capacity`, `depends_on_backlog`, `no_sprint`) and `warnings`. When
   `unreadable` is true, GitHub could not be read: suggest no sprint and say so; do not tell the
   user to create a sprint.
3. Suggest an **assignee** for each task that has none, from the team only:
   - match the task's body to each member's `areas`, then prefer the one with the most room
     (`capacity` minus `load.total`); spread the tasks rather than giving one person everything;
   - never suggest a login that is not in the team list, and never replace an assignee the user
     named;
   - suggest nobody when the team is empty, or when its source is `github` and it has more than
     15 people; then say in the review that there is no team to suggest from (declaring `team`
     in `.github/scrum.yml` fixes that).
4. Suggest a **sprint** for each task whose sprint the user did not set: `"current"` for the tasks
   `fit` puts in the sprint, `null` (backlog) for the others, keeping the reason (over capacity,
   depends on a task in the backlog). With no open sprint every task is `null`, and you suggest
   `/scrum-github:sprint-new`. With an unknown capacity (no closed sprint yet) `fit` keeps every
   task in; say the capacity is not known.
5. Write the suggestions into `plan.json` and run `scrum plan check <plan.json>` again, so
   `plan.md`, `plan.html` and the numbers match the plan. In one call it validates the plan,
   writes `plan.md` and `plan.html` next to it, and prints the waves, the load, the capacity,
   warnings (logins outside the team, people or the sprint over capacity) and what `plan apply`
   would do. If it reports errors, fix the plan and run it again. If GitHub cannot be reached,
   use `--offline` (no load, capacity or actions then; say so).

## 7. Review with the user, once

Offer to open `plan.html` (its absolute path is next to `plan.json`) in the browser: `open <path>`
on macOS, `xdg-open <path>` on Linux. The Claude Code sandbox blocks opening a browser, so run
that command outside the sandbox, and only after the user agrees. The page is only for reading;
the answer comes in the chat.

Show in the chat, in one message:

- a table per feature: id, title, points, depends on, assignee, sprint (suggested values marked
  as suggestions), plus the totals;
- each person's load against their capacity, and the sprint's points after apply against its
  capacity, with the tasks left in the backlog and why;
- the reviewer's findings, and what you already changed because of them;
- the warnings `plan check` printed;
- the actions `plan check` printed (what will be created, linked, skipped);
- the paths of `plan.json`, `plan.md` and `plan.html`.

Then ask **one** question: approve, or say what to change ("T6 into Sprint 5", "T3 to
@minh-ho", "drop T5"). Apply each change to `plan.json`, run step 6.5 again (the page shows
what changed) and show the review again with the same single question. Do not ask separately
about assignees or sprints, and do not create anything before the approval. If they cancel,
stop: the plan files stay in the repository for later and nothing is created on GitHub.

## 8. Apply

Only after an explicit approval: `scrum plan apply <plan.json>`. Do not ask anything more first.
It creates what is missing (epic, features, tasks) with their sprint (milestone) and assignees,
links sub-issues and "blocked by" dependencies, writes each issue number into `plan.json` as it
goes, and renders `plan.md` and `plan.html` again. Report the created issue numbers, and say so
if a fallback was used (checklist or "Blocked by" section in the issue body). The tasks are
already in their sprint and assigned: there is no `sprint-fill` or assignment step after this.

- Run again after a failure: only the missing items are created.
- The user changed tasks that already have issues: `scrum plan apply <plan.json> --update`
  updates title, body, points and sprint of open issues. Run `scrum plan apply <plan.json>
  --dry-run --update` first and show the user what will be overwritten.
- Remind the user to commit `plan.json` and `plan.md` (`plan.html` and `.plan-snapshot.json` are
  generated and ignored by the folder's `.gitignore`).

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
