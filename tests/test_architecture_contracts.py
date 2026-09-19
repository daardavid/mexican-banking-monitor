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
        "  - `20260828164124 / evidence_catalog_schema`\n"
        "  - `20260830234552 / ingestion_run_lifecycle`\n"
        "  - `20260916202900 / institution_identity_schema`\n"
        "  - `20260919143000 / reported_fact_schema`"
        in current_state
    )
    assert (
        "PR12 feat/artifact-storage-contract` — MERGED / COMPLETE; production Storage is "
        "PROVISIONED /\n  VERIFIED."
        in current_state
    )
    assert "PR1\u2013PR15 are complete" in current_state
    assert (
        "PR13\nMERGED / COMPLETE; PR13 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED; "
        "PR14 MERGED /\nCOMPLETE; PR14 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED; "
        "PR15 MERGED / COMPLETE;\nPR15 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED"
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
        "PR13 feat/ingestion-run-lifecycle` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert "The repository contains exactly seven migrations." in current_state
    assert "Production has exactly six migrations." in current_state
    assert (
        "Exactly one repository migration,\n"
        "  `20260919180000_review_decision_events.sql`, is implemented and not deployed."
        in current_state
    )
    assert "PR13 production database deployment workflow run `35168042980`" in current_state
    assert "`audit.ingestion_runs` and `audit.ingestion_run_artifacts`; both tables are empty." in (
        current_state
    )
    assert "RLS is\n  enabled with no policies" in current_state
    assert "no\n  SECURITY DEFINER functions were introduced" in current_state
    assert "PR13 audit ingestion lifecycle is merged, deployed, and verified in production." in (
        current_state
    )
    assert (
        "PR14 feat/institution-identity-schema` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert "PR14 production database deployment workflow run `35235936358`" in current_state
    assert "exactly ten ordinary tables." in current_state
    assert "`btree_gist` is installed in schema `extensions`." in current_state
    assert "`registry.institutions`," in current_state
    assert "`registry.institution_definition_versions`," in current_state
    assert "`registry.regulatory_registrations`," in current_state
    assert "`registry.institution_aliases`," in current_state
    assert "`registry.institution_cohorts`," in current_state
    assert "`registry.regulatory_concepts`," in current_state
    assert "`registry.regulatory_concept_scopes`; all seven PR14" in current_state
    assert "tables exist and are empty." in current_state
    assert "All seven production tables are empty." in current_state
    assert "RLS is enabled on all seven with zero policies" in current_state
    assert "`service_role`\n  is SELECT-only" in current_state
    assert "`public` / `anon` / `authenticated` have no table access" in current_state
    assert "no PR14\n  SECURITY DEFINER functions exist" in current_state
    assert "PR10, PR11, PR12, PR13, and legacy objects remain intact." in current_state
    assert "PR15+ objects remain absent." not in current_state
    assert "PR15 `reported.reported_facts` does not exist in production yet." not in (
        current_state
    )
    assert "PR15a remains blocked." not in current_state
    assert "multiple observed successors" in current_state
    assert "linear supersession" not in current_state
    assert (
        "PR14 institution identity and regulatory taxonomy schema is merged, deployed, and "
        "verified\n  in production."
        in current_state
    )
    assert "PR15 production database deployment workflow run `35453698235`" in current_state
    assert (
        "PR15 feat/reported-fact-schema` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert "PR15 reported-fact schema is merged, deployed, and independently verified" in (
        current_state
    )
    assert "`reported.reported_facts` exists with\n  exactly 28 columns and zero rows." in (
        current_state
    )
    assert "RLS is enabled with zero policies." in current_state
    assert (
        "`service_role` has SELECT\n  and narrow column-level INSERT only, with no UPDATE or "
        "DELETE."
        in current_state
    )
    assert "The two PR15 functions are not\n  SECURITY DEFINER." in current_state
    assert "multiple observed successors remain\n  possible." in current_state
    assert "PR10\u2013PR14 and legacy objects remain intact and empty." in current_state
    assert "In production, PR15a+\n  implementation objects remain absent" in current_state
    assert "`audit.review_decisions` is absent" in current_state
    assert "PR16 current/as-of objects are absent" in current_state
    assert "`public.regulatory_bank_metrics_v1` remains absent" in current_state
    assert "No `review_decisions` rows exist anywhere." in current_state
    assert "PR15 `feat/reported-fact-schema` is NEXT and is not yet implemented." not in (
        current_state
    )
    assert "PR14 `feat/institution-identity-schema` is NEXT and is not yet implemented." not in (
        current_state
    )
    assert "PRODUCTION DEPLOYMENT PENDING" not in current_state
    assert "Production still has no PR14" not in current_state
    assert "Production does not yet contain these objects." not in current_state
    assert "unimplemented-in-production" not in current_state
    assert "PR15 remains blocked" not in current_state
    assert "PR15 BLOCKED" not in current_state
    assert "Production still has exactly five migrations." not in current_state
    assert (
        "Before PR19 / first real CNBV artifact ingestion, measure representative CNBV "
        "artifact sizes"
        in current_state
    )
    assert (
        "separately reviewed Storage capacity/transport change is required. This gate must be "
        "satisfied\n  before PR19 and does not block PR15a\u2013PR18."
        in current_state
    )


def test_pr15a_is_recorded_as_feature_branch_only_state() -> None:
    current_state = (
        REPOSITORY_ROOT / "docs" / "context" / "current-state.md"
    ).read_text(encoding="utf-8")

    assert (
        "PR15a `feat/review-decision-events` is\n  IMPLEMENTED on this feature branch; "
        "it is NOT merged and NOT deployed."
        in current_state
    )
    assert (
        "PR15 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED; PR15A IMPLEMENTED ON FEATURE "
        "BRANCH /\nNOT MERGED / NOT DEPLOYED`"
        in current_state
    )
    assert (
        "PR15a feat/review-decision-events` — IMPLEMENTED ON FEATURE BRANCH; NOT merged; "
        "NOT deployed."
        in current_state
    )
    assert (
        "PR16 feat/fact-current-as-of-queries` — NEXT AFTER PR15a completion; blocked until "
        "PR15a is\n  merged, deployed, and verified."
        in current_state
    )
    assert "the undeployed\n  feature-branch PR15a review-decision schema." in current_state
    assert (
        "PR15a is implemented on the `feat/review-decision-events` branch only. It is not "
        "merged, no\n  production deployment workflow has been run for it"
        in current_state
    )
    assert "do not exist in production yet." in current_state
    assert "`audit.quality_issues` is deliberately still absent everywhere." in current_state
    assert "`audit.quality_issues` does not exist." in current_state

    for frozen_pr15a_contract in (
        "the decision vocabulary `ACCEPT`,",
        "the actor vocabulary `HUMAN` and `SYSTEM_POLICY`",
        "a strictly monotonic per-fact `(decided_at, review_decision_id)` event",
        "enforced under a per-fact advisory lock",
        "a `REVOKE` precondition requiring an",
        "audit-only correction lineage constrained to the same fact",
        "Review authority is never a mutable status on a reported fact.",
        "`audit.effective_review_decisions_as_of(timestamptz)` function; a fact with no event is",
        "PR15a deliberately adds no idempotency or request key",
        "These objects exist only on the feature branch.",
    ):
        assert frozen_pr15a_contract in current_state

    assert (
        "Before the first at-least-once writer of review decisions exists, that writer PR must "
        "either\n  guarantee exactly-once transactional decision insertion or add a "
        "client-supplied\n  request/idempotency key with a `UNIQUE` contract."
        in current_state
    )
    assert (
        "`PR21 feat/cnbv-regulatory-slice` is the\n  first roadmap PR expected to discharge "
        "this gate."
        in current_state
    )
    assert (
        "PR15a permits competing `ACCEPT` events\n  on two successors of the same predecessor "
        "and adds no per-predecessor acceptance uniqueness or\n  competing-acceptance trigger. "
        "PR16 owns fact-level current/publishable semantics and their\n  enforcement mechanism."
        in current_state
    )
    assert (
        "Quality issues, quality blocker workflow, review queues, and automatic acceptance "
        "workflow\n  remain PR24 work."
        in current_state
    )

    for forbidden_claim in (
        "PR15a production database deployment workflow run",
        "PR15a is merged",
        "PR15a review decision schema is merged, deployed",
        "Production has exactly seven migrations",
        "PR15a PRODUCTION DEPLOYMENT COMPLETE",
        "current_publishable",
        "publishable_as_of",
        "quality blocker workflow is implemented",
        "duplicate review events are harmless",
    ):
        assert forbidden_claim not in current_state
