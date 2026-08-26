$ErrorActionPreference = "Stop"

$updateGitScript = Join-Path $PSScriptRoot "update-git.ps1"
$pwsh = (Get-Command "pwsh" -ErrorAction Stop).Source
$temporaryBase = [System.IO.Path]::GetTempPath()
$testRoot = Join-Path $temporaryBase ("mbm-update-tests-" + [guid]::NewGuid().ToString("N"))
$passed = 0

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $output = @(& git -C $Repository @ArgumentList 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Test fixture Git command failed: git $($ArgumentList[0]). $($output -join ' ')"
    }
    return $output
}

function New-TestTopology {
    param([Parameter(Mandatory = $true)][string]$Name)

    $root = Join-Path $testRoot $Name
    $origin = Join-Path $root "origin.git"
    $publisher = Join-Path $root "publisher"
    $local = Join-Path $root "local"
    New-Item -ItemType Directory -Path $root | Out-Null

    $null = Invoke-TestGit $root @("-c", "init.defaultBranch=main", "init", "--bare", $origin)
    $null = Invoke-TestGit $root @("clone", $origin, $publisher)
    $null = Invoke-TestGit $publisher @("config", "user.name", "MONITOR test")
    $null = Invoke-TestGit $publisher @("config", "user.email", "monitor-test@example.invalid")
    Set-Content -LiteralPath (Join-Path $publisher "tracked.txt") -Value "initial"
    $null = Invoke-TestGit $publisher @("add", "tracked.txt")
    $null = Invoke-TestGit $publisher @("commit", "-m", "initial")
    $null = Invoke-TestGit $publisher @("push", "-u", "origin", "main")
    $null = Invoke-TestGit $root @("clone", $origin, $local)
    $null = Invoke-TestGit $local @("config", "user.name", "MONITOR test")
    $null = Invoke-TestGit $local @("config", "user.email", "monitor-test@example.invalid")

    return [pscustomobject]@{
        Root = $root
        Origin = $origin
        Publisher = $publisher
        Local = $local
    }
}

function Add-PublishedCommit {
    param(
        [Parameter(Mandatory = $true)]$Topology,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Add-Content -LiteralPath (Join-Path $Topology.Publisher "tracked.txt") -Value $Label
    $null = Invoke-TestGit $Topology.Publisher @("add", "tracked.txt")
    $null = Invoke-TestGit $Topology.Publisher @("commit", "-m", $Label)
    $null = Invoke-TestGit $Topology.Publisher @("push", "origin", "main")
}

function Invoke-UpdateGitProcess {
    param([Parameter(Mandatory = $true)][string]$Repository)

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $pwsh `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $updateGitScript `
            -RepositoryPath $Repository 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    }
}

function Get-RepositoryState {
    param([Parameter(Mandatory = $true)][string]$Repository)

    return [pscustomobject]@{
        Head = (@(Invoke-TestGit $Repository @("rev-parse", "HEAD")) -join "`n")
        Branch = (@(Invoke-TestGit $Repository @("symbolic-ref", "--short", "HEAD")) -join "`n")
        Status = (@(Invoke-TestGit $Repository @("status", "--porcelain=v1", "--untracked-files=all")) -join "`n")
        WorktreeDiff = (@(Invoke-TestGit $Repository @("diff", "--")) -join "`n")
        CachedDiff = (@(Invoke-TestGit $Repository @("diff", "--cached", "--")) -join "`n")
        Stashes = (@(Invoke-TestGit $Repository @("stash", "list")) -join "`n")
        TrackedContent = Get-Content -LiteralPath (Join-Path $Repository "tracked.txt") -Raw
        UntrackedContent = if (Test-Path -LiteralPath (Join-Path $Repository "untracked.txt")) {
            Get-Content -LiteralPath (Join-Path $Repository "untracked.txt") -Raw
        } else { "" }
    }
}

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-RejectedAndPreserved {
    param(
        [Parameter(Mandatory = $true)]$Topology,
        [Parameter(Mandatory = $true)][string]$MessagePattern,
        [Parameter(Mandatory = $true)][string]$Scenario
    )

    $before = Get-RepositoryState $Topology.Local
    $result = Invoke-UpdateGitProcess $Topology.Local
    $after = Get-RepositoryState $Topology.Local

    Assert-Condition ($result.ExitCode -ne 0) "$Scenario should fail."
    Assert-Condition ($result.Output -match $MessagePattern) `
        "$Scenario did not report the expected actionable message. Output: $($result.Output)"
    foreach ($property in $before.PSObject.Properties.Name) {
        Assert-Condition ($before.$property -ceq $after.$property) `
            "$Scenario changed repository state '$property'."
    }

    $script:passed++
    Write-Host "PASS: $Scenario rejected and preserved local state"
}

New-Item -ItemType Directory -Path $testRoot | Out-Null

try {
    $topology = New-TestTopology "equal"
    $headBefore = @(Invoke-TestGit $topology.Local @("rev-parse", "HEAD")) -join ""
    $result = Invoke-UpdateGitProcess $topology.Local
    $headAfter = @(Invoke-TestGit $topology.Local @("rev-parse", "HEAD")) -join ""
    Assert-Condition ($result.ExitCode -eq 0) "Clean/equal should succeed: $($result.Output)"
    Assert-Condition ($headAfter -ceq $headBefore) "Clean/equal unexpectedly changed HEAD."
    $passed++
    Write-Host "PASS: clean main, correct upstream, equal"

    $topology = New-TestTopology "behind"
    $headBefore = @(Invoke-TestGit $topology.Local @("rev-parse", "HEAD")) -join ""
    Add-PublishedCommit $topology "remote update"
    $result = Invoke-UpdateGitProcess $topology.Local
    $headAfter = @(Invoke-TestGit $topology.Local @("rev-parse", "HEAD")) -join ""
    $remoteHead = @(Invoke-TestGit $topology.Local @("rev-parse", "origin/main")) -join ""
    Assert-Condition ($result.ExitCode -eq 0) "Clean/behind should succeed: $($result.Output)"
    Assert-Condition ($headAfter -cne $headBefore) "Clean/behind did not advance HEAD."
    Assert-Condition ($headAfter -ceq $remoteHead) "Fast-forward did not end at origin/main."
    $passed++
    Write-Host "PASS: clean main, correct upstream, behind fast-forwarded to origin/main"

    $topology = New-TestTopology "unstaged"
    Add-Content -LiteralPath (Join-Path $topology.Local "tracked.txt") -Value "unstaged"
    Assert-RejectedAndPreserved $topology "unstaged changes" "unstaged tracked change"

    $topology = New-TestTopology "staged"
    Add-Content -LiteralPath (Join-Path $topology.Local "tracked.txt") -Value "staged"
    $null = Invoke-TestGit $topology.Local @("add", "tracked.txt")
    Assert-RejectedAndPreserved $topology "staged changes" "staged change"

    $topology = New-TestTopology "untracked"
    Set-Content -LiteralPath (Join-Path $topology.Local "untracked.txt") -Value "untracked"
    Assert-RejectedAndPreserved $topology "untracked files" "untracked file"

    $topology = New-TestTopology "wrong-branch"
    $null = Invoke-TestGit $topology.Local @("switch", "-c", "feature/test")
    Assert-RejectedAndPreserved $topology "exactly 'main' is required" "wrong branch"

    $topology = New-TestTopology "no-upstream"
    $null = Invoke-TestGit $topology.Local @("branch", "--unset-upstream")
    Assert-RejectedAndPreserved $topology "main has no upstream" "main without upstream"

    $topology = New-TestTopology "wrong-upstream"
    $null = Invoke-TestGit $topology.Publisher @("push", "origin", "main:other")
    $null = Invoke-TestGit $topology.Local @("fetch", "origin", "other")
    $null = Invoke-TestGit $topology.Local @("branch", "--set-upstream-to=origin/other", "main")
    Assert-RejectedAndPreserved $topology "exactly 'origin/main' is required" "wrong upstream"

    $topology = New-TestTopology "ahead"
    Add-Content -LiteralPath (Join-Path $topology.Local "tracked.txt") -Value "local ahead"
    $null = Invoke-TestGit $topology.Local @("add", "tracked.txt")
    $null = Invoke-TestGit $topology.Local @("commit", "-m", "local ahead")
    Assert-RejectedAndPreserved $topology "ahead of origin/main" "local ahead"

    $topology = New-TestTopology "diverged"
    Add-Content -LiteralPath (Join-Path $topology.Local "tracked.txt") -Value "local divergence"
    $null = Invoke-TestGit $topology.Local @("add", "tracked.txt")
    $null = Invoke-TestGit $topology.Local @("commit", "-m", "local divergence")
    Add-PublishedCommit $topology "remote divergence"
    Assert-RejectedAndPreserved $topology "have diverged" "diverged history"

    Assert-Condition ($passed -eq 10) "Expected 10 update scenarios, but $passed passed."
    Write-Host "PowerShell update regression checks passed: $passed scenarios."
}
finally {
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedTemporaryBase = [System.IO.Path]::GetFullPath($temporaryBase)
    if ($resolvedTestRoot.StartsWith($resolvedTemporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTestRoot).StartsWith("mbm-update-tests-")) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit 0
