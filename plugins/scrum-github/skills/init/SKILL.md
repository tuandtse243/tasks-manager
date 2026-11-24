---
name: init
description: Set up a GitHub repository for Scrum - create .github/scrum.yml, sync status and points labels, install the task issue form, the PR template, the status/PR-check/digest (and, with a working branch, release) workflows, the governance files (CODEOWNERS, CONTRIBUTING.md, SECURITY.md, dependabot.yml) and the vendored runtime. Use when the user wants to start using Scrum on GitHub in a repo, after changing scrum.yml, or after updating the plugin.
---

# Set up Scrum on GitHub

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.
Run it from the root of the repository the user wants to manage (a clone with a GitHub remote).

## Steps

1. **Preview.** Run `scrum init --dry-run` and show the user what would change: config file,
   labels to create or update, obsolete labels (never deleted), files to create or update, and
   conflicts.
2. **Confirm.** Ask the user to confirm before writing. If there are conflicts, ask per file whether
   to overwrite it; add `--force-file <path>` for each file they want overwritten.
3. **Apply.** Run `scrum init` (with the chosen `--force-file` options).
4. **Commit.** Tell the user to commit and push `.github/` so the workflows run on GitHub. Offer to do
   it for them; only commit and push if they say yes.
5. If `.github/scrum.yml` was just created, mention the main settings they may want to change
   (point scale, sprint length, time zone) and that they can re-run this command afterwards.
6. Suggest `/scrum-github:protect` once `.github/` is pushed (it creates `develop` and the branch
   and tag rules of the preset), then `/scrum-github:doctor` to check the whole setup, and
   `/scrum-github:next` for what to do after it.

## Notes

- The command is idempotent: running it again changes nothing unless the configuration or the
  plugin changed.
- `init` records what it writes in `.github/scrum/files.json`. A file nobody edited since is
  updated on its own when the configuration (`points.scale`, `digest.cron`, `project.poll_cron`)
  or the plugin changes. Only a file edited by hand is a `conflict`.
- A repository set up before 0.5.0 has no record yet, so the first run after updating reports
  every file that differs from the new template as a `conflict`.
- A new `.github/scrum.yml` uses `branching.preset: standard` (`develop` for work, `main` for
  releases). Explain the choice briefly: `trunk` keeps one branch (a task is Done when merged),
  `environments` adds `staging`. An existing file without a `branching` block works as `trunk`.
- Governance files (`.github/CODEOWNERS`, `.github/CONTRIBUTING.md` for the preset,
  `.github/SECURITY.md`, `.github/dependabot.yml`) are created only when the project has none of
  them (also at the root or in `docs/`); `init` never overwrites them and reports `skipped`.
  `CODEOWNERS` lists `governance.codeowners`; with none it has a commented example to fill in.
- The PR check workflow checks the pull request title (Conventional Commits, for example
  `feat(auth): log in with email`), the source branch (task branches target `develop`; `main`
  accepts only `release/*` and `hotfix/*`) and the linked task. Scheduled and issue-triggered
  workflows check out the working branch for the configuration and the runtime.
- With `deploy.platform: docker` or `cloudflare`, `init` installs `.github/workflows/deploy.yml`
  (each long-lived branch to its GitHub environment, manual rollback), and skips a `deploy.yml`
  the project wrote itself. With `vercel` it installs no workflow and writes the Vercel settings
  into the `CONTRIBUTING.md` it creates. Relay the secret names and the settings page `init`
  prints, and tell the user to add required reviewers to the environment `production`. Never ask
  the user for a secret value or set one: they enter values on the GitHub settings page.
- To remove what `init` installed: `scrum uninstall` (it shows what it would remove; add `--yes`).
- Mention the optional `team` block of `.github/scrum.yml` (an example is commented in the
  file): members with `login`, `areas` and `capacity`. `/scrum-github:plan` suggests assignees
  from it and `scrum team` shows each person's load. Without it, the team is the people GitHub
  lets you assign issues to.

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
