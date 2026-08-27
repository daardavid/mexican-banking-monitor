from __future__ import annotations

import platform
from pathlib import Path

import typer

from mx_bank_monitor import __version__
from mx_bank_monitor.config import ConfigValidationError, load_config_bundle
from mx_bank_monitor.persistence.postgres import DatabasePreflightError, PostgresRepository
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
        if not settings.database_configured or settings.database_url is None:
            raise typer.BadParameter("MBM_DATABASE_URL is not configured")

        repository = PostgresRepository(settings.database_url)
        try:
            if not repository.ping():
                raise DatabasePreflightError("Database ping returned an unexpected response.")
            typer.echo("database reachable: yes")
            repository.preflight_schema()
            typer.echo("database schema: expected legacy objects present")
        except DatabasePreflightError as error:
            typer.echo(f"database preflight failed: {error}", err=True)
            raise typer.Exit(code=1) from None


@app.command("validate-config")
def validate_config(config_dir: Path = Path("config")) -> None:
    """Validate the complete version-controlled editorial configuration bundle."""
    try:
        bundle = load_config_bundle(config_dir)
    except ConfigValidationError as error:
        typer.echo(f"config validation failed: {error}", err=True)
        raise typer.Exit(code=1) from None

    typer.echo(
        "config valid: "
        f"schema_version={bundle.schema_version} "
        f"sources={len(bundle.sources.sources)} "
        f"institutions={len(bundle.institutions.institutions)} "
        f"reporting_scopes={len(bundle.reporting_scopes.reporting_scopes)} "
        f"concepts={len(bundle.concepts.concepts)} "
        f"regulatory_concepts={len(bundle.mappings.regulatory_concepts)} "
        f"mappings={len(bundle.mappings.mappings)} "
        f"metrics={len(bundle.metrics.metrics)}"
    )


if __name__ == "__main__":
    app()
