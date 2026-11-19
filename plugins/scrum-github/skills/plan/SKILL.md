---
name: plan
description: Break a requirement into an epic, features and Scrum tasks with acceptance criteria, story points and dependencies; save it as a plan file in the repo (docs/plans/<slug>/plan.json and plan.md) for the user to review; after approval create the issues on GitHub. Re-running continues the same plan without duplicates. Use when the user wants a feature, user story, requirement or brief planned, split or estimated into tasks. Replaces sprint-plan. Pass --quick to skip the independent review.
argument-hint: "<brief path | requirement text> [--quick]"
---

# Plan a requirement into tasks

`scrum` below means `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"`, run from the root of the
target repository. Nothing is created on GitHub until the user approves the plan.

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
  `assignees` only if the user named people, `bug` for defects.
- Several independent streams of work become several features under one `epic`; one stream is
  one feature and no epic.
- From a brief: plan only what its "In scope" section lists; the brief's size estimate gives the
  starting structure (task, feature, or epic); copy its assumptions into `assumptions` and its
  out-of-scope items into `out_of_scope`.
- `sprint`: leave it empty (backlog) unless the user names a sprint or says "this sprint"
  (`"current"`). A task may have its own `sprint`.
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

## 6. Write and check

Write `plan.json`, then run `scrum plan check <plan.json>`. In one call it validates the plan,
writes the view `plan.md`, and prints what `plan apply` would do. If it reports errors, fix the
plan and run it again. If GitHub cannot be reached, use `scrum plan check <plan.json> --offline`.

## 7. Review with the user

Show:

- a table per feature: id, title, points, depends on, plus the totals (from `plan.md`);
- the reviewer's findings, and what you already changed because of them;
- the estimate section of `plan.md` (points, hours if configured, sprints from velocity);
- the actions `plan check` printed (what will be created, linked, skipped);
- the paths of `plan.json` and `plan.md`.

Ask the user to approve, or to change, drop or add tasks. Apply the edits to `plan.json` and repeat
steps 6 and 7 until they approve. If they cancel, stop: the plan files stay in the repository for
later and nothing is created on GitHub.

## 8. Apply

Only after an explicit approval: `scrum plan apply <plan.json>`. It creates what is missing (epic,
features, tasks), links sub-issues and "blocked by" dependencies, writes each issue number into
`plan.json` as it goes, and renders `plan.md` again. Report the created issue numbers, and say so
if a fallback was used (checklist or "Blocked by" section in the issue body).

- Run again after a failure: only the missing items are created.
- The user changed tasks that already have issues: `scrum plan apply <plan.json> --update`
  updates title, body, points and sprint of open issues. Run `scrum plan apply <plan.json>
  --dry-run --update` first and show the user what will be overwritten.
- Remind the user to commit `plan.json` and `plan.md`.

`gh` cannot read its keychain token inside the Claude Code sandbox; run `plan check` and
`plan apply` outside it if needed.
