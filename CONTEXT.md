# TestLink

A test management system exposing an XML-RPC API. This fork adds API surface and a
CI test framework on top of upstream TestLink; the vocabulary below is what the
codebase, the API, and the CI tests must agree on.

## Language

### Domain

**Test Project**:
The root entity of the TestLink hierarchy. Everything else — suites, cases, plans,
requirements — hangs beneath one.
_Avoid_: Project, Product

**Test Project Name**:
A Test Project's human-readable label, stored in `nodes_hierarchy`. Mutable, and
unique across Test Projects.
_Avoid_: Title, Product name

**Test Case Prefix**:
The short string stamped into every Test Case external ID beneath a Test Project.
Part of a Test Case's published identity, not a label — changing it restates how
existing Test Cases are identified. Treated as immutable once the Test Project
exists.
_Avoid_: Prefix, Project code

### CI test framework

**runId**:
A millisecond timestamp generated once **per test case**, not once per run, and
substituted into test YAML as `{{runId}}`. Tests use it to derive collision-free
Test Project names and prefixes. The name is misleading; the scope is a single test.

**Simple judge**:
The regex layer that decides a step passed. Enforces that exact fragments are
present, via a step's `expectPatterns`.
_Avoid_: Pattern judge, matcher

**LLM judge**:
The semantic layer that decides a test passed, reading the log the way a human
engineer would. Configured per test via `objective`, `judgeContext`, and `criteria`.
Catches silent failures the Simple judge's exact matches let through.
_Avoid_: AI judge, semantic checker
