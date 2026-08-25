from __future__ import annotations

import platform
from pathlib import Path

import typer
import yaml

from mx_bank_monitor import __version__
from mx_bank_monitor.persistence.postgres import PostgresRepository
from mx_bank_monitor.settings import get_settings

app = typer.Typer(no_args_is_help=True, help="Mexico Banking Monitor command line.")


@app.command()
def doctor(check_database: bool = typer.Option(False, "--database")) -> None:
    """Check whether a laptop is ready to work on the project."""
    settings = get_settings()
    typer.echo(f"mx-bank-monitor: {__version__}")
    typer.echo(f"python: {platform.python_version()}")
    typer.echo(f"environment: {settings.env}")
    typer.echo(f"database configured: {'yes' if settings.database_configured else 'no'}")

    if check_database:
        if not settings.database_url:
            raise typer.BadParameter("MBM_DATABASE_URL is not configured")
        ok = PostgresRepository(settings.database_url).ping()
        typer.echo(f"database reachable: {'yes' if ok else 'no'}")


@app.command("validate-config")
def validate_config(config_dir: Path = Path("config")) -> None:
    """Validate that version-controlled YAML configuration can be loaded."""
    required = ["institutions.yml", "metrics.yml", "sources.yml"]
    for filename in required:
        path = config_dir / filename
        if not path.exists():
            raise typer.BadParameter(f"Missing configuration file: {path}")
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
        if document.get("schema_version") != 1:
            raise typer.BadParameter(f"Unsupported schema_version in {path}")
        typer.echo(f"ok: {path}")


if __name__ == "__main__":
    app()
