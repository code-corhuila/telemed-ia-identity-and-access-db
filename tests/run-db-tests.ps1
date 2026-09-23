param(
    [string]$DbPassword = $env:TELEMED_DB_TEST_PASSWORD
)

$ErrorActionPreference = "Stop"

$DbContainer = "telemed-identity-db-test"
$Network = "telemed-identity-test-net"

$PostgresImage = "postgres:16-alpine"
$LiquibaseImage = "telemed-liquibase-postgres:5.0.4"

$DbName = "telemed_identity"
$DbUser = "telemed_identity"

$ExpectedChangeSets = 7

if ([string]::IsNullOrWhiteSpace($DbPassword)) {
    $DbPassword = "Tm!" + [guid]::NewGuid().ToString("N")
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ChangelogPath = Join-Path $RepoRoot "db\changelog"
$TestSqlPath = Join-Path $PSScriptRoot "sql\identity-schema-tests.sql"


function Assert-LastCommand {
    param([string]$Step)

    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE."
    }
}


function Remove-TestResources {

    $container = docker ps -aq `
        --filter "name=^/${DbContainer}$"

    if ($container) {
        docker rm -f $DbContainer | Out-Null
    }

    $network = docker network ls -q `
        --filter "name=^${Network}$"

    if ($network) {
        docker network rm $Network | Out-Null
    }
}


function Invoke-Liquibase {
    param([string]$Command)

    docker run --rm `
        --network $Network `
        --mount "type=bind,source=$ChangelogPath,target=/liquibase/changelog,readonly" `
        $LiquibaseImage `
        --search-path=/liquibase/changelog `
        --url="jdbc:postgresql://${DbContainer}:5432/${DbName}" `
        --username=$DbUser `
        --password=$DbPassword `
        --changelog-file=db.changelog-master.yaml `
        $Command

    Assert-LastCommand "Liquibase $Command"
}


try {

    Write-Host ""
    Write-Host "========================================"
    Write-Host " TeleMed IA - Identity DB Validation"
    Write-Host "========================================"


    $liquibaseImageId = docker images -q $LiquibaseImage

    if (-not $liquibaseImageId) {

        Write-Host "Building Liquibase PostgreSQL image..."

        @"
FROM liquibase/liquibase:5.0.4
RUN lpm add postgresql --global
"@ | docker build -t $LiquibaseImage -

        Assert-LastCommand "Liquibase image build"
    }


    Remove-TestResources


    Write-Host "Creating Docker network..."

    docker network create $Network | Out-Null

    Assert-LastCommand "Docker network creation"


    Write-Host "Starting PostgreSQL 16..."

    docker run `
        --name $DbContainer `
        --network $Network `
        -e POSTGRES_DB=$DbName `
        -e POSTGRES_USER=$DbUser `
        -e POSTGRES_PASSWORD=$DbPassword `
        -d `
        $PostgresImage | Out-Null

    Assert-LastCommand "PostgreSQL startup"


    Write-Host "Waiting for PostgreSQL..."

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


    Write-Host "Validating Liquibase changelog..."

    Invoke-Liquibase "validate"


    Write-Host "Applying Liquibase changes..."

    Invoke-Liquibase "update"


    Write-Host "Checking repeated Liquibase update..."

    Invoke-Liquibase "update"


    Write-Host "Validating Liquibase history..."

    $changeCount = docker exec $DbContainer `
        psql `
        -U $DbUser `
        -d $DbName `
        -tAc "SELECT COUNT(*) FROM databasechangelog;"

    Assert-LastCommand "Liquibase history validation"


    $actualChangeSets = [int]$changeCount.Trim()

    if ($actualChangeSets -ne $ExpectedChangeSets) {
        throw "Expected $ExpectedChangeSets Liquibase changesets, found $actualChangeSets."
    }


    Write-Host "Liquibase changesets validated: $actualChangeSets"


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


    Write-Host ""
    Write-Host "========================================"
    Write-Host " ALL IDENTITY DB TESTS PASSED"
    Write-Host "========================================"
}
finally {

    Write-Host ""
    Write-Host "Cleaning Docker test resources..."

    Remove-TestResources

    Write-Host "Cleanup completed."
}