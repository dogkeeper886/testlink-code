---
fr: FR-004
title: LLM judge — enforce grounded evidence citations
status: draft
issue: https://github.com/dogkeeper886/testlink-code/issues/14
authors: ["dogkeeper886"]
created: 2026-04-20
updated: 2026-04-20
---

# FR-004 — LLM judge: enforce grounded evidence citations

## Tracking

- GitHub issue: [#14](https://github.com/dogkeeper886/testlink-code/issues/14)
- Status: draft
- Depends on: None
- Blocks: None (quality improvement; does not gate correctness)

## Problem

The LLM judge's response schema requires an `evidence` field containing "the exact line(s) from OBSERVATIONS that drove the verdict" (see `cicd/tests/src/judge/llm-judge.ts` system message). In practice the field is inconsistently grounded:

- For short, simple tests the model quotes actual response fragments.
- For longer multi-step tests the model often substitutes a paraphrase of the criteria text, or cites a fragment from the wrong part of the observation.

Concrete observations from run `2026-04-20T02:25:32`:

| Test | Reason field | Evidence field | Grounding |
|---|---|---|---|
| TC-SMOKE-001 | cites `"Login"` in stdout | `STDOUT: Login` | ✓ grounded |
| TC-SMOKE-002 | cites `Hello!` in XML-RPC envelope | `<string>Hello!</string>` | ✓ grounded |
| TC-AUTH-001 | cites `<boolean>1</boolean>` | `<boolean>1</boolean>` quote from response | ✓ grounded |
| TC-PLAN-003 | plausible summary of what happened | `"Step 5 response contains feature_id or status with boolean 1. Step 6 stderr contains the case external id or a tc_id field"` — paraphrase of criteria text | ✗ paraphrase |
| TC-EXEC-001 | cites `status "p"` in lastExecutionResult | `"Step 8 stderr contains the literal fragment ..."` — paraphrase of criteria | ✗ paraphrase |
| TC-EXEC-003 | cites `<name>exec_qty</name><value><string>1</string>` from stderr | `{"ok": true}` — stdout envelope, wrong part of observation | ✗ wrong fragment |

The verdicts themselves are correct in every case. The problem is evidence quality: a downstream human auditing the run cannot trust that the model actually grounded its verdict in the observations, because the evidence field sometimes proves only that the model can paraphrase its own input.

This erodes trust in the judge for cases where the verdict is the part that matters — principally, future failures, where the evidence field is supposed to be the first place a triager looks.

## Goals

- Every verdict's `evidence` field must be a substring of one of the observation fields (step stdout, step stderr, or container_logs) for that test.
- When a verdict is `pass: false`, the evidence must quote the specific log line that disproves the claim — not "Step N does not contain X" but the actual Step N contents that led to that conclusion.
- Framework surfaces evidence/observation mismatch so a human can audit.

## Non-goals

- Changing verdict accuracy. Correct verdicts stay correct; this FR only tightens the auditability of the evidence trail.
- Switching models. `LLM_JUDGE_MODEL` stays configurable.
- Re-writing test YAMLs. The per-test fields (`objective`, `judgeContext`, `criteria`) are the test author's responsibility and are not in scope here.
- Supporting fuzzy / semantic matching of evidence against observations. A substring check is enough.

## Proposed solution

Three independent layers; pick one, pick a combination, or pick all.

### Layer 1 — Tighten the system prompt

Add an explicit rule and an example to `llm-judge.ts`'s system message:

```
- evidence MUST be an exact substring of the observations you were given.
  Do not paraphrase the criteria. Quote the log line.

Example (correct): evidence: "<string>b</string>"
Example (wrong):   evidence: "Step 10 stderr contains the expected status value"
```

The wrong example deliberately looks like what the model currently produces for long tests, so the contrast is legible.

Lowest-effort, moderate expected effect. Doesn't fix it when the model misbehaves anyway.

### Layer 2 — Post-process validation

After `JSON.parse` in `judgeOne`, check whether `judgment.evidence` appears verbatim (case-insensitive substring) in any of:

- each step's `stdout`
- each step's `stderr`
- the `container_logs`

If the evidence is non-empty and doesn't match anywhere, emit a structured log entry `[LLM] WARNING: Evidence not grounded for <testId>: <evidence>` and add a flag on the `Judgment` struct (e.g., `evidenceGrounded: false`). The verdict itself stays — we're auditing, not overriding.

Test reports surface the flag. Triagers know which verdicts to double-check.

### Layer 3 — Retry-with-correction on ungrounded evidence

If Layer 2 detects mismatch, re-prompt the model once with the specific observation it should quote from. Additional cost per retry; bounded by a retry cap.

Probably overkill for a first cut; add only if Layers 1+2 leave too much noise.

## Alternatives considered

- **Ignore it, trust the reason field.** Rejected — reasons are also paraphrased sometimes; evidence was supposed to be the grounded anchor, and if it isn't, we've lost the anchor.
- **Replace LLM judge with pure regex everywhere.** Rejected — the LLM judge's job is to catch silent-failure cases the simple judge can't. Correctness is fine; auditability is the gap.
- **Switch to a larger model.** Rejected — this problem is architectural (prompt design + validation), not scale. A larger model would paraphrase less but wouldn't guarantee grounding.

## Acceptance criteria

- After implementation, every verdict in a full suite run has `evidence` appearing as a substring in that test's observation fields.
- If any verdict's evidence doesn't match, the framework surfaces it clearly (log line + judgment flag + visible in report).
- Existing tests continue to pass both judges; no regression in verdict accuracy.
- The judge system prompt documents the evidence-grounding requirement explicitly.

## Risks and tradeoffs

- **Tightening the prompt adds tokens.** The judge prompt is already pushing 7k tokens on the longest tests. Adding examples costs space. Quantify: ~200 tokens for the rule + example; negligible vs. current prompt sizes.
- **Layer 2 adds complexity.** A warning that's frequently triggered becomes noise. If Layer 1 mostly fixes grounding, most runs won't trigger Layer 2; if it doesn't, the warning is signal.
- **Substring matching is brittle.** The model might quote a semantically correct fragment with different whitespace, or combine two adjacent fields. Can mitigate with whitespace normalization before comparison.

## Open questions

- _Is substring matching enough, or do we need token-level overlap checks?_ (nice to resolve) — worth starting with substring and raising if we see mismatches we'd consider semantically grounded.
- _Do we downgrade the verdict to suspect when Layer 2 fails, or just annotate?_ (nice to resolve) — I lean annotate-only, because the verdict might still be right even if the evidence citation is sloppy.

## Implementation notes

- Relevant file: `cicd/tests/src/judge/llm-judge.ts`. Both the system message construction and the `judgeOne` post-processing loop live there.
- Relevant types: `Judgment` in `cicd/tests/src/types.ts` would need an `evidenceGrounded?: boolean` field for Layer 2.
- Reporter changes (`cicd/tests/src/reporter/`) to surface the flag in output.

## Out of scope (deferred)

- Changing test authoring guidance. The testcase-author skill and `TESTCASE_AUTHORING.md` remain as-is — this FR does not push new requirements onto test authors.
- Multi-judge arbitration. If Layers 1-3 aren't enough, a future FR could explore running two judges and comparing.
