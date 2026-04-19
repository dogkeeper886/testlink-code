#!/bin/bash
# XML-RPC helper for test cases.
#
# Reads an XML-RPC <methodCall> document from stdin, POSTs it to the
# TestLink API, mirrors the raw response to stderr (so expectPatterns
# can match), and emits structured JSON on stdout for the test
# framework's capture: mechanism.
#
# Emitted JSON shape:
#   {"ok": true,  "id": N}      — response contained an <int>
#   {"ok": true}                — response had no <int> (no-value call)
#   {"ok": false, "faultCode": N} — server returned a <fault>
#
# Usage in a YAML step:
#   command: |
#     bash cicd/scripts/xmlrpc-capture.sh <<'XMLDOC'
#     <?xml version="1.0"?><methodCall>...</methodCall>
#     XMLDOC
#   capture:
#     projectId: "id"
#
# Env:
#   TL_URL  — base URL of the TestLink instance (default http://localhost:8090)

set -eo pipefail

URL="${TL_URL:-http://localhost:8090}/lib/api/xmlrpc/v1/xmlrpc.php"
REQUEST=$(cat)

RESPONSE=$(curl -sS -X POST "$URL" \
  -H "Content-Type: text/xml" \
  --data-binary "$REQUEST")

# Mirror the response to stderr for expectPatterns / debugging.
printf '%s\n' "$RESPONSE" >&2

# First <int> in the body — typically the created entity id.
ID=$(printf '%s' "$RESPONSE" | grep -oP '(?<=<int>)\d+' | head -1 || true)

# Fault code (if the server returned a <fault>).
FAULT=$(printf '%s' "$RESPONSE" \
  | grep -oP '(?<=<name>faultCode</name><value><int>)\d+' \
  | head -1 || true)

if [ -n "${FAULT:-}" ]; then
  printf '{"ok": false, "faultCode": %s}\n' "$FAULT"
elif [ -n "${ID:-}" ]; then
  printf '{"ok": true, "id": %s}\n' "$ID"
else
  printf '{"ok": true}\n'
fi
