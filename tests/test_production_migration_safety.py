import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPOSITORY_ROOT / "scripts" / "validate_production_migrations.py"
MODULE_SPEC = importlib.util.spec_from_file_location("production_migration_safety", MODULE_PATH)
assert MODULE_SPEC is not None
assert MODULE_SPEC.loader is not None
MIGRATION_SAFETY = importlib.util.module_from_spec(MODULE_SPEC)
sys.modules[MODULE_SPEC.name] = MIGRATION_SAFETY
MODULE_SPEC.loader.exec_module(MIGRATION_SAFETY)

LEGACY_MIGRATION_NAME = MIGRATION_SAFETY.LEGACY_MIGRATION_NAME
LEGACY_MIGRATION_SHA256 = MIGRATION_SAFETY.LEGACY_MIGRATION_SHA256
PR10_MIGRATION_NAME = "20260827223312_data_core_schema_primitives.sql"
HistoryRow = MIGRATION_SAFETY.HistoryRow
Migration = MIGRATION_SAFETY.Migration
MigrationValidationError = MIGRATION_SAFETY.MigrationValidationError
forbidden_operations = MIGRATION_SAFETY.forbidden_operations
load_migrations = MIGRATION_SAFETY.load_migrations
main = MIGRATION_SAFETY.main
parse_history_json = MIGRATION_SAFETY.parse_history_json
validate_dry_run = MIGRATION_SAFETY.validate_dry_run
validate_history = MIGRATION_SAFETY.validate_history
legacy_sha256 = MIGRATION_SAFETY._legacy_sha256


def migration(tmp_path: Path, version: str, name: str = "change") -> Migration:
    path = tmp_path / f"{version}_{name}.sql"
    path.write_text("create table example (id bigint);\n", encoding="utf-8")
    return Migration(version=version, path=path)


def history_row(
    local: str = "", remote: str = "", time: str = "2026-08-27"
) -> dict[str, str]:
    return {"local": local, "remote": remote, "time": time}


def history_output(*rows: object) -> str:
    return json.dumps({"migrations": list(rows), "message": "Migrations listed"})


def dry_run_output(*, omit: str | None = None, **overrides: object) -> str:
    payload: dict[str, object] = {
        "upToDate": True,
        "dryRun": True,
        "migrations": [],
        "seeds": [],
        "roles": [],
        "message": "Finished supabase db push.",
    }
    payload.update(overrides)
    if omit:
        del payload[omit]
    return json.dumps(payload)


def test_repository_migrations_are_valid_and_legacy_is_immutable() -> None:
    migrations = load_migrations(REPOSITORY_ROOT / "supabase" / "migrations")
    content = migrations[0].path.read_bytes().replace(b"\r\n", b"\n")

    assert [item.path.name for item in migrations] == [
        LEGACY_MIGRATION_NAME,
        PR10_MIGRATION_NAME,
    ]
    assert legacy_sha256(content) == LEGACY_MIGRATION_SHA256
    assert legacy_sha256(content.replace(b"\n", b"\r\n")) == LEGACY_MIGRATION_SHA256


def test_pr10_migration_is_additive_private_and_unseeded() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR10_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())

    for schema in (
        "evidence",
        "registry",
        "reported",
        "semantic",
        "metrics",
        "audit",
        "serving",
    ):
        assert f"create schema {schema};" in normalized
        assert f"create schema if not exists {schema}" not in normalized
        assert f"revoke all privileges on schema {schema} from public, anon, authenticated;" in (
            normalized
        )

    assert "create table registry.measurement_units" in normalized
    assert "create table registry.reporting_scopes" in normalized
    assert "create table registry.reporting_scope_versions" in normalized
    assert "default gen_random_uuid()" in normalized
    assert "uuidv7" not in normalized
    assert "float" not in normalized
    assert "insert into" not in normalized
    assert "create schema if not exists" not in normalized
    assert forbidden_operations(migration_text) == []

    for protected_object in (
        "core.",
        "ops.",
        "analytics.",
        "public.bank_metrics",
        "public.regulatory_bank_metrics_v1",
    ):
        assert protected_object not in normalized


def test_pr10_reporting_scope_versions_preserve_stable_identity() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR10_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    identity_definition = normalized.split(
        "create table registry.reporting_scopes (", 1
    )[1].split(");", 1)[0]
    version_definition = normalized.split(
        "create table registry.reporting_scope_versions (", 1
    )[1].split(");", 1)[0]

    assert "reporting_scope_id uuid primary key" in identity_definition
    assert "scope_code text not null unique" in identity_definition
    assert "definition_version" not in identity_definition
    assert "definition_snapshot" not in identity_definition

    assert "reporting_scope_version_id uuid primary key" in version_definition
    assert "references registry.reporting_scopes(reporting_scope_id)" in version_definition
    assert "unique (reporting_scope_id, definition_version)" in version_definition
    assert "unique (reporting_scope_id)" not in version_definition
    assert "scope_code" not in version_definition
    for approved_check in (
        "check (definition_version > 0)",
        "check (btrim(label) <> '')",
        "check (btrim(definition) <> '')",
        "check (btrim(rationale) <> '')",
        "check (lifecycle in ('draft', 'active', 'review_required', 'retired'))",
        "check (jsonb_typeof(definition_snapshot) = 'object')",
        "check (definition_hash ~ '^[a-f0-9]{64}$')",
        "check (git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')",
    ):
        assert approved_check in version_definition
    assert "cascade" not in version_definition
    assert "on delete" not in version_definition
    assert "on update" not in version_definition


@pytest.mark.parametrize(
    "filenames, expected_error",
    [
        (
            ["20260827010101_first.sql", "20260827010101_second.sql"],
            "duplicate migration versions",
        ),
        (
            [LEGACY_MIGRATION_NAME, "20260825000100_conflict.sql"],
            "ambiguous migration ordering",
        ),
        (["notes.txt"], "invalid migration filename"),
        (["20260827010101_Bad-Name.sql"], "invalid migration filename"),
        (["20261327010101_impossible_month.sql"], "invalid migration filename"),
    ],
)
def test_repository_validation_rejects_collisions_and_invalid_names(
    tmp_path: Path, filenames: list[str], expected_error: str
) -> None:
    for filename in filenames:
        (tmp_path / filename).write_text("select 1;\n", encoding="utf-8")

    with pytest.raises(MigrationValidationError, match=expected_error):
        load_migrations(tmp_path, verify_legacy=False)


@pytest.mark.parametrize(
    ("payload", "expected_error"),
    [
        ("{", "Invalid migration list JSON"),
        ("[]", "root must be an object"),
        (json.dumps({}), "missing `migrations`"),
        (json.dumps({"migrations": {}}), "`migrations` must be a list"),
        (history_output({"local": "x"}), "missing `remote`"),
        (history_output({"remote": "x", "time": "x"}), "missing `local`"),
        (history_output({"local": "x", "remote": "x"}), "missing `time`"),
        (history_output({"local": 1, "remote": "", "time": "x"}), "`local` must"),
        (history_output({"local": "", "remote": 1, "time": "x"}), "`remote` must"),
        (history_output({"local": "x", "remote": "", "time": 1}), "`time` must"),
        (history_output({"local": "", "remote": "", "time": "x"}), "no local"),
        (history_output(1), "row 0 must be an object"),
    ],
)
def test_history_parser_rejects_malformed_json_schema(
    payload: str, expected_error: str
) -> None:
    with pytest.raises(MigrationValidationError, match=expected_error):
        parse_history_json(payload)


@pytest.mark.parametrize(
    ("versions", "row_versions", "pending_versions", "expected_error"),
    [
        (["01"], [("01", "01")], [], None),
        (["01", "02"], [("01", "01"), ("02", "")], ["02"], None),
        (["01", "02", "03"], [("01", "01"), ("02", ""), ("03", "")],
         ["02", "03"], None),
        ([], [("", "02")], [], "missing locally"),
        (["01"], [("01", "01"), ("", "02")], [], "missing locally"),
        (["01", "02", "03"], [("01", "01"), ("02", ""), ("03", "03")],
         [], "has a gap"),
        (["01"], [("01", "")], [], "no trusted common baseline"),
        (["01", "02", "03"], [("01", "01"), ("02", "02"), ("03", "03")],
         [], None),
    ],
    ids=("aligned", "one-pending", "multiple-pending", "remote-only",
         "remote-extra", "inserted-local", "empty-remote", "multiple-aligned"),
)
def test_history_contract_matrix(
    tmp_path: Path,
    versions: list[str],
    row_versions: list[tuple[str, str]],
    pending_versions: list[str],
    expected_error: str | None,
) -> None:
    prefix = "202608270101"
    migrations = [migration(tmp_path, prefix + version) for version in versions]
    rows = parse_history_json(
        history_output(
            *(history_row(prefix + local if local else "", prefix + remote if remote else "")
              for local, remote in row_versions)
        )
    )

    if expected_error:
        with pytest.raises(MigrationValidationError, match=expected_error):
            validate_history(rows, migrations, require_aligned=False)
    else:
        pending = validate_history(rows, migrations, require_aligned=False)
        assert [item.version for item in pending] == [prefix + item for item in pending_versions]
        if not pending:
            assert validate_history(rows, migrations, require_aligned=True) == []


def test_remote_only_history_cli_gate_fails_without_pending_output(tmp_path: Path) -> None:
    history_path = tmp_path / "migration-history.json"
    history_path.write_text(
        history_output(
            history_row("202608250001", "202608250001"),
            history_row("", "202608260001"),
        ),
        encoding="utf-8",
    )
    pending_path = tmp_path / "pending-migrations.txt"
    arguments = [
        "--migrations-dir",
        str(REPOSITORY_ROOT / "supabase" / "migrations"),
        "history",
        "--input",
        str(history_path),
        "--pending-output",
        str(pending_path),
    ]

    assert main(arguments) == 1
    assert not pending_path.exists()


def test_post_push_history_requires_full_alignment(tmp_path: Path) -> None:
    migrations = [
        migration(tmp_path, "202608250001", "initial"),
        migration(tmp_path, "20260827010101"),
    ]
    rows = parse_history_json(
        history_output(
            history_row("202608250001", "202608250001"),
            history_row("20260827010101", ""),
        )
    )

    with pytest.raises(MigrationValidationError, match="Post-deploy migration history"):
        validate_history(rows, migrations, require_aligned=True)


@pytest.mark.parametrize(
    "sql",
    [
        "create table example (id bigint);",
        "create view example_view as select 1;",
        "create index example_idx on example (id);",
        "alter table example add column label text;",
        "create policy read_example on example for select using (true);",
        "comment on table example is 'safe';",
        "grant select on example to authenticated;",
        "select 'DROP TABLE example';",
        "select $$DROP TABLE example$$;",
        "-- DROP TABLE example\nselect 1;",
        "/* DROP SCHEMA public; */ select 1;",
    ],
)
def test_sql_safety_allows_additive_statements_comments_and_strings(sql: str) -> None:
    assert forbidden_operations(sql) == []


@pytest.mark.parametrize(
    ("sql", "operation"),
    [
        ("drop table example;", "DROP TABLE"),
        ("DrOp ScHeMa private;", "DROP SCHEMA"),
        ("truncate table example;", "TRUNCATE"),
        ("alter table example drop column label;", "ALTER TABLE DROP COLUMN"),
        (
            "alter table example drop constraint example_pkey;",
            "ALTER TABLE DROP CONSTRAINT",
        ),
        ("drop materialized view example_view;", "DROP VIEW"),
        ("drop type example_type;", "DROP TYPE"),
        ("drop domain example_domain;", "DROP DOMAIN"),
        ("drop function example();", "DROP FUNCTION"),
        ("drop policy read_example on example;", "DROP POLICY"),
        ("delete from example;", "DELETE"),
        ("alter table example rename to old_example;", "destructive RENAME"),
    ],
)
def test_sql_safety_rejects_destructive_operations(sql: str, operation: str) -> None:
    assert operation in forbidden_operations(sql)


def test_sql_safety_checks_multiple_statements_after_stripping_literals() -> None:
    operations = forbidden_operations(
        "select 'drop table harmless'; create table safe (id bigint); DROP TABLE unsafe;"
    )

    assert operations == ["DROP TABLE"]


def test_dry_run_plan_must_match_pending_suffix(tmp_path: Path) -> None:
    pending = [
        migration(tmp_path, "20260827010101"),
        migration(tmp_path, "20260827010201"),
    ]
    expected = [item.path.name for item in pending]

    validate_dry_run(dry_run_output(upToDate=False, migrations=expected), pending)

    for mismatched in (expected[:-1], [*expected, "extra.sql"], list(reversed(expected))):
        with pytest.raises(MigrationValidationError, match="does not match"):
            validate_dry_run(
                dry_run_output(upToDate=False, migrations=mismatched), pending
            )


def test_post_push_dry_run_must_be_a_no_op() -> None:
    validate_dry_run(dry_run_output(), [])

    with pytest.raises(MigrationValidationError, match="inconsistent"):
        validate_dry_run(dry_run_output(upToDate=False), [])


@pytest.mark.parametrize(
    ("payload", "expected_error"),
    [
        ("{", "Invalid db push --dry-run JSON"),
        ("[]", "root must be an object"),
        (dry_run_output(omit="dryRun"), "missing `dryRun`"),
        (dry_run_output(dryRun=False), "`dryRun` must be true"),
        (dry_run_output(omit="upToDate"), "missing `upToDate`"),
        (
            dry_run_output(upToDate="yes"),
            "`upToDate` must be a boolean",
        ),
        (dry_run_output(migrations={}), "`migrations` must be a list"),
        (dry_run_output(upToDate=False, migrations=[1]), "contain only strings"),
        (dry_run_output(seeds=["seed.sql"]), "unexpected seeds"),
        (dry_run_output(roles=["roles.sql"]), "unexpected roles"),
    ],
)
def test_dry_run_rejects_malformed_json_schema(
    payload: str, expected_error: str
) -> None:
    with pytest.raises(MigrationValidationError, match=expected_error):
        validate_dry_run(payload, [])
