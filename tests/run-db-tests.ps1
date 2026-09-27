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

$ContractChangeSetId = "ddl-alter-002-contract-user-identifiers-to-uuid"

if ([string]::IsNullOrWhiteSpace($DbPassword)) {
    $DbPassword = "Tm!" + [guid]::NewGuid().ToString("N")
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TestSqlPath = Join-Path $PSScriptRoot "sql/identity-schema-tests.sql"


function Assert-LastCommand {
    param(
        [string]$Step
    )

    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE."
    }
}


function Remove-TestResources {
    $container = docker ps -aq --filter "name=^/${DbContainer}$"

    if ($container) {
        docker rm -f $DbContainer | Out-Null
    }

    $network = docker network ls -q --filter "name=^${Network}$"

    if ($network) {
        docker network rm $Network | Out-Null
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

    $liquibaseArguments += $CommandArguments

    docker run --rm `
        --network $Network `
        --mount "type=bind,source=$RepoRoot,target=/workspace,readonly" `
        $LiquibaseImage `
        @liquibaseArguments

    Assert-LastCommand "Liquibase $Command"
}


function Get-ChangeSetCount {
    $changeCount = docker exec $DbContainer `
        psql `
        -U $DbUser `
        -d $DbName `
        -tAc "SELECT COUNT(*) FROM databasechangelog;"

    Assert-LastCommand "Liquibase history validation"

    return [int]$changeCount.Trim()
}


function Get-RollbackCountThroughChangeSet {
    param(
        [string]$ChangeSetId
    )

    $rollbackCount = docker exec $DbContainer `
        psql `
        -U $DbUser `
        -d $DbName `
        -tAc @"
SELECT COUNT(*)
FROM databasechangelog
WHERE orderexecuted >= (
    SELECT orderexecuted
    FROM databasechangelog
    WHERE id = '$ChangeSetId'
    ORDER BY orderexecuted DESC
    LIMIT 1
);
"@

    Assert-LastCommand "Rollback count calculation for $ChangeSetId"

    if ([string]::IsNullOrWhiteSpace($rollbackCount)) {
        throw "Could not determine rollback count for changeset $ChangeSetId."
    }

    $actual = [int]$rollbackCount.Trim()

    if ($actual -le 0) {
        throw "Changeset $ChangeSetId was not found in Liquibase history."
    }

    return $actual
}


function Assert-ExpectedChangeSetCount {
    param(
        [int]$Expected,
        [string]$Step
    )

    $actual = Get-ChangeSetCount

    if ($actual -ne $Expected) {
        throw "$Step expected $Expected Liquibase changesets, found $actual."
    }
}


function Assert-DomainTablesRemoved {
    $remainingTables = docker exec $DbContainer `
        psql `
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

    Assert-LastCommand "Rollback table validation"

    $actual = [int]$remainingTables.Trim()

    if ($actual -ne 0) {
        throw "Rollback validation failed: $actual domain tables still exist."
    }
}


try {
    $liquibaseImageId = docker images -q $LiquibaseImage

    if (-not $liquibaseImageId) {
        @"
FROM liquibase/liquibase:5.0.4
RUN lpm add postgresql --global
"@ | docker build -t $LiquibaseImage -

        Assert-LastCommand "Liquibase image build"
    }

    Remove-TestResources

    docker network create $Network | Out-Null
    Assert-LastCommand "Docker network creation"

    docker run `
        --name $DbContainer `
        --network $Network `
        -e POSTGRES_DB=$DbName `
        -e POSTGRES_USER=$DbUser `
        -e POSTGRES_PASSWORD=$DbPassword `
        -d `
        $PostgresImage | Out-Null

    Assert-LastCommand "PostgreSQL startup"

    $ready = $false

    for ($attempt = 1; $attempt -le 30; $attempt++) {
        docker exec $DbContainer `
            pg_isready `
            -U $DbUser `
            -d $DbName `
            2>$null | Out-Null

        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }

        Start-Sleep -Seconds 1
    }

    if (-not $ready) {
        throw "PostgreSQL did not become ready."
    }


    # ------------------------------------------------------------
    # Validate and apply
    # ------------------------------------------------------------

    Write-Host "Validating Liquibase changelog..."
    Invoke-Liquibase "validate"

    Write-Host "Applying Liquibase changes..."
    Invoke-Liquibase "update"

    $expectedChangeSets = Get-ChangeSetCount

    if ($expectedChangeSets -le 0) {
        throw "Expected at least one Liquibase changeset after initial update."
    }

    Write-Host "Initial Liquibase changesets applied: $expectedChangeSets"


    # ------------------------------------------------------------
    # Idempotency
    # ------------------------------------------------------------

    Write-Host "Checking repeated Liquibase update..."
    Invoke-Liquibase "update"

    Assert-ExpectedChangeSetCount `
        -Expected $expectedChangeSets `
        -Step "Repeated update"


    # ------------------------------------------------------------
    # Create a UUID-only fixture
    # ------------------------------------------------------------

    Write-Host "Creating UUID-only rollback fixture..."

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
    (SELECT id FROM roles WHERE name = 'ROLLBACK_TEST'),
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

    Assert-LastCommand "UUID-only rollback fixture creation"


    # ------------------------------------------------------------
    # Roll back through UUID CONTRACT only
    # ------------------------------------------------------------

    $contractRollbackCount = Get-RollbackCountThroughChangeSet `
        -ChangeSetId $ContractChangeSetId

    Write-Host `
        "Rolling back $contractRollbackCount changesets through UUID contract..."

    Invoke-Liquibase `
        -Command "rollback-count" `
        -CommandArguments @("--count=$contractRollbackCount")

    $expectedExpandChangeSets = $expectedChangeSets - $contractRollbackCount

    Assert-ExpectedChangeSetCount `
        -Expected $expectedExpandChangeSets `
        -Step "UUID contract rollback"


    # ------------------------------------------------------------
    # Validate reconstruction in EXPAND state
    # ------------------------------------------------------------

    Write-Host "Validating UUID-only rollback reconstruction..."

    $rollbackFixture = docker exec $DbContainer `
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

    Assert-LastCommand "UUID contract rollback fixture validation"

    $fixtureCount = [int]$rollbackFixture.Trim()

    if ($fixtureCount -ne 1) {
        throw "UUID contract rollback failed to reconstruct legacy identifiers."
    }

    Write-Host "UUID-only rollback reconstruction validated."


    # ------------------------------------------------------------
    # Roll back everything remaining
    # ------------------------------------------------------------

    Write-Host "Rolling back remaining changelog..."

    Invoke-Liquibase `
        -Command "rollback-count" `
        -CommandArguments @("--count=999")

    Assert-ExpectedChangeSetCount `
        -Expected 0 `
        -Step "Rollback"

    Assert-DomainTablesRemoved


    # ------------------------------------------------------------
    # Rebuild after complete rollback
    # ------------------------------------------------------------

    Write-Host "Rebuilding schema after rollback..."
    Invoke-Liquibase "update"

    Assert-ExpectedChangeSetCount `
        -Expected $expectedChangeSets `
        -Step "Rebuild after rollback"


    # ------------------------------------------------------------
    # Run database regression tests
    # ------------------------------------------------------------

    Write-Host "Running PostgreSQL schema tests..."

    docker cp `
        $TestSqlPath `
        "${DbContainer}:/tmp/identity-schema-tests.sql" `
        | Out-Null

    Assert-LastCommand "SQL test copy"

    docker exec $DbContainer `
        psql `
        -v ON_ERROR_STOP=1 `
        -U $DbUser `
        -d $DbName `
        -f /tmp/identity-schema-tests.sql

    Assert-LastCommand "Identity schema tests"

    Write-Host "ALL IDENTITY DB TESTS PASSED"
}
finally {
    Remove-TestResources
}