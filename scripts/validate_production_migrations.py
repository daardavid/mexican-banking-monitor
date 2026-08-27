"""Fail-closed production migration checks used by the deploy workflow."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

LEGACY_MIGRATION_NAME = "202608250001_initial_schema.sql"
LEGACY_MIGRATION_SHA256 = "16c7a9ce774d62b3ee4d643318ef184cdaaffb7754ee43f049c3bbf1e8f93b46"
STANDARD_MIGRATION_NAME = re.compile(
    r"^(?P<version>\d{14})_(?P<name>[a-z][a-z0-9]*(?:_[a-z0-9]+)*)\.sql$"
)


class MigrationValidationError(ValueError):
    """Raised when deployment must stop before touching production."""


@dataclass(frozen=True, slots=True)
class Migration:
    version: str
    path: Path


@dataclass(frozen=True, slots=True)
class HistoryRow:
    local: str | None
    remote: str | None


FORBIDDEN_SQL = (
    ("DROP TABLE", re.compile(r"\bDROP\s+TABLE\b")),
    ("DROP SCHEMA", re.compile(r"\bDROP\s+SCHEMA\b")),
    ("DROP VIEW", re.compile(r"\bDROP\s+(?:MATERIALIZED\s+)?VIEW\b")),
    ("TRUNCATE", re.compile(r"\bTRUNCATE(?:\s+TABLE)?\b")),
    ("ALTER TABLE DROP COLUMN", re.compile(r"\bALTER\s+TABLE\b.*\bDROP\s+COLUMN\b")),
    (
        "ALTER TABLE DROP CONSTRAINT",
        re.compile(r"\bALTER\s+TABLE\b.*\bDROP\s+CONSTRAINT\b"),
    ),
    ("DROP TYPE", re.compile(r"\bDROP\s+TYPE\b")),
    ("DROP DOMAIN", re.compile(r"\bDROP\s+DOMAIN\b")),
    ("DROP FUNCTION", re.compile(r"\bDROP\s+(?:FUNCTION|PROCEDURE)\b")),
    ("DROP POLICY", re.compile(r"\bDROP\s+POLICY\b")),
    ("DELETE", re.compile(r"\bDELETE\s+FROM\b")),
    (
        "destructive RENAME",
        re.compile(
            r"\bALTER\s+(?:TABLE|VIEW|MATERIALIZED\s+VIEW|TYPE|DOMAIN)\b.*\bRENAME\b"
        ),
    ),
    ("CREATE OR REPLACE VIEW", re.compile(r"\bCREATE\s+OR\s+REPLACE\s+VIEW\b")),
)


def _migration_version(name: str) -> str | None:
    if name == LEGACY_MIGRATION_NAME:
        return name.split("_", 1)[0]
    match = STANDARD_MIGRATION_NAME.fullmatch(name)
    if match is None:
        return None
    version = match.group("version")
    try:
        datetime.strptime(version, "%Y%m%d%H%M%S")
    except ValueError:
        return None
    return version


def _legacy_sha256(content: bytes) -> str:
    canonical_crlf = content.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
    return hashlib.sha256(canonical_crlf).hexdigest()


def load_migrations(migrations_dir: Path, *, verify_legacy: bool = True) -> list[Migration]:
    if not migrations_dir.is_dir():
        raise MigrationValidationError(f"Migration directory does not exist: {migrations_dir}")

    migrations: list[Migration] = []
    errors: list[str] = []
    for entry in sorted(migrations_dir.iterdir(), key=lambda item: item.name):
        if not entry.is_file():
            errors.append(f"unexpected directory in migrations: {entry.name}")
            continue
        version = _migration_version(entry.name)
        if version is None:
            errors.append(
                f"invalid migration filename: {entry.name}; expected "
                "<14-digit timestamp>_<lowercase_name>.sql"
            )
            continue
        migrations.append(Migration(version=version, path=entry))

    versions = [migration.version for migration in migrations]
    duplicates = sorted({version for version in versions if versions.count(version) > 1})
    if duplicates:
        errors.append(f"duplicate migration versions: {', '.join(duplicates)}")

    for index, version in enumerate(versions):
        for other in versions[index + 1 :]:
            if version.startswith(other) or other.startswith(version):
                errors.append(
                    f"ambiguous migration ordering: versions {version} and {other} share a prefix"
                )

    numeric_order = sorted(versions, key=int)
    if versions != numeric_order:
        errors.append("migration filenames do not sort in chronological version order")

    if verify_legacy:
        legacy_path = migrations_dir / LEGACY_MIGRATION_NAME
        if not legacy_path.is_file():
            errors.append(f"immutable legacy migration is missing: {LEGACY_MIGRATION_NAME}")
        else:
            actual_hash = _legacy_sha256(legacy_path.read_bytes())
            if actual_hash != LEGACY_MIGRATION_SHA256:
                errors.append(
                    f"immutable legacy migration hash changed: {LEGACY_MIGRATION_NAME}"
                )

    if errors:
        raise MigrationValidationError("\n".join(errors))
    if not migrations:
        raise MigrationValidationError("No migration files found")
    return migrations


def _load_json_object(text: str, *, output_name: str) -> dict[str, Any]:
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as error:
        raise MigrationValidationError(
            f"Invalid {output_name} JSON: {error.msg}"
        ) from error
    if not isinstance(payload, dict):
        raise MigrationValidationError(f"{output_name} JSON root must be an object")
    return payload


def _require(
    payload: dict[str, Any],
    field: str,
    expected_type: type,
    type_name: str,
    context: str,
) -> Any:
    if field not in payload:
        raise MigrationValidationError(f"{context} is missing `{field}`")
    value = payload[field]
    if type(value) is not expected_type:
        raise MigrationValidationError(f"{context} `{field}` must be {type_name}")
    return value


def parse_history_json(text: str) -> list[HistoryRow]:
    payload = _load_json_object(text, output_name="migration list")
    migrations = _require(payload, "migrations", list, "a list", "migration list JSON")

    rows: list[HistoryRow] = []
    for index, row in enumerate(migrations):
        if type(row) is not dict:
            raise MigrationValidationError(
                f"migration list JSON row {index} must be an object"
            )
        context = f"migration list JSON row {index}"
        for field in ("local", "remote", "time"):
            _require(row, field, str, "a string", context)
        local = row["local"] or None
        remote = row["remote"] or None
        if local is None and remote is None:
            raise MigrationValidationError(
                f"migration list JSON row {index} has no local or remote version"
            )
        rows.append(HistoryRow(local=local, remote=remote))
    return rows


def validate_history(
    rows: list[HistoryRow],
    migrations: list[Migration],
    *,
    require_aligned: bool,
) -> list[Migration]:
    expected_versions = [migration.version for migration in migrations]
    listed_local = [row.local for row in rows if row.local is not None]
    if listed_local != expected_versions:
        raise MigrationValidationError(
            "`migration list` local versions do not exactly match the validated repository history"
        )

    remote_versions = [row.remote for row in rows if row.remote is not None]
    if len(remote_versions) != len(set(remote_versions)):
        raise MigrationValidationError("Remote migration history contains duplicate versions")
    if not remote_versions:
        raise MigrationValidationError(
            "Remote migration history has no trusted common baseline; reconciliation is required"
        )

    pending_versions: list[str] = []
    saw_pending = False
    for row in rows:
        if row.local is not None and row.remote is not None:
            if row.local != row.remote:
                raise MigrationValidationError(
                    f"Migration history diverges: local {row.local}, remote {row.remote}"
                )
            if saw_pending:
                raise MigrationValidationError(
                    "Remote history has a gap: an applied migration follows a missing version"
                )
        elif row.remote is not None:
            raise MigrationValidationError(
                f"Remote migration version is missing locally: {row.remote}"
            )
        elif row.local is not None:
            saw_pending = True
            pending_versions.append(row.local)

    if require_aligned and pending_versions:
        raise MigrationValidationError(
            "Post-deploy migration history is not aligned; pending versions: "
            + ", ".join(pending_versions)
        )

    by_version = {migration.version: migration for migration in migrations}
    return [by_version[version] for version in pending_versions]


def strip_sql_literals_and_comments(sql: str) -> str:
    output = list(sql)
    index = 0
    length = len(sql)
    block_depth = 0
    state = "normal"
    dollar_delimiter = ""

    def blank(start: int, end: int) -> None:
        for position in range(start, end):
            if output[position] not in "\r\n":
                output[position] = " "

    while index < length:
        if state == "normal":
            if sql.startswith("--", index):
                blank(index, index + 2)
                index += 2
                state = "line-comment"
            elif sql.startswith("/*", index):
                blank(index, index + 2)
                index += 2
                block_depth = 1
                state = "block-comment"
            elif sql[index] == "'":
                blank(index, index + 1)
                index += 1
                state = "single-quote"
            elif sql[index] == '"':
                blank(index, index + 1)
                index += 1
                state = "double-quote"
            elif sql[index] == "$":
                match = re.match(r"\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$", sql[index:])
                if match is None:
                    index += 1
                else:
                    dollar_delimiter = match.group(0)
                    blank(index, index + len(dollar_delimiter))
                    index += len(dollar_delimiter)
                    state = "dollar-quote"
            else:
                index += 1
        elif state == "line-comment":
            if sql[index] in "\r\n":
                state = "normal"
                index += 1
            else:
                blank(index, index + 1)
                index += 1
        elif state == "block-comment":
            if sql.startswith("/*", index):
                blank(index, index + 2)
                index += 2
                block_depth += 1
            elif sql.startswith("*/", index):
                blank(index, index + 2)
                index += 2
                block_depth -= 1
                if block_depth == 0:
                    state = "normal"
            else:
                blank(index, index + 1)
                index += 1
        elif state == "single-quote":
            if sql.startswith("''", index) or (
                sql[index] == "\\" and index + 1 < length
            ):
                blank(index, index + 2)
                index += 2
            elif sql[index] == "'":
                blank(index, index + 1)
                index += 1
                state = "normal"
            else:
                blank(index, index + 1)
                index += 1
        elif state == "double-quote":
            if sql.startswith('""', index):
                blank(index, index + 2)
                index += 2
            elif sql[index] == '"':
                blank(index, index + 1)
                index += 1
                state = "normal"
            else:
                blank(index, index + 1)
                index += 1
        elif state == "dollar-quote":
            if sql.startswith(dollar_delimiter, index):
                blank(index, index + len(dollar_delimiter))
                index += len(dollar_delimiter)
                state = "normal"
            else:
                blank(index, index + 1)
                index += 1

    if state in {"block-comment", "single-quote", "double-quote", "dollar-quote"}:
        raise MigrationValidationError(f"Unterminated SQL {state.replace('-', ' ')}")
    return "".join(output)


def forbidden_operations(sql: str) -> list[str]:
    stripped = strip_sql_literals_and_comments(sql)
    violations: list[str] = []
    for statement in stripped.split(";"):
        normalized = " ".join(statement.upper().split())
        if not normalized:
            continue
        for label, pattern in FORBIDDEN_SQL:
            if pattern.search(normalized):
                violations.append(label)
    return violations


def validate_pending_sql(migrations: list[Migration]) -> None:
    violations: list[str] = []
    for migration in migrations:
        for operation in forbidden_operations(migration.path.read_text(encoding="utf-8")):
            violations.append(f"{migration.path.name}: forbidden production operation {operation}")
    if violations:
        raise MigrationValidationError("\n".join(violations))


def read_pending_file(path: Path, migrations: list[Migration]) -> list[Migration]:
    names = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    by_name = {migration.path.name: migration for migration in migrations}
    unknown = [name for name in names if name not in by_name]
    if unknown:
        raise MigrationValidationError(
            "Pending migration list contains unknown files: " + ", ".join(unknown)
        )
    return [by_name[name] for name in names]


def validate_dry_run(text: str, pending: list[Migration]) -> None:
    payload = _load_json_object(text, output_name="db push --dry-run")
    context = "Dry-run JSON"
    dry_run = _require(payload, "dryRun", bool, "a boolean", context)
    if dry_run is not True:
        raise MigrationValidationError("Dry-run JSON `dryRun` must be true")
    up_to_date = _require(payload, "upToDate", bool, "a boolean", context)
    planned = _require(payload, "migrations", list, "a list", context)
    seeds = _require(payload, "seeds", list, "a list", context)
    roles = _require(payload, "roles", list, "a list", context)
    if any(type(item) is not str for item in planned):
        raise MigrationValidationError(
            "Dry-run JSON `migrations` must contain only strings"
        )
    if seeds:
        raise MigrationValidationError("Dry-run JSON contains unexpected seeds")
    if roles:
        raise MigrationValidationError("Dry-run JSON contains unexpected roles")

    expected = [migration.path.name for migration in pending]
    if planned != expected:
        raise MigrationValidationError(
            "Dry-run migration plan does not match the gated pending suffix: "
            f"expected {expected}, got {planned}"
        )
    expected_up_to_date = not expected
    if up_to_date is not expected_up_to_date:
        raise MigrationValidationError(
            "Dry-run JSON `upToDate` is inconsistent with the gated pending suffix"
        )


def _write_pending(path: Path, pending: list[Migration]) -> None:
    content = "".join(f"{migration.path.name}\n" for migration in pending)
    path.write_text(content, encoding="utf-8")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--migrations-dir", type=Path, default=Path("supabase/migrations")
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("repository")

    history = subparsers.add_parser("history")
    history.add_argument("--input", type=Path, required=True)
    history.add_argument("--pending-output", type=Path, required=True)
    history.add_argument("--require-aligned", action="store_true")

    sql = subparsers.add_parser("sql")
    sql.add_argument("--files-from", type=Path, required=True)

    dry_run = subparsers.add_parser("dry-run")
    dry_run.add_argument("--input", type=Path, required=True)
    dry_run.add_argument("--files-from", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        migrations = load_migrations(args.migrations_dir)
        if args.command == "repository":
            print(f"Migration repository validation passed ({len(migrations)} files).")
        elif args.command == "history":
            rows = parse_history_json(args.input.read_text(encoding="utf-8"))
            pending = validate_history(rows, migrations, require_aligned=args.require_aligned)
            _write_pending(args.pending_output, pending)
            print(
                "Migration history validation passed; pending: "
                + (", ".join(item.path.name for item in pending) or "none")
            )
        elif args.command == "sql":
            pending = read_pending_file(args.files_from, migrations)
            validate_pending_sql(pending)
            print(f"Production SQL safety validation passed ({len(pending)} pending files).")
        elif args.command == "dry-run":
            pending = read_pending_file(args.files_from, migrations)
            validate_dry_run(args.input.read_text(encoding="utf-8"), pending)
            print("Dry-run plan validation passed.")
    except (MigrationValidationError, OSError, UnicodeError) as error:
        print(f"Production migration validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
