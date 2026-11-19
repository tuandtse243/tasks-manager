---
name: discover
description: Clarify a vague idea or requirement before planning - research it, interview the user in rounds with suggested answers, keep its terms in line with the project glossary, check how it fits an existing codebase, settle the scope, and write a confirmed brief to docs/plans/<slug>/brief.md. A decision that belongs to someone who is not in the session becomes a questionnaire for that person. Writes nothing to GitHub. Use when the user has an idea or a fuzzy request ("let users comment", "make the app faster") and wants it turned into a clear scope, or when /scrum-github:plan says the input is not clear enough. --quick for a small request, --deep for web research and an independent review.
argument-hint: "<idea | path to a requirement> [--quick | --deep]"
---

# Clarify a requirement into a brief

`scrum` below means `bash "${CLAUDE_PLUGIN_ROOT}/runtime/bin/scrum"`, run from the root of the
target repository. This skill writes `brief.md` in the plan folder and, when a decision belongs
to someone who is not in the session, a `questionnaire-<recipient>.md` next to it. It writes
nothing to GitHub and changes no file outside the plan folder.

Depth (argument; default `standard`):

| Level | Agents | Interview |
|---|---|---|
| `--quick` | none | one round at most |
| `standard` | `codebase-scout` on a repo with code; `researcher` only when the request needs outside facts | rounds until the eight topics are covered |
| `--deep` | as standard, plus `researcher` always, plus an independent review of the draft brief by `plan-critic` (brief only) | as standard |

## 1. Read the context

1. Read `${CLAUDE_PLUGIN_ROOT}/reference/planning-rules.md` and follow it throughout.
2. `scrum config` (offline): `planning.dir`, `planning.context_file`. If there is no
   `.github/scrum.yml`, the defaults apply.
3. `scrum plan init "<title>" --slug <slug>`: write the slug yourself in lowercase ASCII with dashes
   (drop accents). If `brief.md` already exists there, read it and continue from it. Read every
   `questionnaire-*.md` in the folder too: an answer written under a question settles that
   question. Move it from "Open questions" to "Decisions", record it in the appendix as a round
   (the question, "Suggested: none (asked by questionnaire)", the answer and who gave it), and do
   not ask it again.
4. `scrum context inventory`: does the repository have code (`has_code`)?
5. If it has code, `scrum context status`:
   - the project context exists: read it. If `stale` is true, say "the project context is
     <commits_behind> commits old" and suggest `/scrum-github:project-scan`; if `unknown` is true,
     say its age cannot be told and suggest a new scan. Use it anyway unless the user refreshes it.
   - it does not exist: suggest `/scrum-github:project-scan` first. If the user declines, read
     only the code related to the request (step 2).
6. Read the brief template `${CLAUDE_PLUGIN_ROOT}/reference/brief-template.md`.

## 2. Find the facts (not with `--quick`)

Facts are your job, never the user's: do not ask what the repository or the web can answer. Start
these in parallel and do not wait on them for questions that do not depend on them:

- **Repository with code:** spawn `scrum-github:codebase-scout` on the areas the request touches.
  Ask for: the parts affected (paths), the data model and flows involved, conventions to follow,
  and what must not break. Pass the project context path if it exists.
- **Outside facts** (always with `--deep`; with `standard` only when the request needs them, for
  example comparing services, a regulation, a third-party API): spawn `scrum-github:researcher`
  with one precise question each. Use only findings that come with a URL; keep the URLs for the
  "Sources" section. If the agent reports that web research is not available, tell the user that
  web research was skipped and continue.

## 3. Interview in rounds

Read `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/grilling/SKILL.md` and follow it, with this adapter.
Read `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/domain-modeling/SKILL.md` too and apply it during the
interview, with its adapter below. **Where they differ, the adapters win.**

**Adapter for `grilling`:**

- A round asks only the questions that can be answered now, without depending on another open
  question. Number them, give a suggested answer for each, and wait for the answers before the
  next round. A question that depends on another open one goes to a later round.
- For facts, use the agents of step 2 instead of a fresh sub-agent of your own.
- Before finishing, each of these eight topics is either answered or written as out of scope:
  1. users and roles; 2. the main flow; 3. data and its lifecycle; 4. edge cases and errors;
  5. non-functional needs (performance, security, accessibility, ...); 6. integrations;
  7. constraints (deadline, budget, infrastructure); 8. what is out of scope.
  If a topic is still open when you are about to finish, ask one more round about it. If the user
  says a topic does not apply, write it under "Out of scope" and do not ask again.
- Record every round in the brief appendix: each question, your suggested answer, and the user's
  answer (also when they just accept).
- `--quick`: one round at most, on the topics that matter for a small request; the rest become
  assumptions.
- Scope, priority and solution choices are the user's. What nobody can answer becomes an
  assumption with a concrete value ("At most 200 concurrent users").
- **A decision that belongs to someone who is not here** (the product owner, a customer, legal):
  when the user says they cannot decide it, offer a questionnaire for that person instead of an
  assumption. Keep interviewing on everything else; collect these questions per recipient.
  - They accept: read `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/to-questionnaire/SKILL.md` and follow
    its three steps, with the adapter below.
  - They decline: write the point as an assumption with a concrete value, as above.
- If the user stops during the interview, ask whether to save a draft. Write `brief.md` (with
  `Status: draft`) only if they agree; otherwise write nothing.

**Adapter for `domain-modeling`:**

- Use three of its moves: challenge a term against the glossary, sharpen fuzzy or overloaded
  language, and cross-reference what the user says with the code (through the scout's findings).
- The glossary is the "Glossary" section of `planning.context_file`. With no project context,
  there is nothing to challenge against: still sharpen fuzzy terms with the user.
- A term used in another sense than the glossary gives it is a question for the current round:
  quote the glossary, say what the user seems to mean, and ask which holds.
- Write each settled term, with its one meaning, under "Decisions" in the brief, and use that
  term in the rest of the brief.
- Write only the brief: no `GLOSSARY.md`, no ADR, and leave `planning.context_file` as it is.
  A new term reaches the glossary at the next `/scrum-github:project-scan`, or the team adds it
  to "Team notes".

**Adapter for `to-questionnaire`:**

- Write the file to `<plan folder>/questionnaire-<recipient-slug>.md` (lowercase ASCII with
  dashes, for example `questionnaire-product-owner.md`), one file per recipient. If it exists,
  add the new questions to it and keep the answers already there.
- Write it in the user's language, with the terms settled in this interview and in the glossary.
- Its questions are the ones collected for that recipient; "How your answers will be used"
  names the brief.
- Tell the user the path, and that running `/scrum-github:discover` on this folder again reads
  the answers.

## 4. Fit and size (repository with code)

From the project context and the scout's findings, decide one of:

- **fits**: list the affected parts with paths;
- **fits with changes**: list what must change first, and why;
- **conflicts** (for example the feature needs server-side state in a stateless design): stop,
  explain the conflict with two or three options and their cost, and let the user choose before
  writing the brief.

Write it under "Project fit" with the conventions to follow and what must not break.

For every brief, estimate the **size** under "Size": one task (one screen, no data change:
suggest `/scrum-github:task-new` instead of a plan), one feature (several tasks), or one epic
(several independent user flows: list the expected features). Give the reason.

## 5. Write and confirm

Read `${CLAUDE_PLUGIN_ROOT}/vendor/pocock/to-spec/SKILL.md` and use its synthesis, with this
adapter. **Where they differ, the adapter wins.**

**Adapter for `to-spec`:**

- Write `brief.md` in the plan folder from `reference/brief-template.md`, with its headings
  exactly as they are (not the `to-spec` template). Write the content in the user's language.
- Do not publish anything to a tracker, do not apply labels, do not run
  `/setup-matt-pocock-skills`. Do not ask about test seams.
- "Project fit" only in a repository with code; "Sources" only when web research was used, with
  a URL for every finding used. Delete an optional section you do not use; always keep "Size".
- With `--deep`: spawn `scrum-github:plan-critic` with the brief path only, asking for missing
  scope, contradictions and untestable statements; fix what is clear, ask about the rest.

Then run `scrum doc check <brief.md>` and fix any missing section. Show the user a short summary:
in scope, out of scope, assumptions, risks, size, and the fit conclusion. Ask them to confirm.

- They want changes (for example drop an item from scope): edit the brief, run `scrum doc check`
  again, show the summary again, and wait.
- They confirm: set `Status: confirmed on <date>`, and print the next step exactly:
  `/scrum-github:plan <planning.dir>/<slug>/brief.md`

**While a questionnaire is waiting for answers**, the brief cannot be confirmed:

- Keep `Status: draft`, and write the section "Open questions": one line per question with who
  answers it and the questionnaire file. Delete the section once it is empty.
- Show the summary as above, plus the open questions and the files to send. Ask the user to
  confirm the rest of the brief, save it, and stop there. Do not print the `/scrum-github:plan`
  step: say instead that the brief is finished by running this skill again on the same folder
  once the answers are in.
