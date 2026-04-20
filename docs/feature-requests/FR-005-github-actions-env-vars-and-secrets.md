---
fr: FR-005
title: Wire GitHub Actions runner with env vars + secrets for the CI suite
status: landed-with-revision
issue: https://github.com/dogkeeper886/testlink-code/issues/19
authors: ["dogkeeper886"]
created: 2026-04-20
updated: 2026-04-20
---

# FR-005 — GitHub Actions runner env vars + secrets

## Update — 2026-04-20 (post-landing revision)

The original proposal (below) routed `LLM_JUDGE_URL` and `LLM_JUDGE_MODEL` through GitHub `secrets`/`vars` and explicitly *rejected* the runner-local `.env` alternative. That landed, and then we reversed it in [PR #32](https://github.com/dogkeeper886/testlink-code/pull/32): the LLM judge config now lives in the self-hosted runner's root `.env` (`/usr/local/actions-runner-testlink-code/.env`), matching the convention used by the sibling `actions-runner-ruckus1-mcp` install.

**Why the reversal:** the GH-secrets route was duplicate state. The URL is host-specific (only the runner can route to the LAN Ollama), so it already had to match what the host could reach. Putting it in GH on top of that created two places to keep in sync for zero benefit. The "writes secrets to disk" concern in the original *Alternatives considered* doesn't apply for a LAN URL and a model tag — neither is a real secret.

**Current state:**
- `TL_DEV_KEY` is still a GH secret (actual per-environment credential).
- `LLM_JUDGE_URL` / `LLM_JUDGE_MODEL` come from the runner's process env on self-hosted.
- See `cicd/CI_SETUP.md` "Set the LLM endpoint" for the operational how-to.

The sections below are preserved as written to record the original reasoning; treat them as historical context, not current guidance.

## Tracking

- GitHub issue: [#19](https://github.com/dogkeeper886/testlink-code/issues/19)
- Status: landed with post-landing revision (PR #21 + PR #32)
- Depends on: None
- Blocks: Re-enabling automatic workflow triggers (push / PR) — all workflows are currently `workflow_dispatch` only.

## Problem

The CI test framework reads configuration from several environment variables:

| Var | Default (when unset) | Who uses it |
|---|---|---|
| `LLM_JUDGE_URL` | `http://localhost:11434` | `cicd/tests/src/config.ts` — Ollama endpoint for semantic judge |
| `LLM_JUDGE_MODEL` | `gemma3:4b` | Model to load on that endpoint |
| `TL_PORT` | `8091` | `docker-compose.ci.yml` host port |
| `TL_URL` | `http://localhost:8091` | `ci-up.sh` health check, `xmlrpc-capture.sh` default |
| `TL_DEV_KEY` | `a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4` | `executor.ts` → `{{devKey}}`, `init-db.sh` → seeded admin key |

Locally, developers put overrides in `cicd/tests/.env` (gitignored). `run-tests.sh` and `ci-up.sh` both source it. This is the established local-dev pattern.

On a GitHub Actions runner, `cicd/tests/.env` does not exist. The shell scripts' fallback defaults cover `TL_PORT`/`TL_URL`/`TL_DEV_KEY` correctly (they match the CI compose and the seed). The LLM variables don't — `localhost:11434` has nothing listening on a clean runner, so the judge either times out per test or falls back to "LLM unavailable" depending on the code path.

Net effect: running `test-pipeline.yml` today via workflow_dispatch would succeed on the simple judge and fail silently on the LLM judge. No plumbing exists to point the runner at a real Ollama instance or to rotate `TL_DEV_KEY` for environments where that matters.

The workflows are already `workflow_dispatch` only (set during issue #5) so this doesn't cause automated CI breakage today — but it blocks any attempt to re-enable push/PR triggers, and it makes manual runs on the hosted runner misleading.

## Goals

- A `test-pipeline.yml` run on GitHub Actions completes end-to-end, with the LLM judge either (a) reaching a reachable endpoint and scoring cleanly, or (b) deliberately disabled via `--no-llm` and the simple judge carrying CI.
- Secrets (LLM URL, LLM model selection if non-public, rotated `TL_DEV_KEY`) are stored in GitHub's repository secrets / variables and passed to the runner via the workflow, not committed to the repo.
- Local-dev workflow (`cicd/tests/.env`) is unchanged — developers keep doing what they're doing. The CI wiring is additive.
- Documentation names the secrets/variables a developer must add to the repo's settings when forking or bootstrapping a new clone.

## Non-goals

- Replacing the LLM judge with a hosted API (Anthropic, OpenAI). If we decide to go that way, it's a separate FR because it changes the judge's cost/latency/governance profile.
- Refactoring the env-var plumbing inside the test framework. The scripts already read env vars correctly and fall back to defaults. The gap is runner-side wiring, not code.
- Enabling automatic triggers (push / PR) on the workflows. That's a downstream consequence; deciding to do it is a separate decision once this FR lands.

## Proposed solution

**Export secrets via the workflow `env:` block; do not materialize `cicd/tests/.env` on the runner.**

Workflow step shape:

```yaml
- name: Run tests
  env:
    LLM_JUDGE_URL:   ${{ secrets.LLM_JUDGE_URL }}
    LLM_JUDGE_MODEL: ${{ vars.LLM_JUDGE_MODEL }}
    TL_DEV_KEY:      ${{ secrets.TL_DEV_KEY }}     # optional; default works
  run: bash cicd/scripts/run-tests.sh --suite ${{ inputs.suite }}
```

The existing shell scripts pick these up unchanged because:
- `run-tests.sh` sources `cicd/tests/.env` only `if [ -f "$ENV_FILE" ]`.
- Absent `.env` on the runner, the env vars set by the workflow stay in the process environment and reach `npx tsx`.
- Everything downstream — `config.ts`'s defaults, `init-db.sh`'s fallback — works if a var is unset.

For the LLM judge specifically, three operational choices:

1. **Self-hosted runner on the same network as an existing Ollama instance.** Best if one exists. `LLM_JUDGE_URL` points at the internal IP; no cross-network secrets needed beyond the one secret for the URL itself.
2. **GitHub-hosted runner, LLM endpoint publicly reachable via a secret URL.** Ollama in a cloud VM with a non-guessable host. Secret contains the full URL. Cost/availability concern.
3. **GitHub-hosted runner, `--no-llm`.** Framework supports skipping the LLM judge. Simple judge handles CI. Lowest complexity, honest tradeoff: CI can't catch silent-failure regressions the LLM judge catches locally.

Recommendation for first landing: **option 3** (`--no-llm` in CI), with `LLM_JUDGE_URL` and `LLM_JUDGE_MODEL` secrets/vars defined but defaulting to unused. The judge already handles its own absence gracefully. Switch to option 1 or 2 later as a targeted follow-up if we decide the LLM judge's CI coverage is worth the infra cost.

## Alternatives considered

- **Materialize `.env` on the runner.** Workflow step writes `cicd/tests/.env` from secrets before `run-tests.sh` runs. Matches local dev exactly; the runner behaves identically to a developer laptop. Rejected as the default because it writes secrets to disk (even if only for the run's duration) and introduces a cleanup-on-failure concern that the env-block approach doesn't have. Still defensible if we ever need identical behavior between local and runner paths.
- **Commit a `.env.example` and source from it.** Rejected because the example can't carry real secret values, so the runner would still need secrets from elsewhere — we'd have two sources of truth. Defeats the point.
- **Use `--no-llm` always in CI and drop the LLM judge from the hosted-runner path entirely.** That's effectively option 3 above, presented as the default recommendation for first landing. Full replacement would also mean the LLM judge runs only locally — acceptable but closes off the possibility of catching regressions at PR time.

## Acceptance criteria

- `test-pipeline.yml` run via `workflow_dispatch` on a GitHub-hosted runner completes end-to-end with exit code 0.
- At least one of:
  - LLM judge runs cleanly against a reachable endpoint named in `secrets.LLM_JUDGE_URL`, or
  - Workflow invokes `run-tests.sh` with `--no-llm` and the simple judge carries the run.
- `cicd/tests/.env` is never created or checked into the workflow — local dev is unaffected.
- `CLAUDE.md` (or a new `cicd/CI_SETUP.md`) documents the secrets/variables the repo expects and how a new collaborator adds them.
- No change to the test YAMLs, the test framework source (`cicd/tests/src/*`), or the XML-RPC helper scripts.

## Risks and tradeoffs

- **The `--no-llm` default means CI can't catch semantic regressions the LLM judge would.** Real tradeoff. The mitigation is that the simple judge is 19/19 reliable on the current suite, so "something broke that only the LLM would notice" is a narrow risk class. Documented explicitly so reviewers know what CI is and isn't checking.
- **Self-hosted runner (option 1) introduces ops burden.** Someone has to maintain the runner, the Ollama host, and their network path. Out of scope for this FR's first landing but flagged for the follow-up decision.
- **Secrets drift.** Once we add a new required secret, a fresh clone won't run without it. The documentation task in acceptance criteria is the counterweight — fail-fast with a clear error is better than failing mysteriously.

## Open questions

- _Do we keep `TL_DEV_KEY` as the hardcoded seed forever, or rotate it via secret?_ (nice to resolve) — The current default is fine for ephemeral CI containers. Rotating would exercise the secret-transport path end-to-end but costs nothing if we trust the containers are actually ephemeral.
- _Do we re-enable automatic triggers on main after this lands?_ (out of scope here; decide in a follow-up) — If we go with option 3 (`--no-llm`) the cost story is cheap enough to consider PR triggers again. Option 1 / 2 make the cost story load-bearing.

## Implementation notes

- Shell plumbing is already in place: `run-tests.sh` line ~22 sources `.env` conditionally; `ci-up.sh` does the same. No code changes there.
- Framework-level fallbacks already exist: `cicd/tests/src/config.ts` reads `process.env.LLM_JUDGE_URL || 'http://localhost:11434'`; `executor.ts` reads `process.env.TL_DEV_KEY || 'a1b2...'`.
- The `--no-llm` flag is already wired into `cicd/tests/src/cli.ts`; no new flag work needed.
- Workflows to touch: `.github/workflows/test-pipeline.yml` and `.github/workflows/test-suite.yml`. Both currently call `bash cicd/scripts/run-tests.sh`.

## Out of scope (deferred)

- Moving to a hosted LLM API (Anthropic, OpenAI). Separate FR if we decide to.
- Re-enabling automatic workflow triggers. Separate decision after this lands.
- Replacing GitHub Actions with a different CI system.
- Changing how local dev handles env vars.
