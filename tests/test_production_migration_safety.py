import hashlib
import importlib.util
import json
import re
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
PR10_MIGRATION_SHA256 = (
    "85cfae07f2999abaafbb22d5a97374dd19cbe824b228bd8b0319463d164b5274"
)
PR11_MIGRATION_NAME = "20260828164124_evidence_catalog_schema.sql"
PR11_MIGRATION_SHA256 = (
    "7ff9299eeba5d7571a957625da7e9216db13b43d02b10566aaf5975b879fe568"
)
PR13_MIGRATION_NAME = "20260830234552_ingestion_run_lifecycle.sql"
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
    pr10_content = migrations[1].path.read_bytes().replace(b"\r\n", b"\n")
    pr11_content = migrations[2].path.read_bytes().replace(b"\r\n", b"\n")

    assert [item.path.name for item in migrations] == [
        LEGACY_MIGRATION_NAME,
        PR10_MIGRATION_NAME,
        PR11_MIGRATION_NAME,
        PR13_MIGRATION_NAME,
    ]
    assert legacy_sha256(content) == LEGACY_MIGRATION_SHA256
    assert legacy_sha256(content.replace(b"\n", b"\r\n")) == LEGACY_MIGRATION_SHA256
    assert hashlib.sha256(pr10_content).hexdigest() == PR10_MIGRATION_SHA256
    assert hashlib.sha256(pr11_content).hexdigest() == PR11_MIGRATION_SHA256


def test_migration_smoke_fails_closed_and_allows_only_pr13_audit_relations() -> None:
    smoke_text = (
        REPOSITORY_ROOT / "supabase" / "tests" / "migration_smoke.sql"
    ).read_text(encoding="utf-8")
    normalized = " ".join(smoke_text.lower().split())

    assert r"\quit 1" not in smoke_text
    conditional_blocks = re.findall(
        r"(?ms)^\\if\s+:[^\r\n]+\r?\n(.*?)^\\endif\s*$", smoke_text
    )
    assert len(conditional_blocks) == len(
        re.findall(r"(?m)^\\if\s+:[^\r\n]+$", smoke_text)
    )
    for block in conditional_blocks:
        assert r"\else" in block
        failure_branch = block.split(r"\else", 1)[1].lower()
        assert "do $$" in failure_branch
        assert "raise exception" in failure_branch

    assert normalized.count(
        "where namespace.nspname in ('reported', 'semantic', 'metrics', 'serving')"
    ) >= 1
    assert (
        "where namespace.nspname in "
        "('reported', 'semantic', 'metrics', 'audit', 'serving')"
    ) not in normalized
    assert (
        "where later_namespace.nspname in "
        "('reported', 'semantic', 'metrics', 'audit', 'serving')"
    ) not in normalized

    audit_boundary = normalized.split("), audit_boundary_gate as (", 1)[1].split(
        "), legacy_table_gate as (", 1
    )[0]
    assert "count(*) = 3" in audit_boundary
    for expected_relation in (
        "('ingestion_runs', 'r')",
        "('ingestion_run_artifacts', 'r')",
        "('ingestion_run_artifacts_ingestion_run_artifact_id_seq', 's')",
    ):
        assert expected_relation in audit_boundary
    assert "bool_and((relation.relname, relation.relkind::text) in" in audit_boundary
    assert "where namespace.nspname = 'audit'" in audit_boundary
    assert "do $ declare" not in normalized


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


def test_pr11_migration_is_additive_private_unseeded_and_in_scope() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR11_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    expected_tables = (
        "regulators",
        "sources",
        "source_definition_versions",
        "source_releases",
        "source_artifacts",
    )

    assert normalized.count("create table evidence.") == len(expected_tables)
    for table_name in expected_tables:
        assert f"create table evidence.{table_name} (" in normalized
        assert f"alter table evidence.{table_name} enable row level security;" in normalized

    assert forbidden_operations(migration_text) == []
    assert "insert into" not in normalized
    assert "create policy" not in normalized
    assert "storage." not in normalized
    assert "regulatory-artifacts" not in normalized
    assert "audit.ingestion_runs" not in normalized
    assert "audit.ingestion_run_artifacts" not in normalized
    assert "public.regulatory_bank_metrics_v1" not in normalized
    assert "seed" not in normalized
    assert "create role " not in normalized
    assert "alter role " not in normalized
    for protected_schema in ("core.", "ops.", "analytics."):
        assert protected_schema not in normalized

    assert "create index source_releases_supersedes_idx" in normalized
    assert "create index source_artifacts_sha256_idx" in normalized
    assert normalized.count("create index ") == 2


def test_pr11_preserves_source_identity_and_immutable_definition_versions() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR11_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    identity_definition = normalized.split(
        "create table evidence.sources (", 1
    )[1].split(");", 1)[0]
    version_definition = normalized.split(
        "create table evidence.source_definition_versions (", 1
    )[1].split(");", 1)[0]

    assert "source_id uuid primary key default gen_random_uuid()" in identity_definition
    assert "regulator_id uuid not null" in identity_definition
    assert "source_code text not null unique" in identity_definition
    for version_only_column in (
        "definition_version",
        "adapter_key",
        "methodological_role",
        "lifecycle",
        "definition_snapshot",
        "config_hash",
        "git_sha",
    ):
        assert version_only_column not in identity_definition

    assert "source_definition_version_id uuid primary key default gen_random_uuid()" in (
        version_definition
    )
    assert "references evidence.sources(source_id)" in version_definition
    assert "unique (source_id, definition_version)" in version_definition
    assert "unique (source_id)" not in version_definition
    for approved_check in (
        "check (definition_version > 0)",
        "check (country ~ '^[a-z]{2}$')",
        "check (methodological_role in ( 'primary', 'reconciliation', "
        "'authoritative_icap' ))",
        "check (lifecycle in ('draft', 'active', 'review_required', 'retired'))",
        "check (jsonb_typeof(definition_snapshot) = 'object')",
        "check (config_hash ~ '^[a-f0-9]{64}$')",
        "check (git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')",
    ):
        assert approved_check in version_definition
    assert "active boolean" not in version_definition


def test_pr11_keeps_logical_releases_separate_from_exact_artifacts() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR11_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    release_definition = normalized.split(
        "create table evidence.source_releases (", 1
    )[1].split(");", 1)[0]
    artifact_definition = normalized.split(
        "create table evidence.source_artifacts (", 1
    )[1].split(");", 1)[0]

    assert "unique (source_id, release_family_key, release_identity_hash)" in (
        release_definition
    )
    assert "unique (source_release_id, source_id, release_family_key)" in (
        release_definition
    )
    assert "references evidence.source_releases( source_release_id, source_id, " in (
        release_definition
    )
    assert "covered_period_start is null and covered_period_end is null" in release_definition
    assert "covered_period_start is not null" in release_definition
    assert "covered_period_end is not null" in release_definition
    assert "covered_period_start <= covered_period_end" in release_definition
    assert "default" not in release_definition.split("first_observed_at", 1)[1].split(",", 1)[0]
    for artifact_only_column in (
        "filename",
        "original_url",
        "final_url",
        "mime_type",
        "byte_length",
        "artifact_role",
        "storage_backend",
        "storage_key",
    ):
        assert artifact_only_column not in release_definition

    assert "unique (source_release_id, artifact_role, sha256)" in artifact_definition
    assert "unique (sha256)" not in artifact_definition
    assert "sha256 text not null unique" not in artifact_definition
    assert "references evidence.source_releases(source_release_id)" in artifact_definition
    for release_only_column in (
        "release_family_key",
        "revision",
        "covered_period_start",
        "covered_period_end",
        "published_at",
        "release_identity_hash",
        "supersedes_source_release_id",
    ):
        assert release_only_column not in artifact_definition
    assert "default" not in artifact_definition.split("first_observed_at", 1)[1].split(",", 1)[0]


def test_pr13_migration_is_additive_private_unseeded_and_in_scope() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR13_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())

    assert normalized.count("create table audit.") == 2
    assert "create table audit.ingestion_runs (" in normalized
    assert "create table audit.ingestion_run_artifacts (" in normalized
    assert "alter table audit.ingestion_runs enable row level security;" in normalized
    assert (
        "alter table audit.ingestion_run_artifacts enable row level security;" in normalized
    )
    assert forbidden_operations(migration_text) == []
    assert "insert into" not in normalized
    assert "create policy" not in normalized
    assert "security definer" not in normalized
    assert "create role " not in normalized
    assert "alter role " not in normalized
    assert "cascade" not in normalized
    assert "on delete" not in normalized
    assert "on update" not in normalized

    for protected_schema in (
        "core.",
        "ops.",
        "analytics.",
        "registry.institutions",
        "reported.",
        "semantic.",
        "metrics.",
        "serving.",
        "public.regulatory_bank_metrics_v1",
    ):
        assert protected_schema not in normalized


def test_pr13_freezes_lifecycle_provenance_and_database_owned_summaries() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR13_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    run_definition = normalized.split(
        "create table audit.ingestion_runs (", 1
    )[1].split("create table audit.ingestion_run_artifacts (", 1)[0]

    assert "ingestion_run_id uuid primary key default gen_random_uuid()" in run_definition
    assert (
        "foreign key (source_id, source_definition_version) references "
        "evidence.source_definition_versions(source_id, definition_version)"
        in run_definition
    )
    assert "check (trigger_kind in ('manual', 'schedule', 'backfill', 'test'))" in (
        run_definition
    )
    assert "restart" not in run_definition.split(
        "constraint ingestion_runs_trigger_kind_valid", 1
    )[1].split(")", 1)[0]
    for status in ("pending", "running", "succeeded", "failed", "no_change"):
        assert f"'{status}'" in run_definition
    for counter in (
        "artifacts_observed_count",
        "artifacts_new_count",
        "artifacts_reused_count",
        "artifacts_revised_count",
        "artifacts_failed_count",
    ):
        assert f"{counter} bigint not null default 0" in run_definition

    assert "new.started_at := clock_timestamp()" in normalized
    assert "new.completed_at := clock_timestamp()" in normalized
    assert "terminal ingestion run is immutable" in normalized
    assert "invalid ingestion run status transition" in normalized
    assert "new.status in ('succeeded', 'failed', 'no_change')" in normalized
    assert "artifacts_failed_count = 0" not in normalized
    assert "artifacts_new_count > 0" not in normalized
    assert "artifacts_revised_count > 0" not in normalized


def test_pr13_artifact_invariants_and_append_only_contract_are_explicit() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR13_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    artifact_definition = normalized.split(
        "create table audit.ingestion_run_artifacts (", 1
    )[1].split("create function audit.enforce_ingestion_run_lifecycle()", 1)[0]

    assert "generated always as identity primary key" in artifact_definition
    assert "check (result in ('new', 'reused', 'revised', 'failed'))" in (
        artifact_definition
    )
    assert "unique (observed_url)" not in artifact_definition
    assert "headers json" not in artifact_definition
    assert "for update;" in normalized
    assert "artifact_source_id <> parent_source_id" in normalized
    assert "new.result = 'revised' and superseded_release_id is null" in normalized
    assert "new.result = 'new' and superseded_release_id is not null" in normalized
    assert "before update or delete on audit.ingestion_run_artifacts" in normalized
    assert "ingestion run artifact observations are append-only" in normalized


def test_pr13_indexes_and_runtime_grants_are_narrow() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR13_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    expected_indexes = (
        "ingestion_runs_source_created_idx",
        "ingestion_runs_status_created_idx",
        "ingestion_runs_restart_of_idx",
        "ingestion_run_artifacts_run_idx",
        "ingestion_run_artifacts_artifact_idx",
    )

    assert normalized.count("create index ") == len(expected_indexes)
    for index_name in expected_indexes:
        assert f"create index {index_name}" in normalized

    assert "grant select on audit.ingestion_runs to service_role;" in normalized
    assert "grant update (status, error_code, error_summary)" in normalized
    assert "grant select on audit.ingestion_run_artifacts to service_role;" in normalized
    assert "grant usage on sequence" in normalized
    assert "grant update on audit.ingestion_runs" not in normalized
    assert "grant update on audit.ingestion_run_artifacts" not in normalized
    assert "grant delete" not in normalized
    assert "grant truncate" not in normalized
    assert "grant references" not in normalized
    assert "grant trigger" not in normalized


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
