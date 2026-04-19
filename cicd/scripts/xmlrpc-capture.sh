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

# The `id` member of the response — typically the created entity id.
# TestLink's XML-RPC is inconsistent about typing and whitespace: the
# same field is sometimes emitted as <int> and sometimes as <string>,
# and the <value> wrapper may or may not have surrounding whitespace.
# Collapse the response to one line and match the `id` member directly
# to cope with both shapes.
FLAT=$(printf '%s' "$RESPONSE" | tr -d '\n' | tr -s ' ')
ID=$(printf '%s' "$FLAT" \
  | grep -oP '<name>id</name>\s*<value>\s*<(?:int|string)>\K[0-9]+' \
  | head -1 || true)

# Fault code (if the server returned a <fault>).
FAULT=$(printf '%s' "$FLAT" \
  | grep -oP '<name>faultCode</name>\s*<value>\s*<(?:int|string)>\K[0-9]+' \
  | head -1 || true)

if [ -n "${FAULT:-}" ]; then
  printf '{"ok": false, "faultCode": %s}\n' "$FAULT"
elif [ -n "${ID:-}" ]; then
  printf '{"ok": true, "id": %s}\n' "$ID"
else
  printf '{"ok": true}\n'
fi
