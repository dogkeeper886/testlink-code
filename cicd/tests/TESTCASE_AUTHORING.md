# Authoring testcases — what the LLM judge reads

This document describes how to write the YAML fields that feed the LLM judge: `objective`, `judgeContext`, and `criteria`. For test framework mechanics (dynamic IDs, lifecycle scopes, teardown order), see [`TESTING_GUIDELINES.md`](./TESTING_GUIDELINES.md).

A good testcase tells the judge:
1. **What am I looking at?** (objective)
2. **What does the evidence look like, and what would silent failure look like in this domain?** (judgeContext)
3. **What exactly must be true for this to pass?** (criteria)

The simple judge (pattern matching) runs first and catches literal regressions. The LLM judge catches semantic regressions — output that looks successful but actually means something broken. Both must pass for a testcase to be considered green.

---

## The three fields, in order

### `objective`

A single short paragraph. State:
- What this test proves (the assertion in plain English).
- Why it matters (what would break if this regressed).

**Good:**
```
Confirm the admin API key seeded by init-db.sh is accepted by
tl.checkDevKey. Every CRUD and workflow test depends on this key being
usable; if it's rejected, the rest of the suite is meaningless.
```

**Bad:**
```
This test calls tl.checkDevKey with the admin key and expects the
response to contain <boolean>1</boolean>.
```
(That's a description of what the test does. The objective should be the reason the test exists. Mechanics belong in `judgeContext`.)

### `judgeContext`

A multi-paragraph briefing for the judge. Covers:
- **Situational framing**: what kind of test this is. For anything unusual (negative test, multi-status cycling, etc.), lead with a loud marker like `THIS IS A NEGATIVE TEST —`.
- **Per-step narrative**: for each step, what command runs and what evidence it produces. Identify which step has the key assertion.
- **Failure hints**: *short list* of silent failure modes the judge should watch for — with the phrase *"only relevant if evidence shows them"* when the list is long or the test has many steps.

Keep this field as short as you can without dropping information the judge can't infer from the steps themselves. For tests with 10+ steps, be especially concise — long prompts degrade small-model accuracy.

**Good (concise, short test):**
```
Step 1 runs `curl -sf` against $TL_URL/login.php and pipes through
`grep -o "Login" | head -1`. A healthy run prints the single word
"Login" on stdout.

Silent failures to watch for:
- HTTP 200 but page content is a PHP error page — grep finds nothing
  and stdout is empty.
- curl follows a redirect to a different page.
```

**Good (multi-step — explicit guardrail to prevent hallucination):**
```
Ten steps. Setup (1-6), exercise (7-8: report + read-back), teardown (9-10).

Step 8 is the key assertion: the response stderr must contain the
literal XML fragment "<name>status</name><value><string>p</string>"
— the exact serialization of status=passed.

IMPORTANT FOR THE JUDGE: if every expectPattern listed in criteria
matches, this test PASSES. The list below is hypothetical; only flag
an item if the observations actually show that symptom.

Hypothetical failure modes (only relevant if evidence shows them):
- Step 7 returns status:true but no execution row was written →
  step 8 would show no status at all.
- Step 8 stderr contains status field with a different value than "p".
```

**Bad:**
```
Silent failures to watch for:
- The entity is in the wrong parent (suite attached to wrong project).
- The pass report succeeds against a stale plan+build.
- Teardown returns true but rows persist in DB.
- Cache issues in the ORM layer might cause...
```
(Small models grab these verbatim as "reason" for a failure, even when the evidence shows the test passed. Speculative lists = hallucination fuel.)

### `criteria`

Explicit `PASS when:` and `FAIL when:` bullet lists. Each bullet points to a specific step and a specific expected pattern — ideally a literal XML/JSON fragment, not a loose word match.

**Good:**
```
PASS when:
- Step 7 stdout contains {"ok": true, "id": <number>}.
- Step 8 stderr contains the literal
  "<name>status</name><value><string>p</string>".
- Steps 9-10 each return <boolean>1</boolean>.

FAIL on any fault envelope, missing execution row on read-back, or
status mismatch.
```

**Bad:**
```
PASS when counters are populated.
FAIL when counters are empty.
```
(Vague. "Populated" isn't something regex can match; the simple judge would let a false-positive through — e.g. a counter response containing the build *name* but zero actual counts.)

**Bad:**
```
expectPatterns:
  - "build-{{testId}}-{{runId}}|total_tc"
```
(Alternation across a guaranteed-present field and a "real assertion" field lets anything pass. Either match on the field that actually proves the assertion, or use two separate asserts.)

---

## The expectPatterns field — tight is better

`expectPatterns` is the simple judge's contract. Once the simple judge passes, the LLM judge reads the same observations. If the simple judge's pattern is too loose, the LLM judge can catch the real issue and correctly FAIL the test — but that surfaces as "LLM flaky" rather than "test had a bug."

**Tight:** match the exact literal fragment that proves the thing you're asserting.
```yaml
expectPatterns:
  - "<name>status</name><value><string>p</string>"
```

**Too loose:** alternate across fields that are usually present anyway.
```yaml
expectPatterns:
  - "build-{{testId}}-{{runId}}|total_tc"   # build name is always present; total_tc may not be
```

Rule of thumb: if the regex has a pipe `|`, every alternative should independently prove the assertion. If one alternative is a field that's always there regardless of correctness, either drop it or split into two expectPatterns.

---

## Lessons from this project's history

- **Negative tests need loud framing.** Without `THIS IS A NEGATIVE TEST —` in the judgeContext, the LLM will see a fault response and mark the test FAIL even though the fault is what we wanted. (See `TC-AUTH-002.yml`.)
- **Long tests need `IMPORTANT FOR THE JUDGE:` guardrails.** Tests with 10+ steps consistently get false-failed by the small-model judge when the judgeContext lists speculative failure modes. The model grabs a phrase from the list and uses it as its "reason" for fail. Always end the failure-modes list with a reminder: only fail if evidence actually shows the symptom.
- **Prefer literal XML fragments over word matches.** The XML-RPC responses are deterministic; there's no reason to match `"status|passed"` when you can match `<string>p</string>` inside a specific element path.
- **Truncation keeps the start of the buffer.** If your assertion is near the end of a long stderr response, either bump `stdoutLimit`/`stderrLimit` in `CONFIG.llm`, or structure the test so the relevant fragment lands in the first N chars.
- **Each test owns its data.** Entity names must include `{{runId}}` / `{{testId}}` and teardown must delete in reverse creation order. See `TESTING_GUIDELINES.md §5`.

---

## Quick reference skeleton

```yaml
id: TC-<SUITE>-<NNN>
name: <one-sentence test name>
suite: <existing suite>
priority: <1 or higher>
timeout: <ms>
dependencies:
  - <TC-... that must have passed>

steps:
  - name: <step name>
    command: |
      bash cicd/scripts/xmlrpc-capture.sh <<'XMLDOC'
      <?xml ...>
      XMLDOC
    expectPatterns:
      - <literal fragment that proves this step's assertion>
    capture:
      <varName>: <field name or path in xmlrpc-capture.sh JSON>

objective: |
  <one short paragraph: what this proves, why it matters>

judgeContext: |
  <situational framing if unusual, e.g. NEGATIVE TEST>

  <per-step narrative: what each step does, what evidence it emits>

  IMPORTANT FOR THE JUDGE: <guardrail for long multi-step tests>

  Hypothetical failure modes (only relevant if evidence shows them):
  - <observable symptom 1>
  - <observable symptom 2>

criteria: |
  PASS when:
  - <step N stdout/stderr contains exact pattern>
  - ...

  FAIL on <specific observable failure modes>
```
