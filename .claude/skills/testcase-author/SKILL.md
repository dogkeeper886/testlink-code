---
name: testcase-author
description: Think through a CI testcase. In authoring mode, produces a new YAML under cicd/tests/testcases/<suite>/. In review mode, produces a short bulleted findings report (possibly empty). Invoke when the user asks to write a new test, author TC-..., or review an existing testcase for correctness and clarity. Canonical guide is cicd/tests/TESTCASE_AUTHORING.md — read it first.
---

# Testcase authoring and review

A testcase is a claim about the system plus the evidence that proves the claim. Three YAML fields are the claim surface:

- `objective` — the claim, in terms a product stakeholder would recognize.
- `judgeContext` — the domain knowledge a new colleague would need to interpret the evidence. Not a step narration; the YAML already has that.
- `criteria` — the observable in the logs that proves or disproves the claim. Specific fragments, not vague success-words.

All three fields, plus the `expectPatterns` on each step, are read by both a regex-matching simple judge and an LLM semantic judge. They are the test-specific prompt to the judge.

This skill guides the reasoning; it does not hand over a template. Fill-in-the-blank tests end up describing themselves instead of teaching the judge anything.

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

The three fields then write themselves:
- `objective` ← (1), plus one phrase on what regression it protects against.
- `criteria` ← (3), tightened to exact observable fragments.
- `judgeContext` ← (4).

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

### Are the criteria precise?
- If any criterion has regex alternation (`A|B`), does each alternative independently prove the claim? Or is one alternative a field that's present in *both* correct and regressed states?
- Do the criteria name the exact fragment at the exact field path, or use vocabulary like *success*, *passed*, *valid*?

### Are the three fields doing different work?
- `objective` states the claim. `criteria` name the observable. `judgeContext` adds interpretive context.
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
