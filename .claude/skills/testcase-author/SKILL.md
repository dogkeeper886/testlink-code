---
name: testcase-author
description: Help an author or reviewer think through a CI testcase — what it's proving, what its evidence means, and how its criteria prove or disprove the claim. Use when the user asks to "write a test for X", "author TC-...", or "review this testcase". The skill guides the reasoning; it does not prescribe a template. Canonical guide is cicd/tests/TESTCASE_AUTHORING.md.
---

# Authoring or reviewing a testcase — guided thinking

A testcase is a claim about the system and the evidence for that claim. The LLM judge reads three fields — `objective`, `judgeContext`, `criteria` — as a per-test prompt. This skill walks through the reasoning a good author or reviewer follows. It does not hand over a template; copy-pasted templates produce testcases that describe themselves instead of teaching the judge anything.

Read [`cicd/tests/TESTCASE_AUTHORING.md`](../../../cicd/tests/TESTCASE_AUTHORING.md) first. It is the canonical source. For framework mechanics (lifecycle, dynamic IDs, teardown), see [`cicd/tests/TESTING_GUIDELINES.md`](../../../cicd/tests/TESTING_GUIDELINES.md).

## Two modes

### Mode A — Authoring a new testcase

Don't start by writing YAML. Start by answering four questions.

1. **What claim about the system is this test making?**
   One sentence. Not "this test calls X and asserts Y" — that's the *how*. The claim is the *why*: "the admin API key accepts valid clients", "executions persist with the reported status", "the Docker image builds reproducibly from the current Dockerfile."
   
   If you can't state a single clean claim, the test is trying to prove too many things. Split it.

2. **What's the minimum scenario that would prove this claim?**
   Walk backwards from the claim to the shortest sequence of operations that exercises it. Don't pad the test with incidental verification — each extra assertion is something that can misfire.

3. **What will the evidence look like if the claim holds? If it doesn't?**
   Be specific. Don't say "the response indicates success." Say: "stderr contains `<member><name>status</name><value><string>p</string></value></member>`; absence of that exact fragment, or presence of a `<fault>` envelope, is the disproof."
   
   If you can't describe the evidence shape confidently, you may not understand the API well enough yet. Go run the operations manually and inspect the real output before writing the test.

4. **What would a new colleague need to know to interpret this evidence correctly?**
   This is what `judgeContext` is for. The judge is a colleague who starts from zero every invocation. Teach it — but teach only what's needed to read *these* logs, not the whole system.

Once those are answered, the three fields write themselves:
- **`objective`** ← answer to (1), plus why it matters.
- **`judgeContext`** ← answer to (4).
- **`criteria`** ← answer to (3), tightened to exact observable fragments.

Then draft the YAML (steps, capture chain, teardown) using the skeleton mechanics in `TESTING_GUIDELINES.md`. Run the suite and read the verdict — if the judge fails, read its reason and check: is the criterion actually met in the evidence? If yes, either the criteria language is imprecise or the judgeContext is missing domain knowledge. Fix at the source.

### Mode B — Reviewing a testcase

Walk through these questions. Record each as a finding. Severity is based on what breaks when it's wrong.

**Is the claim clear?**
- Reading only `objective`, do you understand what regression this test protects against?
- Is it one claim, or is the field secretly listing three?

**Is the evidence explained?**
- Does `judgeContext` tell you what the logs *mean*, or does it retell the YAML's steps?
- If a junior engineer read the logs and this field, could they interpret them correctly?
- Is there speculation about failure modes the evidence couldn't actually reveal? (Those prime the judge to hallucinate.)

**Are the criteria precise?**
- Could a human verify the criteria against a log file without consulting the author?
- If any criterion has regex alternation (`A|B`), does each alternative *independently* prove the claim? Or is one alternative a field that's always present anyway?
- Do the criteria name the exact fragment in the exact place, or vaguely say "success" / "passed" / "valid"?

**Are the three fields doing different work?**
- Is `judgeContext` adding something the `objective` and the steps themselves don't already say?
- Are `criteria` specific to observable evidence, or do they repeat the `objective` in different words?
- All three together should be shorter than the steps block, not longer.

**Mechanics (from `TESTING_GUIDELINES.md`, briefly):**
- All IDs come from `capture:`, no hardcoded numeric literals in XML-RPC params.
- `{{devKey}}` everywhere, no API key literals.
- Teardown in reverse creation order.
- Entity names carry `{{runId}}` or `{{testId}}`.
- All XML-RPC through `cicd/scripts/xmlrpc-capture.sh`.

## What NOT to do in either mode

- **Don't prescribe a formula to the author.** If you find yourself saying "add `IMPORTANT FOR THE JUDGE:` to your context" or any other magic phrase, stop. Ask instead: *what does the author know about this test that the judge doesn't?* The author's answer IS the `judgeContext`. Formulas produce noise; domain knowledge produces signal.
- **Don't grade the test against an LLM model's known quirks.** If a particular model hallucinates on long tests, that's a framework concern. The test author's job is to communicate the claim and evidence well; a well-written test will survive most models.
- **Don't let a loose `expectPattern` slide** because the test currently passes. Loose patterns are silent future regressions. Tight is always better.

## Output

- **Mode A:** produce the YAML, run the suite once, report the verdict. If both judges pass on the first run, the authoring was probably good. If the LLM judge fails with a reason that cites something absent from the evidence, the `judgeContext` may need a concrete statement about what's *not* an error (e.g. "intermediate status values are expected — the final state is the verdict"). Fix specifically, don't generalize.
- **Mode B:** a bulleted finding report. One line per finding: what's weak, why it matters, what would fix it. Don't rewrite the YAML — the author decides scope.
