---
name: project-scan
description: Read an existing codebase and write or refresh the project context document (docs/project-context.md) - overview, technology, structure, flows, data model, integrations, conventions, how to run and test, glossary - with evidence paths and a commit stamp. Later runs re-read only what changed. Use before planning features on an existing project, or when /scrum-github:plan or discover says the context is missing or stale. --full rescans everything.
argument-hint: "[--full]"
---

# Scan the project into a context document

`scrum` is on the PATH while this plugin is enabled. If `scrum` is not found, or `scrum --version`
does not print the plugin's version, run `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"` instead.
Run it from the root of the target repository. The only file this skill writes is `planning.context_file` (default
`docs/project-context.md`). It never runs the application and writes nothing to GitHub.

## 1. Where things stand

1. Read `${CLAUDE_PLUGIN_ROOT}/reference/planning-rules.md` and follow it throughout.
2. `scrum context status` (offline): does the document exist, the stamped commit, how many
   commits behind, which top-level folders changed since.
3. `scrum context inventory` (offline): file counts per folder and extension, manifests, scripts
   in `package.json`, CI files, test folders, docs, and `has_code`.
4. If `has_code` is false (only a README, docs, `.github/`): say there is nothing to scan yet and
   stop. Create no file.

Then choose:

- **First scan**: the document does not exist, or `--full` was given.
- **Refresh**: it exists. Rescan only the folders in `changed_dirs`. If `changed_dirs` is empty
  and `commits_behind` is 0, say the document is up to date and stop. If `unknown` is true (no
  stamp, or the commit is gone from history), do a first scan.

## 2. Read the code through the scout

Spawn `scrum-github:codebase-scout` (read-only) instead of reading the code yourself. Give it the
inventory and the sections to fill: technology, directory structure, main flows, data model,
external integrations, conventions, running and testing, and the terms for the glossary.

- Large repository (several independent top-level folders, or more than a few hundred files):
  spawn one scout per top-level folder (or group of small ones) in parallel, then merge.
- Refresh: give the scouts only the changed folders, plus the current document so they can say
  what is no longer true.

## 3. Glossary

Read `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/domain-modeling/SKILL.md` and
`${CLAUDE_PLUGIN_ROOT}/vendor/pocock/domain-modeling/GLOSSARY-FORMAT.md`, with this adapter.
**Where they differ, the adapter wins.**

**Adapter for `domain-modeling`:** use only its glossary discipline (one precise meaning per term,
the project's own words, flag terms used in two senses). Write the glossary as the "Glossary"
section of the context document, not as a `GLOSSARY.md`. Do not create or edit ADRs, and do not
challenge the user's model here: this is a description of what exists.

## 4. Write the document

Start from `${CLAUDE_PLUGIN_ROOT}/reference/project-context-template.md` (first scan) or from the
current document (refresh). Keep the `## ` headings exactly as in the template.

- Every statement about the code names its evidence in parentheses (a path). What the repository
  does not say is written "unknown" (or "chưa rõ" when writing in Vietnamese), never guessed.
- Refresh: change only the sections affected by the changed folders; leave the rest as it is.
- **"Team notes" is the team's**: copy its content back exactly as it was, on every scan,
  including `--full`.
- Write only `planning.context_file`.

Then:

1. `scrum context stamp`: records the current commit and today's date in the document (one stamp
   line; an old one is replaced).
2. `scrum doc check <planning.context_file>`: fix any missing section or stamp.
3. Tell the user what was scanned (all or which folders), the sections that changed, the
   "unknown" items worth answering in "Team notes", and remind them to commit the file.
