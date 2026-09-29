# telemed-ia-identity-and-access-db

Database repository for the **Identity & Access** bounded context of **TeleMed-IA**.

This repository owns the PostgreSQL database artifacts for the domain, including schema
definition, seed data, database access control, Liquibase migrations, explicit rollbacks,
and database regression validation.

The Identity & Access API consumes this database contract but does not own or version
database migrations.

## Database ownership

Identity & Access follows a **database-per-domain** model.

The domain uses the default PostgreSQL `public` schema inside its dedicated database.
Domain isolation is provided by database ownership, not by creating an additional
`identity_and_access` schema.

Environment isolation is handled through independent databases for:

```text
develop
qa
main
```

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

deploy/        Domain-owned PostgreSQL and migration executor

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

The current model:

- Allows at most one unused reset token per user.
- Supersedes a previous unused token when a new one is issued.
- Records supersession through `superseded_at`.
- Requires a superseded token to also be marked as used.
- Serializes concurrent issuance for the same user with a transaction-scoped advisory lock.
- Preserves the partial unique index as a database integrity defense.
- Leaves expiration validity checks to the application layer.

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
4. Repeated update/idempotency validation.
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

Create a local `.env` from the example and set a **development-only password**:

```powershell
Copy-Item .env.example .env
```

Create the shared platform network once if it does not exist:

```bash
docker network create platform
```

Start the database:

```bash
docker compose --env-file .env -f deploy/compose.yml up -d identity-and-access-db
```

Apply migrations deliberately.

The migration runner is under the `tooling` profile:

```bash
docker compose --env-file .env -f deploy/compose.yml --profile tooling run --rm identity-and-access-db-migrate
```

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
- Identity & Access remains isolated through its dedicated database.
- The domain continues using PostgreSQL `public` inside that database.
- Runtime services must not create or mutate schema objects.
- Database credentials and secrets must not be committed.
- New migrations must include validation and rollback behavior appropriate to their risk.