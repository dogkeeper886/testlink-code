---
name: testcase-author
description: Think through a CI testcase. In authoring mode, produces a new YAML under cicd/tests/testcases/<suite>/. In review mode, produces a short bulleted findings report (possibly empty). Invoke when the user asks to write a new test, author TC-..., or review an existing testcase for correctness and clarity. Canonical guide is cicd/tests/TESTCASE_AUTHORING.md — read it first.
---

# Testcase authoring and review

A testcase is judged by two judges with different jobs. Getting the division of labor right is the first thing a good author does.

- **Simple judge (regex)** — literal character matching. Its contract is each step's `expectPatterns`. Use this for any claim you can state as a substring.
- **LLM judge (semantic)** — the common-sense read a human QA would bring. Its contract is the test-level `objective` / `judgeContext` / `criteria`. Use this for the part of the claim that only a human-like read catches — silent failures where regex passes but the result is wrong.

They are complementary, not redundant. Writing test-level `criteria` that restate regex patterns forces the LLM into the simple judge's role, where it performs worse (hallucinations, long-context drift). The canonical guide at `cicd/tests/TESTCASE_AUTHORING.md` explains this division; read it first.

The four fields at a glance:

- Step-level `expectPatterns` — literal substrings the regex enforces.
- `objective` — the claim, in terms a product stakeholder would recognize.
- `judgeContext` — the domain knowledge a new colleague would need to interpret the evidence. Not a step narration.
- `criteria` — pass/fail narrated the way a human colleague would describe it over your shoulder. Not a repeat of the regex patterns.

This skill guides the reasoning; it does not hand over a template. Fill-in-the-blank tests end up describing themselves instead of teaching the judges anything.

## Deliverables

- **Authoring mode** — a new YAML file at `cicd/tests/testcases/<suite>/TC-<SUITE>-NNN.yml`, plus a run of the suite to confirm both judges agree.
- **Review mode** — a bulleted findings list. *It is valid for the list to be empty.* Do not invent findings to look thorough.

Each review finding: severity · one-line claim of what's weak · one-line why it matters. No more. No fix wording.

---

## Authoring mode — four questions before any YAML

Don't open the editor until these are answered.

1. **What claim about the system does this test make?**
   One sentence, named in product terms. *"Admin API keys are accepted"*, not *"checkDevKey returns `<boolean>1</boolean>`"*. If you can't make one sentence, split the test.

2. **What's the smallest scenario that exercises the claim?**
   Walk from the claim backward to the minimum sequence of operations. Each extra step is another thing that can mis-assert.

3. **What does the evidence look like, specifically, when the claim holds? When it doesn't?**
   The exact XML fragment, at the exact field path, in the exact step's stderr. If you can't describe the success evidence and the failure evidence concretely, run the commands manually first.

4. **What would a new colleague — who has never seen this API — need to interpret these logs correctly?**
   That's the judgeContext. Teach only what's needed for *these* logs, not the whole system.

The fields then write themselves — split between the two judges:
- `expectPatterns` (per-step, simple judge) ← the literal substrings from (3).
- `objective` ← (1), plus one phrase on what regression it protects against.
- `judgeContext` ← (4).
- `criteria` ← narrated pass/fail (how a human would describe the outcome over your shoulder), NOT a repeat of the substring patterns. The substrings belong in `expectPatterns`.

After the YAML is drafted, run `bash cicd/scripts/run-tests.sh --suite <suite>`. If both judges pass on first run, the authoring is likely sound. If the LLM judge flags the test for a reason the evidence doesn't actually show, the gap is in the judgeContext — add the *domain fact* the judge is missing, not a correction addressed to the judge.

## Review mode

**Before reading the three fields, do the warm-up.** Read the steps and the captured evidence. Without consulting the objective / criteria, ask yourself: *does the claim this test appears to be making actually hold given these logs?*

- If you can't tell — the test is unclear or under-evidenced. That's a finding.
- If you can tell *yes*, but the simple judge's `expectPatterns` would also pass on a state where the answer would be *no* — that's a false-positive finding, and it's usually **must-fix**.

Only after the warm-up, walk the fields with these questions.

### Is the claim clear?
- From `objective` alone, do you know what regression this test protects against?
- Is it one claim, or several stapled together?

### Is the evidence explained?
- Does `judgeContext` add something the steps don't already show? Or does it retell what the YAML already says?
- Could a new colleague read the logs + judgeContext and interpret them without asking the author?

### Are the simple-judge and LLM-judge assertions in their right places?
- Step `expectPatterns` should carry the literal substrings — the character-exact, regex-enforceable claims. A missing substring there is a real regex finding.
- Test-level `criteria` should narrate pass/fail for a human reader, not restate the substrings. If the `criteria` field reads like a list of regex patterns with field paths, that's a finding: the claim has been pushed to the wrong judge. The LLM judge gets worse when forced into the regex's role.
- If `expectPatterns` alternates on `A|B`, each alternative must independently prove the claim — otherwise a fault response that happens to include one of the fields will pass silently.

### Does `criteria` name the specific terms a reader would point at?
- Narration without named landmarks is a trap. *"A reader should see the case as passed"* is too abstract — the LLM judge has nothing short to quote in its `evidence` output, so it dumps raw XML and truncates the JSON.
- *"A reader should see the case returned with status 'p' (passed) in the getLastExecutionResult response"* names specific terms — "status 'p'", "getLastExecutionResult" — that are both human-verifiable and short-quotable.
- The check: ask whether the criterion contains at least one short concrete noun (a status letter, a count, a specific field name, an id format) that actually appears in the evidence. If not, flag as **should fix** — the LLM will either paraphrase (ungrounded) or dump long quotes (truncate).

### Are the three test-level fields doing different work?
- `objective` states the claim. `judgeContext` adds interpretive context (domain knowledge). `criteria` narrates pass/fail in human terms.
- Do they overlap or restate each other? Each should be doing its own job.
- Together they should be shorter than the steps block, not longer.

### The domain-vs-directive test

Some `judgeContext` content is legitimately directive toward the judge; some is a workaround for the judge's weaknesses. Use this distinguisher:

> **Would another human engineer, reading these logs for the first time, independently say this?**

- Yes → domain knowledge. Keep it. Example: *"TestLink's execution model is latest-wins."*
- No → model-steering. Example: *"IMPORTANT FOR THE JUDGE: don't conclude fail just because..."*. No human says this to another human about logs.

Model-steering belongs in the framework's system prompt (`llm-judge.ts`), not repeated per-test. When you find it in a `judgeContext`, the finding is: *generic steering masquerading as per-test context.* The information may be correct; the framing is at the wrong layer.

### Mechanics (from `TESTING_GUIDELINES.md`, for completeness)
- IDs come from `capture:`, no numeric literals in XML-RPC params.
- `{{devKey}}` everywhere, no API key literals.
- Teardown in reverse creation order.
- Entity names carry `{{runId}}` / `{{testId}}`.
- All XML-RPC through `cicd/scripts/xmlrpc-capture.sh`.

---

## Anti-patterns

1. **Don't prescribe specific phrases.** A finding says what's missing or vague; it does not dictate wording. Give the author the principle; let them pick words.
2. **Don't forgive a loose pattern because the test currently passes.** If the simple judge would pass on a regressed state, the test is silently broken — surface it regardless of run history.
3. **Don't manufacture findings.** A well-written test gets no findings. Saying so is the correct output.
4. **Don't grade with model names.** Never frame a finding as "gemma3 will confuse this" or "qwen handles this better." The question is whether the test is a clear prompt, not whether a specific model handles it. Model-specific weaknesses are framework-level concerns.

---

## Severity rubric

- **Must fix** — the claim is wrong, or the criteria would pass on a regressed system. The test is broken or silently deceptive.
- **Should fix** — the three fields are not cleanly doing their three jobs; a reader would be confused; framing is off but facts are right.
- **Nice to tighten** — works today, but a foreseeable regression or API shape change would turn it into a must-fix. Usually loose patterns.

## Output shapes

**Authoring:**
```
Wrote: cicd/tests/testcases/<suite>/TC-<SUITE>-NNN.yml
Ran:   bash cicd/scripts/run-tests.sh --suite <suite>
Result: simple X/Y, LLM X/Y
Follow-up (only if needed): <one-line note on any iteration>
```

**Reviewing:**
```
TC-<SUITE>-NNN
  [severity] <one-line finding> — <one-line why>

TC-<SUITE>-NNN
  No findings.
```
