$ErrorActionPreference = "Stop"

uv run ruff check .
uv run mypy
uv run pytest --cov=mx_bank_monitor --cov-report=term-missing
uv run mbm validate-config
