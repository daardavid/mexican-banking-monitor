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
        "  - `20260919143000 / reported_fact_schema`\n"
        "  - `20260919180000 / review_decision_events`\n"
        "  - `20260922120000 / fact_current_as_of_queries`\n"
        "  - `20260926093000 / semantic_mapping_schema`\n"
        "  - `20261002140000 / canonical_observation_view`"
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
        "PR15 MERGED / COMPLETE;\nPR15 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED; "
        "PR15A MERGED / COMPLETE;\nPR15A PRODUCTION DEPLOYMENT COMPLETE / VERIFIED"
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
    assert "The repository contains exactly ten migrations." in current_state
    assert "Production has exactly ten migrations." in current_state
    assert "Production has exactly nine migrations." not in current_state
    assert "Production has exactly eight migrations." not in current_state
    assert "Production has exactly seven migrations." not in current_state
    assert "Exactly one repository migration is pending relative" not in current_state
    assert "Pending production migrations: exactly 1." not in current_state
    assert "No pending production migration remains." in current_state
    assert "Production has exactly six migrations." not in current_state
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
    assert "In production, PR15a+\n  implementation objects remain absent" not in current_state
    assert "`audit.review_decisions` is absent" not in current_state
    assert "PR16 fact-level current/as-of objects\n  remain absent." not in current_state
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


def test_pr15a_is_recorded_as_merged_and_production_verified() -> None:
    current_state = (
        REPOSITORY_ROOT / "docs" / "context" / "current-state.md"
    ).read_text(encoding="utf-8")

    assert (
        "PR15a `feat/review-decision-events` is\n  MERGED / COMPLETE; production deployment "
        "is COMPLETE / VERIFIED."
        in current_state
    )
    assert (
        "PR15a feat/review-decision-events` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert "PR15A PRODUCTION DEPLOYMENT COMPLETE / VERIFIED" in current_state
    assert "GitHub PR #24 merged PR15a at `b3a83c0f92ad5d22948e3453d62988e9c26ee2cc`." in (
        current_state
    )
    assert "PR15a production\n  database deployment workflow run `35467183915`" in current_state
    assert "It applied only `20260919180000_review_decision_events.sql`." in current_state
    assert (
        "the deployed PR15a\n  review-decision schema, and the deployed PR16 fact "
        "current/as-of query surfaces,"
        in current_state
    )
    assert "Production has exactly ten migrations." in current_state
    assert "The repository contains exactly ten migrations." in current_state
    assert "Production has exactly nine migrations." not in current_state
    assert "Production has exactly eight migrations." not in current_state
    assert "Production has exactly seven migrations." not in current_state
    assert "Exactly one repository migration is pending relative" not in current_state
    assert "Pending production migrations: exactly 1." not in current_state
    assert "No pending production migration remains." in current_state
    assert "history is aligned at seven, pending migrations are none" in current_state
    assert "the final production dry-run\n  was a no-op." in current_state
    assert "PR15a review-decision schema is merged, deployed, and independently verified" in (
        current_state
    )
    assert (
        "Independent secret-safe read-only verification confirmed production contains\n  "
        "`audit.review_decisions`, `audit.effective_review_decisions`, and\n  "
        "`audit.effective_review_decisions_as_of(timestamptz)`."
        in current_state
    )
    assert "`audit.review_decisions` exists with\n  exactly 11 columns and zero rows." in (
        current_state
    )
    assert "RLS is enabled with zero policies." in current_state
    assert "No PR15a SECURITY DEFINER\n  functions exist." in current_state
    assert "All PR10\u2013PR15a runtime tables remain empty." in current_state
    assert "`audit.quality_issues` remains absent." in current_state
    assert "`audit.quality_issues` does not exist." in current_state
    assert "PR16 fact-level current/as-of objects\n  remain absent." not in current_state
    assert "`public.regulatory_bank_metrics_v1` remains absent" in current_state
    assert (
        "PR16 feat/fact-current-as-of-queries` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert (
        "`PR17 feat/semantic-mapping-schema` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED."
        in current_state
    )

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
        "no unique correction-target constraint",
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
        "Sibling successor arbitration is enforced by the deployed PR16 fail-closed accepted "
        "frontier."
        in current_state
    )
    assert (
        "Quality issues, quality blocker workflow, review queues, and automatic acceptance "
        "workflow\n  remain PR24 work."
        in current_state
    )

    for forbidden_claim in (
        "IMPLEMENTED on this feature branch",
        "Production has exactly six migrations",
        "implemented and not deployed",
        "review_decisions` is absent",
        "These objects exist only on the feature branch.",
        "the undeployed",
        "feature-branch PR15a",
        "do not exist in production yet.",
        "awaits review, merge",
        "PR16 has begun",
        "publishable_as_of",
        "quality blocker workflow is implemented",
        "duplicate review events are harmless",
    ):
        assert forbidden_claim not in current_state


def test_pr16_is_recorded_as_merged_and_production_verified() -> None:
    current_state = (
        REPOSITORY_ROOT / "docs" / "context" / "current-state.md"
    ).read_text(encoding="utf-8")

    assert "The repository contains exactly ten migrations." in current_state
    assert "Production has exactly ten migrations." in current_state
    assert "Production has exactly nine migrations." not in current_state
    assert "Production has exactly eight migrations." not in current_state
    assert "Pending production migrations: exactly 1." not in current_state
    assert "No pending production migration remains." in current_state
    assert "pending migrations are none" in current_state
    assert (
        "PR16\n  `feat/fact-current-as-of-queries` is MERGED / COMPLETE; production deployment "
        "is COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert "PR16 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED" in current_state
    assert (
        "PR16 feat/fact-current-as-of-queries` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert "GitHub PR #26 merged PR16 at `77da4a2fe0f507fe061db03090637bd50b72d037`." in (
        current_state
    )
    assert "Post-merge main CI\n  run `35871818779` succeeded." in current_state
    assert "Read-only production preflight run `35872608536` succeeded" in current_state
    assert "PR16 production database deployment workflow run `35874772998`" in current_state
    assert (
        "It applied only\n  `20260922120000_fact_current_as_of_queries.sql`."
        in current_state
    )
    assert "the final production dry-run was a no-op." in current_state
    assert "Independent read-only production verification is complete." in current_state
    for production_object in (
        "`serving.reported_fact_revision_ancestry`",
        "`serving.current_observed_facts`",
        "`serving.current_publishable_facts`",
        "`serving.observed_facts_as_of(timestamptz)`",
        "`serving.publishable_facts_as_of(timestamptz)`",
    ):
        assert production_object in current_state
    assert "exactly three ordinary" in current_state
    assert "two SQL `STABLE` invoker functions" in current_state
    assert "The observed contract is exactly 29 columns." in current_state
    assert "The publishable contract is exactly 32 columns." in current_state
    for required_semantics in (
        "Predecessor lineage authority is `reported.reported_facts.predecessor_reported_fact_id`",
        "`fact_key_hash` is not lineage authority",
        "identity correction stays on the same\n  predecessor lineage",
        "As-of graphs require cutoff-visible\n  ancestry",
        "future ancestry cannot leak",
        "fails closed",
        "PR16 does not invent a winner",
        "no accepted-common-ancestor fallback",
        "There is no ancestry depth cap.",
        "`security_invoker` views",
        "query-only access",
        "no\n  mutation authority",
        "`anon`, `authenticated`, and `PUBLIC` have no access",
        "or SECURITY DEFINER function",
        "zero reported facts",
        "zero review decisions",
        "zero current observed rows",
        "zero current publishable rows",
        "zero\n  as-of query results",
        "`audit.quality_issues` remains absent.",
        "`semantic.canonical_concepts`",
        "`semantic.concept_mappings`",
        "`semantic.canonical_observations_v1`",
        "`metrics.metric_definitions`",
        "`metrics.metric_observations`",
        "`public.regulatory_bank_metrics_v1` remains absent",
        "`PR17 feat/semantic-mapping-schema` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED.",
    ):
        assert required_semantics in current_state

    for stale_claim in (
        "Production has exactly seven migrations.",
        "Production has exactly eight migrations.",
        "Production has exactly nine migrations.",
        "20260922120000_fact_current_as_of_queries.sql`. No v1",
        "PR16 fact-level current/as-of objects\n  remain absent.",
        "Production serving schema still has no PR16",
        "PR16 is NOT merged",
        "PR16 is NOT deployed",
    ):
        assert stale_claim not in current_state


def test_pr17_is_recorded_as_merged_and_production_verified() -> None:
    current_state = (
        REPOSITORY_ROOT / "docs" / "context" / "current-state.md"
    ).read_text(encoding="utf-8")
    adr = (
        ADR_ROOT / "0008-semantic-mapping-version-effectiveness.md"
    ).read_text(encoding="utf-8")
    authority = _contract(7)

    assert "- Status: Accepted" in adr
    assert "ADR 0007 remains unchanged" in current_state
    assert "Git/YAML is editorial authority" in authority
    assert "ADR 0008" not in authority
    for heading in (
        "## Context",
        "## Decision",
        "## Consequences",
        "## Rejected alternatives",
    ):
        assert heading in adr
    for frozen_decision in (
        "highest",
        "definition_version",
        "canonical re-pin",
        "Absence from current YAML is not retirement",
        "PROXY",
        "NOT_COMPARABLE",
        "period_end",
        "data_nature",
        "PR21",
    ):
        assert frozen_decision in adr

    assert (
        "PR17 `feat/semantic-mapping-schema` is MERGED / COMPLETE; production deployment\n"
        "  is COMPLETE / VERIFIED."
        in current_state
    )
    assert "PR17 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED" in current_state
    assert (
        "`PR17 feat/semantic-mapping-schema` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert (
        "GitHub PR #28 merged PR17 at `e060a605b43132fd306b718ac05c5309140a23b1`."
        in current_state
    )
    assert "Post-merge main CI\n  run `36668137372` succeeded." in current_state
    assert "PR17 production database deployment workflow run `36669660851`" in current_state
    assert (
        "It applied only\n  `20260926093000_semantic_mapping_schema.sql`."
        in current_state
    )
    assert "aligned at\n  nine, pending migrations are none" in current_state
    assert "the final production dry-run was a no-op." in current_state
    assert "Independent read-only production verification is complete" in current_state
    assert "`PR17_PRODUCTION_VERIFICATION_PASS`" in current_state
    assert "The repository contains exactly ten migrations." in current_state
    assert "Production has exactly ten migrations." in current_state
    assert "Production has exactly nine migrations." not in current_state
    assert "Pending production migrations: exactly 1." not in current_state
    assert "`20261002140000_canonical_observation_view.sql`" in current_state
    assert "No pending production migration remains." in current_state
    assert "`20260926093000 / semantic_mapping_schema`" in current_state
    assert "`20260926093000_semantic_mapping_schema.sql`" in current_state
    assert "ADR 0008 is Accepted" in current_state
    assert "Semantic effectiveness rules remain those frozen in ADR 0008." in current_state
    assert "All five tables exist and are empty." in current_state
    assert "RLS is enabled on all five with zero policies." in current_state
    assert "`service_role` is SELECT-only" in current_state
    assert "No canonical definitions are seeded and no mappings are seeded." in current_state
    for table_name in (
        "`semantic.canonical_concepts`",
        "`semantic.canonical_concept_versions`",
        "`semantic.canonical_concept_version_scopes`",
        "`semantic.concept_mappings`",
        "`semantic.concept_mapping_versions`",
    ):
        assert table_name in current_state
    for boundary in (
        "The PR17 migration did\n  not create `semantic.canonical_observations_v1`.",
        "Metrics implementation remains absent",
        "`audit.quality_issues` remains absent",
        "`public.regulatory_bank_metrics_v1` remains absent",
        "zero seed rows",
        "overlay contract",
        "highest `definition_version` among covering versions",
        "decisive canonical version",
        "Retirement is explicit",
        "Absence from YAML never means retirement",
        "`PROXY` remains private",
        "PR21 definitions-publishing gate",
        "Production contains the five PR17 tables",
        "there is no exclusion constraint",
    ):
        assert boundary in current_state

    for stale_claim in (
        "IMPLEMENTED on feature branch",
        "NOT merged",
        "NOT deployed",
        "Production has exactly eight migrations.",
        "Exactly one repository migration is pending",
        "Production semantic schema remains empty",
        "Production does not contain the five PR17 tables",
        "which is not deployed",
        "PR18 implemented",
        "PR18 has begun",
        "PR18 has not started",
        "NEXT AFTER THIS CHECKPOINT IS MERGED",
    ):
        assert stale_claim not in current_state


def test_adr_0009_freezes_the_canonical_observation_contract() -> None:
    adr = (ADR_ROOT / "0009-canonical-observation-v1-contract.md").read_text(
        encoding="utf-8"
    )

    assert "- Status: Accepted" in adr
    for heading in (
        "## Context",
        "## Decision",
        "## Invariants",
        "## Consequences",
        "## Rejected alternatives",
    ):
        assert heading in adr
    for statement in (
        "The sole fact input is `serving.current_publishable_facts`.",
        "The only PR18 database object is the ordinary view "
        "`semantic.canonical_observations_v1`.",
        "Only `dimensions = '{}'::jsonb` is eligible.",
        "`economic_date` is `period_end` for v1.",
        "The exposed `institution_id` is that registration's institution.",
        "PR18 has no regulatory-head rule.",
        "There is no fallback to an older version.",
        "it does not depend on `economic_date`.",
        "`canonical_value` equals `parsed_value` with no cast.",
        "Economic-key collisions remain visible.",
        "The view is `security_invoker`.",
        "Filtering mapping versions to `active` before the highest covering "
        "version is chosen.",
    ):
        assert statement in adr


def test_pr18_is_recorded_as_merged_and_production_verified() -> None:
    current_state = (
        REPOSITORY_ROOT / "docs" / "context" / "current-state.md"
    ).read_text(encoding="utf-8")

    assert "ADR 0009 is Accepted" in current_state
    assert "PR18 MERGED / COMPLETE" in current_state
    assert "PR18 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED" in current_state
    assert (
        "`PR18 feat/canonical-observation-view` — MERGED / COMPLETE; production deployment is "
        "COMPLETE /\n  VERIFIED."
        in current_state
    )
    assert "The repository contains exactly ten migrations." in current_state
    assert "Repository migrations: 10." in current_state
    assert "Production has exactly ten migrations." in current_state
    assert "Production migrations: 10." in current_state
    assert "Pending production migrations: 0." in current_state
    assert "No pending production migration remains." in current_state
    assert (
        "GitHub PR #30 merged PR18 at `e8515dc89e994dc2766504bfebe18ef0487eb939`."
        in current_state
    )
    assert "Post-merge main CI\n  run `37156145354` succeeded." in current_state
    assert "PR18 production database deployment workflow run `37165967164`" in current_state
    assert (
        "workflow run `37165967164`\n  completed successfully and was executed exactly once."
        in current_state
    )
    assert (
        "It applied only\n  `20261002140000_canonical_observation_view.sql`."
        in current_state
    )
    assert "aligned at\n  ten, pending migrations are none" in current_state
    assert "the final production dry-run was a no-op." in current_state
    assert "`PR18_PRODUCTION_VERIFICATION_PASS`" in current_state
    assert "Production contains\n  `semantic.canonical_observations_v1`" in current_state
    assert "`relkind` `v`" in current_state
    assert "`security_invoker=true`" in current_state
    assert "exactly 21 columns" in current_state
    assert (
        "unconstrained `numeric` `canonical_value`\n  (`atttypmod=-1`), and zero rows."
        in current_state
    )
    assert "`service_role` has SELECT only." in current_state
    for transient_claim in (
        "IMPLEMENTED LOCALLY / FEATURE BRANCH",
        "is not merged",
        "d3e6c01544701d49a6fea0a827172a6e9d7e0be0",
        "On branch `feat/canonical-observation-view`",
        "Production has exactly nine migrations.",
        "Production migrations: 9.",
        "Pending production migrations: exactly 1.",
        "Production deployment: NOT\n  PERFORMED.",
        "Production verification: NOT PERFORMED.",
        "PRODUCTION DEPLOYMENT NOT PERFORMED",
        "PRODUCTION VERIFICATION NOT PERFORMED",
        "production deployment has not been performed or verified.",
        "Production has no\n  `semantic.canonical_observations_v1` view.",
        "In production, `semantic.canonical_observations_v1` remains absent.",
        "`semantic.canonical_observations_v1` remains absent",
        "NEXT AFTER THIS CHECKPOINT IS MERGED",
    ):
        assert transient_claim not in current_state
    for contract_statement in (
        "`security_invoker` view, `semantic.canonical_observations_v1`, with exactly 21 columns.",
        "The sole fact input is `serving.current_publishable_facts`.",
        "`institution_id` comes from\n  the exact regulatory registration",
        "that registration must cover `economic_date`.",
        "The exact regulatory concept must be active and valid at `economic_date`.",
        "dimensionless-only: `dimensions = '{}'`.",
        "`economic_date` equals `period_end` as the v1\n  projection convention.",
        "Mapping effectiveness follows ADR 0008.",
        "The highest covering\n  mapping `definition_version` is decisive before lifecycle.",
        (
            "The canonical head is the\n  highest stored `definition_version`, "
            "independent of lifecycle and date."
        ),
        "A stale canonical\n  pin fails closed until it is explicitly re-pinned.",
        "Allowed private comparability is\n  `EXACT`, `HARMONIZED`, and `PROXY`.",
        "`NOT_COMPARABLE` is suppressed.",
        "A non-null\n  `transformation_key` is suppressed.",
        "There is no unit conversion.",
        "Period kind must match\n  exactly.",
        "`canonical_value` is an exact unconstrained `numeric` pass-through.",
        "Legitimate\n  mapping fan-out is preserved.",
        (
            "There is no economic-key arbitration, no point-in-time or\n  "
            "as-of semantic contract, no public contract, and no seeds."
        ),
        (
            "PR18 does not implement source discovery, a\n  CNBV parser, definitions "
            "publishing, a transformation registry, dimensional mapping, a\n  "
            "metric engine, a quality issue or blocker layer, point-in-time "
            "semantic reconstruction,\n  or a public serving contract."
        ),
        (
            "confirmation of the `period_end` convention, registration-period "
            "behavior, actual\n  dimensional behavior, and source unit behavior."
        ),
        "PR22 and PR23 metric layers must fail\n  closed on unresolved economic-key collisions.",
        "PR24 owns the later quality workflow.",
        "PR25 owns point-in-time semantics.",
    ):
        assert contract_statement in current_state


def test_pr19_is_recorded_as_merged_and_complete() -> None:
    current_state = (
        REPOSITORY_ROOT / "docs" / "context" / "current-state.md"
    ).read_text(encoding="utf-8")

    assert "PR19 `feat/cnbv-release-discovery`" in current_state
    assert "`PR19 feat/cnbv-release-discovery` — MERGED / COMPLETE" in current_state
    assert "NO PRODUCTION DEPLOYMENT REQUIRED" in current_state
    assert "NO DATABASE MIGRATION" in current_state
    assert "ADR 0010 is Accepted and frozen on `main`." in current_state
    assert "PR19 live CNBV smoke: PASS" in current_state
    assert "GitHub PR #32" in current_state
    assert "e5d828abc3ad7204f6c5198aa4b6f258795ed4ca" in current_state
    for stale_state in (
        "IMPLEMENTED ON FEATURE BRANCH",
        "LOCAL REVIEW COMPLETE",
        "NOT YET MERGED",
        "It is not frozen on `main`.",
        "`PR19 feat/cnbv-release-discovery` — NOT STARTED",
        "PR19 has not started",
        "LOCAL REVIEW COMPLETE THROUGH PHASE " + "3",
        "THROUGH PHASE " + "4",
        "`PR19 feat/cnbv-release-discovery` — CLOSED",
        "PR19 is CLOSED",
        "COMPLETE ON MAIN",
        "PR19 closed",
        "PR19 deployed",
        "CNBV artifacts persisted",
        "Storage capacity fixed",
        "PR20 started",
        "PR21 started",
        "Before PR19 / first real CNBV artifact ingestion",
    ):
        assert stale_state not in current_state

    for role in (
        "historical_series_data",
        "concept_catalog",
        "institution_catalog",
    ):
        assert role in current_state
    assert "XLSX is excluded from the" in current_state
    assert "exact observed snapshot" in current_state
    assert "68,899,653" in current_state
    assert "16,470,853" in current_state
    assert "sh_datos_40.csv" in current_state
    assert "584,795,606" in current_state
    assert "200012 through 202607" in current_state
    assert "portafolioinfdoctos.cnbv.gob.mx" in current_state
    assert "HTTP 200" in current_state
    assert "structural validation passed" in current_state
    assert "no redirects" in current_state
    assert "d9d182a99f26b3c37254f345552e43acf5febf85996ffb9ff49d043fef57ae00" in current_state
    assert "effective/default `file_size_limit` of 52,428,800 bytes (50 MiB)" in current_state
    assert "52,428,800" in current_state
    assert "PR19 makes no ArtifactStore calls." in current_state
    assert (
        "Before PR21 performs the first real CNBV ArtifactStore/Supabase upload"
        in current_state
    )
    assert "package consistency" in current_state
    assert "publication eligibility" in current_state
    assert "PR19 intentionally defines no arbitrary quiet window." in current_state
    assert "PR20_FULL_ZIP_STREAM_CAP_REQUIRED" in current_state
    assert "ZipInfo.file_size" in current_state
    assert 'roadmap phrase "June 2026 release"' in current_state
    assert "first observed cumulative snapshot containing Apr\u2013Jun 2026" in current_state
    assert "PR20 has not started." in current_state
    assert "`PR20 feat/cnbv-three-period-parser` — NOT STARTED." in current_state
    assert "Repository migrations: 10." in current_state
    assert "Production migrations: 10." in current_state
    assert "Pending production migrations: 0." in current_state
    assert (
        "zero real CNBV artifacts, zero evidence rows, zero reported facts,"
        in current_state
    )
    assert "zero review decisions, and zero canonical observations." in current_state
    assert "PR19 does not discharge these semantic gates." in current_state
    assert "ADRs 0003\u20130009 remain unchanged." in current_state
