# End-to-end tests on a sandbox repository

The offline tests (`bash tests/run.sh`) cover the logic. These scenarios check the real GitHub
API and workflows. Use a throwaway private repository: every step writes labels, milestones,
issues and pull requests. `SCRUM` is the path to `runtime/bin/scrum` in this plugin.

Each section lists the steps, then the result of the last run.

## Core workflow (0.1.0)

```bash
gh repo create <you>/scrum-sandbox --private --add-readme
gh repo clone <you>/scrum-sandbox && cd scrum-sandbox

# 1. Set up (run twice: the second run must report everything unchanged)
bash "$SCRUM" init --dry-run
bash "$SCRUM" init
git add .github && git commit -m "Set up Scrum on GitHub" && git push
bash "$SCRUM" init

# 2. The guide's example: a 5-day sprint and four tasks
bash "$SCRUM" sprint new --start <monday> --goal "Register, login, post, comment"
bash "$SCRUM" task new --title "Sign up via email, Facebook, LinkedIn" --points 7 --assignee <you>
bash "$SCRUM" task new --title "Login" --points 3 --assignee <you>
bash "$SCRUM" task new --title "Write a post" --points 1 --assignee <you>
bash "$SCRUM" task new --title "Add a comment" --points 3
bash "$SCRUM" task new --title "x" --points 5          # must fail: 5 is not in the scale

# 3. Pull requests
bash "$SCRUM" task start 2                             # branch feat/2-login, #2 In progress
#    commit, push, open a PR with "Closes #2"
#    open a PR from another branch with "Closes #1"    -> #1 moves New -> In progress
#    open a PR with "Solve #3"                         -> scrum-pr-link-check fails and suggests "Closes #3"
#    merge the first two PRs                           -> #1 and #2 Done and closed
#    edit the third PR to "Closes #3"                  -> check passes, #3 In progress

# 4. Progress, report, digest, close
bash "$SCRUM" status
bash "$SCRUM" report --out sprint-1.html               # open it offline
gh workflow run scrum-daily-digest.yml                 # comment on the "Sprint 1 digest" issue
bash "$SCRUM" sprint close                             # plan only
bash "$SCRUM" sprint close --yes --create-next         # velocity recorded, #3 #4 moved to Sprint 2

# 5. Feature breakdown (what /scrum-github:plan applies after approval)
bash "$SCRUM" plan apply plan.json                     # feature issue + tasks as sub-issues
```

Result of the last run (2026-11-18, `tuandtse243/scrum-sandbox`): every step behaved as described.
`init` created 10 labels and 5 files, the second run changed nothing. PR events moved #1 and #2
through In progress to Done and closed them; the `Solve #3` PR failed the check with the
suggestion, and passed after the edit. `status` showed 10 of 14 points done (71%), the report's
burndown read 14, 14, 4 for the first three days, the digest posted on issue #8, and closing the
sprint recorded velocity 10, created Sprint 2 and moved #3 and #4 with a comment. `plan apply`
created feature #9 with #10 and #11 as sub-issues.

## Project board (0.2.0)

```bash
gh auth refresh -s project
gh project create --owner <you> --title "scrum-sandbox board"      # then link it to the repo
#    turn off the conflicting built-in workflows (project > Workflows)
#    add the secret SCRUM_PROJECT_TOKEN (classic token: repo, project)
#    add project: {enabled: true, owner: <you>, number: <n>} to .github/scrum.yml
bash "$SCRUM" init --force-file .github/workflows/scrum-status-sync.yml   # push .github
bash "$SCRUM" project init --dry-run
bash "$SCRUM" project init                             # twice: the second run changes nothing
gh workflow run scrum-project-sync.yml                 # green: "0 added, 0 changed, N unchanged"
#    open and merge a PR "Closes #4"                   -> card In Progress, then Done, in the status-sync run
#    drag a card Todo -> In Progress, run the sync      -> label "status: In progress"
#    drag a card to Done, run the sync                 -> issue closed as completed
#    drag it back to Todo, run the sync                -> issue reopened, label New, status-sync keeps New
bash "$SCRUM" task new --title "x" --points 1           # card added in Todo with Points 1
```

Result of the last run (2026-11-18, `tuandtse243/scrum-sandbox`, project #1):
- `project init` created *Synced status* and *Points*, and added #3, #4, #10 and #11 in their
  columns with their points. The second run changed nothing.
- The workflow failed with a clear error while the secret was empty, and again while it held a
  bad token (HTTP 401). It passed once the secret held a classic token with `repo` and `project`.
- The PR for #4 moved its card to In Progress and then to Done, within the status-sync runs.
- Dragging #10 changed its label.
- Dragging #11 to Done closed it as completed. Dragging it back to Todo reopened it as New, and
  the status-sync run for the reopen reported "already new".
- A label change started `project sync --issue 3` through `issues.labeled`.
- `task new` put #13 on the board.

Covered only by the offline tests:
- **"Both sides changed: the label wins."** Here, dragging #3 to Done while setting its label to
  New ended as Done, because the built-in *Auto-close issue* closes the issue as soon as the card
  reaches Done, and a completed issue counts as Done. The end state agrees on both sides.
- **A column that is not in `status_options`.** Adding an option through the API recreates every
  option and empties the cards' Status, so this needs the board UI.

## Plans (0.3.0)

Run inside a sandbox clone that has some code, after `scrum init` (for the `type: epic` label).

```bash
# Offline first: no GitHub call, no write outside docs/
bash "$SCRUM" context inventory                        # has_code: true
bash "$SCRUM" plan init "Blog post comments"           # docs/plans/blog-post-comments/
#    write docs/plans/blog-post-comments/plan.json: an epic, two features, a dependency,
#    one task with "sprint": null (backlog) and the others with "sprint": "current"
bash "$SCRUM" plan validate docs/plans/blog-post-comments/plan.json
bash "$SCRUM" plan render docs/plans/blog-post-comments/plan.json --offline

# Against GitHub
bash "$SCRUM" plan check docs/plans/blog-post-comments/plan.json      # actions, nothing written
bash "$SCRUM" plan apply docs/plans/blog-post-comments/plan.json      # epic, features, tasks, links
bash "$SCRUM" plan apply docs/plans/blog-post-comments/plan.json      # second run: "Nothing to do"
#    set "sprint": "Sprint 1" on the backlog task
bash "$SCRUM" plan apply docs/plans/blog-post-comments/plan.json --dry-run --update
bash "$SCRUM" plan apply docs/plans/blog-post-comments/plan.json --update   # milestone set
bash "$SCRUM" status                                   # epic and feature not counted

# Skills, in Claude Code
/scrum-github:project-scan                             # docs/project-context.md with a stamp
/scrum-github:discover let readers comment under a post
/scrum-github:plan docs/plans/<slug>/brief.md
```

Result of the last run (2026-11-19, `tuandtse243/scrum-sandbox`, a small Node blog API; the skills
were driven in headless Claude Code sessions with the plugin loaded):
- `scrum init` on the 0.2.0 install created only `type: epic` and updated the runtime.
- The API answers were recorded in `tests/fixtures/github-*.json`. An existing "blocked by" or
  sub-issue link answers 422, the same as a refusal, which is why `apply` reads the links first.
- `/scrum-github:plan` with a clear feature: the critic's two findings were fixed in the draft, a
  task's points were changed, and after approval it created feature #14 with #15 and #16 as
  sub-issues, #16 blocked by #15, both in Sprint 2 and on the board. Adding a task and applying
  again created only #17. "làm cho app nhanh hơn" got the missing parts named and `discover`
  suggested.
- `/scrum-github:project-scan` wrote the context with a stamp. After a commit to `tests/` the next
  scan re-read only that folder. A `--full` scan kept the "Team notes" byte for byte.
- `/scrum-github:discover`:
  - `--quick` used no agent and asked one round. Without a project context it suggested
    `project-scan` and read only the code involved.
  - Standard depth asked two rounds of numbered questions with suggestions, then wrote a brief
    that passed `doc check`.
  - Cancelling saved nothing.
  - The fit check gave "fits", "fits with changes", and, for an in-memory list of online users in
    the stateless API, "conflicts" with three options before any brief.
  - The context warning said "81 commits old" after 81 commits, and "cannot tell" for a stamp
    whose commit is not in the history.
- `/scrum-github:plan docs/plans/binh-luan-bai-viet/brief.md` copied the brief's assumptions and
  out-of-scope items. Apply created epic #18 with features #19 (Sprint 2) and #20 (backlog), and
  tasks #21-#26 with four "blocked by" links. The backlog tasks had no milestone and were not
  added to the board.
- `plan apply --dry-run --update` listed one update (T4 #25: sprint backlog -> Sprint 2);
  `--update` set the milestone, kept the status label and added the card. A second `apply` said
  "Nothing to do" and left `plan.md` identical.
- `scrum status` counted 13 tasks (25 points) in Sprint 2; features #9 and #14 were not counted.

## Vendored skills, pull request description, questionnaire (0.4.0)

```bash
# Maintainer side, in this repository
scripts/vendor-sync.sh                                 # clones upstream; `git diff vendor/` must be empty when up to date

# In the sandbox clone
bash "$SCRUM" init                                     # runtime 0.4.0; the old PR template is reported as a conflict
bash "$SCRUM" init --force-file .github/pull_request_template.md    # commit and push .github
bash "$SCRUM" task new --title "..." --body "..." --points 1
bash "$SCRUM" task start <n>                           # commit a change on the branch, push it
/scrum-github:task-pr                                  # description in four sections with "Closes #<n>"; approve; PR opened
#    the check scrum-pr-link-check passes; merge       -> task Done and closed
/scrum-github:discover <idea using a word the glossary avoids, with a decision someone else owns> --quick
#    -> a question about the term; an offer to write a questionnaire; brief stays "Status: draft"
/scrum-github:plan docs/plans/<slug>/brief.md          # lists the open questions; continue -> assumptions
#    write the answers under the questions in questionnaire-<who>.md
/scrum-github:discover docs/plans/<slug> --quick       # answers move to "Decisions"; "Open questions" is gone
bash <plugin>/wizards/project-board.sh                 # in a terminal you type into
```

Result of the last run (2026-11-19, `tuandtse243/scrum-sandbox`; the skills were driven in
headless Claude Code sessions with the plugin loaded from this repository):
- `vendor-sync.sh` without a path cloned upstream at `5863806` and produced a tree identical to
  `vendor/pocock/`.
- `scrum init` installed runtime 0.4.0 and kept the 0.3.0 pull request template as a conflict;
  `--force-file` replaced it. Nothing under `vendor/` and no wizard reached the sandbox.
- `/scrum-github:task-pr` on `feat/27-count-the-posts-in-the-store`: Summary as a small diff
  sketch, Evidence with the failing and passing test run, Merge Danger, and "Closes #27". It said
  which acceptance criteria the evidence covered, and waited for approval. The headless session
  could not call `gh` (its sandbox), so it stated what it had not read, took the issue pasted in,
  and handed over the `gh pr create` command; run by hand, that opened PR #28. `linked-task`
  passed, the task went to In progress, and merging closed #27 as Done.
- `/scrum-github:discover --quick` with "owner của bài viết" and a limit "do product owner
  quyết": the first question quoted the glossary ("Avoid: user id, owner") and proposed
  **Author**; the second offered `questionnaire-chi-lan.md`. The brief was written with
  `Status: draft` and an "Open questions" section, passed `doc check`, and the `/scrum-github:plan`
  step was not printed.
- `/scrum-github:plan` on that draft listed the two open questions and asked whether to wait or
  continue. Continuing wrote them as assumptions. The four task bodies describe behaviour, cite no
  file path, and each ends with "Out of scope: ...". The critic's findings included a criterion
  that tested an internal mechanism, which was rewritten as behaviour.
- After the answers were written into the questionnaire, `/scrum-github:discover` on the folder
  moved them to "Decisions", recorded them as round 2, removed "Open questions", and warned that
  the existing `plan.json` still held the assumed limit.
- The wizard, run on the sandbox's own `.github/scrum.yml` with typed answers on stdin and no
  token entered: all five stages, the secret reported as still to do, and the config byte for
  byte unchanged (the block already held these values). An earlier build rewrote the file with
  `yq -i` and lost every blank line; the wizard now edits only the three lines.

Not run yet, needs a person:
- **The wizard in a real terminal**: the browser pages it opens, the names of the things to click
  on GitHub, and `gh secret set` with a real token. The offline tests cover its logic with a
  stand-in `gh`.
- **`/scrum-github:task-pr` creating the pull request itself**: in a session where `gh` works,
  the skill runs `gh pr create` after approval instead of handing over the command.

One thing to know when driving skills headless from a very long working directory: one session
wrote the brief under a mistyped copy of the path. Asking for paths relative to the current
directory avoided it.

## Team, backlog and my tasks (0.9.0)

```bash
# A sandbox with one sprint open and no team block (the team is who GitHub lets you assign)
/scrum-github:plan "show the app version, with a test"   # critic, plan.html, approve once
bash "$SCRUM" plan check docs/plans/<slug>/plan.json --json   # sprint and assignee per task
bash "$SCRUM" plan apply docs/plans/<slug>/plan.json
bash "$SCRUM" mine                                     # sprint open: the new task, "Next: ..."
#    close the open sprint (or use a repository without one)
bash "$SCRUM" task new --title "..." --points 1         # no open sprint -> backlog
bash "$SCRUM" mine                                     # "(no sprint is open)", Backlog group
bash "$SCRUM" team                                     # "no load is shown" without a sprint
```

Result of the last run (2026-11-24, `tuandtse243/scrum-sandbox`, preset `standard`, one person,
Sprint 2 over capacity: 27 of 10 points):
- `plan init` wrote a `.gitignore` for `plan.html` and `.plan-snapshot.json` only. The critic gave
  five findings, recorded as `review` entries and shown in `plan.html`.
- `plan check --json` suggested the backlog for the task (sprint over capacity) and the only
  person as assignee, and wrote neither `plan.html` nor the snapshot.
- `plan.html`: eight sections, no remote `src`/`href`, light and dark, reduced motion, escaped text.
  The first view said there was nothing to compare yet; after "T1 into Sprint 2" the next view
  listed "T1 sprint: Backlog → Sprint 2" and nothing was created. Checked by reading the file (the
  session could not open a browser).
- After one approval, `plan apply` created feature #38 and task #39: Sprint 2, assignee,
  `status: New`, `points: 1`, `ai-ready`, sub-issue of #38, on the board.
- `mine` with Sprint 2 open listed #39 with "Next: #39 … scrum task start 39"; with no sprint open
  it showed "(no sprint is open)" and the Backlog group, and suggested `/scrum-github:sprint-new`.
- `task new` with no sprint open put #40 in the backlog: "There is no open sprint, so the task is in
  the backlog".
- Noted: `plan check` still says "better left in the backlog: T1" after T1 was put in the sprint by
  hand; the feature gets no milestone (only tasks do).

## Branches and releases (0.13.0)

```bash
# A sandbox clone with preset standard in .github/scrum.yml
bash "$SCRUM" init                                     # on: develop, scrum-release.yml, governance files
git add .github && git commit -m "Set up Scrum on GitHub" && git push
bash "$SCRUM" protect                                  # preview
bash "$SCRUM" protect --yes                            # develop, rulesets, settings
bash "$SCRUM" task new --title "..." --points 1 && bash "$SCRUM" task start <n>
#    commit, push; meanwhile push another commit to develop
/scrum-github:task-pr                                  # base develop, warns: behind develop
bash "$SCRUM" sync                                     # merges origin/develop into the task branch
#    open the PR into develop ("feat: ...", "Closes #<n>"); checks pass; squash-merge it
#                                                      -> task stays In review, label "on: develop"
bash "$SCRUM" release 0.1.0                            # preview: the task, the version
bash "$SCRUM" release 0.1.0 --yes                      # release/v0.1.0 -> main; no tag yet
#    merge the release PR with a merge commit          -> scrum-release.yml: tag, GitHub Release,
#                                                         task Done and closed, back-merge PR
#    close and reopen the back-merge PR (its checks), merge it with a merge commit
```

Result of the last run (2026-11-24, `tuandtse243/scrum-sandbox`, private, free plan):
- `protect --yes` created `develop` and applied the merge settings and the Actions setting; the
  three rulesets were refused with 403 (rulesets need a public repository or a paid plan), each
  reported, exit 1.
- Task #32 started from `origin/develop`; its PR #33 into `develop` passed `pr-check` and moved #32
  to In review; after the squash merge #32 stayed open, In review, with `on: develop`.
- `release 0.1.0 --yes` opened #34 from `release/v0.1.0`. Merging it ran `scrum-release.yml`:
  annotated tag `v0.1.0` on the merge commit, GitHub Release, #32 Done and closed without its
  location label, back-merge #35 opened by the workflow. #35 ran its checks only after close and
  reopen; merged, `develop` contained `main`.
- The `task-pr` steps on `feat/36-…` (task #36): base `develop` from the preset, 1 commit ahead and
  1 behind, so the warning and the `sync` suggestion; `sync` brought the commit in; PR #37 with
  `feat: show the version in the footer` and "Closes #36" passed `pr-check`, #36 In review. The
  steps were run by hand from the skill text, not by invoking the skill.

The same flow on a public repository, this one (2026-11-24, release 0.13.1): `protect --yes`
applied all three rulesets; `release 0.13.1 --yes` committed `plugin.json`, `runtime/VERSION` and
the README version on `release/v0.13.1` (PR #29); merging it tagged `v0.13.1` on the merge commit,
published the release and opened back-merge #30, merged after close and reopen.

## Hotfix (0.13.0)

```bash
# In a sandbox clone with preset standard, v0.1.0 already tagged on main
bash "$SCRUM" task new --title "..." --bug --points 1 --backlog   # a bug task with acceptance criteria
bash "$SCRUM" hotfix <n>                               # hotfix/<n>-slug from origin/main; task In progress
#    fix it with a test, commit, push
bash "$SCRUM" hotfix prepare                           # preview: version, marker, notes; changes nothing
bash "$SCRUM" hotfix prepare --yes                     # version files and changelog, one commit
bash "$SCRUM" hotfix prepare --json                    # {tag, version, previous, task, marker, bump, notes}
#    open the PR into main ("fix: ...", "Closes #<n>", "Merging this publishes vX.Y.Z.", the marker)
#    pr-check passes; merge it with a merge commit     -> scrum-release.yml: tag, GitHub Release,
#                                                         task Done and closed, back-merge PR
#    close and reopen the back-merge PR (its checks), merge it with a merge commit
```

Result of the last run (2026-11-25, `tuandtse243/scrum-sandbox`, private, free plan, `node --test`):
- Bug task #46 ("createPost reuses an id after a gap", `bug`, 1 point, backlog). `hotfix 46` created
  `hotfix/46-createpost-reuses-an-id-after-a-gap` from `origin/main` (its parent is the head of
  `main`, not of `develop`), assigned #46 and set it In progress. The fix and its test were
  committed and pushed by hand.
- `hotfix prepare` previewed `v0.1.1` (patch, previous `v0.1.0`) with release notes from the task
  title. The sandbox's `.github/scrum.yml` has no `release.version_files` or `release.changelog`, so
  `--yes` committed nothing and said so, and `--json` gave `marker`
  `<!-- scrum-release-tag: v0.1.1 -->`. Writing version files and a changelog on a hotfix branch was
  therefore not exercised by this run.
- PR #47 into `main` with `fix: give a new post an id above every existing id`, "Closes #46", the
  line "Merging this publishes v0.1.1." and the marker: `pr-check` passed (a `hotfix/*` source into
  `main` is allowed). Merged with a merge commit.
- `scrum-release.yml` ran (17 s): annotated tag `v0.1.1` pointing at the merge commit, GitHub Release
  `v0.1.1` with the notes, #46 Done and closed, back-merge PR #48 into `develop` opened. #48 ran its
  checks only after close and reopen; merged with a merge commit, `develop` contained `main`.
- Everything matched the specs ("Start a hotfix", "Hotfix release", "Publishing on merge"); no
  plugin problem found. Noted: the sandbox's `npm test` (`node --test tests/`) fails on a directory
  argument with the Node of this machine; `node --test tests/*.test.js` passes (7 of 7).

## AI run (0.11.0)

```bash
# In the sandbox clone (preset standard): two ai-ready tasks in the open sprint, #43 blocked by #42
bash "$SCRUM" run plan                                 # 2 waves
claude --plugin-dir <plugin>                           # in a terminal you type into
/scrum-github:run 42,43                                # plan, warning, yes; wave 1, wave 2; one PR
```

Result of the last run (2026-11-25, `tuandtse243/scrum-sandbox`, a Node API, `node --test`):
- The run created `run/sprint-2-tuandtse243` from `origin/develop`, one agent per task in its own
  worktree (wave 1: #42, wave 2: #43), one merge commit per task, `node --test` 11 of 11 on the
  integration branch, and one pull request into `develop` (#45) with "Closes #42", "Closes #43",
  the acceptance criteria as checkboxes and "look closely at" notes. Both tasks were In review.
  Only the integration branch reached origin; no task branch did.
- Found: the title of that pull request ("Sprint 2: 2 tasks by AI (#42, #43)") failed `pr-check`
  in preset `standard`. Fixed: it starts with `feat:`.
- Found: the agents' worktrees started at the default branch (`main`), not at the integration
  branch, so the first agent stopped on its base check; the others reset the worktree by hand.
  Fixed: the `implementer` resets a fresh worktree to the base commit.
- The sandbox's tests write to `/tmp`, which the agents' sandbox blocks, so the tests were run
  outside it. Estimates: none were set, so "estimated against actual" showed nothing (0 minutes
  actual: each agent took 20 to 30 seconds).
- The headless attempts (`claude -p`) could not run it: `gh` fails its certificate check inside the
  Claude sandbox (OSStatus -26276). Run it in a terminal.

Not run yet on GitHub: `promote` (preset `environments`), the
deployment templates, and `--pr-per-wave`.
