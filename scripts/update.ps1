$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

& (Join-Path $PSScriptRoot "update-git.ps1") -RepositoryPath (Get-Location).Path
Invoke-ExternalCommand "uv" @("sync", "--locked", "--all-groups")
Invoke-ExternalCommand "uv" @("run", "--no-sync", "mbm", "validate-config")
Invoke-ExternalCommand "uv" @("run", "--no-sync", "pytest")
