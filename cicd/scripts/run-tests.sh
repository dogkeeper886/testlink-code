#!/bin/bash
# Session-scope test runner with guaranteed teardown.
#
# Brings up the CI stack (for suites that need it), runs the test CLI,
# and tears the stack down on any exit path — pass, fail, Ctrl-C, or
# crash. The build suite skips infrastructure since it only exercises
# the image artifact.
#
# Usage:
#   cicd/scripts/run-tests.sh [--suite <name>] [--id <id>] [tsx cli flags]
#
# Examples:
#   cicd/scripts/run-tests.sh                          # all suites
#   cicd/scripts/run-tests.sh --suite crud
#   cicd/scripts/run-tests.sh --suite build            # no ci-up/ci-down
#   cicd/scripts/run-tests.sh --id TC-WORKFLOW-001 --no-llm

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load cicd/tests/.env if present so LLM_JUDGE_URL / LLM_JUDGE_MODEL etc.
# reach the tsx CLI. Keep it optional — absent .env means rely on defaults.
# Caller-wins: a variable already present in the inherited environment is
# left alone, so `LLM_JUDGE_URL=... bash run-tests.sh ...` works as expected.
ENV_FILE="$REPO_ROOT/cicd/tests/.env"
if [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"
    value="${line#*=}"
    if [ -z "${!key+set}" ]; then
      export "$key=$value"
    fi
  done < "$ENV_FILE"
fi

# Defaults for values .env provides locally but CI runners don't (no .env
# on the runner — GitHub's checkout skips gitignored files). The ${VAR:-...}
# pattern preserves precedence: anything the parent shell or .env set wins;
# the fallback only fires when the variable is unset or empty. Match the
# literals in ci-up.sh / xmlrpc-capture.sh so CI behaves like a developer
# laptop with a populated .env.
export TL_PORT="${TL_PORT:-8091}"
export TL_URL="${TL_URL:-http://localhost:${TL_PORT}}"
export TL_DEV_KEY="${TL_DEV_KEY:-a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4}"

ARGS=("$@")

# The build suite lints PHP and builds the image via `docker build`.
# It does not talk to a running stack, so skip the heavy lifecycle.
NEEDS_STACK=true
for ((i=0; i<${#ARGS[@]}; i++)); do
  if [ "${ARGS[i]}" = "--suite" ] && [ "${ARGS[i+1]:-}" = "build" ]; then
    NEEDS_STACK=false
    break
  fi
done

cleanup() {
  local exit_code=$?
  if [ "$NEEDS_STACK" = "true" ]; then
    echo "" >&2
    echo "=== Session teardown (exit code: $exit_code) ===" >&2
    "$SCRIPT_DIR/ci-down.sh" || echo "[WARN] Teardown failed — inspect containers manually" >&2
  fi
  exit "$exit_code"
}

if [ "$NEEDS_STACK" = "true" ]; then
  # Arm the trap before ci-up so a failed startup still triggers teardown.
  trap cleanup EXIT INT TERM
  echo "=== Session setup ===" >&2
  "$SCRIPT_DIR/ci-up.sh"
fi

cd "$REPO_ROOT/cicd/tests"
npx tsx src/cli.ts run "${ARGS[@]}"
