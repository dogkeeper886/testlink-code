# Feature Requests

Durable design records for non-trivial changes. Each feature request (FR) is a markdown document paired with a GitHub issue.

## Why both?

| | GitHub issue | FR document |
|---|---|---|
| Lives where | github.com | repo (versioned) |
| Editable by | issue commenters | PR review |
| Carries | status, assignment, conversation | decisions, tradeoffs, rationale |
| Survives | as long as the issue tracker exists | as long as the code does |

The issue is the conversation surface. The FR is the design record that travels with the code. Both must link to each other.

## Naming

`FR-NNN-<slug>.md`

- `NNN` — zero-padded 3-digit sequence number, never reused.
- `<slug>` — lowercase, hyphens, ~6 words max, no articles or generic verbs.

Numbering is independent of GitHub issue numbers. One FR can spawn multiple issues; one issue may not deserve an FR.

## Lifecycle

```
draft  →  proposed  →  accepted  →  in-progress  →  done
                                                 ↘  rejected
                              ↘ superseded (any state → newer FR replaces it)
```

The `status` field in the FR's YAML frontmatter is authoritative. Update it as the work progresses.

## Authoring

The canonical way is to copy [`_template.md`](./_template.md), fill in the sections, open the matching GitHub issue, and link the two together (FR's `issue:` frontmatter ↔ a `Spec:` line at the top of the issue body).

If you happen to use Claude Code, there's an optional personal skill (`~/.claude/skills/feature-request/`) that automates the create-and-link flow. It's not part of this repository — install it locally if you want it. Without it, the `_template.md` plus a few `gh issue` commands gets you the same result.

## Index

| FR | Title | Status | Issue |
|---|---|---|---|
| [FR-001](./FR-001-extend-functional-test-coverage.md) | Extend functional test coverage | in-progress | [#7](https://github.com/dogkeeper886/testlink-code/issues/7) |
| [FR-002](./FR-002-delete-build-and-remove-test-case-from-test-plan.md) | Add `deleteBuild` and `removeTestCaseFromTestPlan` | done | [#8](https://github.com/dogkeeper886/testlink-code/issues/8) |
| [FR-003](./FR-003-requirement-spec-and-requirement-crud.md) | Add Requirement Spec + Requirement CRUD | draft | [#9](https://github.com/dogkeeper886/testlink-code/issues/9) |
| [FR-004](./FR-004-llm-judge-evidence-grounding.md) | LLM judge — enforce grounded evidence citations | done | [#14](https://github.com/dogkeeper886/testlink-code/issues/14) |
| [FR-005](./FR-005-github-actions-env-vars-and-secrets.md) | GitHub Actions runner env vars + secrets | in-progress | [#19](https://github.com/dogkeeper886/testlink-code/issues/19) |
