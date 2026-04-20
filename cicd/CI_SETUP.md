# CI setup — GitHub Actions

How the `.github/workflows/*.yml` workflows consume configuration, and what a new collaborator needs to add to their fork to run them.

Design record: [FR-005](../docs/feature-requests/FR-005-github-actions-env-vars-and-secrets.md). Issue: [#19](https://github.com/dogkeeper886/testlink-code/issues/19).

## The basics

Workflows are **manual only** (`workflow_dispatch`). Trigger them from the Actions tab against any ref. They do not fire on push or PR. That is intentional.

The default `judge_mode` is `simple`, which invokes `run-tests.sh` with `--no-llm`. The simple regex judge carries CI on its own. No LLM endpoint is required for a green CI run.

Switch `judge_mode` to `dual` at dispatch time if you want the LLM judge to run too — that requires an accessible Ollama endpoint (see below).

## Secrets and variables

Add these in your fork's **Settings → Secrets and variables → Actions**. All are optional — the framework falls back to defaults when they are unset.

| Name | Kind | Purpose | Default if unset |
|---|---|---|---|
| `LLM_JUDGE_URL` | Secret | Ollama endpoint for the LLM judge | `http://localhost:11434` (unreachable on hosted runners) |
| `LLM_JUDGE_MODEL` | Variable | Model tag the judge asks Ollama to load | `llama3:8b` |
| `TL_DEV_KEY` | Secret | Rotated admin API key (32 hex chars) | `a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4` (seeded by `init-db.sh`) |

Leave them unset for simple-judge-only CI. Set `LLM_JUDGE_URL` + `LLM_JUDGE_MODEL` when you want `dual` mode to work against a real endpoint.

## Why these aren't in a `.env` file on the runner

Local developers put these in `cicd/tests/.env` (gitignored). The workflow does **not** materialize that file on the runner — values flow through the job's `env:` block straight into the test framework's process environment. See FR-005's *Alternatives considered* for the reasoning.

## Local dev is unchanged

Your `cicd/tests/.env` keeps working exactly as before. `run-tests.sh` sources it only when present, and the runner has no `.env` to source.
