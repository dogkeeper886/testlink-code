# Test Project updates are partial, and Test Case Prefix is immutable

`tl.updateTestProject` applies only the fields the caller supplied, reading the
current Test Project first and overlaying on top, and it rejects any attempt to
change the Test Case Prefix. This is deliberately narrower than the manager
method it wraps: `tlTestProject::update()` supports prefix changes and overwrites
name, notes, colour and options unconditionally.

## Considered Options

**Full replace** — require every field on every call, matching `update()`'s own
semantics. Rejected: the primary consumer is an MCP server where a model composes
the call, and a model that omits `notes` would blank it, while an omitted
`options` struct would serialize as `null` and silently strip
`requirementsEnabled`, `testPriorityEnabled`, `automationEnabled` and
`inventoryEnabled` from the project. A destructive default is the wrong shape for
a caller that improvises its arguments.

**Mutable prefix** — expose `$tcasePrefix`, which `update()` already accepts.
Rejected because Test Project Name and Test Case Prefix are different kinds of
thing, and only the glossary makes that obvious. The Name is a label. The Prefix
is stamped into the external ID of every Test Case beneath the project, so
changing it restates the published identity of work that already exists. Renaming
is cheap and reversible; re-prefixing is neither.

## Consequences

Partial updates cost one extra `get_by_id()` per call. That is the price of not
losing data, and it is worth paying.

`options` is accepted as a whitelist of the four known keys rather than the
free-form struct `tl.createTestProject` accepts. `update()` interpolates
`serialize($options)` into SQL without escaping, so an arbitrary key is an
injection vector; the existing passthrough in `createTestProject` survives only
because serialized integer properties happen to emit no single quotes. New code
should not inherit that.

The prefix refusal is raised as `NOT_YET_IMPLEMENTED` (50), which reads as
"later" where this decision means "by design". No existing error code expresses
"this field is immutable", and adding one was ruled out, so the accurate half of
the answer lives in the message rather than the code. Worth revisiting if a
suitable code ever appears.

Because prefix is never changed, the method passes the project's *current* prefix
to `update()` rather than `null`. That is not decoration: `update()` assigns
`$tcprefix` only inside the `!is_null($tcasePrefix)` branch but reads it
unconditionally when building the `EVENT_TEST_PROJECT_UPDATE` context, so passing
`null` would emit an undefined-variable notice on every call. Writing the
identical prefix back is a no-op and avoids modifying a method the GUI shares.
