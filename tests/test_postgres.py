from __future__ import annotations

import re
import traceback

import psycopg
import pytest
from pydantic import SecretStr

from mx_bank_monitor.persistence.postgres import (
    CONNECT_TIMEOUT_SECONDS,
    PING_SQL,
    READ_ONLY_PREFLIGHT_SQL,
    REQUIRED_SCHEMA_OBJECTS,
    SCHEMA_PREFLIGHT_SQL,
    DatabaseConnectionError,
    DatabaseSchemaError,
    PostgresRepository,
)

SECRET_MARKER = "THIS_PASSWORD_MUST_NEVER_APPEAR"
TRANSACTION_POOLER_URL = (
    f"postgresql://postgres.project:{SECRET_MARKER}@pooler.invalid:6543/postgres"
)
DIRECT_DATABASE_URL = f"postgresql://monitor:{SECRET_MARKER}@database.invalid:5432/postgres"


class FakeCursor:
    def __init__(
        self,
        *,
        ping_row: tuple[object, ...] = (1,),
        schema_rows: list[tuple[object, ...]] | None = None,
    ) -> None:
        self.ping_row = ping_row
        self.schema_rows = schema_rows or []
        self.executed: list[tuple[str, object | None]] = []

    def __enter__(self) -> FakeCursor:
        return self

    def __exit__(
        self,
        _exc_type: object,
        _exc_value: object,
        _traceback: object,
    ) -> None:
        return None

    def execute(self, query: str, params: object | None = None) -> None:
        self.executed.append((query, params))

    def fetchone(self) -> tuple[object, ...]:
        return self.ping_row

    def fetchall(self) -> list[tuple[object, ...]]:
        return self.schema_rows


class FakeConnection:
    def __init__(self, cursor: FakeCursor) -> None:
        self._cursor = cursor

    def __enter__(self) -> FakeConnection:
        return self

    def __exit__(
        self,
        _exc_type: object,
        _exc_value: object,
        _traceback: object,
    ) -> None:
        return None

    def cursor(self) -> FakeCursor:
        return self._cursor


@pytest.mark.parametrize("database_url", [TRANSACTION_POOLER_URL, DIRECT_DATABASE_URL])
def test_connection_uses_timeout_and_disables_prepared_statements(
    monkeypatch: pytest.MonkeyPatch,
    database_url: str,
) -> None:
    captured: list[tuple[str, dict[str, object]]] = []
    cursor = FakeCursor()

    def fake_connect(conninfo: str, **kwargs: object) -> FakeConnection:
        captured.append((conninfo, kwargs))
        return FakeConnection(cursor)

    monkeypatch.setattr(psycopg, "connect", fake_connect)

    assert PostgresRepository(SecretStr(database_url)).ping() is True
    assert captured == [
        (
            database_url,
            {
                "connect_timeout": CONNECT_TIMEOUT_SECONDS,
                "prepare_threshold": None,
            },
        )
    ]


def test_repository_repr_does_not_expose_database_url() -> None:
    repository = PostgresRepository(SecretStr(TRANSACTION_POOLER_URL))

    assert SECRET_MARKER not in repr(repository)
    assert TRANSACTION_POOLER_URL not in repr(repository)


def test_ping_executes_select_one(monkeypatch: pytest.MonkeyPatch) -> None:
    cursor = FakeCursor()
    monkeypatch.setattr(psycopg, "connect", lambda *_args, **_kwargs: FakeConnection(cursor))

    assert PostgresRepository(SecretStr(DIRECT_DATABASE_URL)).ping() is True
    assert cursor.executed == [(PING_SQL, None)]


def test_schema_preflight_passes_when_expected_objects_exist(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    schema_rows = [(object_name, True) for object_name in REQUIRED_SCHEMA_OBJECTS]
    cursor = FakeCursor(schema_rows=schema_rows)
    monkeypatch.setattr(psycopg, "connect", lambda *_args, **_kwargs: FakeConnection(cursor))

    PostgresRepository(SecretStr(DIRECT_DATABASE_URL)).preflight_schema()

    assert cursor.executed == [
        (SCHEMA_PREFLIGHT_SQL, (list(REQUIRED_SCHEMA_OBJECTS),)),
    ]


def test_schema_preflight_reports_missing_required_object_safely(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    missing_object = "ops.pipeline_runs"
    schema_rows = [
        (object_name, object_name != missing_object) for object_name in REQUIRED_SCHEMA_OBJECTS
    ]
    cursor = FakeCursor(schema_rows=schema_rows)
    monkeypatch.setattr(psycopg, "connect", lambda *_args, **_kwargs: FakeConnection(cursor))

    with pytest.raises(DatabaseSchemaError) as exc_info:
        PostgresRepository(SecretStr(DIRECT_DATABASE_URL)).preflight_schema()

    assert exc_info.value.missing_objects == (missing_object,)
    assert missing_object in str(exc_info.value)
    assert SECRET_MARKER not in str(exc_info.value)
    assert DIRECT_DATABASE_URL not in repr(exc_info.value)


def test_connection_error_does_not_expose_database_url_or_password(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fail_connect(conninfo: str, **_kwargs: object) -> FakeConnection:
        raise psycopg.OperationalError(f"Could not connect using {conninfo}")

    monkeypatch.setattr(psycopg, "connect", fail_connect)

    with pytest.raises(DatabaseConnectionError) as exc_info:
        PostgresRepository(SecretStr(DIRECT_DATABASE_URL)).ping()

    application_error = f"{exc_info.value!r} {exc_info.value}"
    application_traceback = "".join(
        traceback.format_exception(exc_info.type, exc_info.value, exc_info.tb)
    )
    assert SECRET_MARKER not in application_error
    assert DIRECT_DATABASE_URL not in application_error
    assert SECRET_MARKER not in application_traceback
    assert DIRECT_DATABASE_URL not in application_traceback


def test_preflight_sql_is_select_only() -> None:
    forbidden = re.compile(r"\b(CREATE|ALTER|DROP|INSERT|UPDATE|DELETE|TRUNCATE)\b")

    for query in READ_ONLY_PREFLIGHT_SQL:
        normalized = query.strip().upper()
        assert normalized.startswith("SELECT")
        assert forbidden.search(normalized) is None
