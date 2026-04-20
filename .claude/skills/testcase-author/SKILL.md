---
name: testcase-author
description: Author or review a TestLink CI test case YAML. Use when the user asks to "add a test for X", "write a testcase", "draft TC-...", or "review this testcase for pattern conformance". Keeps the objective / judgeContext / criteria fields aligned with what the LLM judge expects and avoids the priming-hallucination failure modes documented in cicd/tests/TESTCASE_AUTHORING.md.
---

# Authoring and reviewing TestLink testcases

This skill operates on YAML testcases under `cicd/tests/testcases/<suite>/TC-<SUITE>-NNN.yml`. The canonical authoring guide is [`cicd/tests/TESTCASE_AUTHORING.md`](../../../cicd/tests/TESTCASE_AUTHORING.md) — read it before writing a new test or reviewing an existing one. Framework mechanics (dynamic IDs, teardown order) are in [`cicd/tests/TESTING_GUIDELINES.md`](../../../cicd/tests/TESTING_GUIDELINES.md).

## When to invoke

- User says: "add a test for X", "write TC-<SUITE>-<NNN>", "draft a testcase that exercises Y", "review this YAML for pattern conformance"
- User has changed a YAML and wants feedback before committing
- An LLM-judge failure needs triaging — is the test wrong or is the LLM hallucinating?

## What this skill does

Two modes:

### Mode A — Author a new testcase

1. Confirm the suite. If the user wants a test in a new suite (not in `SUITES` in `cicd/tests/src/config.ts`), add the suite to that array first — otherwise the test won't be discovered.
2. Pick the next `TC-<SUITE>-NNN` number by listing existing files in `cicd/tests/testcases/<suite>/`.
3. Start from the skeleton at the bottom of `TESTCASE_AUTHORING.md`.
4. For each step: write a real XML-RPC call using `cicd/scripts/xmlrpc-capture.sh` — never shell out directly to `curl`. Use `{{devKey}}`, `{{runId}}`, `{{testId}}`, `{{projectId}}`, `{{suiteId}}`, etc. Never hardcode IDs or API keys.
5. Capture each new entity's id via `capture:` and reference it in subsequent steps. No numeric literals in XML-RPC params except semantic constants (e.g., `step_number=1`, `version=1`).
6. Teardown in reverse creation order as the last steps of the testcase.
7. Write the three framing fields carefully (next section).
8. Run the suite once before committing — the test should pass both the simple judge AND the LLM judge. If only the simple judge passes, re-read the LLM judge's reason and either:
   - Tighten `expectPatterns` if the LLM caught a real false-positive.
   - Tighten `judgeContext` if the LLM is primed to hallucinate (see "anti-patterns" below).

### Mode B — Review an existing testcase

Walk through this checklist. Flag each miss as a finding:

**Structure**
- [ ] `objective`, `judgeContext`, `criteria` all present and non-empty.
- [ ] `dependencies` lists every earlier test the runner must have passed before this one.
- [ ] Every step has a `name`, a `command`, and either `expectPatterns` or explicit `capture:`.
- [ ] Test-case-level `timeout` generous enough for the slowest step (often setup+teardown).

**Conventions**
- [ ] `{{devKey}}` used everywhere, no hardcoded API key literals.
- [ ] Every created entity has a `{{runId}}` or `{{testId}}` suffix in its name.
- [ ] Entity IDs flow via `capture:` — no numeric literals in XML-RPC params except `step_number`/`version` style constants.
- [ ] Teardown deletes in reverse creation order.
- [ ] Suite name in the YAML matches the directory name.

**LLM-judge precision**
- [ ] `expectPatterns` are tight. Any `|` alternation has alternatives that independently prove the assertion — not one real assertion OR'd with a field that's always present regardless of correctness. (See TC-EXEC-003 history: `"build-{{testId}}-{{runId}}|total_tc"` let a false-positive through.)
- [ ] For negative tests, the `judgeContext` opens with `THIS IS A NEGATIVE TEST —`.
- [ ] For tests with 10+ steps, the `judgeContext`'s failure-modes list ends with a guardrail: `IMPORTANT FOR THE JUDGE: only flag these if evidence actually shows them.`
- [ ] Assertion patterns prefer literal XML/JSON fragments (e.g., `<name>status</name><value><string>p</string>`) over loose word matches (`status|passed`).

**Anti-patterns to call out**
- [ ] Long speculative lists in judgeContext without a guardrail. Small-model judges (gemma3:4b) grab a phrase verbatim and use it as "reason" for fail even when evidence contradicts. Either shorten the list or mark it hypothetical.
- [ ] `expectPatterns` that match on fields present in BOTH success and failure responses. These pass the simple judge silently even when the assertion doesn't hold.
- [ ] `objective` that describes the mechanics (what the test does) instead of the purpose (what the test proves and why it matters).
- [ ] Missing teardown for any entity created in setup. Even when the plan/project cascade would clean up, an explicit per-entity delete is preferred because it lets the test catch the delete-API regression too.

## Output

- Mode A: produce the YAML file, run the suite once, summarize the verdict. If either judge fails, iterate.
- Mode B: a bulleted report by finding — "Issue: X; Severity: should-fix/worth-considering; Suggested fix: Y". Don't rewrite the YAML in the report; let the user decide scope.

## Anti-patterns this skill specifically tries to prevent

- **Using `curl` directly in steps.** Every XML-RPC call must go through `cicd/scripts/xmlrpc-capture.sh` — it mirrors the raw response to stderr (for expectPatterns) and produces a structured JSON envelope on stdout (for `capture:`). Direct `curl` calls bypass both.
- **Putting new testcase YAML in the root or a random dir.** Always `cicd/tests/testcases/<suite>/TC-<SUITE>-NNN.yml`.
- **Forgetting to register a new suite name in `cicd/tests/src/config.ts` (`SUITES` const).** If the suite isn't in that array, the test doesn't run.
- **Running the test without the stack up.** The runner (`bash cicd/scripts/run-tests.sh`) handles ci-up/ci-down automatically — don't start containers manually unless explicitly debugging.
