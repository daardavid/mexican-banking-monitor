$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

Invoke-ExternalCommand "git" @("status", "--short")
Invoke-ExternalCommand "git" @("pull", "--ff-only")
Invoke-ExternalCommand "uv" @("sync", "--locked", "--all-groups")
Invoke-ExternalCommand "uv" @("run", "mbm", "validate-config")
Invoke-ExternalCommand "uv" @("run", "pytest")
