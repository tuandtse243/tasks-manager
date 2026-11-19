---
name: doctor
description: Check that Scrum on GitHub can work in this repository - jq, yq (mikefarah), gh login and scopes, .github/scrum.yml, labels, workflows pushed to the default branch, runtime version, generated files, and the project board secret - and say how to fix each problem. Read-only. Use when a scrum-github command fails, after installing the plugin, or when the user asks whether their setup is right.
---

# Check the setup

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.

1. From the root of the repository the user wants to manage, run `scrum doctor`. It only reads,
   from the machine and from GitHub, and exits with 1 when there is at least one error.
2. Show the report as it is. Then go through the lines marked `error`, then `warn`: say in one
   sentence what each means for the user, and the fix printed under it.
3. Offer to run the fixes that are commands (for example `gh auth refresh -s workflow`, or
   `/scrum-github:init`). Run one only when the user agrees. Steps only a person can do (adding a
   repository secret, approving a command outside the sandbox) stay with the user.
4. After fixing, run `scrum doctor` again and confirm what is left.

`skip` lines were not checked because something before them failed; they need no action of
their own. `scrum doctor --json` gives the same checks as JSON.

If `gh` reports an invalid login while you run inside the Claude Code sandbox, the sandbox is
the likely cause: it blocks `gh` from reading its token in the keychain and from reaching
GitHub. Run the command again outside the sandbox; the user is asked to approve it.
