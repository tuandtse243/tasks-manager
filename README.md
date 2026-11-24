# tasks-manager

[![CI](https://github.com/tuandtse243/tasks-manager/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tuandtse243/tasks-manager/actions/workflows/ci.yml)

Run Scrum on GitHub itself, without Jira or Trello. This repository is a **Claude Code plugin
marketplace**. It currently holds one plugin, [`scrum-github`](plugins/scrum-github/README.md)
(version 0.13.0, see the [releases](https://github.com/tuandtse243/tasks-manager/releases)).

| Scrum | On GitHub |
|---|---|
| Sprint | Milestone `Sprint {n}` |
| Task | Issue with a `status: …` label and a `points: N` label, optionally a time estimate (AI work and human review) |
| Backlog | Open tasks with no milestone |
| Status | Changes on its own when a pull request with `Closes #n` is opened or merged; with a `develop` branch a merged task waits In review, labelled `on: develop`, and is Done when released into `main` |
| Branches | A preset: `trunk` (`main` only), `standard` (`develop` → `main`, the default) or `environments` (`develop` → `staging` → `main`); `protect` sets the branch rules, every pull request is checked for its title, source branch and task |
| Team | A `team` block in `.github/scrum.yml`: who works here, their areas and capacity |
| Planning | Claude splits a requirement into epic → features → tasks with suggested assignees and sprint; you approve once, then the issues are created |
| AI work | Tasks labelled `ai-ready` are worked by agents in local worktrees and come back as one pull request to review |
| Release | A tag and a GitHub Release with notes written from the tasks and their pull requests, the version suggested by semver; with `develop`, through a release pull request into `main` that publishes on merge and opens the back-merge; hotfixes from `main` |
| Deployment | Optional: a workflow for Docker (SSH and Compose) or Cloudflare (Wrangler), or the Vercel settings, mapping each long-lived branch to an environment, with approval before production and a manual rollback |
| Tracking | A progress table with a "Needs attention" section, an HTML report with a burndown, a digest every morning (also on Slack or Telegram if you want) |

## Install in three steps

1. Tools: `brew install gh jq yq`, then `gh auth login -h github.com -s repo,workflow`.
2. The plugin, in Claude Code:
   ```
   /plugin marketplace add tuandtse243/tasks-manager
   /plugin install scrum-github@tasks-manager
   ```
3. In your project's repository: `/scrum-github:init`, commit and push `.github/` to the default
   branch, `/scrum-github:protect` to create `develop` and the branch rules, then
   `/scrum-github:doctor` to check the whole setup.

## One task from start to finish

```
/scrum-github:sprint-new starting next Monday          # SM: create Sprint 1
/scrum-github:task-new Log in with email, 3 points     # PO: create task #12 in the sprint
/scrum-github:my-tasks                                 # Dev: what is on my plate, what to do next
/scrum-github:task-start 12                            # Dev: take the task, In progress, create the branch
git push -u origin feat/12-log-in-with-email           # Dev: push when the code is done
/scrum-github:task-pr                                  # Dev: PR description with "Closes #12", open the PR
                                                       # Merge the PR into develop: #12 In review, on: develop
/scrum-github:sprint-status                            # Everyone: progress and "Needs attention"
/scrum-github:release                                  # SM: release PR into main; merging it makes #12 Done
```

That is preset `standard`, what a new `init` writes. With `branching.preset: trunk` (or no
`branching` block, as before 0.13.0) the PR goes into `main` and its merge makes the task Done.

With no sprint open, `task-new` puts the task in the backlog and says so (`--backlog` does it on
purpose); `/scrum-github:sprint-fill` later moves it into a sprint. For a larger requirement,
`/scrum-github:plan` writes a plan file and a `plan.html` page to review, and creates every issue,
assigned and in its sprint, after your one approval.

Not sure what to do next? Ask `/scrum-github:next`. Tasks labelled `ai-ready` can be left to AI
agents, which work them in parallel in local git worktrees and open one pull request for review:
`/scrum-github:run` (it shows the plan and asks before anything starts; see the
[adoption guide](docs/adoption-guide.md)).

After closing a sprint, `/scrum-github:release` publishes a version: it suggests the number
(major, minor or patch from the tasks' labels), writes the release notes, and once you agree
creates the tag and the GitHub Release (`trunk`) or opens the release pull request whose merge
publishes them (`standard`, `environments`).

![One sprint with scrum-github](docs/diagrams/sprint-flow.png)

## Who reads what

| You are | Read |
|---|---|
| Product Owner | [PO cheat sheet](docs/cheat-sheet-po.md) |
| Scrum Master | [SM cheat sheet](docs/cheat-sheet-sm.md), then the [adoption guide](docs/adoption-guide.md) to set up the repository and the team's conventions |
| Developer | [Dev cheat sheet](docs/cheat-sheet-dev.md) |
| Looking up any command, option or configuration key | [The plugin's README](plugins/scrum-github/README.md) |
| Working on the plugin itself | [Project context](docs/project-context.md), [end-to-end testing](plugins/scrum-github/docs/e2e-testing.md), specs in `openspec/specs/` |

## Repository layout

```
.claude-plugin/marketplace.json   declares the "tasks-manager" marketplace
plugins/scrum-github/             the plugin's source
  skills/                         the /scrum-github:* commands
  agents/                         agents: implementer (for run), and the read-only
                                  codebase-scout, researcher, plan-critic
  runtime/                        the `scrum` CLI (bash + jq), copied into the project repo by init
  templates/                      workflows, issue form and PR template installed in the project repo
  tests/                          offline tests with a fake `gh`
docs/                             adoption guide, cheat sheets by role, project context
  diagrams/                       flow diagram (archify .json source, interactive .html, .png image)
openspec/                         specs (specs/) and change history (changes/archive/)
```

## Development

```bash
bash plugins/scrum-github/tests/run.sh          # all tests, offline, about 2 minutes
bash plugins/scrum-github/tests/run.sh plan     # only tests/test_plan.sh
```

Lint the shell code (not `vendor/`) and validate the plugin:

```bash
(cd plugins/scrum-github && shellcheck --severity=warning bin/scrum runtime/bin/scrum runtime/lib/*.sh scripts/*.sh wizards/*.sh tests/run.sh tests/test_*.sh tests/fake-gh)
claude plugin validate plugins/scrum-github     # run by hand; CI does not install Claude Code
```

CI (`.github/workflows/ci.yml`) runs the tests on Ubuntu and the `shellcheck` command above on
every pull request, and the tests on macOS too on every push to `main` (a private repository pays
ten times as much for macOS minutes). The plugin's version history is in the
[CHANGELOG](plugins/scrum-github/CHANGELOG.md).

Claude Code may create an `openspec/changes/.claude/` folder when it writes files under
`openspec/changes/`. The folder is in `.gitignore`, but `openspec list` may still show it as a
change named `.claude`; ignore it or delete it.

Every larger change goes through OpenSpec: propose it with `/opsx:propose`, implement it with
`/opsx:apply`, and when it is done, `/opsx:archive` merges its specs into `openspec/specs/`.
