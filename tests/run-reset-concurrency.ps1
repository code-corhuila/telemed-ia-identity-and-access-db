param(
    [Parameter(Mandatory = $true)]
    [string]$DbContainer,

    [Parameter(Mandatory = $true)]
    [string]$DbUser,

    [Parameter(Mandatory = $true)]
    [string]$DbName
)

$ErrorActionPreference = "Stop"

function Invoke-SqlFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $source = Join-Path $PSScriptRoot "sql/$Name.sql"
    $target = "/tmp/$Name.sql"

    docker cp $source "${DbContainer}:$target" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Copy failed: $Name"
    }

    docker exec $DbContainer `
        psql `
        -v ON_ERROR_STOP=1 `
        -U $DbUser `
        -d $DbName `
        -f $target

    if ($LASTEXITCODE -ne 0) {
        throw "SQL execution failed: $Name"
    }
}

function Copy-SqlFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $source = Join-Path $PSScriptRoot "sql/$Name.sql"
    $target = "/tmp/$Name.sql"

    docker cp $source "${DbContainer}:$target" | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Copy failed: $Name"
    }
}

Invoke-SqlFile "reset-concurrency-setup"

Copy-SqlFile "reset-concurrency-first"
Copy-SqlFile "reset-concurrency-second"

$first = Start-Job -ArgumentList @(
    $DbContainer,
    $DbUser,
    $DbName
) -ScriptBlock {
    param(
        $Container,
        $User,
        $Database
    )

    & docker exec `
        $Container `
        psql `
        -v ON_ERROR_STOP=1 `
        -U $User `
        -d $Database `
        -f /tmp/reset-concurrency-first.sql

    if ($LASTEXITCODE -ne 0) {
        throw "First concurrent issuer failed with exit code $LASTEXITCODE."
    }
}

# Transaction A holds the user-row lock while pg_sleep(8) runs.
Start-Sleep -Seconds 2

$second = Start-Job -ArgumentList @(
    $DbContainer,
    $DbUser,
    $DbName
) -ScriptBlock {
    param(
        $Container,
        $User,
        $Database
    )

    & docker exec `
        $Container `
        psql `
        -v ON_ERROR_STOP=1 `
        -U $User `
        -d $Database `
        -f /tmp/reset-concurrency-second.sql

    if ($LASTEXITCODE -ne 0) {
        throw "Second concurrent issuer failed with exit code $LASTEXITCODE."
    }
}

Wait-Job $first, $second | Out-Null

$firstOutput = Receive-Job $first
$secondOutput = Receive-Job $second

$firstOutput
$secondOutput

if ($first.State -ne "Completed") {
    throw "First concurrent issuer job failed."
}

if ($second.State -ne "Completed") {
    throw "Second concurrent issuer job failed."
}

Remove-Job $first, $second

Invoke-SqlFile "reset-concurrency-assert"

Write-Host "PASS: password reset concurrency tests"