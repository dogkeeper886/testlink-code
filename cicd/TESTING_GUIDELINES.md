# CI Testing Guidelines

Design rules for the TestLink CI test suite under `cicd/`. Framework-agnostic — applies whether the runner is YAML-based, Vitest, or plain shell.

---

## 1. Purpose

TestLink is a test management system. Its value is the correctness of its API and data operations. These guidelines define **how we test it** so that:

- CI runs are reproducible and deterministic
- Test failures point to the real cause, not infrastructure drift
- Tests can be run in isolation, reordered, or rerun without manual cleanup
- Teardown is guaranteed, even on failure

---

## 2. Design Principles

1. **Tests talk through the public API.** XML-RPC and REST are the contracts under test. Go through them like a real client would.
2. **Direct DB access is reserved for three jobs only:** seeding the admin API key, asserting side effects that are not exposed via API, and emergency cleanup. Never use SQL to shortcut a test setup that could go through the API.
3. **Every test owns its data.** A test creates what it needs, asserts against it, and deletes it. Tests do not rely on residue from previous tests.
4. **IDs flow through capture, never hardcoded.** The ID of a created entity comes from the creation response, not from assuming "it'll be id=1".
5. **Teardown is guaranteed.** Every scope's teardown runs in a `finally` / `trap EXIT` so that a failure does not leak state into the next run.
6. **Idempotency.** Running the same suite twice in a row against a fresh environment produces identical results.

---

## 3. Nested Lifecycle Scopes

Four scopes nest like Russian dolls. Each has its own `setup → run children → teardown`, with teardown always guaranteed.

```
SESSION (once per CI run)
  └── SUITE (once per suite: smoke, auth, crud, workflow, …)
        └── TEST CASE (once per test)
              └── STEP (one action)
```

### 3.1 Session scope

Runs once per CI invocation. Owns the infrastructure.

**Setup:**
- `docker compose -f cicd/docker-compose.ci.yml up -d`
- Wait for healthchecks
- Load schema: `testlink_create_tables.sql` + UDFs
- Load default data: `testlink_create_default_data.sql`
- Seed the admin API key (`UPDATE users SET script_key='…' WHERE id=1`)

**Teardown (always):**
- `docker compose -f cicd/docker-compose.ci.yml down -v --remove-orphans`

**Rule:** session setup owns infrastructure and baseline (admin + API key) **only**. No test-specific data.

### 3.2 Suite scope

One per feature area (auth, crud, workflow, …). Owns shared fixtures for that area.

**Setup:**
- Create a dedicated test project with a unique name (`suite-<name>-<timestamp>`)
- Capture the project ID for all tests in the suite
- Create any users, roles, or custom fields this suite needs

**Teardown (always):**
- Delete the suite's test project (cascades to everything under it)

**Rule:** no suite may depend on another suite's residue. Any suite must be runnable alone and in any order.

### 3.3 Test case scope

One per test. Owns the minimum entities the test needs.

**Setup:**
- Create the entities the test acts on (test suite, test case, test plan, build)
- Use unique names tied to the test ID: `<testId>-<random>`
- Capture every created ID

**Teardown (always):**
- Delete the entities this test created, in reverse order

**Rule:** a test must be runnable twice in a row against the same suite fixtures without manual cleanup between runs.

### 3.4 Step scope

One API call with one assertion. No hidden side effects. If a step creates state that outlives itself, the creation must be explicit and captured.

---

## 4. Test Flow

Test categories layer on top of each other. A failure at a lower layer should short-circuit the higher layers — no point testing CRUD if the server isn't responding.

| Layer | Tests | Purpose |
|---|---|---|
| **Smoke** | `tl.ping`, login page loads | Is the system alive? |
| **Auth** | valid key, invalid key, missing key | Can we talk to it? |
| **CRUD (leaf-up)** | create/read/update/delete for each entity in dependency order: **project → testsuite → testcase → testplan → build → execution** | Do basic operations work? |
| **Workflow** | assign case to plan → create build → record execution → query results | Do operations compose end-to-end? |
| **Negative** | bad input, missing required fields, permission denied, FK violations | Does it fail correctly? |
| **Regression** | specific bug repros (one test per closed bug) | Does a past bug stay fixed? |

**Short-circuit rule:** if Smoke fails, skip everything below. Implementation: make Auth depend on Smoke, CRUD on Auth, and so on. The runner skips dependents when a dep fails.

---

## 5. Dynamic ID Capture

IDs are never hardcoded. They flow from creation responses into subsequent steps via captured variables.

### 5.1 Rule

> **No numeric ID literal (`1`, `2`, `42`) may appear in a test step except in assertions about the response shape itself.**

### 5.2 Pattern

```yaml
- name: Create test project
  command: |
    curl -sf -X POST http://localhost:8090/lib/api/xmlrpc/v1/xmlrpc.php \
      -H "Content-Type: text/xml" \
      -d '<?xml … tl.createTestProject … testprojectname=proj-{{runId}} …>'
  capture:
    projectId: "$[name=id].value"    # resolve from response

- name: Create test suite under it
  command: |
    curl -sf … testprojectid={{projectId}} testsuitename=suite-{{runId}} …
  capture:
    suiteId: "$[name=id].value"

- name: Delete test suite
  command: curl -sf … testsuiteid={{suiteId}} …

- name: Delete test project
  command: curl -sf … prjid={{projectId}} …
```

### 5.3 Rationale

- Runs are reorderable: no dependency on seed counters.
- Runs are re-runnable: no "id=1 already exists" collisions.
- Parallel safety: different runs pick different IDs without coordination.
- Failures are traceable: logs show which concrete IDs were in play.

---

## 6. Test Data Rules

1. **Unique names.** Every created entity gets a name that includes the run ID or a timestamp: `proj-20260419-143022`. Never `proj`, never `CI Test Project`.
2. **Prefix by test ID** where practical (`TC-CRUD-003-project-…`) so orphaned data is traceable.
3. **Capture every ID** from creation responses. Never assume the next auto-increment value.
4. **Delete in reverse creation order.** Children before parents.
5. **Idempotency.** A second run against the same fixtures must behave identically. Verify by running the suite twice locally before committing.
6. **No implicit ordering between test cases** beyond declared `dependencies`. If test B silently needs test A's data, declare the dependency or duplicate the setup.

---

## 7. Teardown Guarantees

Each scope's teardown must run **even when a test or step fails**. Implementation depends on scope:

| Scope | Guarantee mechanism |
|---|---|
| Session | Wrapper script with `trap 'ci-down.sh' EXIT` |
| Suite | Runner executes suite-teardown in a `finally` block after all tests, regardless of results |
| Test case | Runner executes test-teardown in a `finally` block after all steps, regardless of step outcomes |
| Step | Step is atomic; no sub-teardown |

A teardown failure must surface loudly but must **not** prevent outer teardowns from running.

---

## 8. Why `docker-compose.ci.yml` Is Separate from `docker-compose.yml`

The repo has two compose files on purpose. They serve different audiences and have incompatible lifecycle assumptions. This section is grounded in the actual current files (`docker-compose.yml` at repo root and `cicd/docker-compose.ci.yml`).

| Aspect | `docker-compose.yml` (dev) | `cicd/docker-compose.ci.yml` (CI) |
|---|---|---|
| Audience | Developers working locally | Automated CI and test runs |
| Lifecycle | `up` once, leave running for days | `up → test → down -v` every run |
| DB state | Named volume `postgres` — persistent across restarts | No named DB volume — anonymous, destroyed by `down -v` |
| Services | `db` + `maildev` + `app` + `restore` (profile=tools, opt-in) | `db` + `app` only |
| DB credentials | `teste` / `teste` | `testlink` / `testlink` |
| Config injection | None — relies on defaults baked into the image | Mounts `ci-config_db.inc.php` (CI DB creds) + `ci-custom_config.inc.php` (API on, SMTP off) |
| Seed data | Optional: `restore` service loads `docs/db_sample` sample data | `init-db.sh` loads schema + default data + hardcoded admin API key |
| Image build | `build: .` from repo root Dockerfile | `build: ..` from the same Dockerfile |
| Image pinning | `postgres:9.6` pinned; `maildev:latest` floats | Fully pinned (`postgres:9.6`) |
| Host port | `0.0.0.0:8090:80` | `8090:80` |

### Important: port 8090 collides

Both compose files publish the app on host port **8090**. They cannot run at the same time. If the dev stack is up, CI setup will fail to bind. This is a known constraint — tests and the dev environment are serialized on a single developer machine. Long-term, the CI compose should either take a different port or use ephemeral host port assignment to remove this footgun.

### Why the separation is mandatory

1. **Teardown safety.** CI teardown runs `down -v`, which destroys volumes. The dev compose's `postgres` named volume holds a developer's in-progress database. Because the two compose files live in different directories (`./` and `cicd/`), Docker Compose gives them different project namespaces (`testlink-code` vs `cicd`) — so their volumes, containers, and networks are isolated. `down -v` run against the CI compose cannot touch the dev compose's `postgres` volume. Merging them would break this guarantee.
2. **Reproducibility of seed and config.** CI must start from a known state: fresh schema, default data, known admin API key `a1b2…`, API enabled, SMTP off. The dev compose intentionally does not inject any of that — it relies on whatever the developer has set up. Merging the two would either corrupt dev state on every CI run or require runtime conditionals that obscure both flows.
3. **Credentials and data isolation.** Different DB users (`teste` vs `testlink`), different injected configs, different (or no) seed data. A single file trying to serve both audiences would need env-var gymnastics that make each flow harder to reason about.
4. **Service minimalism.** CI starts only `db` + `app`. Dev adds `maildev` for catching outbound mail and `restore` (profile-gated) for loading sample data. CI doesn't need either — faster startup, narrower failure surface, fewer moving parts when diagnosing a test failure.

### Naming convention

- Dev compose: **`docker-compose.yml`** at the repo root. The file `docker compose up` picks up by default — optimize for developer ergonomics.
- CI compose: **`cicd/docker-compose.ci.yml`**, explicit path, never the default. Living under `cicd/` also changes Docker Compose's default project name to `cicd`, which is what keeps volumes and containers isolated from the dev stack.

**Rule:** any new compose file for a specific purpose (e2e-only, perf testing, …) gets its own name under a dedicated directory (not the repo root). Never overload `docker-compose.yml`.

---

## 9. Directory Conventions

```
cicd/
├── docker-compose.ci.yml      # CI environment definition
├── scripts/                   # Session-scope lifecycle
│   ├── ci-up.sh               # Session setup (build + up + seed)
│   ├── ci-down.sh             # Session teardown (down -v)
│   ├── init-db.sh             # Schema + default data + admin API key
│   ├── ci-config_db.inc.php   # DB config injected into app
│   └── ci-custom_config.inc.php  # App config (API on, SMTP off)
├── tests/
│   ├── src/                   # Test runner (TypeScript)
│   └── testcases/             # Test definitions
│       ├── smoke/
│       ├── auth/
│       ├── crud/
│       ├── workflow/
│       ├── negative/
│       └── regression/
└── results/                   # Per-run output (gitignored)
```

**Rule:** infrastructure code (scripts, compose) lives in `cicd/`. Test definitions live in `cicd/tests/testcases/`. Nothing test-related lives outside `cicd/`.

---

## 10. Checklist for Writing a New Test

- [ ] Suite category is correct (smoke / auth / crud / workflow / negative / regression)
- [ ] `dependencies` is declared if this test needs another test's entities to already pass
- [ ] All created entities use unique names that include the run ID or timestamp
- [ ] All IDs used in later steps are `capture:`d from earlier responses — no hardcoded integers
- [ ] Test creates exactly what it needs and deletes it in reverse order in teardown
- [ ] Test passes when run alone: `npm run test -- --id TC-XXX-NNN`
- [ ] Test passes when run twice in a row against the same session
- [ ] Assertions check response shape and content, not just exit code
- [ ] Teardown runs even when a prior step fails (verified by injecting a failure locally)
