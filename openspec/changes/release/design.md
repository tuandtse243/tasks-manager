# Design

Paths are relative to `plugins/scrum-github/`.

## Context

The runtime already has `is_completed` / `is_not_planned`, `is_task`, `report_tasks` (`scrum.jq`), reading milestones and their issues, `closing_refs` for pull requests, sub-issue relations for the parent feature, and en/vi strings through `tr`. Writes to GitHub always go through `gh_send`. Other writing commands (`sprint fill`, `sprint close`) follow the same pattern: without `--yes` they only preview. Shared jq helpers live in `scrum.jq`, because a jq library may not include another library (jq 1.8.2).

## Goals / Non-Goals

**Goals:** version choice and release notes are pure jq, testable offline; a single write phase after confirmation.

**Non-Goals:** editing version files or CHANGELOG in the repository; signed tags; publishing packages.

## Decisions

### 1. Previous tag through the API, not local git

`GET repos/{r}/tags` (paginated), filtered by `^<prefix>?\d+\.\d+\.\d+$`, highest semver first. The tag must be reachable from the default branch: `GET repos/{r}/compare/{tag}...{default}` returns `status` `ahead` or `identical`. An unreachable tag is skipped and the next one tried. This works even when the local clone has not fetched tags.

### 2. Tasks since the previous tag

The start time is the commit date of the tag (`base_commit.commit.committer.date` from compare). Read `issues?state=closed&since=<time>` (paginated), then keep `closed_at > time`, `is_completed`, `is_task`. With `--sprint`, read the issues of those milestones as `sprint-status` does, with no time filter. The selection lives in `release-plan.jq`.

### 3. Pull requests that closed a task

The timeline of each task (`repos/{r}/issues/{n}/timeline`: a `closed` event with `commit_id`, or a `cross-referenced` event from a merged pull request), at most 100 tasks, like `blocked_map`. When it cannot be read, the task is still listed, without pull request numbers.

### 4. Version: `release-plan.jq`

`bump($prev; $tasks; $cfg)`: labels compared case-insensitively; major when `breaking_label` is present, minor when a task has no bug label, patch otherwise. A user `VERSION` is normalised (prefix added or removed) and compared as semver.

### 5. Release notes: `release-notes.jq`

Markdown, groups in the order of the spec. The parent feature comes from "Part of #N" in the issue body (written by `task_issue_body`) or from sub-issues when readable. Each line: `- <title> (#12, PR #40)`. Ends with a compare link `<prev>...<new>` when there is a previous tag. Text from issues is inserted as is; GitHub renders the markdown.

### 6. Writes

1. Check the tag: `GET git/ref/tags/<tag>`. If it exists and `GET releases/tags/<tag>` finds a release, stop. If it exists without a release, skip to step 5.
2. Head SHA of the default branch.
3. `POST git/tags` (annotated, message "Release <tag>").
4. `POST git/refs`.
5. `POST releases` with `body` = notes, `draft` from the flag.

A failure at step 5 prints how to run again (`scrum release <ver> --yes`), which then only creates the release.

### 7. Skill

`/scrum-github:release`:

1. Run `scrum release … --json` for the preview.
2. Show the new version, why it was chosen (which tasks caused major or minor), and the notes.
3. Take edits: a different version runs the command again with `VERSION`; edited notes are written to a file with the Write tool and passed with `--notes-file`.
4. Run with `--yes` after the user agrees.

## Risks / Trade-offs

- [Repositories with non-semver tags] → those tags are ignored; `--since TAG` names the starting tag.
- [Tasks closed by hand without a pull request] → still in the notes, without a pull request number.
- [Large repositories] → the timeline reads are capped; tasks past the cap have no pull request number.
- [Token permissions] → creating a tag needs `contents: write`; a 403 is reported with a hint to `/scrum-github:doctor`.

## Migration Plan

No migration. The `release` block has defaults. Version 0.12.0.
