$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

Invoke-ExternalCommand "uv" @("run", "ruff", "check", ".")
Invoke-ExternalCommand "uv" @("run", "mypy")
Invoke-ExternalCommand "uv" @(
    "run",
    "pytest",
    "--cov=mx_bank_monitor",
    "--cov-report=term-missing"
)
Invoke-ExternalCommand "uv" @("run", "mbm", "validate-config")
