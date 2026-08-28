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
    assert "PR10 feat/data-core-schema-primitives` — IN PROGRESS" in current_state
    assert (
        "Regulatory Data Core v1 schema work — IN PROGRESS LOCALLY / NOT DEPLOYED TO PRODUCTION"
        in current_state
    )
