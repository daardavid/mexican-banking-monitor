from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

import psycopg
from psycopg import Connection
from pydantic import SecretStr

CONNECT_TIMEOUT_SECONDS = 10
PING_SQL = "SELECT 1"
REQUIRED_SCHEMA_OBJECTS = (
    "analytics.metric_definitions",
    "core.current_financial_facts",
    "core.institutions",
    "ops.pipeline_runs",
    "public.bank_metrics",
)
SCHEMA_PREFLIGHT_SQL = """
SELECT required.object_name, to_regclass(required.object_name) IS NOT NULL
FROM unnest(%s::text[]) AS required(object_name)
ORDER BY required.object_name
"""
READ_ONLY_PREFLIGHT_SQL = (PING_SQL, SCHEMA_PREFLIGHT_SQL)


class DatabasePreflightError(RuntimeError):
    """A database preflight failure whose message is safe for user-facing output."""


class DatabaseConnectionError(DatabasePreflightError):
    """The configured database could not complete a preflight operation."""


class DatabaseSchemaError(DatabasePreflightError):
    """The database is reachable but is missing required legacy objects."""

    def __init__(self, missing_objects: tuple[str, ...]) -> None:
        self.missing_objects = missing_objects
        missing = ", ".join(missing_objects)
        super().__init__(f"Database schema is missing required objects: {missing}")


class PostgresRepository:
    def __init__(self, database_url: SecretStr) -> None:
        self._database_url = database_url

    def __repr__(self) -> str:
        return (
            f"{type(self).__name__}(connect_timeout_seconds={CONNECT_TIMEOUT_SECONDS}, "
            "prepare_threshold=None)"
        )

    @contextmanager
    def connection(self) -> Iterator[Connection[tuple[object, ...]]]:
        try:
            with psycopg.connect(
                self._database_url.get_secret_value(),
                connect_timeout=CONNECT_TIMEOUT_SECONDS,
                prepare_threshold=None,
            ) as connection:
                yield connection
        except psycopg.Error:
            raise DatabaseConnectionError(
                "Database preflight could not connect or execute; check configuration, "
                "network access, and database permissions."
            ) from None

    def ping(self) -> bool:
        with self.connection() as connection, connection.cursor() as cursor:
            cursor.execute(PING_SQL)
            return cursor.fetchone() == (1,)

    def preflight_schema(self) -> None:
        with self.connection() as connection, connection.cursor() as cursor:
            cursor.execute(SCHEMA_PREFLIGHT_SQL, (list(REQUIRED_SCHEMA_OBJECTS),))
            rows = cursor.fetchall()

        present_by_name = {str(row[0]): row[1] is True for row in rows}
        missing_objects = tuple(
            object_name
            for object_name in REQUIRED_SCHEMA_OBJECTS
            if not present_by_name.get(object_name, False)
        )
        if missing_objects:
            raise DatabaseSchemaError(missing_objects)
