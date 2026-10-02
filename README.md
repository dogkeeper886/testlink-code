# TestLink mcp-1.0.0

TestLink 1.9.20 is an open-source test management system, and its XML-RPC API lets other tools create and run test projects. AI assistants now do that work through MCP servers, which call the same API. Upstream's 1.9.20 code has a typo in the XML-RPC class that breaks every API call with HTTP 500, and the API creates test cases, test suites and builds that only the web UI can delete.

This fork fixes the API, adds ten methods, and tests them in CI, so the [TestLink MCP server](https://github.com/dogkeeper886/testlink-mcp) can manage a whole test project.

## Run it with Docker

The compose stack starts TestLink with PostgreSQL and a mail catcher, and the install wizard creates the database on first visit.

```bash
git clone https://github.com/dogkeeper886/testlink-code.git
cd testlink-code
docker compose up -d
```

The first run builds the image, which takes a few minutes. Then open <http://localhost:8090>, choose **New installation**, and enter these values on the database page:

| Field | Value |
|---|---|
| Database type | Postgres (9.1 and later) |
| Database host | `db` |
| Database name | `testlink` |
| Database admin login | `teste` |
| Database admin password | `teste` |
| TestLink DB login | `testlink` |
| TestLink DB password | `testlink` |

The admin login and password come from `docker-compose.yml`. The TestLink login and password are new, and you can choose your own.

Run the database function the wizard asks for, then save its generated config so a rebuild keeps it:

```bash
docker compose exec -T db psql -U teste -d testlink < install/sql/postgres/testlink_create_udf0.sql
docker compose cp app:/var/www/html/config_db.inc.php .
```

Log in as `admin` with password `admin`, and change the password.

[README.containers.md](README.containers.md) covers the stack: rebuilding, mail, the published image and resetting.

## Connect an AI assistant

The TestLink MCP server reaches TestLink through its API, which this fork enables by default.

1. In TestLink, open **My Settings** (the icon at the top right) and click **Generate a new key** under **API interface**.
2. Add the MCP server to Claude Code with that key:

   ```bash
   claude mcp add testlink -- docker run --rm -i --network host \
     -e TESTLINK_URL=http://localhost:8090 \
     -e TESTLINK_API_KEY=<your key> \
     dogkeeper886/testlink-mcp:latest
   ```

`--network host` lets the MCP container reach `localhost:8090` on Linux. Drop it on macOS or Windows and use `http://host.docker.internal:8090`.

The [testlink-mcp README](https://github.com/dogkeeper886/testlink-mcp#readme) covers other MCP clients and the server's tools.

## API methods this fork adds

Upstream's XML-RPC API already has 89 methods, listed in the next section. This fork adds ten that fill its gaps: deleting test cases, suites, builds and requirements, creating requirements, and updating a test project. All of them live in `lib/api/xmlrpc/v1/xmlrpc.class.php`.

| Purpose | Method |
|---|---|
| Delete a test case | `tl.deleteTestCase` |
| Delete a test suite | `tl.deleteTestSuite` |
| Delete a build | `tl.deleteBuild` |
| Remove a test case from a test plan | `tl.removeTestCaseFromTestPlan` |
| List requirement specifications | `tl.getRequirementSpecificationsForTestProject` |
| Create a requirement specification | `tl.createRequirementSpecification` |
| Delete a requirement specification | `tl.deleteRequirementSpecification` |
| Create a requirement | `tl.createRequirement` |
| Delete a requirement | `tl.deleteRequirement` |
| Update a test project | `tl.updateTestProject` |

## API methods TestLink already has

Upstream TestLink 1.9.20 ships these 89 methods. Two pairs are aliases: `tl.ping` for `tl.sayHello`, and `tl.setTestCaseExecutionResult` for `tl.reportTCResult`.

### Server and users

| Purpose | Method |
|---|---|
| Check the server is up | `tl.sayHello`, `tl.ping` |
| Echo a message back | `tl.repeat` |
| Get the TestLink version | `tl.testLinkVersion` |
| Get information about the API | `tl.about` |
| Check an API key | `tl.checkDevKey` |
| Turn test mode on or off | `tl.setTestMode` |
| Create a user | `tl.createUser` |
| Check a user exists | `tl.doesUserExist` |
| Get a user by ID | `tl.getUserByID` |
| Get a user by login | `tl.getUserByLogin` |
| Set a user's role on a test project | `tl.setUserRoleOnProject` |

### Test projects

| Purpose | Method |
|---|---|
| List test projects | `tl.getProjects` |
| Get a test project by name | `tl.getTestProjectByName` |
| Create a test project | `tl.createTestProject` |
| Delete a test project | `tl.deleteTestProject` |
| List a test project's test plans | `tl.getProjectTestPlans` |
| List a test project's keywords | `tl.getProjectKeywords` |
| List a test project's platforms | `tl.getProjectPlatforms` |
| Create a platform | `tl.createPlatform` |
| Upload a test project attachment | `tl.uploadTestProjectAttachment` |
| Get an issue tracker | `tl.getIssueTrackerSystem` |

### Test suites

| Purpose | Method |
|---|---|
| List top-level test suites | `tl.getFirstLevelTestSuitesForTestProject` |
| Get a test suite | `tl.getTestSuite` |
| Get a test suite by ID | `tl.getTestSuiteByID` |
| List child test suites | `tl.getTestSuitesForTestSuite` |
| Create a test suite | `tl.createTestSuite` |
| Update a test suite | `tl.updateTestSuite` |
| List a test suite's attachments | `tl.getTestSuiteAttachments` |
| Upload a test suite attachment | `tl.uploadTestSuiteAttachment` |
| Get a test suite custom field | `tl.getTestSuiteCustomFieldDesignValue` |
| Update a test suite custom field | `tl.updateTestSuiteCustomFieldDesignValue` |

### Test cases

| Purpose | Method |
|---|---|
| Get a test case | `tl.getTestCase` |
| Find a test case ID by name | `tl.getTestCaseIDByName` |
| List a test suite's test cases | `tl.getTestCasesForTestSuite` |
| Create a test case | `tl.createTestCase` |
| Update a test case | `tl.updateTestCase` |
| Move a test case to another test suite | `tl.setTestCaseTestSuite` |
| Set a test case's execution type | `tl.setTestCaseExecutionType` |
| Create or update test case steps | `tl.createTestCaseSteps` |
| Delete test case steps | `tl.deleteTestCaseSteps` |
| List a test case's keywords | `tl.getTestCaseKeywords` |
| Add keywords to a test case | `tl.addTestCaseKeywords` |
| Remove keywords from a test case | `tl.removeTestCaseKeywords` |
| List a test case's attachments | `tl.getTestCaseAttachments` |
| Upload a test case attachment | `tl.uploadTestCaseAttachment` |
| List a test case's bugs | `tl.getTestCaseBugs` |
| List a test case's requirements | `tl.getTestCaseRequirements` |
| Get an item's full path | `tl.getFullPath` |
| Get a test case custom field | `tl.getTestCaseCustomFieldDesignValue` |
| Update a test case custom field | `tl.updateTestCaseCustomFieldDesignValue` |

### Test plans

| Purpose | Method |
|---|---|
| Get a test plan by name | `tl.getTestPlanByName` |
| Create a test plan | `tl.createTestPlan` |
| Delete a test plan | `tl.deleteTestPlan` |
| List a test plan's test cases | `tl.getTestCasesForTestPlan` |
| List a test plan's test suites | `tl.getTestSuitesForTestPlan` |
| Add a test case to a test plan | `tl.addTestCaseToTestPlan` |
| List a test plan's platforms | `tl.getTestPlanPlatforms` |
| Add a platform to a test plan | `tl.addPlatformToTestPlan` |
| Remove a platform from a test plan | `tl.removePlatformFromTestPlan` |
| Get a test plan's result totals | `tl.getTotalsForTestPlan` |
| Get a test plan custom field | `tl.getTestPlanCustomFieldDesignValue` |
| Get a test case's test plan custom field | `tl.getTestCaseCustomFieldTestPlanDesignValue` |

### Builds

| Purpose | Method |
|---|---|
| List a test plan's builds | `tl.getBuildsForTestPlan` |
| Get a test plan's latest build | `tl.getLatestBuildForTestPlan` |
| Create a build | `tl.createBuild` |
| Close a build | `tl.closeBuild` |
| Update a build's custom fields | `tl.updateBuildCustomFieldsValues` |
| Count executions by build | `tl.getExecCountersByBuild` |

### Executions

| Purpose | Method |
|---|---|
| Record a test result | `tl.reportTCResult`, `tl.setTestCaseExecutionResult` |
| Get a test case's last result | `tl.getLastExecutionResult` |
| List a test case's executions | `tl.getExecutionSet` |
| List all execution results | `tl.getAllExecutionsResults` |
| Delete an execution | `tl.deleteExecution` |
| Upload an execution attachment | `tl.uploadExecutionAttachment` |
| Get an execution custom field | `tl.getTestCaseCustomFieldExecutionValue` |
| Assign a tester to a test case | `tl.assignTestCaseExecutionTask` |
| Unassign a tester from a test case | `tl.unassignTestCaseExecutionTask` |
| Get a test case's assigned tester | `tl.getTestCaseAssignedTester` |

### Requirements

| Purpose | Method |
|---|---|
| List a test project's requirements | `tl.getRequirements` |
| Get a requirement | `tl.getRequirement` |
| Link requirements to test cases | `tl.assignRequirements` |
| Get requirement coverage | `tl.getReqCoverage` |
| Upload a requirement attachment | `tl.uploadRequirementAttachment` |
| Upload a requirement specification attachment | `tl.uploadRequirementSpecificationAttachment` |
| Get a requirement custom field | `tl.getRequirementCustomFieldDesignValue` |
| Get a requirement specification custom field | `tl.getReqSpecCustomFieldDesignValue` |

### Attachments

| Purpose | Method |
|---|---|
| Upload an attachment to any item | `tl.uploadAttachment` |

## Contributing

A non-trivial change starts as a GitHub issue paired with a feature request document in [docs/feature-requests/](docs/feature-requests/). [CLAUDE.md](CLAUDE.md) lists the branch, commit and testing conventions, and [CONTEXT.md](CONTEXT.md) defines the terms the code and tests share.

## Upstream TestLink documentation

[README.upstream.md](README.upstream.md) keeps upstream's 1.9.20 README for what this fork leaves unchanged: installing without Docker, PHP settings, LDAP and OAuth, upgrades and security notes. The user and installation manuals are in [docs/](docs/).

TestLink uses the GNU GPL license; see [LICENSE](LICENSE).
