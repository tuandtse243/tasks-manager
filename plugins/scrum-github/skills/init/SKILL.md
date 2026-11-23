---
name: init
description: Set up a GitHub repository for Scrum - create .github/scrum.yml, sync status and points labels, install the task issue form, the PR template, the status/link-check/digest workflows and the vendored runtime. Use when the user wants to start using Scrum on GitHub in a repo, after changing scrum.yml, or after updating the plugin.
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
6. Suggest `/scrum-github:doctor` to check the whole setup, and `/scrum-github:next` for what to do
   after it.

## Notes

- The command is idempotent: running it again changes nothing unless the configuration or the
  plugin changed.
- `init` records what it writes in `.github/scrum/files.json`. A file nobody edited since is
  updated on its own when the configuration (`points.scale`, `digest.cron`, `project.poll_cron`)
  or the plugin changes. Only a file edited by hand is a `conflict`.
- A repository set up before 0.5.0 has no record yet, so the first run after updating reports
  every file that differs from the new template as a `conflict`.
- To remove what `init` installed: `scrum uninstall` (it shows what it would remove; add `--yes`).

If a `scrum` or `gh` command fails on login or network, run `/scrum-github:doctor`.
