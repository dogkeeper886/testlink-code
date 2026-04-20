# CI setup — GitHub Actions

How the `.github/workflows/*.yml` workflows consume configuration, and what a new collaborator needs to add to their fork to run them.

Design record: [FR-005](../docs/feature-requests/FR-005-github-actions-env-vars-and-secrets.md). Issue: [#19](https://github.com/dogkeeper886/testlink-code/issues/19).

## The basics

Workflows are **manual only** (`workflow_dispatch`). Trigger them from the Actions tab against any ref. They do not fire on push or PR. That is intentional.

The default `judge_mode` is `simple`, which invokes `run-tests.sh` with `--no-llm`. The simple regex judge carries CI on its own. No LLM endpoint is required for a green CI run.

Switch `judge_mode` to `dual` at dispatch time if you want the LLM judge to run too — that requires an accessible Ollama endpoint (see below).

## Secrets and variables

Add this in your fork's **Settings → Secrets and variables → Actions**. It's optional — the framework falls back to a default when unset.

| Name | Kind | Purpose | Default if unset |
|---|---|---|---|
| `TL_DEV_KEY` | Secret | Rotated admin API key (32 hex chars) | `a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4` (seeded by `init-db.sh`) |

The LLM judge's endpoint and model are **not** configured via GH secrets/variables. They live in the self-hosted runner's root `.env` (see *Set the LLM endpoint* below) so that the same value the runner reaches at LAN routing time is the one the judge uses, with no GH-side editing required.

## Local dev is unchanged

Your `cicd/tests/.env` keeps working exactly as before. `run-tests.sh` sources it only when present, and a hosted GitHub runner has no `.env` to source.

## Self-hosted runner (for `dual` judge mode with a LAN Ollama)

When `judge_mode=dual` is dispatched against a GitHub-hosted runner, the LLM judge has no way to reach an Ollama instance that only lives on your LAN. The workarounds are (a) expose Ollama publicly behind a secret URL, or (b) register a **self-hosted runner** on a box with network access to it. This section covers option (b).

### Prerequisites on the runner host

- Docker installed and the user who will run the runner is in the `docker` group (`ci-up.sh` uses `docker compose` without `sudo`).
- Network route to the Ollama instance (e.g. `192.168.2.103:11434`).
- A user account (can be the developer's own — no dedicated account required).
- `sudo` access for the systemd install step.

### Install location

The runner lives under `/usr/local/actions-runner-testlink-code/` rather than the user's home directory. Systemd's default service context cannot reliably reach files under `$HOME`, so keeping the runner tree outside home avoids a whole class of permission puzzles. The directory is chown'd to the runner user so the service can start without sudo-shimming.

### Register

1. Go to **Settings → Actions → Runners → New self-hosted runner** on the fork. GitHub generates a single-use registration token (expires in ~1 hour) and shows the current runner version + checksum.
2. On the runner host, download the tarball to your home directory (not `/usr/local` — keep the one-shot download outside the persistent install path):
   ```
   cd ~
   curl -sSfL -o actions-runner-linux-x64-<version>.tar.gz \
     https://github.com/actions/runner/releases/download/v<version>/actions-runner-linux-x64-<version>.tar.gz
   sha256sum actions-runner-linux-x64-<version>.tar.gz   # compare against GitHub's page
   ```
   This doc intentionally doesn't pin a version — check GitHub's "New self-hosted runner" page for the current one.
3. Create the install path, chown to the user who will run the service, and extract:
   ```
   sudo mkdir -p /usr/local/actions-runner-testlink-code
   sudo chown "$USER:$USER" /usr/local/actions-runner-testlink-code
   tar xzf ~/actions-runner-linux-x64-<version>.tar.gz \
     -C /usr/local/actions-runner-testlink-code
   ```
4. Register:
   ```
   cd /usr/local/actions-runner-testlink-code
   ./config.sh --unattended \
     --url https://github.com/<owner>/testlink-code \
     --token <token>
   ```
   `--unattended` accepts defaults for runner group, runner name (the hostname), labels (`self-hosted,Linux,X64`), and work folder (`_work`). The workflows dispatch against the bare `self-hosted` label, which is one of the defaults — no custom labels needed for a single-runner setup.

### Install as a service (so it survives reboots)

From `/usr/local/actions-runner-testlink-code/`:

```
sudo ./svc.sh install <user>      # e.g. sudo ./svc.sh install jack
sudo ./svc.sh start
sudo ./svc.sh status
```

Pass the username explicitly — without it, `svc.sh` defaults via `$SUDO_USER`, which is right in interactive shells but not always in automation contexts. The install creates a systemd unit at `/etc/systemd/system/actions.runner.<owner>-<repo>.<hostname>.service`, enables it for boot, and starts it.

Foreground mode (`./run.sh`) works for a first-test sanity check but dies with the shell — use the service install for durable CI.

### Set the LLM endpoint

The GitHub Actions runner reads `/usr/local/actions-runner-testlink-code/.env` at startup and bakes those vars into every job's process environment. Append the LLM config there:

```
LLM_JUDGE_URL=http://<ollama-host-on-lan>:11434
LLM_JUDGE_MODEL=gemma3:4b
```

(Use whichever model you've pulled on that Ollama.)

Restart the service after editing so the new vars are picked up:

```
sudo systemctl restart actions.runner.<owner>-<repo>.<hostname>.service
```

The workflow does not flow `LLM_JUDGE_URL` / `LLM_JUDGE_MODEL` through `secrets`/`vars` — they reach the test framework directly from the runner's process env. This keeps the URL co-located with the host that has to route to it; nothing in the GH UI needs editing when your Ollama box's IP changes.

### Dispatch

In the Actions tab, pick **CI Pipeline** (`test-pipeline.yml`) and dispatch with:

- `judge_mode` = `dual`
- `runner` = `self-hosted`

For a green-path sanity check without the LLM judge, leave `judge_mode=simple` and `runner=ubuntu-latest` — that keeps using GitHub-hosted infra and the simple regex judge.

### Operational notes

- **Ephemeral workspaces:** the runner's default is persistent — each job reuses the same working directory. `run-tests.sh` tears down the docker-compose stack via `trap EXIT` so state doesn't accumulate across runs, but if you hit weirdness, `docker system prune` on the runner host is safe.
- **Runner updates:** GitHub updates the runner agent regularly. The installed service auto-updates in most cases, but if a workflow starts failing with a version mismatch, re-run `./config.sh remove` + `./config.sh` with a fresh token to reinstall.
- **Fallback:** `runs-on` is input-driven, so you can always dispatch against `ubuntu-latest` if the self-hosted box is down or you want to sanity-check on hosted infra.
