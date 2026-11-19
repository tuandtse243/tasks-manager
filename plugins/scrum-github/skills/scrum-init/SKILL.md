---
name: scrum-init
description: Old name of /scrum-github:init, kept for 0.5.x. Tells the user the new name, then sets up the repository the same way.
disable-model-invocation: true
---

# Renamed: /scrum-github:init

First tell the user, in one sentence: "`/scrum-github:scrum-init` is now `/scrum-github:init`;
the old name goes away in 0.6.0."

Then read `${CLAUDE_PLUGIN_ROOT}/skills/init/SKILL.md` and follow it exactly, as if the user had
run `/scrum-github:init`.
