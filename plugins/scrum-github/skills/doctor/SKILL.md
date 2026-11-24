---
name: doctor
description: Check that Scrum on GitHub can work in this repository - jq, yq (mikefarah), gh login and scopes, .github/scrum.yml, labels, workflows pushed to the default branch, runtime version, generated files, the long-lived branches of the preset, the default branch, branch rules, a missing back-merge, the governance files, and the project board secret - and say how to fix each problem. Read-only. Use when a scrum-github command fails, after installing the plugin, or when the user asks whether their setup is right.
---

# Check the setup

Every `scrum ...` command below means `bash "${CLAUDE_PLUGIN_ROOT}/bin/scrum" ...`. Use that full form from
the first call: a bare `scrum` is only on the PATH when the plugin is installed for the user and was loaded
at session start, so it fails right after an install or with a local-scope install. `gh` reads its token
from the keychain and talks to GitHub, which the Claude Code sandbox blocks, so run commands that reach
GitHub outside the sandbox from the start (the user approves it) instead of failing inside it first.

1. From the root of the repository the user wants to manage, run `scrum doctor`. It only reads,
   from the machine and from GitHub, and exits with 1 when there is at least one error.
2. Show the report as it is. Then go through the lines marked `error`, then `warn`: say in one
   sentence what each means for the user, and the fix printed under it.
3. Offer to run the fixes that are commands (for example `gh auth refresh -s workflow`, or
   `/scrum-github:init`). Run one only when the user agrees. Steps only a person can do (adding a
   repository secret, approving a command outside the sandbox) stay with the user.
4. After fixing, run `scrum doctor` again and confirm what is left.

The "Branches and governance" group checks that the default branch is the release branch
(`main`), that every long-lived branch of the preset exists and has a rule (fix:
`/scrum-github:protect`), that `main` holds nothing the lower branches lack (otherwise a
back-merge is missing), and that `CODEOWNERS`, `CONTRIBUTING.md`, `SECURITY.md` and
`dependabot.yml` exist. With `deploy.platform` set, it warns when the GitHub environment
`production` is missing or has no required reviewers, with the settings page to open (adding
reviewers is for the user). An `info` line (no `branching` block) needs no action; it says how to
adopt a preset.

`skip` lines were not checked because something before them failed; they need no action of
their own. `scrum doctor --json` gives the same checks as JSON.

If `gh` reports an invalid login while you run inside the Claude Code sandbox, the sandbox is
the likely cause: it blocks `gh` from reading its token in the keychain and from reaching
GitHub. Run the command again outside the sandbox; the user is asked to approve it.
