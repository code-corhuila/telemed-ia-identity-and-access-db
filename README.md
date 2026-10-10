# telemed-ia-identity-and-access-db

Database repository for the **Identity & Access** bounded context of **TeleMed-IA**.

This repository owns the PostgreSQL database artifacts for the domain, including schema
definition, seed data, database access control, Liquibase migrations, explicit rollbacks,
and database regression validation.

The Identity & Access API consumes this database contract but does not own or version
database migrations.

## Database ownership

Identity & Access owns its database artifacts and migrations, but it does not own a PostgreSQL instance.

TeleMed IA uses a single PostgreSQL instance per environment, defined by `telemed-ia-infra-postgres`. Identity & Access shares that PostgreSQL engine with the other PostgreSQL-backed domains while remaining the owner of its own tables and data.

The existing Identity & Access objects remain in the PostgreSQL `public` schema. This repository does not introduce a schema migration as part of the shared-instance alignment.

Environment isolation is provided by the infrastructure environments:

```text
develop
qa
main
```

The Identity & Access API must use its own runtime database user and must not write data owned by another domain.

## Migration Authority

This repository uses **Liquibase** as the only migration authority.

The single changelog entry point is:

```text
changelog/changelog-master.yaml
```

The master changelog includes the migration families in execution order:

```text
01_ddl → 02_dml → 03_dcl → 04_tcl
```

Applied changesets are treated as **immutable**.

Corrections to an already applied migration must be introduced through a **new changeset** rather than by editing migration history.

Reversible DDL/DML changesets use explicit rollback SQL under:

```text
05_rollbacks/
```

---

## Structure

```text
01_ddl/        Database definition:
               extensions, schemas, types, tables, alters,
               views, functions, procedures, triggers, indexes

02_dml/        Seed data and controlled data changes

03_dcl/        Database roles, grants and access-control artifacts

04_tcl/        Explicit transaction, recovery and release artifacts

05_rollbacks/  Rollback SQL mirroring the migration families

changelog/     Liquibase master changelog and migration composition

deploy/        Liquibase migration executor; PostgreSQL lives in infra-postgres

tests/         Migration, rollback, schema, lifecycle and
               concurrency validation
```

---

## Current Identifier Contract

Identity & Access uses **UUID identifiers as the active contract**.

The UUID migration follows an **expand/contract strategy**:

1. UUID shadow identifiers are introduced and backfilled.
2. Existing relationships are validated.
3. UUID identifiers become the definitive primary and foreign-key contract.
4. Legacy numeric identifiers are retained where required for rollback support.

After contract completion:

- `users.id` is UUID.
- `refresh_tokens.user_id` references the UUID user identifier.
- `password_reset_tokens.user_id` references the UUID user identifier.
- Legacy numeric identifiers may remain in `legacy_id` / `legacy_user_id`.
- Legacy identifiers are nullable for rows created after the UUID cutover.
- New runtime rows are not required to generate legacy numeric identifiers.

---

## UUID Rollback Semantics

UUID rollback is validated as a **structural reconstruction**, not as an exact restoration of historical numeric identity.

Rows created after the UUID cutover may never have had a previous `BIGINT` identifier. During rollback, missing legacy identifiers can therefore be reconstructed so that the previous `BIGINT`-based relational structure can be restored.

The rollback validation explicitly checks that:

- A post-contract fixture can exist with UUID identifiers and null legacy identifiers.
- Rollback reconstructs the required legacy identifiers.
- User/token relationships remain consistent.
- The expected `BIGINT` relationship columns are restored.
- The remaining changelog can still be rolled back completely.
- The database can be rebuilt successfully afterwards.

> **Important:** A reconstructed `BIGINT` value must not be interpreted as recovering an original numeric identifier that never existed.

---

## Password-Reset Token Lifecycle

The database enforces the persistence-side invariants of password-reset tokens.

The definitive token-state contract is:

```text
ACTIVE
used = FALSE
superseded_at = NULL

CONSUMED
used = TRUE
superseded_at = NULL

SUPERSEDED
used = FALSE
superseded_at != NULL
```

A superseded token is different from a consumed token. Replacing a recovery token therefore records `superseded_at` without marking the previous token as used.

The current model:

- Allows at most one active reset token per user.
- Supersedes the previous active token when a new token is issued.
- Records supersession through `superseded_at`.
- Keeps consumption state in `used`.
- Uses a partial unique index over active tokens.
- Serializes concurrent issuance for the same user.
- Leaves expiration validity checks to the application layer.

Password-reset issuance uses the dedicated PostgreSQL advisory-lock namespace:

```text
12001
```

The lock is transaction-scoped and keyed by the user identifier, keeping reset-token serialization isolated from unrelated advisory-lock usage.

The supersession trigger is validated as a:

```sql
BEFORE INSERT FOR EACH ROW
```

trigger.

Concurrency tests exercise **two real database transactions** and verify through PostgreSQL lock state that the second issuer waits for the first before the final token state is asserted.

---

## Database Access Control

Runtime database access uses dedicated PostgreSQL roles.

The regression suite validates that:

- Runtime roles are `NOLOGIN`.
- The writer role inherits the reader role where required.
- Read access is limited to the expected tables.
- Writer permissions allow the required mutations.
- Destructive operations such as unauthorized `DELETE` are rejected.
- Runtime roles cannot create schema objects.
- Required sequence privileges are enforced where applicable.

Privileges are tested through **actual PostgreSQL role switching**, not only through catalog inspection.

---

## Index Migration Policy

Existing applied index changesets are **immutable**.

For **future indexes created on populated tables**, migrations should prefer:

```sql
CREATE INDEX CONCURRENTLY ...
```

The corresponding Liquibase changeset must use:

```yaml
runInTransaction: false
```

when PostgreSQL requires execution outside a transaction.

This rule avoids introducing unnecessary long-lived blocking during future production index creation.

---

## Local Validation

### Requirements

```text
Docker
PowerShell 7+
```

Run the complete database validation suite with:

```powershell
./tests/run-db-tests.ps1
```

### Validation Flow

The validation suite currently performs:

1. Liquibase changelog validation.
2. Clean PostgreSQL startup.
3. Initial Liquibase update.
4. Repeated Liquibase update / migration idempotency validation.
5. Liquibase history validation.
6. Creation of a post-contract UUID-only fixture.
7. UUID contract rollback.
8. UUID structural reconstruction validation.
9. Complete remaining rollback.
10. Verification that domain tables were removed.
11. Full database rebuild.
12. Identity & Access schema regression tests.
13. Password-reset lifecycle tests.
14. Concurrent password-reset issuance tests.

A successful execution ends with:

```text
ALL IDENTITY DB TESTS PASSED
```

---

## Compose

This repository does not define or start its own PostgreSQL instance or persistent volume.

The PostgreSQL instance and persistent volume are owned by `telemed-ia-infra-postgres`.

The `deploy/compose.yml` file contains only the Identity & Access Liquibase migration executor. The executor connects to the shared PostgreSQL service named `postgres` through the `platform` network.

The infrastructure environment provides:

```text
PG_DATABASE
PG_ADMIN_USER
PG_ADMIN_PASSWORD
```

From `telemed-ia-infra-postgres`, start the shared PostgreSQL service:

```bash
docker compose --env-file env/dev.env up -d --wait postgres
```

Then apply the Identity & Access migrations through the root infrastructure composition:

```bash
docker compose --env-file env/dev.env --profile tooling run --rm identity-and-access-db-migrate
```

Identity & Access uses dedicated Liquibase control tables inside the shared PostgreSQL database:

```text
databasechangelog_identity_and_access
databasechangeloglock_identity_and_access
```

The domain continues using the approved PostgreSQL `public` schema. This repository remains the only migration authority for Identity & Access database objects.

---

## Branching

Permanent branches represent environments and do **not** receive direct commits:

```text
develop ← PR from feat/... fix/... chore/... test/...
qa      ← PR from the team's QA promotion branch convention
main    ← PR from release/... or hotfix/...
```

Promotion between permanent environments is performed by re-applying validated commits with:

```bash
git cherry-pick -x
```

Permanent branches are **not merged directly into one another**.

---

## Operational Principles

- **Liquibase is the only migration authority.**
- Applied changesets are immutable.
- Schema changes and rollback behavior belong in this repository.
- Identity & Access owns only its domain tables, migrations and data inside the shared PostgreSQL instance.
- The domain continues using the approved PostgreSQL `public` schema.
- Runtime services must not create or mutate schema objects.
- Database credentials and secrets must not be committed.
- New migrations must include validation and rollback behavior appropriate to their risk.
