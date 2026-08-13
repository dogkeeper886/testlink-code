# CLAUDE.md — Project guidance for AI agents

This repository is a fork of TestLink (PHP test management system). This file tells AI agents how to work in it.

## Orientation

- **`lib/`** — Core PHP. XML-RPC server at `lib/api/xmlrpc/v1/xmlrpc.class.php`. Enumerate the registered methods with `grep "'tl\." lib/api/xmlrpc/v1/xmlrpc.class.php`.
- **`gui/`, `cfg/`, `install/`** — Web UI, config, and DB schema. Rarely touched in AI-assisted work.
- **`cicd/`** — CI test framework and docker-compose for the test stack. Most AI-assisted work happens here.
  - `cicd/docker-compose.ci.yml` — CI stack. Publishes on `${TL_PORT:-8091}`; dev stack on 8090.
  - `cicd/scripts/run-tests.sh` — session wrapper. Sources `cicd/tests/.env`, guarantees teardown via `trap EXIT`, skips the lifecycle for the `build` suite.
  - `cicd/scripts/xmlrpc-capture.sh` — the only thing YAML test steps should use to call the XML-RPC API. Never shell out to `curl` directly.
  - `cicd/tests/testcases/<suite>/TC-<SUITE>-NNN.yml` — test definitions.
  - `cicd/TESTING_GUIDELINES.md` — framework mechanics (lifecycle, dynamic IDs, teardown).
  - `cicd/tests/TESTCASE_AUTHORING.md` — how to think about `objective`, `judgeContext`, and `criteria` for the LLM judge.
- **`docs/feature-requests/`** — paired design records. Each non-trivial change gets an FR doc linked to its GitHub issue before code is written.
- **`.claude/skills/`** — project-scoped Claude Code skills (see "Skills" below).

## Main branch

`testlink_1_9_20_fixed`. Inherited from upstream; not renamed to `main` because the fork still pulls from `TestLinkOpenSourceTRMS/testlink-code`.

## GitHub workflows

All workflows in `.github/workflows/` are `workflow_dispatch` only. They do not fire on push or PR. That is intentional — run them manually from the Actions tab when you want them. Do not change this to automatic triggers without an explicit instruction.

## Skills

**Project-specific skills live in `.claude/skills/<name>/` and are committed to the repo.**

Skills belong in the repo — not in `~/.claude/skills/` — so every collaborator (human or AI) starts with the same tooling. When adding a skill for this project, put it under `.claude/skills/` in this tree. If you notice a project skill sitting in the user folder, move it.

To see what skills currently exist here: `ls .claude/skills/`. Each skill's purpose is documented in its own `SKILL.md`.

## Commit and PR conventions

- Git identity for this repo is set locally to Shang Chieh Tseng / shangchieh.tseng@tsengsyu.com / dogkeeper886. Don't change it.
- Branch names: `issue-N-short-slug` for tracked issues, `docs/short-slug` for docs-only work, `feat/...` or `fix/...` only when no issue exists.
- Commit subjects follow Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
- Every non-trivial change is paired with an FR doc + GitHub issue before code is written. Small one-file fixes can skip this.
- PR descriptions reference issues with `Closes #N`. Merge deletes the branch.

## Testing

- `bash cicd/scripts/run-tests.sh` runs the full suite. The wrapper brings the stack up, runs the tests, tears down on any exit path.
- `--suite <name>` filters by suite. The set of valid suite names is the `SUITES` const in `cicd/tests/src/config.ts`. Registering a new suite directory means adding its name there.
- A test is green only when both the simple judge (pattern match) and the LLM judge (semantic review) agree. A disagreement usually means one of them is wrong — read the reason before deciding which.
- LLM judge configuration lives in `cicd/tests/.env` (`LLM_JUDGE_URL`, `LLM_JUDGE_MODEL`).

## The two judges have different jobs — do not make them compete

This is a design principle, not a mechanical rule. Get it wrong and the suite gets noisier without getting sharper.

- **Simple judge (regex):** literal character and string matching. Its job is to enforce *exact fragments must be present*. Configured per-step via `expectPatterns`.
- **LLM judge (semantic):** the common-sense read a human QA would bring to a log. Its job is to catch *silent failures where the regex passes but the result is wrong* — counters that look populated but aren't, builds that completed mid-stream, status fields with unexpected neighboring values. Configured per-test via `criteria` + `judgeContext` + `objective`.

They are **complementary**, not redundant. The simple judge's guarantees (exact match, no hallucination, fast) free the LLM judge to do what only it can — apply general engineering judgment to output it's seeing for the first time.

**Author anti-pattern:** writing test-level `criteria` that are essentially regex patterns — *"stderr contains exactly `<name>status</name><value><string>p</string>`"*. This forces the LLM to do the simple judge's job, which it does worse (hallucinations, off-by-one, long-context confusion). The right shape is the opposite: put the exact fragment in the step's `expectPatterns` where regex enforces it; describe pass/fail in `criteria` the way a human engineer would narrate it — *"the plan's totals show one passing execution was counted"*.

A useful test: would you describe this pass/fail condition the same way to a human colleague reading the log over your shoulder? If yes, it's LLM-judge language. If you'd instead point at a specific substring, it's simple-judge language — put it in `expectPatterns`.

## Rules

- Don't use `sudo` with docker. The user is in the docker group — if a docker command fails with a permission error, something is wrong, stop and report rather than escalating.
- Don't hardcode the admin API key. Use `{{devKey}}` in test YAMLs and `$TL_DEV_KEY` in scripts. The value flows from `cicd/tests/.env` through the framework.
- Don't hardcode entity IDs in test steps. Every ID comes from a prior step's `capture:`.
- Don't put project-specific skills in `~/.claude/skills/`. They belong in `.claude/skills/` here.
- Don't switch workflows to automatic triggers without an explicit instruction.
