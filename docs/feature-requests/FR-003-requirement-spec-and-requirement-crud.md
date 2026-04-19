---
fr: FR-003
title: Add Requirement Specification + Requirement CRUD to XML-RPC API
status: draft
issue: https://github.com/dogkeeper886/testlink-code/issues/9
authors: ["dogkeeper886"]
created: 2026-04-19
updated: 2026-04-19
---

# FR-003 — Add Requirement Specification + Requirement CRUD to XML-RPC API

## Tracking

- GitHub issue: [#9](https://github.com/dogkeeper886/testlink-code/issues/9)
- Status: draft
- Depends on: None
- Blocks: [FR-001](./FR-001-extend-functional-test-coverage.md) Phase 2 (requirement traceability tests cannot run without these methods)

## Problem

The XML-RPC API has read-only and traceability access to requirements but **no way to create, update, or delete the underlying entities**. A consumer can read a requirement, assign it to a case, and query coverage — but cannot author a requirement spec or a requirement at all.

This means:
- External integrations (e.g. importing requirements from Jira via API) must bypass the API and write directly to the DB.
- The CI suite (FR-001 Phase 2) cannot validate the requirement traceability flow because there's no API path to set up the requirement entities the test would assign.
- Any automation around the requirements feature is blocked at the front door.

The underlying business logic exists — the web UI uses `requirement_mgr.class.php` and `requirement_spec_mgr.class.php` daily. The work is the XML-RPC adapter, not new business logic.

## Goals

- Add five new XML-RPC methods covering Requirement Spec and Requirement CRUD:
  - `tl.createRequirementSpecification(devKey, testprojectid, name, scope[, parentid][, typ][, coverage])` → returns new spec id.
  - `tl.deleteRequirementSpecification(devKey, reqspecid)` → returns boolean; faults on FK violation.
  - `tl.createRequirement(devKey, reqspecid, testprojectid, docid, title, scope, coverage[, status][, type][, validity][, expected_coverage])` → returns new requirement id.
  - `tl.deleteRequirement(devKey, reqid)` → returns boolean.
  - `tl.getRequirementSpecificationsForTestProject(devKey, testprojectid)` → returns array of spec records.
- All five methods registered in the XML-RPC dispatch map.
- All five methods delegate to the existing helper classes (`requirement_mgr`, `requirement_spec_mgr`).

## Non-goals

- Requirement versioning operations.
- Requirement-to-requirement parent/child links between *requirements* (specs already support nesting via `parentid`).
- Custom-field write API for requirements (only design-time read exists today).
- `tl.updateRequirement` / `tl.updateRequirementSpecification` — listed Nice-to-have only.
- `tl.unassignRequirements` (inverse of `assignRequirements`) — listed Nice-to-have only.

## Proposed solution

Land one method end-to-end first, then replicate the pattern for the remaining four.

Suggested order:
1. `createRequirementSpecification` — establishes the dispatch + permission + helper-call shape.
2. `getRequirementSpecificationsForTestProject` — read pair for #1; verifies #1 actually persisted.
3. `deleteRequirementSpecification` — close the loop on the spec entity.
4. `createRequirement` — same shape as #1 but the child entity.
5. `deleteRequirement` — close the loop on the requirement entity.

Each follows the same template:
- Public method on `lib/api/xmlrpc/v1/xmlrpc.class.php` (parameter validation + permission check + helper delegation + response wrapping).
- Permission check based on requirement-management ACL (read existing UI usage to confirm exact rights).
- Delegate to the existing manager class method.
- Register the method name in the dispatch table.

## Alternatives considered

- **Add only the two methods strictly needed by FR-001 Phase 2 (`createRequirement` + `deleteRequirement`).** Rejected — without spec CRUD, requirements have nowhere to live and the API still requires UI/DB intervention. False economy.
- **Add bulk variants (`createRequirements` plural).** Rejected for v1 — singular form covers the common case; bulk can come later as a separate FR if performance demands it.
- **Generate the methods from the existing UI handlers (codegen).** Rejected — the existing handlers mix presentation logic with business logic; cleaner to write thin adapters than to extract.

## Acceptance criteria

- All five Must methods appear in `grep "'tl\\." lib/api/xmlrpc/v1/xmlrpc.class.php`.
- Manual XML-RPC roundtrip: create spec → create requirement under it → assign to a case → `getReqCoverage` shows the linkage → delete requirement → delete spec, all via XML-RPC only (no UI or DB seed).
- FR-001 Phase 2 (TC-REQ-001/002/003) becomes implementable as scoped.

## Risks and tradeoffs

- **Surface area is bigger than FR-002** (5 methods vs. 2). Mitigation: explicit incremental delivery — one method end-to-end before fanning out. Each method is independently mergeable.
- **Requirement schema has more fields than test entities** (custom field design values, coverage targets, expected_coverage, validity, status). Risk: API signature becomes wide. Mitigation: required vs. optional split; only the minimum viable set of params is required, the rest default sensibly per the helper.
- **Permission scoping may differ from test-entity ACL** — requirements are a separate management area in TestLink. Mitigation: read existing UI `req*.php` files in `lib/requirements/` for the actual ACL pattern before mirroring.

## Open questions

- _Are requirement spec types user-defined or fixed enum?_ (nice to resolve) — affects whether `typ` param accepts an integer ID, a string name, or both.
- _Does deleting a requirement cascade to its assignments to test cases?_ (blocking) — if not, callers need to call `unassignRequirements` first; documentation must say so.

## Implementation notes

- Helper classes already exist (UI uses them today): `lib/functions/requirement_mgr.class.php`, `lib/functions/requirement_spec_mgr.class.php`. The work is the XML-RPC adapter, not new business logic.
- Reference impl patterns:
  - `createTestSuite`, `deleteTestSuite` (issue #1) for create/delete shape on a parent-child entity.
  - `getRequirements` (already exists) for read-list shape.
- Registration site: same dispatch table edits as FR-002.

## Out of scope (deferred)

- `tl.updateRequirement` / `tl.updateRequirementSpecification` — open as follow-up FR after Must lands.
- `tl.unassignRequirements` — open as follow-up FR; currently only matters if cascade on delete is not implemented.
- Requirement versioning API — much bigger scope, separate FR if user demand emerges.
- Requirement custom-field write API — separate FR.
