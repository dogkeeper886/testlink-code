# TestLink mcp-1.0.0

TestLink 1.9.20 is an open-source test management system, and its XML-RPC API lets other tools create and run test projects. AI assistants now do that work through MCP servers, which call the same API. Upstream's 1.9.20 code has a typo in the XML-RPC class that breaks every API call with HTTP 500, and the API creates test cases, test suites and builds that only the web UI can delete.

This image runs a fork of TestLink 1.9.20 with the API fixed and ten methods added, ready for the [TestLink MCP server](https://hub.docker.com/r/dogkeeper886/testlink-mcp).

## Quick start

Save this as `docker-compose.yml`:

```yaml
services:
  db:
    image: postgres:9.6
    restart: unless-stopped
    environment:
      - POSTGRES_USER=teste
      - POSTGRES_PASSWORD=teste
      - POSTGRES_DB=testlink
    volumes:
      - postgres:/var/lib/postgresql/data

  app:
    image: dogkeeper886/testlink-code:latest
    restart: unless-stopped
    depends_on:
      - db
    ports:
      - "8090:80"
    volumes:
      - logs:/var/testlink/logs
      - upload_area:/var/testlink/upload_area

volumes:
  postgres:
  logs:
  upload_area:
```

Then start it:

```bash
docker compose up -d
```

Postgres reads the `teste` / `teste` account only when it first creates the `postgres` volume, so change it before the first start.

**The `mcp-1.0.0` image stops at the install wizard's folder check**, because it predates the fix that makes the log and upload folders writable. Use a later tag, or [build from source](#build-from-source) until Docker Hub has one.

## First install

Open <http://localhost:8090>, choose **New installation**, and enter these values on the database page:

| Field | Value |
|---|---|
| Database type | Postgres (9.1 and later) |
| Database host | `db` |
| Database name | `testlink` |
| Database admin login | `teste` |
| Database admin password | `teste` |
| TestLink DB login | `testlink` |
| TestLink DB password | `testlink` |

The TestLink login and password are new, and you can choose your own.

Run the database function the wizard asks for:

```bash
docker compose exec -T app cat install/sql/postgres/testlink_create_udf0.sql \
  | docker compose exec -T db psql -U teste -d testlink
```

Log in as `admin` with password `admin`, and change the password.

## Keep your install across restarts

The wizard writes its database config inside the app container, and a recreated container loses it. **The wizard drops TestLink's tables when it runs again on the same database**, so save the config before you recreate or upgrade the container:

```bash
docker compose cp app:/var/www/html/config_db.inc.php .
```

Then mount it under `app` in `docker-compose.yml` and restart:

```yaml
    volumes:
      - logs:/var/testlink/logs
      - upload_area:/var/testlink/upload_area
      - ./config_db.inc.php:/var/www/html/config_db.inc.php:ro
```

```bash
docker compose up -d
```

## Connect an AI assistant

In TestLink, open **My Settings** (the icon at the top right) and click **Generate a new key** under **API interface**. Then add the MCP server to Claude Code with that key:

```bash
claude mcp add testlink -- docker run --rm -i --network host \
  -e TESTLINK_URL=http://localhost:8090 \
  -e TESTLINK_API_KEY=<your key> \
  dogkeeper886/testlink-mcp:latest
```

`--network host` lets the MCP container reach `localhost:8090` on Linux. Drop it on macOS or Windows and use `http://host.docker.internal:8090`. The [testlink-mcp page](https://hub.docker.com/r/dogkeeper886/testlink-mcp) covers other MCP clients and the server's tools.

## Turn on email

TestLink sends mail for password resets and notifications. A maildev container catches that mail and keeps it away from real inboxes. Save this as `custom_config.inc.php`:

```php
<?php
$g_tl_admin_email = 'admin@example.com';
$g_from_email = 'testlink@example.com';
$g_return_path_email = 'no-reply@example.com';
$g_smtp_host = 'maildev';
$g_smtp_port = 1025;
```

Add the maildev service under `services`:

```yaml
  maildev:
    image: maildev/maildev:latest
    restart: unless-stopped
    ports:
      - "1080:1080"
```

Mount the file in the `app` service's `volumes` list:

```yaml
      - ./custom_config.inc.php:/var/www/html/custom_config.inc.php:ro
```

Run `docker compose up -d`, and sent mail appears at <http://localhost:1080>.

## Logs and uploads

TestLink writes logs to `/var/testlink/logs` and attachments to `/var/testlink/upload_area`, both on named volumes. Read them through the container:

```bash
docker compose exec app ls /var/testlink/logs
docker compose exec app tail -f /var/testlink/logs/userlog0.log
```

## Build from source

The repository's own compose file builds the image and adds maildev:

```bash
git clone https://github.com/dogkeeper886/testlink-code.git
cd testlink-code
docker compose up -d --build
```

The build copies the repo folder into the image, so config files there survive every rebuild, and git ignores both config files.

Copy the database config out after the first install:

```bash
docker compose cp app:/var/www/html/config_db.inc.php .
```

Turn on email, then rebuild:

```bash
sed 's/testlink-maildev/maildev/' docker/custom_config.inc.php > custom_config.inc.php
docker compose up -d --build
```

The repository's `restore` service loads a MySQL sample dump, so it stops at its first MySQL command on this PostgreSQL stack.

## Start over

```bash
docker compose down -v
rm -f config_db.inc.php
docker compose up -d
```

`down -v` deletes the database, logs and uploads. Then run the [first install](#first-install) again.

## Security

The base image, `php:7.4-apache`, runs on Debian 11, whose support ended in August 2026. Debian's security repository has removed its packages, so the image installs from the main repository only, and keeps only the fixes that repository carries. PHP 7.4's security support ended in 2022. **Run this stack only on a local machine or a trusted network.**

## Source and support

- Source, API reference and issues: [github.com/dogkeeper886/testlink-code](https://github.com/dogkeeper886/testlink-code)
- MCP server: [dogkeeper886/testlink-mcp](https://hub.docker.com/r/dogkeeper886/testlink-mcp)
- TestLink uses the GNU GPL license.
