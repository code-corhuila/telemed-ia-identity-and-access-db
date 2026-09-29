# telemed-ia-identity-and-access-db

Database repository for the **Identity & Access** bounded context of **TeleMed-IA**.
It owns the PostgreSQL schema, seed data, access-control database artifacts, migrations,
rollbacks, and database validation for this domain. The API consumes this schema; it does
not version database migrations.

## Migration tool

This repository uses **Liquibase**. The only entry point is:

```text
changelog/changelog-master.yaml
```

The master changelog includes the SQL families in execution order:

```text
01_ddl -> 02_dml -> 03_dcl -> 04_tcl
```

Every DDL/DML changeset that can be reverted points to an explicit file under
`05_rollbacks/`.

## Structure

```text
01_ddl/       database definition: extensions, schemas, types, tables, alters,
              views, functions, procedures, triggers, indexes
02_dml/       seed data and data changes
03_dcl/       database roles, grants, policies
04_tcl/       explicit transaction/recovery/release artifacts
05_rollbacks/ rollback SQL mirroring the migration families
changelog/    Liquibase master changelog
deploy/       domain-owned PostgreSQL + migration executor
tests/        rebuild and schema validation
```

## Local validation

Requirements: Docker and PowerShell 7+.

```powershell
./tests/run-db-tests.ps1
```

The validation starts a clean PostgreSQL instance, validates and applies the Liquibase
changelog twice, checks migration history, and executes schema tests.

## Compose

Create a local `.env` from the example and set a real development-only password:

```powershell
Copy-Item .env.example .env
```

Create the shared platform network once if it does not exist:

```powershell
docker network create platform
```

Start the database:

```powershell
docker compose --env-file .env -f deploy/compose.yml up -d identity-and-access-db
```

Apply migrations deliberately (the migration runner is under the `tooling` profile):

```powershell
docker compose --env-file .env -f deploy/compose.yml --profile tooling run --rm identity-and-access-db-migrate
```

## Branching

Permanent branches represent environments and do not receive direct commits:

```text
develop  <- PR from feat/... fix/... chore/...
qa       <- PR from the team's QA promotion branch convention
main     <- PR from release/... or hotfix/...
```

Promotion between environments is by re-application with `git cherry-pick -x`, never by
merging one permanent branch into another.

## Identifier migration

The structure-refactor package intentionally preserves the current BIGSERIAL/BIGINT
identifier model so the repository reorganization can be reviewed independently.
A separate overlay in the companion package migrates the public user identifier and its
foreign keys to UUID in a dedicated change.
