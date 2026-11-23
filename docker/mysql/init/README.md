# MySQL initialization scripts

Any `.sql` file placed in this directory is executed by the official MySQL
image during the **first** initialization of an empty data directory.

Rules:

- The script should be idempotent-friendly (`CREATE DATABASE IF NOT EXISTS`,
  etc.) so re-running it against a populated database does not fail.
- It runs only when the data volume is empty. To force a re-run:
  `docker compose -f compose.getbela.yaml down -v` (destroys all data).

Note: the database and the application user are also created by the official
MySQL image from `MYSQL_DATABASE` / `MYSQL_USER` / `MYSQL_PASSWORD` (defined in
the group's `.env`). This script makes the GRANT explicit so the permissions
are guaranteed even if the user already existed.