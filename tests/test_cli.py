from __future__ import annotations

from pydantic import SecretStr
from typer.testing import CliRunner

from mx_bank_monitor import cli
from mx_bank_monitor.persistence.postgres import DatabaseConnectionError
from mx_bank_monitor.settings import Settings

SECRET_MARKER = "THIS_PASSWORD_MUST_NEVER_APPEAR"
DATABASE_URL = f"postgresql://monitor:{SECRET_MARKER}@database.invalid:6543/postgres"
runner = CliRunner()


def test_doctor_database_rejects_missing_configuration(monkeypatch) -> None:
    monkeypatch.setattr(cli, "get_settings", lambda: Settings(_env_file=None))

    result = runner.invoke(cli.app, ["doctor", "--database"])

    assert result.exit_code != 0
    assert "MBM_DATABASE_URL is not configured" in result.output


def test_doctor_database_runs_ping_and_schema_preflight(monkeypatch) -> None:
    calls: list[str] = []

    class PassingRepository:
        def __init__(self, database_url: SecretStr) -> None:
            assert database_url.get_secret_value() == DATABASE_URL

        def ping(self) -> bool:
            calls.append("ping")
            return True

        def preflight_schema(self) -> None:
            calls.append("schema")

    settings = Settings(_env_file=None, database_url=DATABASE_URL)
    monkeypatch.setattr(cli, "get_settings", lambda: settings)
    monkeypatch.setattr(cli, "PostgresRepository", PassingRepository)

    result = runner.invoke(cli.app, ["doctor", "--database"])

    assert result.exit_code == 0
    assert calls == ["ping", "schema"]
    assert "database reachable: yes" in result.output
    assert "database schema: expected legacy objects present" in result.output
    assert SECRET_MARKER not in result.output
    assert DATABASE_URL not in result.output


def test_doctor_database_connection_failure_is_secret_safe(monkeypatch) -> None:
    class FailingRepository:
        def __init__(self, _database_url: SecretStr) -> None:
            pass

        def ping(self) -> bool:
            raise DatabaseConnectionError(
                "Database preflight could not connect; check configuration and network access."
            )

        def preflight_schema(self) -> None:
            raise AssertionError("schema preflight must not run after a failed ping")

    settings = Settings(_env_file=None, database_url=DATABASE_URL)
    monkeypatch.setattr(cli, "get_settings", lambda: settings)
    monkeypatch.setattr(cli, "PostgresRepository", FailingRepository)

    result = runner.invoke(cli.app, ["doctor", "--database"])

    assert result.exit_code == 1
    assert "database preflight failed" in result.output
    assert SECRET_MARKER not in result.output
    assert DATABASE_URL not in result.output
