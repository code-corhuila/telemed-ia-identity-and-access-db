$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Content.Contains($Expected)) {
        throw $Message
    }
}

$workflowPath = Join-Path $repoRoot ".github/workflows/db-ci.yml"
$composePath = Join-Path $repoRoot "deploy/compose.yml"
$readmePath = Join-Path $repoRoot "README.md"

$workflow = [System.IO.File]::ReadAllText($workflowPath)
$compose = [System.IO.File]::ReadAllText($composePath)
$readme = [System.IO.File]::ReadAllText($readmePath)

# ------------------------------------------------------------
# CI trigger contract
# ------------------------------------------------------------

Assert-Contains `
    -Content $workflow `
    -Expected "pull_request:" `
    -Message "CI contract failed: pull_request trigger is missing."

foreach ($branch in @("develop", "qa", "main")) {
    Assert-Contains `
        -Content $workflow `
        -Expected "- $branch" `
        -Message "CI contract failed: pull_request branch '$branch' is missing."
}

Assert-Contains `
    -Content $workflow `
    -Expected "workflow_dispatch:" `
    -Message "CI contract failed: manual workflow trigger is missing."

# ------------------------------------------------------------
# Shared PostgreSQL / Liquibase contract
# ------------------------------------------------------------

if ($compose -match "(?m)^\s{2}identity-and-access-db:\s*$") {
    throw "Compose contract failed: domain-owned PostgreSQL service still exists."
}

Assert-Contains `
    -Content $compose `
    -Expected "identity-and-access-db-migrate:" `
    -Message "Compose contract failed: migration executor is missing."

Assert-Contains `
    -Content $compose `
    -Expected "--database-changelog-table-name=databasechangelog_identity_and_access" `
    -Message "Liquibase contract failed: dedicated changelog table is missing."

Assert-Contains `
    -Content $compose `
    -Expected "--database-changelog-lock-table-name=databasechangeloglock_identity_and_access" `
    -Message "Liquibase contract failed: dedicated changelog lock table is missing."

# ------------------------------------------------------------
# Password-reset documentation contract
# ------------------------------------------------------------

foreach ($state in @("ACTIVE", "CONSUMED", "SUPERSEDED")) {
    Assert-Contains `
        -Content $readme `
        -Expected $state `
        -Message "README contract failed: password-reset state '$state' is missing."
}

Assert-Contains `
    -Content $readme `
    -Expected "12001" `
    -Message "README contract failed: advisory-lock namespace 12001 is missing."

Write-Host "ALL REPOSITORY CONTRACT TESTS PASSED"
