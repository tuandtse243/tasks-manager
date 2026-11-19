---
name: project-setup
description: Turn on the GitHub Projects board for Scrum - hand the user an interactive wizard for the steps only a person can do (create and link the project, turn off its built-in workflows, create a token, set the SCRUM_PROJECT_TOKEN secret, add the project block to .github/scrum.yml), then check the result with a dry run. Use when the user wants to set up, enable or connect the project board.
---

# Set up the project board

`scrum` below means `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"`, run from the root of the
target repository. The repository needs `.github/scrum.yml` first (`/scrum-github:scrum-init`).

## 1. Hand over the wizard

Five of the steps happen in a browser and in a terminal that can ask for a hidden value, so a
person does them. The wizard opens each page, says what to click, takes the token without
showing it, sets the secret, and writes the `project:` block after asking.

Print this command with the plugin path resolved, and ask the user to run it **in their own
terminal**, from the root of the target repository:

```
bash "${CLAUDE_PLUGIN_ROOT}/wizards/project-board.sh"
```

The wizard waits for typed answers and opens a browser, so it only works in a terminal the user
types into: the Bash tool and the `!` prefix give it no input, and a secret set that way is
stored empty. Wait until the user says the wizard has finished, and ask what its closing
summary listed under "still to do by hand".

## 2. Check the result

1. `scrum config`: `project.enabled` is true, and `owner` and `number` are set. If not, show the
   block to add to `.github/scrum.yml`.
2. `scrum init --force-file .github/workflows/scrum-status-sync.yml`: installs
   `scrum-project-sync.yml` and gives the status workflow the token.
3. Ask the user to run `gh auth refresh -s project` in their terminal if they have not.
4. `scrum project init --dry-run`. Show what it would do. If it stops on a built-in workflow that
   is still on, or on a missing Status option, say which one and how to fix it on the board.
5. After the user agrees with the dry run: `scrum project init`.

Then remind them to hide the "Synced status" field in every view of the board, and to commit and
push `.github/`.

To change the wizard's stages, read `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/wizard/SKILL.md`: the
part of `wizards/project-board.sh` above its `STAGES` marker is the vendored library and stays
as it is.

`gh` cannot read its keychain token inside the Claude Code sandbox; run the `scrum` commands that
call GitHub outside it if needed.
