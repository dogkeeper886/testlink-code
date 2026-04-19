---
fr: FR-001
title: Extend functional CI test coverage to plans, builds, executions, and requirements
status: draft
issue: https://github.com/dogkeeper886/testlink-code/issues/7
authors: ["dogkeeper886"]
created: 2026-04-19
updated: 2026-04-19
---

# FR-001 — Extend functional CI test coverage

## Tracking

- GitHub issue: [#7](https://github.com/dogkeeper886/testlink-code/issues/7)
- Status: draft
- Depends on: [FR-002](./FR-002-delete-build-and-remove-test-case-from-test-plan.md) (cleaner Phase 1 teardown), [FR-003](./FR-003-requirement-spec-and-requirement-crud.md) (Phase 2 unblocked)
- Blocks: None

## Problem

The CI suite landed by issue #5 covers project / suite / case CRUD plus smoke and auth — but it stops at the *static* setup of TestLink. The product's actual daily workflow (test plan → build → attach cases → record executions) and its compliance flow (requirement spec → requirement → assign to case → coverage report) have **zero automated coverage**.

This means a regression in the execution-recording path — the part users touch every release — would ship unnoticed. Every "test result" assertion currently passes by virtue of the static entity API, not by virtue of TestLink actually doing what users use it for.

## Goals

- Validate the test-plan and build lifecycle through the XML-RPC API end-to-end.
- Validate execution recording (pass / fail / blocked) and read-back via `getLastExecutionResult` and `getExecCountersByBuild`.
- Validate requirement traceability (assign to case, coverage report) once the API supports requirement creation.
- Stitch the dynamic flow into a single end-to-end workflow test (the `TC-WORKFLOW-002` analogue of the existing static `TC-WORKFLOW-001`).
- All new tests follow the patterns in `cicd/TESTING_GUIDELINES.md`: dynamic IDs via `capture:`, `{{runId}}` / `{{testId}}` / `{{devKey}}` substitution, reverse-order teardown, full `objective` / `judgeContext` / `criteria` fields.

## Non-goals

- Negative tests (invalid IDs, malformed XML, FK violations, permission denials).
- Security tests (injection, XSS, key-leak in errors, direct config fetch).
- Performance tests (bulk create, concurrent reports).
- Infra extensions (PHP extension presence, schema-migration idempotency, container user assertions).
- Supporting features: keywords, custom fields, attachments, user/role administration.
- Replacement of the YAML test runner with Vitest or another standard framework.

## Proposed solution

Three phases of new YAML testcases under `cicd/tests/testcases/`:

```
plan/
  TC-PLAN-001  test plan CRUD
  TC-PLAN-002  build CRUD under plan (closeBuild today; deleteBuild after FR-002)
  TC-PLAN-003  attach case to plan (cascade-detach today; remove API after FR-002)

execution/
  TC-EXEC-001  record passing result
  TC-EXEC-002  record fail then blocked (single test, one setup, status transitions)
  TC-EXEC-003  counters per build via getExecCountersByBuild + getTotalsForTestPlan
  TC-EXEC-004  delete execution and verify gone

requirement/  (BLOCKED on FR-003)
  TC-REQ-001   requirement spec CRUD
  TC-REQ-002   requirement CRUD under spec
  TC-REQ-003   assign requirement to case + getReqCoverage

workflow/
  TC-WORKFLOW-002  full plan-and-execute lifecycle
                   (project → suite → case → plan → build → attach → report → read → reverse teardown)
```

Each test must verify each XML-RPC method exists in `lib/api/xmlrpc/v1/xmlrpc.class.php` before referencing it (the API surface map in issue #7 documents what's available today vs. what needs FR-002 / FR-003).

## Alternatives considered

- **Bigger single suite that covers everything in one giant flow.** Rejected — fails one-failure-blocks-all, makes diagnosis harder, doesn't isolate per-entity verification.
- **Drive tests through the UI (Selenium / Playwright).** Rejected — slower, more brittle, doesn't exercise the API surface third-party integrations actually use. UI tests are a separate concern for a future FR.
- **Wait for FR-003 before starting any of this.** Rejected — Phase 1 (execution flow) is the higher-value gap and is largely buildable today.

## Acceptance criteria

- Phase 1 and Phase 3 testcases pass under `bash cicd/scripts/run-tests.sh` (both simple judge and LLM judge).
- Phase 2 testcases pass once FR-003 has landed.
- Running each new suite twice in a row against a fresh stack produces identical results (idempotency).
- No hardcoded IDs, names, or API keys in any new test step.
- Each test's `objective` and `judgeContext` follow the patterns set in `TC-BUILD-002.yml` and `TC-AUTH-002.yml`.
- Per-test logs in `cicd/results/<run>/<testId>.log` are non-empty for every test that talks to the running stack.
- `TC-WORKFLOW-002` lives in `testcases/workflow/` so it joins the default run alongside `TC-WORKFLOW-001`.

## Risks and tradeoffs

- **Phase 1 written before FR-002 lands** uses cascade-deletion via `deleteTestPlan` for cleanup. When `deleteBuild` and `removeTestCaseFromTestPlan` arrive, those tests need a small refactor to use them properly. Mitigation: write a comment in each Phase 1 test pointing at FR-002 so the follow-up isn't forgotten.
- **TC-EXEC-002 cycles statuses in one test.** If a single status transition fails, the whole test fails — slightly noisier diagnosis than three separate tests. Tradeoff accepted because setup cost is high and the transitions share state.
- **Requirements coverage stays at zero** until FR-003 lands. If FR-003 slips, this FR's "compliance track" goal slips with it.

## Open questions

- _None._ The phased plan and the API surface map make scope unambiguous.

## Implementation notes

- Existing tests to copy from: `cicd/tests/testcases/crud/TC-CRUD-003.yml` (multi-entity CRUD with reverse teardown), `cicd/tests/testcases/workflow/TC-WORKFLOW-001.yml` (full flow with capture chain), `cicd/tests/testcases/auth/TC-AUTH-002.yml` (negative test framing in `judgeContext`).
- API surface verification: `grep "'tl\\." lib/api/xmlrpc/v1/xmlrpc.class.php`.
- The XML-RPC helper at `cicd/scripts/xmlrpc-capture.sh` produces stdout JSON envelopes and mirrors raw XML to stderr — `expectPatterns` matches against the combined stream.

## Out of scope (deferred)

- Negative-test suite — open a follow-up FR if needed after Phase 1 lands.
- Security suite — open a follow-up FR after Phase 1 lands.
- Performance suite — open a follow-up FR after Phase 1 lands.
- Supporting features (keywords, custom fields, attachments, user admin) — separate FRs as the demand surfaces.
- UI tests — separate FR, separate stack.
