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
PR13_MIGRATION_SHA256 = (
    "ca882b04bb36a646afd5aefae9a76ada34e657070ce355e81425e84b28eaac2b"
)
PR14_MIGRATION_NAME = "20260916202900_institution_identity_schema.sql"
PR15_MIGRATION_NAME = "20260919143000_reported_fact_schema.sql"
PR15A_MIGRATION_NAME = "20260919180000_review_decision_events.sql"
PR16_MIGRATION_NAME = "20260922120000_fact_current_as_of_queries.sql"
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

    pr13_content = migrations[3].path.read_bytes().replace(b"\r\n", b"\n")
    pr14_content = migrations[4].path.read_bytes().replace(b"\r\n", b"\n")
    pr15_content = migrations[5].path.read_bytes().replace(b"\r\n", b"\n")
    pr15a_content = migrations[6].path.read_bytes().replace(b"\r\n", b"\n")
    pr16_content = migrations[7].path.read_bytes().replace(b"\r\n", b"\n")

    assert [item.path.name for item in migrations] == [
        LEGACY_MIGRATION_NAME,
        PR10_MIGRATION_NAME,
        PR11_MIGRATION_NAME,
        PR13_MIGRATION_NAME,
        PR14_MIGRATION_NAME,
        PR15_MIGRATION_NAME,
        PR15A_MIGRATION_NAME,
        PR16_MIGRATION_NAME,
    ]
    assert len(migrations) == 8
    assert legacy_sha256(content) == LEGACY_MIGRATION_SHA256
    assert legacy_sha256(content.replace(b"\n", b"\r\n")) == LEGACY_MIGRATION_SHA256
    assert hashlib.sha256(pr10_content).hexdigest() == PR10_MIGRATION_SHA256
    assert hashlib.sha256(pr11_content).hexdigest() == PR11_MIGRATION_SHA256
    assert hashlib.sha256(pr13_content).hexdigest() == PR13_MIGRATION_SHA256
    assert "create table registry.institutions" in pr14_content.decode("utf-8")
    assert "create table reported.reported_facts" in pr15_content.decode("utf-8")
    assert "create table audit.review_decisions" in pr15a_content.decode("utf-8")
    assert "create view serving.current_observed_facts" in pr16_content.decode("utf-8")
    assert PR15A_MIGRATION_NAME > PR15_MIGRATION_NAME
    assert PR16_MIGRATION_NAME > PR15A_MIGRATION_NAME


def test_migration_smoke_fails_closed_and_allows_only_approved_audit_relations() -> None:
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

    assert "where namespace.nspname in ('semantic', 'metrics')" in normalized
    assert "where namespace.nspname in ('semantic', 'metrics', 'serving')" not in normalized
    assert "('reported_fact_revision_ancestry', 'v')" in normalized
    assert "('current_observed_facts', 'v')" in normalized
    assert "('current_publishable_facts', 'v')" in normalized
    assert (
        "where namespace.nspname in "
        "('reported', 'semantic', 'metrics', 'audit', 'serving')"
    ) not in normalized
    assert (
        "where later_namespace.nspname in "
        "('reported', 'semantic', 'metrics', 'audit', 'serving')"
    ) not in normalized
    assert "('reported_facts', 'r')" in normalized
    assert "('reported_facts_reported_fact_id_seq', 's')" in normalized

    expected_audit_relations = (
        "('ingestion_runs', 'r')",
        "('ingestion_run_artifacts', 'r')",
        "('ingestion_run_artifacts_ingestion_run_artifact_id_seq', 's')",
        "('review_decisions', 'r')",
        "('review_decisions_review_decision_id_seq', 's')",
        "('effective_review_decisions', 'v')",
    )
    audit_boundary = normalized.split("), audit_boundary_gate as (", 1)[1].split(
        "), legacy_table_gate as (", 1
    )[0]
    assert "count(*) = 6" in audit_boundary
    for expected_relation in expected_audit_relations:
        assert expected_relation in audit_boundary
    assert "to_regclass('audit.quality_issues') is null" in audit_boundary
    assert "bool_and((relation.relname, relation.relkind::text) in" in audit_boundary
    assert "where namespace.nspname = 'audit'" in audit_boundary

    evidence_boundary = normalized.split("), evidence_boundary_gate as (", 1)[1].split(
        "), legacy_table_gate as (", 1
    )[0]
    nested_audit_inventory = evidence_boundary.split(
        "from pg_catalog.pg_class audit_relation", 1
    )[0].rsplit("select", 1)[1]
    assert "count(*) = 6" in nested_audit_inventory
    assert "count(*) = 3" not in nested_audit_inventory
    for expected_relation in expected_audit_relations:
        assert expected_relation in nested_audit_inventory
    assert "count(*) = 5" in evidence_boundary
    assert "to_regclass('public.regulatory_bank_metrics_v1') is null" in evidence_boundary

    pr14_boundary = normalized.split("), pr14_boundary_gate as (", 1)[1].split(
        ") select", 1
    )[0]
    assert "to_regclass('audit.review_decisions') is not null" in pr14_boundary
    assert re.search(
        r"to_regclass\('audit.review_decisions'\) is null\b", pr14_boundary
    ) is None
    assert "to_regclass('audit.quality_issues') is null" in pr14_boundary
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


def test_pr14_migration_is_additive_private_unseeded_and_in_scope() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR14_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    expected_tables = (
        "institutions",
        "institution_definition_versions",
        "regulatory_registrations",
        "institution_aliases",
        "institution_cohorts",
        "regulatory_concepts",
        "regulatory_concept_scopes",
    )

    assert normalized.count("create table registry.") == len(expected_tables)
    for table_name in expected_tables:
        assert f"create table registry.{table_name} (" in normalized
        assert f"alter table registry.{table_name} enable row level security;" in normalized

    assert "create extension if not exists btree_gist with schema extensions;" in (
        normalized
    )
    assert normalized.count("create extension") == 1
    assert "with schema public" not in normalized
    assert "set local search_path" in normalized
    assert "set search_path =" not in normalized.replace("set local search_path", "")

    assert forbidden_operations(migration_text) == []
    assert "insert into" not in normalized
    assert "create policy" not in normalized
    assert "security definer" not in normalized
    assert "create role " not in normalized
    assert "alter role " not in normalized
    assert "cascade" not in normalized
    assert "on delete" not in normalized
    assert "on update" not in normalized
    assert "create function" not in normalized
    assert "grant insert" not in normalized
    assert "grant update" not in normalized
    assert "grant delete" not in normalized
    assert "grant select" in normalized

    for protected_schema in (
        "core.",
        "ops.",
        "analytics.",
        "reported.",
        "semantic.",
        "metrics.",
        "serving.",
        "public.regulatory_bank_metrics_v1",
    ):
        assert protected_schema not in normalized


def test_pr14_identity_versions_and_projection_invariants() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR14_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    identity_definition = normalized.split(
        "create table registry.institutions (", 1
    )[1].split(");", 1)[0]
    version_definition = normalized.split(
        "create table registry.institution_definition_versions (", 1
    )[1].split(");", 1)[0]
    registration_definition = normalized.split(
        "create table registry.regulatory_registrations (", 1
    )[1].split(");", 1)[0]
    alias_definition = normalized.split(
        "create table registry.institution_aliases (", 1
    )[1].split(");", 1)[0]
    concept_definition = normalized.split(
        "create table registry.regulatory_concepts (", 1
    )[1].split(");", 1)[0]

    assert "institution_id uuid primary key default gen_random_uuid()" in (
        identity_definition
    )
    assert "institution_code text not null unique" in identity_definition
    assert "country text not null" in identity_definition
    for version_only_column in (
        "canonical_label",
        "lifecycle",
        "provenance",
        "definition_snapshot",
        "definition_hash",
        "git_sha",
    ):
        assert version_only_column not in identity_definition

    assert "unique (institution_id, definition_version)" in version_definition
    assert "unique (institution_definition_version_id, institution_id)" in (
        version_definition
    )
    assert "check (jsonb_typeof(definition_snapshot) = 'object')" in version_definition

    assert "daterange(valid_from, valid_to, '[]')" in registration_definition
    assert "source_id" not in registration_definition
    assert (
        "foreign key (institution_definition_version_id, institution_id) "
        "references registry.institution_definition_versions"
    ) in registration_definition
    assert "exclude using gist" in registration_definition

    assert "normalized_alias text not null" in alias_definition
    assert "generated always as" not in alias_definition.split(
        "normalized_alias text not null", 1
    )[1].split("alias_type", 1)[0]
    assert "lower(" not in alias_definition
    assert "casefold" not in alias_definition
    assert "source_id uuid not null" in alias_definition

    assert "unique (source_id, external_code, definition_version)" in (
        concept_definition
    )
    assert "measurement_unit" not in concept_definition
    assert "data_nature" not in concept_definition
    assert "frequency" not in concept_definition
    assert "canonical_concept" not in normalized


def test_pr14_lookup_indexes_and_select_only_grants() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR14_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    expected_indexes = (
        "regulatory_registrations_lookup_idx",
        "institution_aliases_lookup_idx",
        "institution_cohorts_lookup_idx",
    )

    assert normalized.count("create index ") == len(expected_indexes)
    for index_name in expected_indexes:
        assert f"create index {index_name}" in normalized

    assert "grant select" in normalized
    assert "to service_role;" in normalized
    assert "grant insert" not in normalized
    assert "grant update" not in normalized
    assert "grant delete" not in normalized
    assert "grant truncate" not in normalized
    assert "grant references" not in normalized
    assert "grant trigger" not in normalized


def test_pr15_migration_is_additive_private_unseeded_and_in_scope() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR15_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())

    assert normalized.count("create table reported.") == 1
    assert "create table reported.reported_facts (" in normalized
    assert "alter table reported.reported_facts enable row level security;" in normalized
    assert "set local search_path" in normalized
    assert "set search_path =" not in normalized.replace("set local search_path", "")

    assert forbidden_operations(migration_text) == []
    assert "insert into" not in normalized
    assert "create policy" not in normalized
    assert "security definer" not in normalized
    assert "create role " not in normalized
    assert "alter role " not in normalized
    assert "cascade" not in normalized
    assert "on delete" not in normalized
    assert "on update" not in normalized
    assert "drop " not in normalized
    assert "truncate" not in normalized
    assert "core." not in normalized
    assert "ops." not in normalized
    assert "analytics." not in normalized
    assert "semantic." not in normalized
    assert "metrics." not in normalized
    assert "serving." not in normalized
    assert "public.regulatory_bank_metrics_v1" not in normalized
    assert "review_decisions" not in normalized
    assert "quality_issues" not in normalized
    assert "current_observed" not in normalized
    assert "current_publishable" not in normalized
    assert "float" not in normalized
    assert "double precision" not in normalized
    assert " real " not in f" {normalized} "
    assert "numeric(38,18)" not in normalized
    assert "text::bytea" not in normalized.replace(" ", "")
    assert "::bytea" not in normalized
    assert "generated always as (encode" not in normalized
    assert "generated always as identity primary key" in normalized
    assert "locator_hash text not null" in normalized
    assert "fact_key_hash text not null" in normalized
    assert "convert_to(" in normalized
    assert "'utf8'" in normalized
    assert "sha256(" in normalized
    assert "new.locator_hash :=" in normalized
    assert "new.fact_key_hash :=" in normalized
    assert "unique (predecessor_reported_fact_id)" not in normalized
    assert "unique (ingestion_run_id, source_artifact_id)" not in normalized
    assert "methodology_correction" not in normalized.split(
        "constraint reported_facts_supersession_reason_valid", 1
    )[1].split("constraint reported_facts_supersession_pair_valid", 1)[0]


def test_pr15_reported_facts_shape_hashes_and_narrow_grants() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR15_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    table_definition = normalized.split(
        "create table reported.reported_facts (", 1
    )[1].split("create function reported.prepare_reported_fact_insert()", 1)[0]

    assert "parsed_value numeric not null" in table_definition
    assert "parsed_value <> 'nan'::numeric" in table_definition
    assert "parsed_value <> 'infinity'::numeric" in table_definition
    assert "parsed_value <> '-infinity'::numeric" in table_definition
    assert "period_kind in ('instant', 'duration')" in table_definition
    assert "locator_kind in ('excel', 'csv', 'json', 'pdf')" in table_definition
    assert "references registry.measurement_units (unit_code)" in table_definition
    assert "unique (source_id, regulator_id)" in normalized
    assert "unique (source_release_id, source_id)" in normalized
    assert "unique (source_artifact_id, source_release_id)" in normalized
    assert "unique (regulatory_registration_id, regulator_id)" in normalized
    assert "unique (regulatory_concept_id, source_id)" in normalized
    assert "ingestion_runs_fact_provenance_key" in normalized
    assert (
        "unique ( source_artifact_id, locator_hash, source_definition_version, "
        "parser_implementation_key, parser_implementation_version, fact_key_hash )"
    ) in table_definition
    assert "ingestion_run_id" not in table_definition.split(
        "constraint reported_facts_extraction_identity_key", 1
    )[1].split("constraint reported_facts_source_definition_version_positive", 1)[0]
    assert "deferrable" not in normalized
    assert "create index using gin" not in normalized
    assert "gin (" not in normalized

    expected_indexes = (
        "reported_facts_predecessor_idx",
        "reported_facts_logical_observed_idx",
        "reported_facts_registration_lookup_idx",
    )
    assert normalized.count("create index ") == len(expected_indexes)
    for index_name in expected_indexes:
        assert f"create index {index_name}" in normalized
    assert "where predecessor_reported_fact_id is not null" in normalized

    assert "grant select on reported.reported_facts to service_role;" in normalized
    assert "grant insert (" in normalized
    granted_columns = {
        column.strip()
        for column in normalized.split("grant insert (", 1)[1]
        .split(") on reported.reported_facts to service_role;", 1)[0]
        .split(",")
        if column.strip()
    }
    assert "locator_hash" not in granted_columns
    assert "fact_key_hash" not in granted_columns
    assert "reported_fact_id" not in granted_columns
    assert "predecessor_reported_fact_id" in granted_columns
    assert "grant usage on sequence reported.reported_facts_reported_fact_id_seq" in (
        normalized
    )
    assert "grant update" not in normalized
    assert "grant delete" not in normalized
    assert "grant truncate" not in normalized
    assert "grant references" not in normalized
    assert "grant trigger" not in normalized
    assert "before insert on reported.reported_facts" in normalized
    assert "before update or delete on reported.reported_facts" in normalized
    assert "reported facts are append-only" in normalized


def test_pr15a_migration_is_additive_private_unseeded_and_in_scope() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR15A_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())

    assert normalized.count("create table ") == 1
    assert "create table audit.review_decisions (" in normalized
    assert "alter table audit.review_decisions enable row level security;" in normalized
    assert "set local search_path" in normalized
    assert "set search_path =" not in normalized.replace("set local search_path", "")

    assert forbidden_operations(migration_text) == []
    assert "insert into" not in normalized
    assert "create policy" not in normalized
    assert "security definer" not in normalized
    assert "create role " not in normalized
    assert "alter role " not in normalized
    assert "cascade" not in normalized
    assert "on delete" not in normalized
    assert "on update" not in normalized
    assert "drop " not in normalized
    assert "truncate" not in normalized
    assert "delete from" not in normalized
    assert "core." not in normalized
    assert "ops." not in normalized
    assert "analytics." not in normalized
    assert "semantic." not in normalized
    assert "metrics." not in normalized
    assert "serving." not in normalized
    assert "public.regulatory_bank_metrics_v1" not in normalized
    assert "float" not in normalized
    assert "double precision" not in normalized
    assert " real " not in f" {normalized} "

    for later_phase_object in (
        "quality_issues",
        "quality_issue_id",
        "current_observed",
        "current_publishable",
        "observed_as_of",
        "publishable_as_of",
        "review_status",
        "idempotency",
        "request_key",
        "bank_metrics",
    ):
        assert later_phase_object not in normalized


def test_pr15a_review_decision_timeline_actor_and_reason_contracts() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR15A_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    table_definition = normalized.split(
        "create table audit.review_decisions (", 1
    )[1].split("create function audit.enforce_review_decision_insert()", 1)[0]

    assert "review_decision_id bigint generated always as identity primary key" in (
        table_definition
    )
    assert "decided_at timestamptz not null," in table_definition
    assert "decided_at timestamptz not null default" not in table_definition
    assert "reason text not null," in table_definition
    assert "reason_code" not in table_definition
    assert "reason_detail" not in table_definition
    assert (
        "foreign key (reported_fact_id) references reported.reported_facts "
        "(reported_fact_id)"
    ) in table_definition
    assert "unique (review_decision_id, reported_fact_id)" in table_definition
    assert (
        "foreign key (corrects_review_decision_id, reported_fact_id) references "
        "audit.review_decisions ( review_decision_id, reported_fact_id )"
    ) in table_definition
    assert "unique (corrects_review_decision_id)" not in normalized
    assert "corrects_review_decision_id <> review_decision_id" in table_definition

    assert "decision in ('accept', 'reject', 'revoke')" in table_definition
    assert "actor_kind in ('human', 'system_policy')" in table_definition
    for actor_shape_clause in (
        "actor_kind = 'human' and human_actor_key is not null "
        "and policy_implementation_key is null "
        "and policy_implementation_version is null and policy_git_sha is null",
        "actor_kind = 'system_policy' and human_actor_key is null "
        "and policy_implementation_key is not null "
        "and policy_implementation_version is not null "
        "and policy_git_sha is not null",
    ):
        assert actor_shape_clause in table_definition
    assert "human_actor_key) <= 128" in table_definition
    assert "human_actor_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'" in table_definition
    assert (
        "policy_implementation_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'"
        in table_definition
    )
    assert "policy_implementation_version) <= 128" in table_definition
    assert "btrim(policy_implementation_version) <> ''" in table_definition
    assert (
        "policy_git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$'" in table_definition
    )
    assert r"\|" not in migration_text
    assert (
        "check ( btrim(reason) <> '' and char_length(reason) <= 512 "
        "and reason !~ '[[:cntrl:]]' )"
    ) in table_definition

    assert "new.decided_at > pg_catalog.clock_timestamp()" in normalized
    assert "pg_catalog.pg_advisory_xact_lock(new.reported_fact_id)" in normalized
    assert "hashtext" not in normalized
    assert "hashtextextended" not in normalized
    assert "order by head.decided_at desc, head.review_decision_id desc limit 1" in (
        normalized
    )
    assert (
        "(new.decided_at, new.review_decision_id) <= "
        "(head_decided_at, head_review_decision_id)"
    ) in normalized
    assert "new.decision = 'revoke' and head_decision is distinct from 'accept'" in (
        normalized
    )
    assert "before insert on audit.review_decisions" in normalized
    assert "before update or delete on audit.review_decisions" in normalized
    assert "review decisions are append-only" in normalized
    assert "now()" not in normalized


def test_pr15a_query_surface_indexes_and_grants_are_narrow() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR15A_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())

    assert normalized.count("create view ") == 1
    assert (
        "create view audit.effective_review_decisions with (security_invoker = true) as"
        in normalized
    )
    assert "distinct on (decision_event.reported_fact_id)" in normalized
    assert (
        "create function audit.effective_review_decisions_as_of"
        "(decision_cutoff timestamptz)" in normalized
    )
    assert "language sql stable" in normalized
    assert "decision_event.decided_at <= decision_cutoff" in normalized
    assert normalized.count(
        "decision_event.reported_fact_id, decision_event.decided_at desc, "
        "decision_event.review_decision_id desc"
    ) == 2

    expected_indexes = (
        "review_decisions_fact_timeline_idx",
        "review_decisions_corrects_idx",
    )
    assert normalized.count("create index ") == len(expected_indexes)
    assert "create unique index" not in normalized
    for index_name in expected_indexes:
        assert f"create index {index_name}" in normalized
    assert (
        "on audit.review_decisions ( reported_fact_id, decided_at desc, "
        "review_decision_id desc )" in normalized
    )
    assert "where corrects_review_decision_id is not null" in normalized
    assert "gin (" not in normalized
    assert "partition" not in normalized

    assert "grant select on audit.review_decisions to service_role;" in normalized
    granted_columns = {
        column.strip()
        for column in normalized.split("grant insert (", 1)[1]
        .split(") on audit.review_decisions to service_role;", 1)[0]
        .split(",")
        if column.strip()
    }
    assert granted_columns == {
        "reported_fact_id",
        "decision",
        "decided_at",
        "actor_kind",
        "human_actor_key",
        "policy_implementation_key",
        "policy_implementation_version",
        "policy_git_sha",
        "reason",
        "corrects_review_decision_id",
    }
    assert "review_decision_id" not in granted_columns
    assert (
        "grant usage on sequence audit.review_decisions_review_decision_id_seq "
        "to service_role;" in normalized
    )
    assert (
        "grant select on audit.effective_review_decisions to service_role;"
        in normalized
    )
    assert (
        "grant execute on function "
        "audit.effective_review_decisions_as_of(timestamptz) to service_role;"
        in normalized
    )
    assert "grant update" not in normalized
    assert "grant delete" not in normalized
    assert "grant truncate" not in normalized
    assert "grant references" not in normalized
    assert "grant trigger" not in normalized
    for revoked_role_list in (
        "revoke all privileges on audit.review_decisions "
        "from public, anon, authenticated, service_role;",
        "revoke all privileges on sequence "
        "audit.review_decisions_review_decision_id_seq "
        "from public, anon, authenticated, service_role;",
        "revoke all privileges on audit.effective_review_decisions "
        "from public, anon, authenticated, service_role;",
    ):
        assert revoked_role_list in normalized
    assert (
        "revoke all privileges on function audit.enforce_review_decision_insert(), "
        "audit.reject_review_decision_mutation() "
        "from public, anon, authenticated, service_role;" in normalized
    )
    assert (
        "revoke all privileges on function "
        "audit.effective_review_decisions_as_of(timestamptz) "
        "from public, anon, authenticated, service_role;" in normalized
    )


def test_pr15a_smoke_freezes_timeline_revoke_and_idempotency_boundaries() -> None:
    smoke_text = (
        REPOSITORY_ROOT / "supabase" / "tests" / "migration_smoke.sql"
    ).read_text(encoding="utf-8")
    normalized = " ".join(smoke_text.lower().split())

    for required_gate in (
        "pr15a_columns_gate",
        "pr15a_identity_gate",
        "pr15a_relationship_gate",
        "pr15a_check_gate",
        "pr15a_vocabulary_gate",
        "pr15a_index_gate",
        "pr15a_object_gate",
        "pr15a_access_gate",
        "pr15a_boundary_gate",
        "pr15a_behavior_passed",
        "pr15a_rollback_passed",
    ):
        assert required_gate in normalized

    assert "to_regclass('audit.review_decisions') is not null" in normalized
    assert "to_regclass('audit.quality_issues') is null" in normalized
    assert "security_invoker=true" in normalized
    assert "effective_review_decisions_as_of(pg_catalog.clock_timestamp())" in normalized
    assert "effective_review_decisions_as_of(now())" not in normalized
    assert "'approve'" in normalized
    assert "first-event revoke was accepted" in normalized
    assert "revoke after reject was accepted" in normalized
    assert "revoke after revoke was accepted" in normalized
    assert "revoke after accept then reject was accepted" in normalized
    assert "future decided_at was accepted" in normalized
    assert "decision behind the current head was accepted" in normalized
    assert "backdated correction behind the current head was accepted" in normalized
    assert "cross-fact correction was accepted" in normalized
    assert "self-correction was accepted" in normalized
    assert "sibling successor c is also accepted" in normalized
    assert "service_role updated a review decision" in normalized
    assert "service_role deleted a review decision" in normalized
    assert "table-owner update of a review decision was accepted" in normalized
    assert "table-owner delete of a review decision was accepted" in normalized


def test_pr16_migration_is_private_forward_only_query_semantics() -> None:
    migration_text = (
        REPOSITORY_ROOT / "supabase" / "migrations" / PR16_MIGRATION_NAME
    ).read_text(encoding="utf-8")
    normalized = " ".join(migration_text.lower().split())
    smoke_text = (
        REPOSITORY_ROOT / "supabase" / "tests" / "migration_smoke.sql"
    ).read_text(encoding="utf-8")
    smoke_normalized = " ".join(smoke_text.lower().split())

    assert normalized.count("create view ") == 3
    assert normalized.count("create function ") == 2
    assert normalized.count("with (security_invoker = true)") == 3
    assert normalized.count("language sql stable") == 2
    assert "create view serving.reported_fact_revision_ancestry" in normalized
    assert "create view serving.current_observed_facts" in normalized
    assert "create view serving.current_publishable_facts" in normalized
    assert "create function serving.observed_facts_as_of(cutoff timestamptz)" in normalized
    assert "create function serving.publishable_facts_as_of(cutoff timestamptz)" in normalized
    assert "create view serving.current " not in normalized
    assert "create view serving.current(" not in normalized
    assert "with recursive" in normalized
    assert "union all" in normalized
    assert "generations > 0" in normalized
    assert "generations <" not in normalized
    for depth_ceiling in ("< 32", "< 64", "< 128", "< 256"):
        assert depth_ceiling not in normalized
    assert " cycle " not in f" {normalized} "
    assert "group by fact_key_hash" not in normalized
    assert "group by fact.fact_key_hash" not in normalized
    assert "order by" not in normalized
    assert "corrects_review_decision_id" not in normalized
    assert "now()" not in normalized
    assert "clock_timestamp()" not in normalized
    assert normalized.count("ancestor.first_observed_at > cutoff") == 2
    assert normalized.count("fact.first_observed_at <= cutoff") == 2
    assert normalized.count("cutoff is not null") == 2
    assert "cutoff_eligible_facts" in normalized
    assert "eligible_child" in normalized
    assert "eligible_descendant" in normalized
    assert "audit.effective_review_decisions " in normalized
    assert "audit.effective_review_decisions_as_of(cutoff)" in normalized
    assert "decision = 'accept'" in normalized
    assert "having count(*) = 1" in normalized
    assert " strict" not in normalized
    assert "security definer" not in normalized
    assert "create table " not in normalized
    assert "create index " not in normalized
    assert "create policy " not in normalized
    assert "create materialized view " not in normalized
    assert "insert into" not in normalized
    assert "create role " not in normalized
    assert "alter role " not in normalized
    assert forbidden_operations(migration_text) == []
    for protected_token in (
        "core.",
        "ops.",
        "analytics.",
        "semantic.",
        "metrics.",
        "quality_issues",
        "public.regulatory_bank_metrics_v1",
        "drop ",
        "truncate",
        "delete from",
    ):
        assert protected_token not in normalized
    assert (
        "revoke all privileges on serving.reported_fact_revision_ancestry, "
        "serving.current_observed_facts, serving.current_publishable_facts "
        "from public, anon, authenticated, service_role;"
    ) in normalized
    assert (
        "grant select on serving.reported_fact_revision_ancestry, "
        "serving.current_observed_facts, serving.current_publishable_facts "
        "to service_role;"
    ) in normalized
    assert (
        "grant execute on function serving.observed_facts_as_of(timestamptz), "
        "serving.publishable_facts_as_of(timestamptz) to service_role;"
    ) in normalized
    assert "grant insert" not in normalized
    assert "grant update" not in normalized
    assert "grant delete" not in normalized

    for smoke_token in (
        "pr16_catalog_passed",
        "pr16_relation_gate",
        "pr16_definition_gate",
        "pr16_access_gate",
        "pr16_boundary_gate",
        "pr16_rollback_passed",
        "future ancestry was visible before its root",
        "sibling accept conflict returned a publishable row",
        "null cutoff returned rows",
        "late cutoff observed set diverged from current",
        "service_role acquired a pr16 write privilege",
    ):
        assert smoke_token in smoke_normalized


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
