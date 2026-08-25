$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

Invoke-ExternalCommand "cmd.exe" @("/d", "/c", "exit /b 0") -SafeLabel "success probe"

$sensitiveMarker = "SENSITIVE_ARGUMENT_MARKER_DO_NOT_ECHO"
$errorMessage = $null

try {
    Invoke-ExternalCommand "cmd.exe" @(
        "/d",
        "/c",
        "exit /b 7",
        $sensitiveMarker
    ) -SafeLabel "intentional failure probe"
}
catch {
    $errorMessage = $_.Exception.Message
}

if (-not $errorMessage) {
    throw "Expected the failure probe to produce an error."
}

if ($errorMessage -notmatch "exit code 7") {
    throw "Failure message did not include exit code 7."
}

if ($errorMessage.Contains($sensitiveMarker)) {
    throw "Failure message exposed a sensitive argument."
}

Write-Host "PowerShell command regression checks passed."
exit 0
