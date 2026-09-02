import re
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
ADR_ROOT = REPOSITORY_ROOT / "docs" / "adr"
ADR_PATHS = tuple(ADR_ROOT.glob("000[3-7]-*.md"))


def _contract(number: int) -> str:
    matches = tuple(ADR_ROOT.glob(f"{number:04d}-*.md"))
    assert len(matches) == 1
    return matches[0].read_text(encoding="utf-8")


def test_architecture_adrs_have_accepted_structure() -> None:
    assert len(ADR_PATHS) == 5

    for path in ADR_PATHS:
        text = path.read_text(encoding="utf-8")
        assert "- Status: Accepted" in text
        for heading in (
            "## Context",
            "## Decision",
            "## Consequences",
            "## Rejected alternatives",
        ):
            assert heading in text


def test_responsibilities_identifiers_and_exact_values_are_frozen() -> None:
    contract = _contract(3)
    for schema in (
        "evidence",
        "registry",
        "reported",
        "semantic",
        "metrics",
        "audit",
        "serving",
        "public",
    ):
        assert f"`{schema}`:" in contract

    for legacy_schema in ("core", "ops", "analytics"):
        assert f"`{legacy_schema}`" in contract
    assert "frozen legacy" in contract
    assert "never dual-writes" in contract
    assert "UUID v4" in contract
    assert "`bigint identity`" in contract
    assert "alternate `UNIQUE` keys" in contract
    assert "`Decimal`" in contract
    assert "exact `numeric`" in contract
    assert "never use `float`" in contract


def test_temporal_review_and_supersession_vocabularies_are_explicit() -> None:
    temporal = _contract(4)
    for term in (
        "Economic time",
        "Published time",
        "Observed time",
        "Review decision time",
        "current_observed",
        "current_publishable",
        "observed_as_of(cutoff)",
        "publishable_as_of(cutoff)",
        "knowledge_cutoff_at",
        "calculated_at",
    ):
        assert term in temporal
    assert set(re.findall(r"`(ACCEPT|REJECT|REVOKE)`", temporal)) == {
        "ACCEPT",
        "REJECT",
        "REVOKE",
    }
    assert "append-only" in temporal

    revisions = _contract(5)
    expected_reasons = {
        "SOURCE_REVISION",
        "EXTRACTION_CORRECTION",
        "IDENTITY_CORRECTION",
        "METHODOLOGY_CORRECTION",
    }
    assert set(re.findall(r"`([A-Z_]+CORRECTION|SOURCE_REVISION)`", revisions)) == (
        expected_reasons
    )
    assert "invalid for reported facts" in revisions
    assert "separate effective review decision" in revisions


def test_scope_and_definition_authorities_are_explicit() -> None:
    scope = _contract(6)
    assert "`config/reporting_scopes.yml`" in scope
    assert "`individual_legal_entity`" in scope
    assert "never free text" in scope
    assert "exact scope equality" in scope
    assert "no implicit compatibility matrix" in scope
    assert "`registry.reporting_scopes`" in scope
    assert "`registry.reporting_scope_versions`" in scope
    assert "definition revision does not create a new" in scope
    assert "scope code rather than silently redefining" in scope

    authority = _contract(7)
    assert "Git/YAML is editorial authority" in authority
    assert "Python is executable authority" in authority
    assert "queryable immutable definition snapshots" in authority
    assert "Reporting scope identity and reporting scope definition versions are separate" in (
        authority
    )
    assert "append-only, immutable definition snapshots" in authority
    assert "Formula text in YAML or the database" in authority
    for term in ("EXACT", "HARMONIZED", "PROXY", "NOT_COMPARABLE"):
        assert f"`{term}`" in authority
    for term in ("draft", "active", "review_required", "retired"):
        assert f"`{term}`" in authority


def test_pr7_operational_amendment_and_roadmap_state_are_current() -> None:
    automation_adr = (ADR_ROOT / "0002-supabase-and-automation.md").read_text(
        encoding="utf-8"
    )
    assert "## Operational amendment — 2026-08-27" in automation_adr
    assert "placeholder weekday schedule was disabled" in automation_adr
    assert "manual database preflight only" in automation_adr

    current_state = (
        REPOSITORY_ROOT / "docs" / "context" / "current-state.md"
    ).read_text(encoding="utf-8")
    assert "PR7 chore/disable-placeholder-refresh-schedule` — MERGED / COMPLETE" in current_state
    assert "PR8 docs/regulatory-core-architecture-v1` — MERGED / COMPLETE" in current_state
    assert "PR9 refactor/versioned-config-contracts` — MERGED / COMPLETE" in current_state
    assert (
        "PR10 feat/data-core-schema-primitives` — MERGED / COMPLETE; production deployment "
        "is COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert "20260827223312 / data_core_schema_primitives" in current_state
    assert (
        "PR11 feat/evidence-catalog-schema` — MERGED / COMPLETE; production deployment "
        "is COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert (
        "Production migration history is exactly:\n"
        "  - `202608250001 / initial_schema`\n"
        "  - `20260827223312 / data_core_schema_primitives`\n"
        "  - `20260828164124 / evidence_catalog_schema`"
        in current_state
    )
    assert (
        "PR12 feat/artifact-storage-contract` — MERGED / COMPLETE; production Storage is "
        "PROVISIONED /\n  VERIFIED."
        in current_state
    )
    assert (
        "PR13\nIMPLEMENTED / PRODUCTION DEPLOYMENT PENDING; PR14 BLOCKED;"
        in current_state
    )
    assert (
        "Production has exactly one private `regulatory-artifacts` bucket, it\n  contains zero "
        "objects"
        in current_state
    )
    assert (
        "no applicable public, `anon`, or `authenticated` Storage policy\n  exposes it"
        in current_state
    )
    assert "No MIME-type restriction is configured." in current_state
    assert (
        "The repository intentionally has no explicit per-bucket file-size override."
        in current_state
    )
    assert (
        "effective/default `file_size_limit` of 52,428,800 bytes (50 MiB)"
        in current_state
    )
    assert (
        "current platform/default/effective Storage capacity, not a repository-selected "
        "per-bucket\n  restriction"
        in current_state
    )
    assert "No repair or second provisioning run was performed." in current_state
    assert (
        "PR13 feat/ingestion-run-lifecycle` — IMPLEMENTED / PRODUCTION DEPLOYMENT PENDING."
        in current_state
    )
    assert "The repository contains exactly four migrations." in current_state
    assert (
        "`20260830234552 / ingestion_run_lifecycle`; production does not yet contain it."
        in current_state
    )
    assert (
        "PR14 feat/institution-identity-schema` — BLOCKED until PR13 is merged, deployed, "
        "verified, and\n  recorded in the production-state documentation checkpoint."
        in current_state
    )
    assert (
        "PR14 cannot begin until PR13 is merged, deployed to production, verified read-only, "
        "and followed\n  by a production-state documentation checkpoint on `main`."
        in current_state
    )
    assert (
        "Before PR19 / first real CNBV artifact ingestion, measure representative CNBV "
        "artifact sizes"
        in current_state
    )
    assert (
        "separately reviewed Storage capacity/transport change is required. This gate does "
        "not block\n  PR13."
        in current_state
    )
