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

function Wait-ForFirstTransactionReady {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Job]$Job,

        [int]$Attempts = 40,

        [int]$DelayMilliseconds = 250
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {

        if ($Job.State -eq "Failed") {
            Receive-Job $Job -ErrorAction SilentlyContinue
            throw "First transaction failed before acquiring the reset issuance lock."
        }

        if ($Job.State -eq "Completed") {
            Receive-Job $Job -ErrorAction SilentlyContinue
            throw "First transaction completed before concurrency could be observed."
        }

        $readyCount = docker exec $DbContainer `
            psql `
            -v ON_ERROR_STOP=1 `
            -U $DbUser `
            -d $DbName `
            -tAc @"
SELECT COUNT(*)
FROM pg_stat_activity
WHERE application_name = 'identity-reset-first'
  AND state = 'active'
  AND wait_event_type = 'Timeout'
  AND wait_event = 'PgSleep';
"@

        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect first transaction state."
        }

        if (-not [string]::IsNullOrWhiteSpace($readyCount) `
                -and [int]$readyCount.Trim() -gt 0) {
            return
        }

        Start-Sleep -Milliseconds $DelayMilliseconds
    }

    throw "First transaction did not reach the lock-holding state."
}

function Wait-ForSecondTransactionBlock {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Job]$Job,

        [int]$Attempts = 40,

        [int]$DelayMilliseconds = 250
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {

        if ($Job.State -eq "Failed") {
            Receive-Job $Job -ErrorAction SilentlyContinue
            throw "Second transaction failed before lock contention was observed."
        }

        if ($Job.State -eq "Completed") {
            Receive-Job $Job -ErrorAction SilentlyContinue
            throw "Second transaction completed without observable lock contention."
        }

        $blockedCount = docker exec $DbContainer `
            psql `
            -v ON_ERROR_STOP=1 `
            -U $DbUser `
            -d $DbName `
            -tAc @"
SELECT COUNT(*)
FROM pg_stat_activity
WHERE application_name = 'identity-reset-second'
  AND cardinality(pg_blocking_pids(pid)) > 0;
"@

        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect concurrent lock state."
        }

        if (-not [string]::IsNullOrWhiteSpace($blockedCount) `
                -and [int]$blockedCount.Trim() -gt 0) {
            return
        }

        Start-Sleep -Milliseconds $DelayMilliseconds
    }

    throw "Second transaction was not observed waiting on the reset issuance lock."
}

$first = $null
$second = $null

try {
    Invoke-SqlFile "reset-concurrency-setup"

    Copy-SqlFile "reset-concurrency-first"
    Copy-SqlFile "reset-concurrency-second"

    $dockerPath = (Get-Command docker -ErrorAction Stop).Source

    $first = Start-Job -ArgumentList @(
        $dockerPath,
        $DbContainer,
        $DbUser,
        $DbName
    ) -ScriptBlock {
        param(
            $Docker,
            $Container,
            $User,
            $Database
        )

        & $Docker exec `
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

    Wait-ForFirstTransactionReady `
        -Job $first

    $second = Start-Job -ArgumentList @(
        $dockerPath,
        $DbContainer,
        $DbUser,
        $DbName
    ) -ScriptBlock {
        param(
            $Docker,
            $Container,
            $User,
            $Database
        )

        & $Docker exec `
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

    Wait-ForSecondTransactionBlock `
        -Job $second

    Write-Host "PASS: second reset issuer was observed waiting on the advisory lock"

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

    Invoke-SqlFile "reset-concurrency-assert"

    Write-Host "PASS: password reset concurrency tests"
}
finally {
    if ($first) {
        if ($first.State -eq "Running") {
            Stop-Job $first | Out-Null
        }

        Remove-Job $first -Force -ErrorAction SilentlyContinue
    }

    if ($second) {
        if ($second.State -eq "Running") {
            Stop-Job $second | Out-Null
        }

        Remove-Job $second -Force -ErrorAction SilentlyContinue
    }
}