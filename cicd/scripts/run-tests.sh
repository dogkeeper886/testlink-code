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
ENV_FILE="$REPO_ROOT/cicd/tests/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

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
