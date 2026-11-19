# Brief: <title>

<!-- Written by /scrum-github:discover. Keep the "## " headings exactly as they are: `scrum doc check`
     reads them (runtime/share/doc-sections.json). Write the content in the user's language.
     Optional sections: "Open questions" (only while a questionnaire is waiting for answers),
     "Size" (always write it), "Project fit" (only in a repository with code), "Sources" (only
     when web research was used). Delete an optional section you do not use. -->

Status: draft | confirmed on <YYYY-MM-DD>

## Problem

What is wrong or missing today, for whom, and why it matters now. Facts only, with their source.

## Solution

The outcome the user wants, in a few sentences, from the user's point of view. When it counts as done.

## Users and user stories

- **<role>**: who they are, what they need.
- As a <role>, I want <action> so that <benefit>.

## In scope

- Each item is a behaviour someone can check. `/scrum-github:plan` creates tasks only for this list.

## Out of scope

- What this requirement deliberately does not do, including whole topics the user ruled out
  (for example "Integrations: none for this requirement").

## Decisions

- **<decision>**: the choice the user made, and the option(s) not taken.
- **<term>**: the one meaning it has in this requirement (a term settled during the interview).

## Assumptions

- Things nobody could answer, written as a concrete guess ("At most 200 concurrent users").
  `/scrum-github:plan` copies these into the plan.

## Risks

- **<risk>**: what could go wrong, how likely, and what would reduce it.

## Open questions

- <question>: waiting for <who answers it>, see `questionnaire-<recipient>.md` in this folder.

Only while a questionnaire is out. The status stays `draft` as long as this section has items;
an answered question moves to "Decisions" and leaves this list.

## Size

One task | one feature (several tasks) | one epic (several features), and why. For an epic, list the
expected features. For one task, suggest `/scrum-github:task-new` instead of a plan.

## Project fit

Conclusion: fits | fits with changes | conflicts. Then: the parts of the project affected (with
paths), conventions to follow, and what must not break. Source: the project context and the code.

## Sources

- <finding>: <URL>

## Appendix: questions and answers

### Round 1

1. **<question>**
   - Suggested: <the suggested answer>
   - Answer: <the user's answer>
