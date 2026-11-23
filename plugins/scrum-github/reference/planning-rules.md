# Planning rules

Shared by the `plan`, `discover` and `project-scan` skills. Read these first; they win over
anything a vendored skill under `vendor/` says.

1. **Nothing goes to GitHub before the user approves.** Only the `scrum` CLI touches GitHub, and
   only `scrum plan apply` after an explicit approval. Research, interviews, drafts and checks
   write nothing there.
2. **Agents only read.** `plan-critic`, `researcher` and `codebase-scout` return findings to the
   skill. Only the skill writes files, and only under `planning.dir` (plans, briefs and
   questionnaires for people who are not in the session) or to
   `planning.context_file` (the project context). Read both paths from `scrum config`.
3. **Facts come from the code and the web; decisions belong to the user.** Say where a fact comes
   from (a file path, a URL). Never decide scope, priority or trade-offs for the user: ask.
4. **What has to be guessed is written down as an assumption,** in concrete words ("Comments are
   plain text, no images"), never vague ones ("some details TBD").
5. **A task is a vertical slice.** It delivers one checkable behaviour on its own, not one
   technical layer. A task bigger than the largest value of `points.scale` is split. Required
   order between tasks is a dependency (`depends_on`), not the order of the list.
6. **Speak the user's language; keep the template headings.** Talk with the user in the language
   they use. Section headings of the brief, the plan view and the project context stay exactly as
   in their templates, so `scrum doc check` can read them.
7. **Every task has a time estimate next to its points.** Points measure complexity; time says
   when it is done. Give each task `estimate.work_minutes` (how long the work takes),
   `estimate.review_minutes` (a person reviewing and testing by hand, often the bottleneck when
   AI does the work) and `estimate.by`: `ai`, or `human` when the task needs a person (design, a
   product decision, work on a live system). The plan view adds them up by wave: the tasks of one
   wave run in parallel, with `planning.merge_minutes` between waves.
