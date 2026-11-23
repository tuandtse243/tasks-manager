# Tasks

Paths are relative to `plugins/scrum-github/`. Run tests with `bash tests/run.sh`.

## 1. Configuration (spec scrum-config)

- [x] 1.1 `release` block in `defaults.json`, `validate-config.jq`, `templates/scrum.yml` and the README Configuration block. Verify: tests in `test_config.sh` for the defaults and `first_version: "1.0"`; `bash tests/run.sh config` green

## 2. Version choice and task selection (design 1, 2, 4; spec release)

- [x] 2.1 `release-plan.jq`: previous tag by semver and prefix, task selection (completed, not not-planned, not epic/feature/meta/PR, after the tag time), `bump`, `VERSION` check. jq tests in `tests/test_release.sh` for every scenario of "Previous version", "Gather done tasks" and "Suggested version". Verify: `bash tests/run.sh release` green
- [x] 2.2 `release-notes.jq`: breaking, features by parent feature, bug fixes; lines with task and pull request numbers; en and vi. Verify: test for the "Parent feature" scenario

## 3. Command (design 1, 2, 3, 6; spec release)

- [ ] 3.1 `runtime/lib/cmd_release.sh` and `scrum release [VERSION] [--since TAG] [--sprint S…] [--draft] [--notes-file FILE] [--json] [--yes]`, registered in `bin/scrum` and `--help`. Tests with `fake-gh`: preview makes no write call, nothing to release, release (tag, ref, release in order), already released, release failing after the tag and the rerun creating only the release, `--draft`. Verify: `bash tests/run.sh release` green

## 4. Skill and suggestions (design 7; spec sprint-lifecycle, next-step-guidance)

- [ ] 4.1 `skills/release/SKILL.md` (preview, why this version, edits, wait for agreement, then `--yes`). Verify: `claude plugin validate plugins/scrum-github` passes; skill test in `test_cli.sh`
- [ ] 4.2 `sprint close` suggests a release when the sprint has Done tasks; release step in `next-step.jq` and `cmd_next.sh`. Verify: `bash tests/run.sh sprint` and `next` green

## 5. Version and docs

- [ ] 5.1 Version 0.12.0, CHANGELOG, plugin README, `docs/adoption-guide.md` (command table and a flow for releasing), cheat sheets where relevant. Verify: `bash tests/run.sh manifest`, `init` and `docs` green

## 6. Integration check

- [ ] 6.1 Full `bash tests/run.sh`, `shellcheck`, `openspec validate release --strict`. Verify: all pass

## Workflow follow-up

- Open a pull request, merge, then publish 0.12.0 with `/scrum-github:release` itself.
