---
fr: FR-002
title: Add deleteBuild and removeTestCaseFromTestPlan to XML-RPC API
status: draft
issue: https://github.com/dogkeeper886/testlink-code/issues/8
authors: ["dogkeeper886"]
created: 2026-04-19
updated: 2026-04-19
---

# FR-002 — Add `deleteBuild` and `removeTestCaseFromTestPlan` to XML-RPC API

## Tracking

- GitHub issue: [#8](https://github.com/dogkeeper886/testlink-code/issues/8)
- Status: draft
- Depends on: None
- Blocks: [FR-001](./FR-001-extend-functional-test-coverage.md) Phase 1 (improves teardown shape; Phase 1 can start without this but will require rework when this lands)

## Problem

Two operations exist in the TestLink web UI but have no XML-RPC equivalent:

- **No way to delete a build via API.** `tl.closeBuild` (mark inactive) and `tl.updateBuildCustomFieldsValues` (mutate custom fields) exist; outright delete does not. Tests that create a build to record an execution against can only "close" it, leaving rows in the DB across runs.
- **No way to detach a case from a plan via API.** `tl.addTestCaseToTestPlan` exists with no inverse. Tests that exercise plan-attachment cannot cleanly detach the case afterward; subsequent runs see stale linkage.

This forces test authors into one of three bad choices: rely on cascade via `deleteTestPlan`, leave residue, or seed/teardown directly in the DB. Issue #1 fixed the same shape of gap for `deleteTestCase` / `deleteTestSuite`; this FR finishes the job for builds and plan-case linkages.

## Goals

- Add `tl.deleteBuild(devKey, buildid)` that returns `<boolean>1</boolean>` on success, fault on FK violation when executions still attached.
- Add `tl.removeTestCaseFromTestPlan(devKey, testplanid, testcaseid[, version])` that returns `<boolean>1</boolean>` on success, fault if the case is not attached to the plan.
- Both methods registered in the XML-RPC dispatch map alongside existing entries.
- Both wired to existing helper-class methods (the UI's path) — no new business logic.

## Non-goals

- Full `updateBuild` (beyond `updateBuildCustomFieldsValues`).
- `updateTestPlan`, `updateTestProject`.
- Cascade delete (force-drop attached executions when deleting a build) — listed as a Nice-to-have only.
- Requirements API — covered by FR-003.

## Proposed solution

For each method:
1. Add the public method to `lib/api/xmlrpc/v1/xmlrpc.class.php` following the shape of `deleteTestCase` (`xmlrpc.class.php:8209` — closest precedent, added by issue #1).
2. Permission check: read the existing `closeBuild` (`xmlrpc.class.php:9018`) and `addTestCaseToTestPlan` (`xmlrpc.class.php:3461`) implementations; mirror their ACL scaffolding rather than guessing.
3. Delegate to the existing helper-class method (build manager / test plan manager).
4. Register the method name in the dispatch table alongside the others.
5. If new error codes are introduced, add them to `lib/api/xmlrpc/v1/api.const.inc.php`.

## Alternatives considered

- **Cascade-delete builds when test plan is deleted.** Already happens implicitly via `deleteTestPlan`. But it's coarse — there's no way to delete a single misnamed build without nuking the plan. Rejected as the only mechanism.
- **`removeTestCasesFromTestPlan` (plural batch).** Useful but a separate concern; the singular form covers the common case and matches the singular `addTestCaseToTestPlan`. Add later if needed.
- **Skip the API and have tests use DB cleanup.** Rejected — would couple tests to schema details and break the "tests use only public API" principle established by issue #5.

## Acceptance criteria

- `tl.deleteBuild` and `tl.removeTestCaseFromTestPlan` both appear in `grep "'tl\\." lib/api/xmlrpc/v1/xmlrpc.class.php`.
- Manual XML-RPC roundtrip for each: create the parent state → call the new method → read back and verify the entity is gone (or no longer attached).
- The CI test suite (`cicd/tests/testcases/plan/`) under FR-001 can teardown cleanly without leaving builds or plan-case linkages behind.
- FK violations return a clear fault response, not a 500 or silent success.

## Risks and tradeoffs

- **Permission model misjudgment.** Assuming "same as closeBuild" without verifying could over- or under-restrict. Mitigation: explicit instruction in the issue to read the actual implementation before mirroring.
- **Order of teardown matters.** A `deleteBuild` that doesn't fault on attached executions would silently lose data. Mitigation: fault on FK violation by default, with cascade as Nice-to-have only.

## Open questions

- _Does `addTestCaseToTestPlan` track per-version attachment?_ (nice to resolve) — affects whether `removeTestCaseFromTestPlan` needs an optional `version` parameter. Read the helper to confirm before defining the signature.

## Implementation notes

- Reference patterns in the existing file:
  - `addTestCaseToTestPlan` impl at `lib/api/xmlrpc/v1/xmlrpc.class.php:3461`
  - `closeBuild` impl at `lib/api/xmlrpc/v1/xmlrpc.class.php:9018`
  - `deleteTestCase` impl at `lib/api/xmlrpc/v1/xmlrpc.class.php:8209` (added by issue #1 — closest precedent for a delete operation)
- Helper classes likely live in `lib/functions/` — search for `build_mgr` and `testplan` to find the existing manager methods to delegate to.

## Out of scope (deferred)

- `tl.updateBuild` (full update beyond custom fields) — open as a separate FR if/when needed.
- `tl.updateTestPlan`, `tl.updateTestProject` — same.
- Cascade-delete option (`force` flag) — listed Nice-to-have in issue #8; defer until a real test or user needs it.
