---
name: scrum-init
description: Set up a GitHub repository for Scrum - create .github/scrum.yml, sync status and points labels, install the task issue form, the PR template, the status/link-check/digest workflows and the vendored runtime. Use when the user wants to start using Scrum on GitHub in a repo, or after changing scrum.yml.
---

# Set up Scrum on GitHub

The script is `${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum`. Run it with `bash` from the root of the
repository the user wants to manage (a clone with a GitHub remote). Call it `scrum` below.

## Steps

1. **Preview.** Run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum" init --dry-run` and show the user
   what would change: config file, labels to create or update, obsolete labels (never deleted),
   files to create, and conflicts.
2. **Confirm.** Ask the user to confirm before writing. If there are conflicts, ask per file whether
   to overwrite it; add `--force-file <path>` for each file they want overwritten.
3. **Apply.** Run `scrum init` (with the chosen `--force-file` options).
4. **Commit.** Tell the user to commit and push `.github/` so the workflows run on GitHub. Offer to do
   it for them; only commit and push if they say yes.
5. If `.github/scrum.yml` was just created, mention the main settings they may want to change
   (point scale, sprint length, time zone) and that they can re-run this command afterwards.

## Notes

- The command is idempotent: running it again changes nothing unless the configuration changed.
- After changing `digest.cron`, re-run with `--force-file .github/workflows/scrum-daily-digest.yml`.
- After changing `points.scale`, re-run with `--force-file .github/ISSUE_TEMPLATE/task.yml`.
- `gh` reads its token from the macOS keychain, which the Claude Code sandbox blocks. If `gh`
  reports an invalid token although the user is logged in, run the command outside the sandbox.
