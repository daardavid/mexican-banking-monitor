$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "common.ps1")

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is required. Install Git for Windows and reopen PowerShell."
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "uv is required. Install it with: winget install --id astral-sh.uv -e"
}

Invoke-ExternalCommand "uv" @("python", "install", "3.12")
Invoke-ExternalCommand "uv" @("sync", "--locked", "--all-groups")

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Created .env. Add this laptop's Supabase values before database work."
}

Invoke-ExternalCommand "uv" @("run", "mbm", "validate-config")
Invoke-ExternalCommand "uv" @("run", "pytest")
Write-Host "Laptop bootstrap completed."
