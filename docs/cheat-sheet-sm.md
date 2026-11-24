# Cheat sheet: Scrum Master

The Scrum Master's commands in the order a sprint uses them. Type them in Claude Code, at the
root of the project's repository. Every option: [the plugin's README](../plugins/scrum-github/README.md).
Setting up a repository and the team's conventions: [the adoption guide](adoption-guide.md).

## Once per repository

| What | Command | Example |
|---|---|---|
| Set up the repository: configuration, labels, workflows | `/scrum-github:init` | `/scrum-github:init`, then commit and push `.github/` |
| Branch rules, `develop` (and `staging`), merge settings (admin) | `/scrum-github:protect` | `scrum protect`, then `scrum protect --yes` |
| Check the whole setup | `/scrum-github:doctor` | `/scrum-github:doctor` |
| (Optional) Turn on the project board | `/scrum-github:project-setup` | `/scrum-github:project-setup` |

After changing `.github/scrum.yml` (points scale, digest time, language, In review, preset,
deployment platform), run `init` again; after changing `branching.preset`, run `protect` again.

A new `init` writes `branching.preset: standard`: tasks go into `develop`, and reach `main` (and
Done) with a release. `trunk` keeps a single `main`; `environments` adds `staging`. With
`deploy.platform` (`docker`, `cloudflare`, `vercel`) `init` sets up the deployment and prints the
secret names to create; add required reviewers to the GitHub environment `production`. Details:
[the adoption guide](adoption-guide.md#flow-k-deploy).

## The team

List who works on the repository in the `team` block of `.github/scrum.yml`:

```yaml
team:
  - login: tuandt
    areas: [backend, api]
    capacity: 10        # points per sprint
    review_hours: 6     # hours of review and manual testing per sprint
  - login: an-nguyen
    areas: [frontend]
```

Every key but `login` is optional. `/scrum-github:plan` suggests assignees from it, and creating
or assigning a task warns (without stopping) about a login that is not in it. Without `team`, the
team is the people GitHub lets you assign issues to. To see each person's areas, capacity and
load in the open sprint, run `scrum team` (there is no slash command for it: ask Claude to run
it, or run it in a terminal).

## Start of the sprint

| What | Command | Example |
|---|---|---|
| Create the sprint | `/scrum-github:sprint-new` | `/scrum-github:sprint-new starting next Monday, goal "Sign-up and login"` |
| Choose the sprint's tasks against its capacity | `/scrum-github:sprint-fill` | `/scrum-github:sprint-fill` |
| Check the load per person | `scrum team` | `scrum team` |

`sprint-fill` works out the capacity from the average velocity of up to the last three closed
sprints (or the capacity you give), shows what is planned and the backlog, proposes tasks in
dependency order, and moves them only after you approve. When tasks have time estimates, it also
compares each person's review minutes with their `review_hours`.

## Every day

| What | Command | Example |
|---|---|---|
| Progress by person, "Needs attention" | `/scrum-github:sprint-status` | `/scrum-github:sprint-status who is blocked?` |
| Change a task: points, assignee, sprint, drop it | `/scrum-github:task` | `/scrum-github:task assign #15 to an-nguyen` |
| One person's work and their pending reviews | `/scrum-github:my-tasks` | `/scrum-github:my-tasks for an-nguyen` |
| Your own next step | `/scrum-github:next` | `/scrum-github:next` |

| What waits on `develop` (merged, not released), drift, stale branches | `/scrum-github:branches` | `scrum branches` |
| Move `develop` to `staging` for testing (preset `environments`) | `/scrum-github:promote` | `/scrum-github:promote` |

"Needs attention" lists blocked tasks, tasks In progress with no activity, tasks without an
assignee or points, tasks waiting on a branch longer than `attention.promote_days`, and a sprint
behind the ideal line. When tasks have time estimates, the
status table also shows the work and review minutes left per person. The morning digest has the
same section.

## End of the sprint

| What | Command | Example |
|---|---|---|
| Burndown and velocity report | `/scrum-github:sprint-report` | `/scrum-github:sprint-report` |
| Close the sprint, record velocity, carry over unfinished tasks | `/scrum-github:sprint-close` | `/scrum-github:sprint-close` |
| Publish a version | `/scrum-github:release` | `/scrum-github:release --sprint "Sprint 5"` (`trunk`), `/scrum-github:release` (with `develop`) |
| Merge the back-merge PR the release opened (merge commit) | (on GitHub) | "Back-merge main into develop" |

Closing the sprint posts a summary on the issue `Sprint N digest` for the review, and suggests a
release when the sprint had Done tasks. With `develop`, tasks merged but not released are not in
the velocity: closing carries them over as "merged but not released", so release before closing to
count them. `release` suggests the version (major for a task labelled `breaking`, minor when a task
is not a bug, patch for bugs only) and writes the notes from the tasks and their pull requests;
after you agree it creates the tag and the GitHub Release (`trunk`) or opens the release PR
`release/<tag>` into `main`. Merging that PR publishes the tag and the release, sets the tasks Done
and opens the back-merge PR. That PR was opened by the workflow's token, so its checks do not
start: close and reopen it, then merge it with a merge commit.

A command fails on login or network: `/scrum-github:doctor`.
