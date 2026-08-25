from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

import psycopg
from psycopg import Connection


class PostgresRepository:
    def __init__(self, database_url: str) -> None:
        self._database_url = database_url

    @contextmanager
    def connection(self) -> Iterator[Connection[tuple[object, ...]]]:
        with psycopg.connect(self._database_url) as connection:
            yield connection

    def ping(self) -> bool:
        with self.connection() as connection, connection.cursor() as cursor:
            cursor.execute("select 1")
            return cursor.fetchone() == (1,)
