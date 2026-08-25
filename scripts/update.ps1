$ErrorActionPreference = "Stop"

git status --short
git pull --ff-only
uv sync --locked --all-groups
uv run mbm validate-config
uv run pytest
