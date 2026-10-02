# Running TestLink in containers

`docker-compose.yml` runs TestLink, PostgreSQL and a mail catcher on one machine. A rebuild or recreate of the app container discards everything written inside it, including the database config the install wizard writes. A rebuild after the first install would send you back to the wizard while your data sits in the database.

This guide keeps all state outside the container: the database and folders on named volumes, and config files in the repo folder, which the build copies into the image.

First-time setup is in the [README](README.md#run-it-with-docker). This guide covers what comes after.

## What runs

| Service | Image | Reach it at | Keeps data in |
|---|---|---|---|
| `app` | built from `Dockerfile` (PHP 7.4, Apache) | <http://localhost:8090> | volumes `logs`, `upload_area` |
| `db` | `postgres:9.6` | `db:5432`, inside the stack only | volume `postgres` |
| `maildev` | `maildev/maildev` | <http://localhost:1080> (inbox), port 1025 (SMTP) | nothing |
| `restore` | same as `app` | does not start with `up` | see [Sample data](#sample-data) |

The database account is `teste` / `teste`, set in `docker-compose.yml`. Postgres reads it only when it first creates the `postgres` volume, so change it before the first `docker compose up`.

## Keep your setup across rebuilds

The image contains a copy of the source code. Code changes appear only after a rebuild:

```bash
docker compose up -d --build
```

The build copies the repo folder into the image, so a config file in the repo folder survives every rebuild. Both config files are git-ignored, so they stay out of commits.

| File | Written by | Put it in the repo folder with |
|---|---|---|
| `config_db.inc.php` | the install wizard | `docker compose cp app:/var/www/html/config_db.inc.php .` |
| `custom_config.inc.php` | you | see [Turn on email](#turn-on-email) |

A rebuilt container opens the install wizard when the repo folder lacks `config_db.inc.php`. **The wizard drops TestLink's tables when it runs again on the same database**, so copy the file out before you rebuild.

## Turn on email

TestLink sends mail for password resets and notifications. The stack's maildev service catches that mail and keeps it away from real inboxes, and TestLink starts sending once you point it at maildev:

```bash
sed 's/testlink-maildev/maildev/' docker/custom_config.inc.php > custom_config.inc.php
docker compose up -d --build
```

Sent mail appears at <http://localhost:1080>. The `sed` changes the sample file's host name, `testlink-maildev`, to the compose service name, `maildev`.

Delete `custom_config.inc.php` and rebuild to turn email off. You can also remove the `maildev` service from `docker-compose.yml`: TestLink uses it only after these steps.

## Logs and uploads

TestLink writes logs to `/var/testlink/logs` and attachments to `/var/testlink/upload_area`, both on named volumes. Read them through the container:

```bash
docker compose exec app ls /var/testlink/logs
docker compose exec app tail -f /var/testlink/logs/userlog0.log
```

This stack ignores the repo's own `logs/` and `upload_area/` folders.

## Use the published image

The release workflow publishes `dogkeeper886/testlink-code` to Docker Hub. To run it instead of building, replace `build: .` under `app` in `docker-compose.yml` and mount your database config into it:

```yaml
  app: &app
    image: dogkeeper886/testlink-code:mcp-1.0.0
    volumes:
      - logs:/var/testlink/logs
      - upload_area:/var/testlink/upload_area
      - ./config_db.inc.php:/var/www/html/config_db.inc.php:ro
```

Remove the `config_db.inc.php` line for the first install, then add it back once you have copied the file out.

The `mcp-1.0.0` image predates the fix that makes the log and upload folders writable. TestLink runs on it and loses every log and attachment it tries to write. Build the image locally until Docker Hub has an image from a later commit, which includes the fix.

## Sample data

`docs/db_sample/restore_sample.sh` loads a MySQL dump into a MySQL server. This stack runs PostgreSQL, so the `restore` service stops at its first MySQL command. Create your own test project after logging in instead.

## Start over

```bash
docker compose down -v
rm -f config_db.inc.php
docker compose up -d --build
```

`down -v` deletes the database, logs and uploads. Then run the install wizard again as in the [README](README.md#run-it-with-docker).

## Security

The base image, `php:7.4-apache`, runs on Debian 11, whose support ended in August 2026. Debian's security repository has removed its packages, so the `Dockerfile` installs from the main repository only, and the image keeps only the fixes that repository carries. PHP 7.4's security support ended in 2022. **Run this stack only on a local machine or a trusted network.**

## The CI stack

`cicd/docker-compose.ci.yml` runs a separate stack for the test suite on port 8091. It skips the wizard by mounting a prepared config, seeds a known admin API key, and starts only `app` and `db`. [cicd/TESTING_GUIDELINES.md](cicd/TESTING_GUIDELINES.md) explains why the two stacks stay separate.
