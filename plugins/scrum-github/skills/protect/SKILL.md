---
name: protect
description: Protect a GitHub repository for the team's branching preset - create the missing long-lived branches (develop, staging) from main, apply rulesets to every long-lived branch (pull request required, required checks, approvals, merge methods, no force push or deletion), protect version tags, and set the repository merge settings. Shows a preview first and applies only after the user agrees. Use after init, when doctor reports an unprotected branch or a missing branch, or when the user asks to protect main or set up branch rules.
---

# Protect the repository

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the repository (a clone with a GitHub remote). Changing rules and settings
needs admin rights on the repository.

## Steps

1. **Preview.** Run `scrum protect`. It reads the repository and prints what the preset
   (`branching.preset` in `.github/scrum.yml`) needs and what differs:
   - **Branches**: long-lived branches to create from the head of the release branch (`main`).
     Existing branches are never moved or deleted.
   - **Rules**: one ruleset per long-lived branch (`scrum: working`, `scrum: staging`,
     `scrum: release`) and one for version tags (`scrum: tags`), each `create`, `update` or `ok`.
   - **Repository settings**: merge methods, deleting head branches after merge, auto-merge.
   If it says "Nothing to change", tell the user the repository already matches and stop.
2. **Explain.** Say in plain words what changes for the team, for example: nobody can push to
   `main` directly any more; every change needs a pull request with `governance.approvals`
   approvals and the `pr-check` check (plus `governance.required_checks`); task pull requests are
   squash-merged into `develop`; releases and back-merges use merge commits; version tags can no
   longer be moved or deleted. For `governance.approvals: 0` say that a pull request is still
   required but no approval.
3. **Confirm.** Ask the user to confirm. Never run `--yes` before they agree.
4. **Apply.** Run `scrum protect --yes`. Show the result. Lines marked `FAILED` say why
   (for example rules are not available for a private repository on a free plan, or the token has
   no admin rights); the other items are still applied and the command exits with 1.
5. Suggest `/scrum-github:doctor` to check the result.

## Notes

- `scrum protect --json` prints the plan as data (with `--yes`, also the result of each item).
- The required check `pr-check` is the job of `.github/workflows/scrum-pr-link-check.yml`
  (installed by `/scrum-github:init`); push `.github/` first so the check exists, or pull requests
  wait for a check that never runs.
- Rulesets named `scrum: ...` that the preset no longer uses are listed as `obsolete` and not
  deleted; the user deletes them in Settings → Rules if they want.
- Running it again is safe: it only changes what differs.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
