param(
    [string]$DbPassword = $env:TELEMED_DB_TEST_PASSWORD
)

$ErrorActionPreference = "Stop"

$DbContainer = "telemed-identity-db-test"
$Network = "telemed-identity-test-net"
$PostgresImage = "postgres:16.4-alpine"
$LiquibaseImage = "telemed-liquibase-postgres:5.0.4"

$DbName = "telemed_identity"
$DbUser = "telemed_identity"

$ContractChangeSetId =
        "ddl-alter-002-contract-user-identifiers-to-uuid"

if ([string]::IsNullOrWhiteSpace($DbPassword)) {
    $DbPassword =
            "Tm!" + [guid]::NewGuid().ToString("N")
}

$RepoRoot =
        (Resolve-Path (
            Join-Path $PSScriptRoot ".."
        )).Path

$TestSqlPath =
        Join-Path `
            $PSScriptRoot `
            "sql/identity-schema-tests.sql"


function Assert-LastCommand {
    param(
        [string]$Step
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE."
    }
}


function Remove-TestResources {

    $container =
            docker ps -aq `
                --filter "name=^/${DbContainer}$"

    if ($container) {
        docker rm -f $DbContainer |
            Out-Null
    }

    $network =
            docker network ls -q `
                --filter "name=^${Network}$"

    if ($network) {
        docker network rm $Network |
            Out-Null
    }
}


function Invoke-Liquibase {
    param(
        [string]$Command,
        [string[]]$CommandArguments = @()
    )

    $liquibaseArguments = @(
        "--search-path=/workspace"
        "--url=jdbc:postgresql://${DbContainer}:5432/${DbName}"
        "--username=$DbUser"
        "--password=$DbPassword"
        "--changelog-file=changelog/changelog-master.yaml"
        $Command
    )

    $liquibaseArguments +=
            $CommandArguments

    docker run --rm `
        --network $Network `
        --mount "type=bind,source=$RepoRoot,target=/workspace,readonly" `
        $LiquibaseImage `
        @liquibaseArguments

    Assert-LastCommand `
        "Liquibase $Command"
}


function Get-ChangeSetCount {

    $changeCount =
            docker exec $DbContainer `
                psql `
                -v ON_ERROR_STOP=1 `
                -U $DbUser `
                -d $DbName `
                -tAc `
                "SELECT COUNT(*) FROM databasechangelog;"

    Assert-LastCommand `
        "Liquibase history validation"

    if ([string]::IsNullOrWhiteSpace(
            $changeCount
        )) {
        throw `
            "Could not determine Liquibase changeset count."
    }

    return [int]$changeCount.Trim()
}


function Get-RollbackCountThroughChangeSet {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChangeSetId
    )

    if ([string]::IsNullOrWhiteSpace($ChangeSetId)) {
        throw "Changeset id must not be empty."
    }

    $lookupSql = @"
SELECT COUNT(*)
FROM databasechangelog
WHERE id = :'target_changeset';
"@

    $matchingCount = $lookupSql |
        docker exec -i $DbContainer `
            psql `
            -v ON_ERROR_STOP=1 `
            -v "target_changeset=$ChangeSetId" `
            -U $DbUser `
            -d $DbName `
            -tA

    Assert-LastCommand `
        "Changeset lookup for $ChangeSetId"

    if ([string]::IsNullOrWhiteSpace($matchingCount)) {
        throw "Could not inspect Liquibase history for changeset $ChangeSetId."
    }

    $matches = [int]$matchingCount.Trim()

    if ($matches -eq 0) {
        throw "Changeset $ChangeSetId was not found in Liquibase history."
    }

    if ($matches -gt 1) {
        throw "Changeset $ChangeSetId is ambiguous in Liquibase history."
    }

    $rollbackSql = @"
SELECT COUNT(*)
FROM databasechangelog
WHERE orderexecuted >= (
    SELECT orderexecuted
    FROM databasechangelog
    WHERE id = :'target_changeset'
);
"@

    $rollbackCount = $rollbackSql |
        docker exec -i $DbContainer `
            psql `
            -v ON_ERROR_STOP=1 `
            -v "target_changeset=$ChangeSetId" `
            -U $DbUser `
            -d $DbName `
            -tA

    Assert-LastCommand `
        "Rollback count calculation for $ChangeSetId"

    if ([string]::IsNullOrWhiteSpace($rollbackCount)) {
        throw "Could not determine rollback count for changeset $ChangeSetId."
    }

    $actual = [int]$rollbackCount.Trim()

    if ($actual -le 0) {
        throw "Rollback count for changeset $ChangeSetId must be greater than zero."
    }

    return $actual
}


function Assert-ExpectedChangeSetCount {
    param(
        [int]$Expected,
        [string]$Step
    )

    $actual =
            Get-ChangeSetCount

    if ($actual -ne $Expected) {
        throw `
            "$Step expected $Expected Liquibase changesets, found $actual."
    }
}


function Assert-DomainTablesRemoved {

    $remainingTables =
            docker exec $DbContainer `
                psql `
                -v ON_ERROR_STOP=1 `
                -U $DbUser `
                -d $DbName `
                -tAc @"
SELECT COUNT(*)
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
      'roles',
      'users',
      'refresh_tokens',
      'password_reset_tokens'
  );
"@

    Assert-LastCommand `
        "Rollback table validation"

    if ([string]::IsNullOrWhiteSpace(
            $remainingTables
        )) {
        throw `
            "Could not validate rollback table state."
    }

    $actual =
            [int]$remainingTables.Trim()

    if ($actual -ne 0) {
        throw `
            "Rollback validation failed: $actual domain tables still exist."
    }
}


try {

    # ------------------------------------------------------------
    # Prepare test infrastructure
    # ------------------------------------------------------------

    $liquibaseImageId =
            docker images -q $LiquibaseImage

    if (-not $liquibaseImageId) {

        @"
FROM liquibase/liquibase:5.0.4
RUN lpm add postgresql --global
"@ |
            docker build `
                -t $LiquibaseImage -

        Assert-LastCommand `
            "Liquibase image build"
    }

    Remove-TestResources

    docker network create $Network |
        Out-Null

    Assert-LastCommand `
        "Docker network creation"

    docker run `
        --name $DbContainer `
        --network $Network `
        -e POSTGRES_DB=$DbName `
        -e POSTGRES_USER=$DbUser `
        -e POSTGRES_PASSWORD=$DbPassword `
        -d `
        $PostgresImage |
        Out-Null

    Assert-LastCommand `
        "PostgreSQL startup"

    $ready = $false

    for (
        $attempt = 1;
        $attempt -le 30;
        $attempt++
    ) {

        docker exec $DbContainer `
            pg_isready `
            -U $DbUser `
            -d $DbName `
            2>$null |
            Out-Null

        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }

        Start-Sleep -Seconds 1
    }

    if (-not $ready) {
        throw `
            "PostgreSQL did not become ready."
    }


    # ------------------------------------------------------------
    # Validate and apply
    # ------------------------------------------------------------

    Write-Host `
        "Validating Liquibase changelog..."

    Invoke-Liquibase "validate"

    Write-Host `
        "Applying Liquibase changes..."

    Invoke-Liquibase "update"

    $expectedChangeSets =
            Get-ChangeSetCount

    if ($expectedChangeSets -le 0) {
        throw `
            "Expected at least one Liquibase changeset after initial update."
    }

    Write-Host `
        "Initial Liquibase changesets applied: $expectedChangeSets"


    # ------------------------------------------------------------
    # Idempotency
    # ------------------------------------------------------------

    Write-Host `
        "Checking repeated Liquibase update..."

    Invoke-Liquibase "update"

    Assert-ExpectedChangeSetCount `
        -Expected $expectedChangeSets `
        -Step "Repeated update"


    # ------------------------------------------------------------
    # Create a post-contract UUID-only fixture
    # ------------------------------------------------------------

    Write-Host `
        "Creating UUID-only rollback fixture..."

    docker exec $DbContainer `
        psql `
        -v ON_ERROR_STOP=1 `
        -U $DbUser `
        -d $DbName `
        -c @"
INSERT INTO roles (name)
VALUES ('ROLLBACK_TEST');

INSERT INTO users (
    full_name,
    email,
    identity_document,
    role_id,
    password_hash
)
VALUES (
    'UUID Rollback Fixture',
    'uuid.rollback@example.com',
    'UUID-ROLLBACK-001',
    (
        SELECT id
        FROM roles
        WHERE name = 'ROLLBACK_TEST'
    ),
    'rollback-test-hash'
);

INSERT INTO refresh_tokens (
    user_id,
    token_hash,
    expires_at
)
SELECT
    id,
    'uuid-rollback-refresh-token',
    CURRENT_TIMESTAMP + INTERVAL '7 days'
FROM users
WHERE email = 'uuid.rollback@example.com';

INSERT INTO password_reset_tokens (
    user_id,
    token_hash,
    expires_at
)
SELECT
    id,
    'uuid-rollback-reset-token',
    CURRENT_TIMESTAMP + INTERVAL '30 minutes'
FROM users
WHERE email = 'uuid.rollback@example.com';
"@

    Assert-LastCommand `
        "UUID-only rollback fixture creation"


    # ------------------------------------------------------------
    # Confirm fixture is truly post-contract / UUID-only
    # ------------------------------------------------------------

    $uuidOnlyFixture =
            docker exec $DbContainer `
                psql `
                -v ON_ERROR_STOP=1 `
                -U $DbUser `
                -d $DbName `
                -tAc @"
SELECT COUNT(*)
FROM users u
JOIN refresh_tokens rt
    ON rt.user_id = u.id
JOIN password_reset_tokens prt
    ON prt.user_id = u.id
WHERE u.email = 'uuid.rollback@example.com'
  AND u.id IS NOT NULL
  AND u.legacy_id IS NULL
  AND rt.user_id = u.id
  AND rt.legacy_user_id IS NULL
  AND prt.user_id = u.id
  AND prt.legacy_user_id IS NULL
  AND prt.legacy_id IS NULL;
"@

    Assert-LastCommand `
        "UUID-only fixture contract validation"

    if ([string]::IsNullOrWhiteSpace(
            $uuidOnlyFixture
        )) {
        throw `
            "Could not inspect UUID-only rollback fixture."
    }

    $uuidOnlyFixtureCount =
            [int]$uuidOnlyFixture.Trim()

    if ($uuidOnlyFixtureCount -ne 1) {
        throw `
            "UUID-only rollback fixture was not created in post-contract state."
    }

    Write-Host `
        "UUID-only fixture validated before rollback."


    # ------------------------------------------------------------
    # Roll back through UUID CONTRACT only
    # ------------------------------------------------------------

    $contractRollbackCount =
            Get-RollbackCountThroughChangeSet `
                -ChangeSetId $ContractChangeSetId

    Write-Host `
        "Rolling back $contractRollbackCount changesets through UUID contract..."

    Invoke-Liquibase `
        -Command "rollback-count" `
        -CommandArguments @(
            "--count=$contractRollbackCount"
        )

    $expectedExpandChangeSets =
            $expectedChangeSets `
            - $contractRollbackCount

    Assert-ExpectedChangeSetCount `
        -Expected $expectedExpandChangeSets `
        -Step "UUID contract rollback"


    # ------------------------------------------------------------
    # Validate reconstruction in EXPAND state
    # ------------------------------------------------------------

    Write-Host `
        "Validating UUID-only rollback reconstruction..."

    $rollbackFixture =
            docker exec $DbContainer `
                psql `
                -v ON_ERROR_STOP=1 `
                -U $DbUser `
                -d $DbName `
                -tAc @"
SELECT COUNT(*)
FROM users u
JOIN refresh_tokens rt
    ON rt.user_id = u.id
JOIN password_reset_tokens prt
    ON prt.user_id = u.id
WHERE u.email = 'uuid.rollback@example.com'
  AND u.id IS NOT NULL
  AND u.id_uuid IS NOT NULL
  AND rt.user_id IS NOT NULL
  AND rt.user_id_uuid = u.id_uuid
  AND prt.user_id IS NOT NULL
  AND prt.user_id_uuid = u.id_uuid;
"@

    Assert-LastCommand `
        "UUID contract rollback fixture validation"

    if ([string]::IsNullOrWhiteSpace(
            $rollbackFixture
        )) {
        throw `
            "Could not inspect UUID rollback reconstruction."
    }

    $fixtureCount =
            [int]$rollbackFixture.Trim()

    if ($fixtureCount -ne 1) {
        throw `
            "UUID contract rollback failed to reconstruct legacy identifiers."
    }


    # ------------------------------------------------------------
    # Validate restored BIGINT relationship contract
    # ------------------------------------------------------------

    $rollbackTypes =
            docker exec $DbContainer `
                psql `
                -v ON_ERROR_STOP=1 `
                -U $DbUser `
                -d $DbName `
                -tAc @"
SELECT COUNT(*)
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
      (
          table_name = 'users'
          AND column_name = 'id'
          AND data_type = 'bigint'
      )
      OR
      (
          table_name = 'refresh_tokens'
          AND column_name = 'user_id'
          AND data_type = 'bigint'
      )
      OR
      (
          table_name = 'password_reset_tokens'
          AND column_name = 'user_id'
          AND data_type = 'bigint'
      )
  );
"@

    Assert-LastCommand `
        "UUID rollback type validation"

    if ([string]::IsNullOrWhiteSpace(
            $rollbackTypes
        )) {
        throw `
            "Could not inspect UUID rollback relationship types."
    }

    $rollbackTypeCount =
            [int]$rollbackTypes.Trim()

    if ($rollbackTypeCount -ne 3) {
        throw `
            "UUID contract rollback did not restore the expected BIGINT relationship columns."
    }

    Write-Host `
        "UUID-only rollback structural reconstruction validated."


    # ------------------------------------------------------------
    # Roll back everything remaining
    # ------------------------------------------------------------

    Write-Host `
        "Rolling back remaining changelog..."

    Invoke-Liquibase `
        -Command "rollback-count" `
        -CommandArguments @(
            "--count=999"
        )

    Assert-ExpectedChangeSetCount `
        -Expected 0 `
        -Step "Rollback"

    Assert-DomainTablesRemoved


    # ------------------------------------------------------------
    # Rebuild after complete rollback
    # ------------------------------------------------------------

    Write-Host `
        "Rebuilding schema after rollback..."

    Invoke-Liquibase "update"

    Assert-ExpectedChangeSetCount `
        -Expected $expectedChangeSets `
        -Step "Rebuild after rollback"


    # ------------------------------------------------------------
    # Run database regression tests
    # ------------------------------------------------------------

    Write-Host `
        "Running PostgreSQL schema tests..."

    docker cp `
        $TestSqlPath `
        "${DbContainer}:/tmp/identity-schema-tests.sql" |
        Out-Null

    Assert-LastCommand `
        "SQL test copy"

    docker exec $DbContainer `
        psql `
        -v ON_ERROR_STOP=1 `
        -U $DbUser `
        -d $DbName `
        -f /tmp/identity-schema-tests.sql

    Assert-LastCommand `
        "Identity schema tests"


    # ------------------------------------------------------------
    # Password reset lifecycle regression tests
    # ------------------------------------------------------------

    Write-Host `
        "Running password reset lifecycle tests..."

    $resetLifecyclePath =
            Join-Path `
                $PSScriptRoot `
                "sql/reset-lifecycle-tests.sql"

    docker cp `
        $resetLifecyclePath `
        "${DbContainer}:/tmp/reset-lifecycle-tests.sql" |
        Out-Null

    Assert-LastCommand `
        "Reset lifecycle test copy"

    docker exec $DbContainer `
        psql `
        -v ON_ERROR_STOP=1 `
        -U $DbUser `
        -d $DbName `
        -f /tmp/reset-lifecycle-tests.sql

    Assert-LastCommand `
        "Password reset lifecycle tests"


    # ------------------------------------------------------------
    # Password reset concurrency regression tests
    # ------------------------------------------------------------

    Write-Host `
        "Running password reset concurrency tests..."

    & (
        Join-Path `
            $PSScriptRoot `
            "run-reset-concurrency.ps1"
    ) `
        -DbContainer $DbContainer `
        -DbUser $DbUser `
        -DbName $DbName

    if (-not $?) {
        throw `
            "Password reset concurrency tests failed."
    }

    Write-Host `
        "ALL IDENTITY DB TESTS PASSED"
}
finally {
    Remove-TestResources
}