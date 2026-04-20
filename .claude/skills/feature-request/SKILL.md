---
name: feature-request
description: Author a feature request document and link it bidirectionally with a GitHub issue. Use when a user asks to "draft a feature request", "open a feature spec", "write an FR for issue N", or wants to formalize an idea into a tracked spec doc + issue pair before any code is written.
---

# Feature request authoring

This skill produces a **paired artifact** for any non-trivial change:
1. A markdown spec at `docs/feature-requests/FR-NNN-<slug>.md` in the repository
2. A GitHub issue with the same content, cross-linked

The spec is the durable design record (versioned with the code, editable via PR). The issue is the conversation, status, and assignment surface. Neither replaces the other.

## When to invoke

- User says something like: "draft a feature request for X", "open an FR", "let's spec this out before coding", "write an FR for issue N"
- An idea has emerged from chat that's worth more than a one-line issue — there are decisions, tradeoffs, dependencies, or scope concerns to capture
- An existing GitHub issue is sketchy and the user wants a fuller spec backing it

**Do NOT invoke for:**
- Bug fixes (use a regular issue)
- Trivial chores (rename, version bump, formatting)
- Already-decided implementation work that's about to start (skip straight to a PR)

## Modes

### Mode A — From scratch (`new`)

User provides a topic. You ask 3-5 clarifying questions to get enough material, then:
1. Pick the next FR number by listing `docs/feature-requests/FR-*.md`
2. Slugify the title
3. Render the template (see below) into `docs/feature-requests/FR-NNN-<slug>.md`
4. Create a GitHub issue with the same body via `gh issue create`
5. Edit the FR doc to insert the issue URL into the front-matter and the "Tracking" section
6. Edit the issue body to insert the FR doc path
7. Stage both files for commit (don't commit unless the user says so)

### Mode B — From existing issue (`from-issue <number>`)

User points at an existing issue. You:
1. `gh issue view <N> --json number,title,body,url`
2. Pick the next FR number (sequential, not matching the issue number — issue numbers are reused/sparse, FR numbers are durable)
3. Slugify the issue title
4. Convert the issue body into the FR template structure (lift sections that map; flag gaps in "Open questions")
5. Save as `docs/feature-requests/FR-NNN-<slug>.md`
6. Edit the issue body to prepend a "Spec: [docs/feature-requests/FR-NNN-…](docs/feature-requests/FR-NNN-…)" line
7. Stage the FR doc for commit

### Mode C — Backfill multiple

User points at several existing issues. Run Mode B for each, in number order. Stage all FR docs. One commit per FR is cleaner than one mega-commit.

## Template

Use this exact structure. Don't add sections unless the user asks. Don't drop sections — leave a placeholder like "_None._" if a section doesn't apply, so the structure stays predictable across docs.

```markdown
---
fr: FR-NNN
title: <One short sentence>
status: draft        # draft | proposed | accepted | in-progress | done | rejected | superseded
issue: <URL or #N>   # GitHub issue this FR pairs with
authors: ["<name>"]  # optional
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# FR-NNN — <Title>

## Tracking

- GitHub issue: <link>
- Status: <status>
- Depends on: <other FRs / issues, or "None">
- Blocks: <other FRs / issues, or "None">

## Problem

What's broken or missing today, and who feels the pain. One short paragraph. If the answer is "no one feels pain yet, this is speculative," say that explicitly so the reader can weight it.

## Goals

What "done" looks like, in user-visible or system-observable terms. Bulleted, 3-7 items. Each goal should be testable.

## Non-goals

Explicit list of what this FR does NOT cover, especially adjacent things readers might assume are in scope. Bulleted.

## Proposed solution

How. Enough detail that another engineer could start building. Diagrams in ASCII are fine. Cite file paths and line numbers when referring to existing code.

## Alternatives considered

For each: what it is, why it was rejected. Even one sentence each is fine — the value is in showing the option was looked at.

## Acceptance criteria

Concrete, checkable conditions. Bulleted. Should map 1:1 with goals where possible. These become the test plan and the merge gate.

## Risks and tradeoffs

What can go wrong, what we're giving up, who needs to be notified. Be honest — the doc is more useful when it admits weaknesses.

## Open questions

Anything not yet decided. Mark each as `(blocking)` or `(nice to resolve)`. Don't bury these — answering them is often what unblocks the work.

## Implementation notes

Pointers to relevant code, related FRs, prior art. Optional but valuable for whoever picks the work up.

## Out of scope (deferred)

Items explicitly punted to later FRs/issues. Each item should ideally name the follow-up issue if one exists.
```

## File and naming conventions

- Path: `docs/feature-requests/FR-NNN-<slug>.md` where `NNN` is zero-padded 3-digit.
- Slug: lowercase, words joined by `-`, max ~6 words. Strip articles ("the", "a"), punctuation, action verbs ("add", "implement") if they don't add information.
- Numbering: sequential, never reused. Never re-use a number even if an FR is rejected — it stays as a record.
- Status transitions:
  - `draft` → `proposed` (ready for review)
  - `proposed` → `accepted` (approved to implement)
  - `accepted` → `in-progress` (PR opened)
  - `in-progress` → `done` (merged) OR `rejected` (decision reversed)
  - Any → `superseded` (replaced by a newer FR; link to the successor in the doc body)

## Bidirectional linking

The FR doc's `issue:` frontmatter field and the GitHub issue body must always agree. When you update one, update the other in the same operation. If you ever observe drift (FR points at issue X, issue X doesn't link back), fix it as part of the next edit.

When closing the loop after a PR merges:
1. Set the FR `status` to `done`
2. Add a "Resolution" subsection at the bottom of the FR with the merge commit / PR link
3. The GitHub issue is closed automatically by the PR's "Closes #N" — leave that alone

## Concrete commands

```bash
# Pick next FR number
ls docs/feature-requests/FR-*.md 2>/dev/null | sed 's/.*FR-\([0-9]*\)-.*/\1/' | sort -n | tail -1
# Then increment and zero-pad to 3 digits.

# Read an existing issue
gh issue view <N> --repo <owner>/<repo> --json number,title,body,url

# Create a new issue
gh issue create --repo <owner>/<repo> --title "<title>" --body-file <fr-doc-path>

# Update an existing issue body
gh issue edit <N> --repo <owner>/<repo> --body-file <fr-doc-path>
```

## Anti-patterns to avoid

- Don't create an FR for work the user has already started or merged. Document what was actually built, not a hypothetical plan.
- Don't pad. If a section is genuinely empty, write `_None._` and move on. Empty placeholders ("TBD", "TODO") rot.
- Don't promise dates. Status field carries the lifecycle; dates belong on the issue, not the spec.
- Don't duplicate API surface tables or data the issue already has — link to the source. The FR is for *decisions*, the issue is for *conversation*, the code is for *truth*.
- Don't number FRs to match issue numbers. They drift (one FR can spawn many issues; one issue may not deserve an FR).
