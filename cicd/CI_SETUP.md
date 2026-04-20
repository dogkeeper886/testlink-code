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
| `LLM_JUDGE_MODEL` | Variable | Model tag the judge asks Ollama to load | `gemma3:4b` |
| `TL_DEV_KEY` | Secret | Rotated admin API key (32 hex chars) | `a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4` (seeded by `init-db.sh`) |

Leave them unset for simple-judge-only CI. Set `LLM_JUDGE_URL` + `LLM_JUDGE_MODEL` when you want `dual` mode to work against a real endpoint.

## Why these aren't in a `.env` file on the runner

Local developers put these in `cicd/tests/.env` (gitignored). The workflow does **not** materialize that file on the runner — values flow through the job's `env:` block straight into the test framework's process environment. See FR-005's *Alternatives considered* for the reasoning.

## Local dev is unchanged

Your `cicd/tests/.env` keeps working exactly as before. `run-tests.sh` sources it only when present, and the runner has no `.env` to source.

## Self-hosted runner (for `dual` judge mode with a LAN Ollama)

When `judge_mode=dual` is dispatched against a GitHub-hosted runner, the LLM judge has no way to reach an Ollama instance that only lives on your LAN. The workarounds are (a) expose Ollama publicly behind a secret URL, or (b) register a **self-hosted runner** on a box with network access to it. This section covers option (b).

### Prerequisites on the runner host

- Docker installed and the user running the runner is in the `docker` group (`ci-up.sh` uses `docker compose` without `sudo`).
- Network route to the Ollama instance (e.g. `192.168.2.103:11434`).
- A user account dedicated to the runner.

### Register

1. Go to **Settings → Actions → Runners → New self-hosted runner** on the fork. GitHub generates a single-use registration token (expires in ~1 hour) and shows the download/config commands.
2. On the runner host:
   ```
   mkdir actions-runner && cd actions-runner
   curl -o actions-runner-linux-x64-<version>.tar.gz -L https://github.com/actions/runner/releases/download/v<version>/actions-runner-linux-x64-<version>.tar.gz
   tar xzf actions-runner-linux-x64-<version>.tar.gz
   ./config.sh --url https://github.com/<owner>/testlink-code --token <token>
   ```
   Use GitHub's current "New self-hosted runner" page for the exact version number and checksum — this doc intentionally doesn't pin one.
3. Accept the default `self-hosted` label. The workflows dispatch against the bare `self-hosted` label; no custom labels are needed for a single-runner setup.

### Install as a service (so it survives reboots)

From inside the `actions-runner` directory:

```
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

This installs a systemd unit that starts the runner on boot and respawns it if it dies. The alternative, `./run.sh` in the foreground, stops as soon as you close the shell — fine for a first test, not for durable CI.

### Set the LLM endpoint

In **Settings → Secrets and variables → Actions**:

- `secrets.LLM_JUDGE_URL` = `http://<ollama-host-on-lan>:11434`
- `vars.LLM_JUDGE_MODEL` = `gemma3:4b` (or whichever model you've pulled on that Ollama)

These flow into the job environment when the workflow dispatches — see the "Secrets and variables" table above.

### Dispatch

In the Actions tab, pick **CI Pipeline** (`test-pipeline.yml`) and dispatch with:

- `judge_mode` = `dual`
- `runner` = `self-hosted`

For a green-path sanity check without the LLM judge, leave `judge_mode=simple` and `runner=ubuntu-latest` — that keeps using GitHub-hosted infra and the simple regex judge.

### Operational notes

- **Ephemeral workspaces:** the runner's default is persistent — each job reuses the same working directory. `run-tests.sh` tears down the docker-compose stack via `trap EXIT` so state doesn't accumulate across runs, but if you hit weirdness, `docker system prune` on the runner host is safe.
- **Runner updates:** GitHub updates the runner agent regularly. The installed service auto-updates in most cases, but if a workflow starts failing with a version mismatch, re-run `./config.sh remove` + `./config.sh` with a fresh token to reinstall.
- **Fallback:** `runs-on` is input-driven, so you can always dispatch against `ubuntu-latest` if the self-hosted box is down or you want to sanity-check on hosted infra.
