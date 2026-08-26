$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

Invoke-ExternalCommand "uv" @("sync", "--locked", "--all-groups")
Invoke-ExternalCommand "uv" @("run", "--no-sync", "ruff", "check", ".")
Invoke-ExternalCommand "uv" @("run", "--no-sync", "mypy")
Invoke-ExternalCommand "uv" @(
    "run",
    "--no-sync",
    "pytest",
    "--cov=mx_bank_monitor",
    "--cov-report=term-missing"
)
Invoke-ExternalCommand "uv" @("run", "--no-sync", "mbm", "validate-config")
