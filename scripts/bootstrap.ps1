$ErrorActionPreference = "Stop"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is required. Install Git for Windows and reopen PowerShell."
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw "uv is required. Install it with: winget install --id astral-sh.uv -e"
}

uv python install 3.12
uv sync --locked --all-groups

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "Created .env. Add this laptop's Supabase values before database work."
}

uv run mbm validate-config
uv run pytest
Write-Host "Laptop bootstrap completed."
