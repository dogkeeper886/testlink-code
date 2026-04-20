# Authoring testcases — a thinking guide

When you write a testcase, you're writing for two judges with different jobs. Getting the division of labor wrong is the most common mistake; understanding it is the first thing.

This guide is about the thinking, not a template. For mechanics (framework lifecycle, dynamic IDs, teardown), see [`TESTING_GUIDELINES.md`](./TESTING_GUIDELINES.md).

---

## The two judges, and what each is for

Every test run is evaluated by both judges. A test is green only when both agree.

**Simple judge — regex.** Fast, literal, never hallucinates. Its job is to enforce *the exact character sequence X must appear in the evidence*. Configured per-step via `expectPatterns`. Use it for any claim you can state as a literal substring.

**LLM judge — semantic.** The common-sense read of the logs a human QA engineer would bring. Its job is to catch *silent failures where the regex passes but the result is wrong*: counters that look populated but are all zeros; a build that completed mid-stream without an explicit error; a status field with adjacent values that don't make sense. Configured per-test via `objective`, `judgeContext`, `criteria`.

These are complementary, not redundant. **The simple judge's exactness frees the LLM judge to do what only it can** — apply general engineering judgment to output it's seeing for the first time. Writing LLM-facing `criteria` that restate what the regex already checks forces the LLM into the simple judge's role, where it performs worse (hallucinations, long-context drift, off-by-one substring misses).

A useful check while writing: *would I describe this pass/fail condition the same way to a human colleague reading the log over my shoulder?* If yes, it belongs in `criteria` (LLM-facing). If instead you'd point to a specific substring, it belongs in `expectPatterns` on the relevant step (regex-facing).

---

## What each judge has

**Simple judge has:**
- Each step's stdout and stderr.
- The `expectPatterns` array you defined for that step.
- Nothing else. It does not read `objective` / `judgeContext` / `criteria`.

**LLM judge has:**
- The same evidence (truncated to the framework's limits).
- The three YAML fields: `objective`, `judgeContext`, `criteria`.
- A system prompt that defines its role.

**The LLM judge does NOT have:**
- Domain knowledge about TestLink. It doesn't know what `<boolean>1</boolean>` means in a `tl.checkDevKey` response. It doesn't know that `testplan_tcversions` rows are what "attached" looks like. You have to teach it.
- The reason the test exists. It can read the YAML, but "what this test proves" is editorial — it comes from you.

Everything the judge doesn't know has to come from your three fields. Everything it *does* know (from the raw evidence) doesn't need repeating.

---

## The three fields, and the question each answers

### `objective` — *what claim about the system am I making?*

A test is a claim about the system. `objective` is you stating that claim in plain terms. Not what the test *does* — what it *proves*, and why that matters.

If you can't state the claim in one sentence, the test is probably trying to prove too many things.

Ask yourself: *if this test were removed and the regression it protects against shipped to production, what would break?* That sentence is your objective.

### `judgeContext` — *what does the evidence mean in this domain?*

The judge sees raw XML-RPC responses, build logs, curl output. It doesn't know what those mean until you say. This is where your domain knowledge goes.

Ask yourself: *if a new colleague read this test's logs cold, what would they need to know to interpret them correctly?*

Things that belong here:
- What the response format represents semantically. ("XML-RPC `<boolean>1</boolean>` inside a methodResponse envelope means the call succeeded; a `<fault>` element means it didn't.")
- Which part of the evidence is the actual assertion, if it's not obvious. ("The executions are layered inside `additionalInfo.with_tester[]`; `exec_qty` is the count per status.")
- Unusual dynamics of the test. ("This is a negative test — a fault response is the expected outcome." / "This test reports multiple statuses in sequence; the last one is the verdict.")
- What an error would look like in this domain, versus a success. (Judges can't tell from raw output alone whether an absent field is normal or a regression.)

Things that do **not** belong here:
- A narration of the steps. The YAML already shows what the test runs.
- Speculation about things that *could* go wrong but aren't specifically detectable from the evidence. Vague warnings prime the judge to hallucinate.
- Instructions to the judge about how to reason. The judge's role is set at the framework level, not in your YAML.

### `criteria` — *narrated pass/fail, naming the terms a reader would notice*

Plain-language pass/fail description, read by the LLM judge. Two things matter:

1. **Narrated** — like commentary to a human colleague reading the logs over your shoulder, not a regex schema.
2. **Named** — specific domain terms the reader would *point at*. "Status 'p' (passed)", "exec_qty of 1 in the p bucket", "faultCode 2000", "the build's sha256 id". Short, concrete nouns that actually appear in the evidence.

These two properties are both needed. Here are three phrasings of the same claim, showing the gradient:

```
BAD (regex-dictation):
  Step 8 stderr contains the literal fragment
  <name>status</name><value><string>p</string>.

BAD (too abstract):
  A reader should see the case as passed in the read-back.

GOOD (narrated + named):
  A reader should see the case returned with status 'p' (passed)
  in the getLastExecutionResult response.
```

The first form forces the LLM to do the simple judge's job (character-level matching). The second form gives the LLM nothing specific to cite — it reasons correctly but then reaches into the raw observations for something to quote, often dumping a verbose XML block that blows the output budget. The third form narrates for a human *and* provides short named landmarks the LLM can lift into its `evidence` output without going long.

**Named terms do double duty.** They make the criterion concrete enough for a human to verify, and they hand the LLM judge a short quotable anchor. Without them, the evidence field either paraphrases the criterion text (ungrounded) or dumps raw XML (truncates).

**Ask yourself:** what specific domain term would a human point at in the log to say "yes, that's the pass"? *Status 'p'*. *exec_qty=1*. *faultCode 2000*. *The case's external id*. Put that in the criterion. You're not dictating a regex — you're naming a landmark.

**Regex-facing patterns still belong in each step's `expectPatterns`.** This is where XML fragments and exact substrings go. The simple judge enforces those character-for-character. The LLM judge does not see `expectPatterns`; it sees the evidence and your `criteria`, and independently forms a judgment.

---

## A worked example

Suppose you're writing a test that reports a failing execution and reads it back.

**Thinking, before writing:**

- *Claim I'm making:* `reportTCResult` persists a failing status, and the read-back API reflects it. If this regressed, dashboards would show wrong counts for failing test runs — a direct product regression.
- *What the evidence looks like:* `reportTCResult` returns an XML-RPC response with `status:true` and the new execution id. `getLastExecutionResult` returns a struct whose `status` field is a single-char code (`p` / `f` / `b`). The failing case emits `<member><name>status</name><value><string>f</string></value></member>`.
- *What the regex must enforce (simple judge work):* the literal fragment `<name>status</name><value><string>f</string></value>` has to appear in the read-back step's stderr. That's a substring check — no judgment needed, and the judgment-free check is fast and certain.
- *What only a human-like read will catch (LLM judge work):* a response shape that says `status:true` but with a surrounding envelope that actually carries a warning or degraded state. A status code of `f` written inside an `additionalInfo` block instead of the top-level result. Anything where the regex says "yes" but a human would say "wait, that's not right."
- *Domain knowledge the judge needs:* that TestLink uses single-char status codes, that the path matters (`f` alone could appear as a substring elsewhere), that the read-back step is where the assertion lives.

**What makes it into the three fields plus the step:**

The step's `expectPatterns`:
```yaml
expectPatterns:
  - "<name>status</name><value><string>f</string>"
```
That's the regex-facing assertion. Character-exact, fast, no hallucination.

`objective`:
> Verify that `reportTCResult` persists a failing status and that `getLastExecutionResult` reads it back correctly. A regression here would cause TestLink's execution dashboards and counter APIs to under-report failures — silently green release reports that should be red.

`judgeContext`:
> The evidence consists of two XML-RPC responses: one from `reportTCResult` (a report acknowledgement), one from `getLastExecutionResult` (the read-back). TestLink encodes execution status as a single character: `p` (passed), `f` (failed), `b` (blocked), empty for no-execution. The read-back response is the source of truth — if it carries `status=f`, the failure was persisted correctly.

`criteria`:
> Pass: the fail report is acknowledged, and the read-back response returns the case with status 'f' (failed). A human reading the logs should see the acknowledgement on the report call and the 'f' status field on the getLastExecutionResult struct.
> Fail: the read-back shows a status other than 'f', or a fault envelope indicates the report didn't persist.

Notice the criterion names *specific terms a reader would point at* — "status 'f' (failed)", "getLastExecutionResult". These are narration, not regex, but they're concrete enough that the LLM judge can cite them short-form when it writes its `evidence` output. Compare with a too-abstract version — *"the read-back response shows the case as failed"* — which reads fine to a human but leaves the LLM with nothing short to quote, so it reaches into raw XML and often truncates.

Notice what's *not* in the `criteria`: character-level substrings. Those went into `expectPatterns`, where they belong. The `criteria` is narrated for a reader; the regex does the character-level work.

Notice also what's not there: no step-by-step narration of what the YAML runs, no list of "things that could go wrong," no formulaic phrases. The author wrote three things they uniquely know: the *claim*, the *domain*, the *narrated pass/fail*.

---

## Traps, by principle

### Trap 1: describing what the test does instead of what the logs mean

The YAML already shows the steps. Your `judgeContext` should add something the judge can't see from the YAML alone — what those outputs *mean*. If your `judgeContext` reads like a README of the steps, you haven't added anything.

### Trap 2: loose criteria that mask false-positives

If the simplest-matching pattern in your criteria also matches on an uninteresting field (e.g. a build *name* that's always present, regardless of whether executions were actually counted), then a broken test will look green. Tight patterns on the exact thing that proves the claim — not the nearest field that usually exists.

### Trap 3: speculating about failure modes the evidence can't reveal

A list of "things that might silently go wrong" sounds thorough, but it asks the judge to imagine. Imaginings are hallucinations. Only talk about things that would show up in the observable logs if they happened.

### Trap 4: overfitting one test to many claims

A test that "also verifies" some tangential concern usually has loose criteria and a bloated `judgeContext`. Split it. One claim per test.

### Trap 5: forgetting that the judge starts from zero every call

Each judgment is independent. The judge doesn't remember prior tests in the run. Don't write `judgeContext` that assumes context from earlier tests — everything it needs must be in this one test's fields.

---

## Signs of a well-authored test

- Reading the `objective` alone, you understand why the test matters.
- Reading the `judgeContext` alone, you understand what the logs represent without the YAML.
- Reading the `criteria` alone, you could verify the test manually against a log file.
- All three fields together are shorter than the steps block, not longer.
- The test proves exactly one thing.
