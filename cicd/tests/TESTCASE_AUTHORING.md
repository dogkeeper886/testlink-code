# Authoring testcases — a thinking guide

When you write a testcase, you're not just running commands. You're asking the LLM judge a question: *did this test prove what it was meant to prove?* The three fields `objective`, `judgeContext`, and `criteria` are how you pose that question. Together they are the test-specific prompt the judge receives.

Good testcases think clearly about three different things in three different fields. Bad testcases mash them together or describe the YAML back to itself.

This guide is about the thinking, not a template. For mechanics (framework lifecycle, dynamic IDs, teardown), see [`TESTING_GUIDELINES.md`](./TESTING_GUIDELINES.md).

---

## What the judge has and what it lacks

The judge receives:
- The evidence — raw stdout, stderr, and container logs from every step that ran.
- Your three fields: objective, judgeContext, criteria.

The judge does **not** receive:
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

### `criteria` — *what specific observation proves or disproves the claim?*

Concrete, visible-in-the-evidence conditions. If a human read the logs and the criteria, they should be able to run the check themselves without consulting you.

Ask yourself: *what's the most specific pattern that distinguishes this test's success from the adjacent failure modes?*

Good criteria name the exact fragment you're looking for in the exact place you expect it. Vague criteria ("status is passed", "counters are populated") hide false-positives.

---

## A worked example

Suppose you're writing a test that reports a failing execution and reads it back.

**Thinking, before writing:**

- *Claim I'm making:* `reportTCResult` correctly persists a failing status, and the read-back API reflects it. If this regressed, dashboards would show wrong counts for failing test runs — a direct product regression.
- *What the evidence looks like:* `reportTCResult` returns an XML-RPC response with `status:true` and the new execution id. `getLastExecutionResult` returns a struct whose `status` field is a single-char code (`p` / `f` / `b`). The failing case emits `<member><name>status</name><value><string>f</string></value></member>` — exactly that fragment.
- *Domain knowledge the judge needs:* single-char status codes. Which call's response is which. That `<string>f</string>` alone could appear in many contexts; the element path matters.
- *The observable that proves correctness:* the literal fragment `<name>status</name><value><string>f</string></value>` in the stderr of the read-back step.

**What makes it into the three fields:**

`objective`:
> Verify that `reportTCResult` persists a failing status and that `getLastExecutionResult` reads it back correctly. A regression here would cause TestLink's execution dashboards and counter APIs to under-report failures — silently green release reports that should be red.

`judgeContext`:
> The evidence consists of two XML-RPC responses: one from `reportTCResult` (step N), one from `getLastExecutionResult` (step M). TestLink encodes execution status as a single character: `p` (passed), `f` (failed), `b` (blocked), or an empty string when no execution exists. The relevant fragment in the read-back response is `<name>status</name><value><string>f</string></value>` — the element path matters because "f" alone can appear elsewhere (e.g. a substring of "Success", field names).

`criteria`:
> - Step N stdout contains `{"ok": true, "id": <number>}`.
> - Step M stderr contains the literal fragment `<name>status</name><value><string>f</string></value>`.
> - Any fault envelope in either step is a failure.

Notice what's *not* there: no step-by-step narration of what the YAML runs, no list of "things that could go wrong," no formulaic phrases. The author wrote three things they uniquely know: the *claim*, the *domain*, the *observable*.

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
