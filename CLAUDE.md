# CLAUDE.md — Project guidance for AI agents

This repository is a fork of TestLink (PHP test management system). This file tells AI agents how to work in it.

## What lives where

- **`lib/`** — Core PHP. XML-RPC server at `lib/api/xmlrpc/v1/xmlrpc.class.php` (91 registered methods; grep `'tl\.` to enumerate).
- **`gui/`, `cfg/`, `install/`** — Web UI, config, and DB schema. Rarely touched.
- **`cicd/`** — CI test framework and docker-compose for the test stack. This is where most AI-assisted work happens.
  - `cicd/docker-compose.ci.yml` — CI stack (app on port 8091 by default; dev is 8090).
  - `cicd/scripts/run-tests.sh` — session wrapper; sources `cicd/tests/.env`; guaranteed teardown via `trap EXIT`.
  - `cicd/scripts/xmlrpc-capture.sh` — XML-RPC helper every YAML test step uses.
  - `cicd/tests/testcases/<suite>/TC-<SUITE>-NNN.yml` — test definitions.
  - `cicd/tests/TESTING_GUIDELINES.md` — framework mechanics (lifecycle, dynamic IDs, teardown).
  - `cicd/tests/TESTCASE_AUTHORING.md` — how to write the LLM-judge-facing fields (`objective`, `judgeContext`, `criteria`).
- **`docs/feature-requests/`** — Paired design records for every non-trivial change. Each FR links to a GitHub issue.
- **`.claude/skills/`** — Project-scoped Claude Code skills (see "Skills" below).

## Main branch

`testlink_1_9_20_fixed`. Inherited from upstream; not renamed to `main` because the fork still pulls from `TestLinkOpenSourceTRMS/testlink-code`. Workflows in `.github/workflows/` are `workflow_dispatch`-only (manual trigger).

## Skills

Skills live at `.claude/skills/<name>/SKILL.md`. They're committed to the repo so every collaborator (AI or human) has access to the same tooling.

**IMPORTANT: Project-specific skills NEVER go in `~/.claude/skills/`.** Anything about this repo, its testcases, its workflows, or its conventions belongs in `.claude/skills/<name>/` in the repo tree. User-folder skills are for cross-project tooling only. If you catch yourself putting project work into the user folder, stop and put it in `.claude/skills/` instead.

Current skills in this repo:
- `feature-request` — Author a feature request doc (`docs/feature-requests/FR-NNN-*.md`) paired with a GitHub issue. Use before starting any non-trivial change.
- `testcase-author` — Author or review a CI test YAML. Use for anything under `cicd/tests/testcases/`.

## Workflow conventions

### Branches and PRs
- Branch names: `issue-N-short-slug` for issues, `docs/short-slug` for docs-only work, `feat/...` or `fix/...` only if no issue exists.
- Every non-trivial change gets an FR doc paired with a GitHub issue *before* code is written. Small fixes can skip the FR.
- PR titles: conventional-commit style (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`). Reference issues via `Closes #N`.

### Commits
- `git config` for this repo is set to commit as Shang Chieh Tseng / shangchieh.tseng@tsengsyu.com / dogkeeper886. Don't change it.
- No sudo for docker commands. If `docker ps` fails, the user account isn't in the docker group — stop and flag it.

### Testing
- `bash cicd/scripts/run-tests.sh` runs the full suite. It brings the stack up, runs all tests, and tears down via `trap EXIT` regardless of outcome.
- `--suite <name>` filters by suite (`build`, `smoke`, `auth`, `crud`, `plan`, `execution`, `workflow`, `negative`, `regression`).
- `build` suite skips ci-up/ci-down (it only exercises the image artifact).
- Tests must pass both the simple judge (regex) and the LLM judge (semantic) to be green. If only one passes, read the failing judge's reason — it's often a real finding (the LLM caught a loose pattern the regex let through).

### LLM judge
- Config in `cicd/tests/.env`: `LLM_JUDGE_URL`, `LLM_JUDGE_MODEL`.
- Current model is `gemma3:4b`. It's reliable on short tests but flakes on 10+ step multi-entity tests due to small-model long-context limits. Don't treat a single LLM-judge failure on a long test as dispositive without reading the actual stderr.
- See `TESTCASE_AUTHORING.md` for how to write test fields that minimize LLM-judge flakiness.

## Things not to do

- **Don't run the test runner from inside a workflow** that's configured to fire on every push. All GitHub workflows in this repo are `workflow_dispatch` only; keep them that way.
- **Don't `sudo docker`.** User's in the docker group.
- **Don't put project-specific skills in `~/.claude/skills/`.** Always `.claude/skills/<name>/` here.
- **Don't hardcode `a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4`** (the admin API key) in new test steps. Use `{{devKey}}` — it's injected from `TL_DEV_KEY` in `.env`.
- **Don't hardcode entity IDs.** Capture every ID from its create-response. Grep for `testcaseid=1` / `testprojectid=1` / similar in new code as a lint check.
- **Don't merge to main without the suite passing.** Simple judge: 19/19. LLM judge: whatever it says (known flake on ~0-3 multi-step tests with gemma3:4b).

## Memory vs. this file

Anything in this file is authoritative for AI-agent behavior in this repo. Personal memory (`~/.claude/projects/.../memory/`) is for cross-session continuity with one user and shouldn't override anything here.

## Contacts

- Upstream repo: `TestLinkOpenSourceTRMS/testlink-code` (issues disabled upstream; we track issues on our fork).
- Fork: `dogkeeper886/testlink-code`.
