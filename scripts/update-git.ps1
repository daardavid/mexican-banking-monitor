param(
    [string]$RepositoryPath = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

function Invoke-GitCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage
    )

    $output = @(& git @ArgumentList 2>&1)
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw $FailureMessage
    }

    return @($output | ForEach-Object { $_.ToString() })
}

function Assert-CleanWorkingTree {
    $statusLines = @(Invoke-GitCapture `
        -ArgumentList @("status", "--porcelain=v1", "--untracked-files=all") `
        -FailureMessage "Unable to inspect the Git working tree. Confirm this is a valid repository.")

    if ($statusLines.Count -eq 0) {
        return
    }

    $hasStaged = $false
    $hasUnstaged = $false
    $hasUntracked = $false

    foreach ($line in $statusLines) {
        if ($line.Length -lt 2) {
            continue
        }

        $indexStatus = $line.Substring(0, 1)
        $worktreeStatus = $line.Substring(1, 1)

        if ($indexStatus -eq "?" -and $worktreeStatus -eq "?") {
            $hasUntracked = $true
            continue
        }

        if ($indexStatus -ne " ") {
            $hasStaged = $true
        }
        if ($worktreeStatus -ne " ") {
            $hasUnstaged = $true
        }
    }

    $changeKinds = @()
    if ($hasStaged) {
        $changeKinds += "staged changes"
    }
    if ($hasUnstaged) {
        $changeKinds += "unstaged changes"
    }
    if ($hasUntracked) {
        $changeKinds += "untracked files"
    }
    if ($changeKinds.Count -eq 0) {
        $changeKinds += "local changes"
    }

    throw "Unsafe update: the working tree is not clean ($($changeKinds -join ', ')). " +
        "Commit or remove the local work before updating; this script will not stash or discard it."
}

$resolvedRepository = (Resolve-Path -LiteralPath $RepositoryPath).Path
Push-Location -LiteralPath $resolvedRepository

try {
    Assert-CleanWorkingTree

    $branch = @(Invoke-GitCapture `
        -ArgumentList @("symbolic-ref", "--quiet", "--short", "HEAD") `
        -FailureMessage "Unsafe update: HEAD is detached. Switch to main before updating.")
    if ($branch.Count -ne 1 -or $branch[0] -cne "main") {
        $branchLabel = if ($branch.Count -eq 1) { $branch[0] } else { "unknown" }
        throw "Unsafe update: current branch is '$branchLabel'; exactly 'main' is required. " +
            "Finish or preserve this branch's work, then switch to main."
    }

    $upstream = @(Invoke-GitCapture `
        -ArgumentList @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}") `
        -FailureMessage ("Unsafe update: main has no upstream. Configure it explicitly with: " +
            "git branch --set-upstream-to=origin/main main"))
    if ($upstream.Count -ne 1 -or $upstream[0] -cne "origin/main") {
        $upstreamLabel = if ($upstream.Count -eq 1) { $upstream[0] } else { "unknown" }
        throw "Unsafe update: main tracks '$upstreamLabel'; exactly 'origin/main' is required. " +
            "Correct the upstream explicitly before updating."
    }

    Invoke-ExternalCommand "git" @("fetch", "--prune", "origin") -SafeLabel "git fetch origin"

    $countOutput = @(Invoke-GitCapture `
        -ArgumentList @("rev-list", "--left-right", "--count", "HEAD...origin/main") `
        -FailureMessage "Unable to compare HEAD with origin/main after fetch.")
    $counts = if ($countOutput.Count -eq 1) {
        @($countOutput[0] -split "\s+")
    }
    else {
        @()
    }

    if ($counts.Count -ne 2) {
        throw "Git returned an unexpected ahead/behind result for HEAD and origin/main."
    }

    [long]$ahead = 0
    [long]$behind = 0
    if (-not [long]::TryParse($counts[0], [ref]$ahead) -or
        -not [long]::TryParse($counts[1], [ref]$behind)) {
        throw "Git returned a non-numeric ahead/behind result for HEAD and origin/main."
    }

    if ($ahead -gt 0 -and $behind -gt 0) {
        throw "Unsafe update: main and origin/main have diverged " +
            "(local ahead $ahead, behind $behind). Reconcile the history manually; no changes were applied."
    }
    if ($ahead -gt 0) {
        throw "Unsafe update: local main is ahead of origin/main by $ahead commit(s). " +
            "Publish or reconcile those commits explicitly; no changes were applied."
    }

    if ($behind -gt 0) {
        Assert-CleanWorkingTree
        Invoke-ExternalCommand "git" @("merge", "--ff-only", "origin/main") `
            -SafeLabel "git fast-forward main to origin/main"
    }

    $head = @(Invoke-GitCapture `
        -ArgumentList @("rev-parse", "HEAD") `
        -FailureMessage "Unable to verify HEAD after the update.")
    $remoteHead = @(Invoke-GitCapture `
        -ArgumentList @("rev-parse", "origin/main") `
        -FailureMessage "Unable to verify origin/main after the update.")

    if ($head.Count -ne 1 -or $remoteHead.Count -ne 1 -or $head[0] -cne $remoteHead[0]) {
        throw "Update verification failed: HEAD does not equal origin/main."
    }

    Write-Host "Git update completed safely: HEAD equals origin/main."
}
finally {
    Pop-Location
}
