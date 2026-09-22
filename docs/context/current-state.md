# Current project state

This file is a compact, replaceable snapshot. It describes the repository as it exists now; it is
not a changelog and does not make the roadmap executable.

## Current baseline

- Repository: `daardavid/mexican-banking-monitor`.
- Approved branch base: updated `main`; feature work uses short-lived branches.
- Product scope: Mexico / banca multiple.
- Approved target: modular Regulatory Data Core v1 with evidence, registry, reported, semantic,
  metrics, audit, serving, and versioned public contracts.
- Stack: CPython 3.12.14, `uv` 0.12.6, PostgreSQL/Supabase, Supabase CLI migrations, GitHub
  Actions, YAML, Ruff, Mypy, Pytest, Streamlit, and Plotly.
- General state: bootstrap/MVP foundation and PR1–PR15 are complete. PR10, PR11, PR13, PR14, and
  PR15 are merged, deployed, and independently verified. PR12 is merged and complete, and its
  production artifact Storage is provisioned and verified. PR15a `feat/review-decision-events` is
  MERGED / COMPLETE; production deployment is COMPLETE / VERIFIED.

## Implemented now

- Installable `mx_bank_monitor` package organized as a modular monolith.
- Settings for local environment and Supabase connectivity, with the database DSN and Supabase
  secret key protected from settings repr.
- CLI commands `mbm validate-config` and `mbm doctor`; `doctor --database` performs a secret-safe,
  read-only connectivity and legacy-schema preflight when `MBM_DATABASE_URL` is configured.
- PostgreSQL connections use an explicit 10-second connect timeout and conservatively disable
  client-side prepared statements for transaction-pooler compatibility.
- Exact domain models/formulas, YTD conversion, cohort helpers, and HTTP artifact validation/hash
  primitives with tests.
- A synchronous, immutable, content-addressed ArtifactStore contract with equivalent local and
  Supabase backends, full SHA-256/byte-length verification, create-only/no-overwrite behavior,
  safe concurrent-writer handling, and bounded ambiguous-upload recovery. Supabase access uses
  direct `httpx` rather than an SDK, and MIME remains catalog metadata rather than content identity.
- Declarative configuration for the private `regulatory-artifacts` bucket and a dedicated manual,
  main-only production provisioning workflow. The workflow shares the production database
  deployment concurrency lock but does not run database migrations or upload artifacts. The
  repository config intentionally sets neither a MIME-type restriction nor an explicit per-bucket
  file-size limit.
- Version-controlled YAML editorial definitions for sources, institutions/cohorts, controlled
  reporting scopes, canonical/source concepts, mappings, and metric metadata, with strict Pydantic
  contracts, duplicate-safe YAML loading, whole-bundle cross-validation, institution
  `definition_version`, canonical Python alias normalization, and same-cohort overlap rejection.
- The deployed PR11 evidence catalog implements stable regulator/source identity, immutable
  source-definition versions, logical releases, exact artifacts, and append-only runtime
  privileges. All five relations are unseeded by design.
- The deployed PR13 audit lifecycle implements private v1 ingestion runs and append-only
  artifact observation attempts in `audit`, with a PostgreSQL-owned lifecycle, terminal
  counters, same-source artifact lineage, restart lineage, and narrow service-role writes. Both
  production tables are empty.
- The deployed PR14 institution-identity schema implements seven empty private registry
  tables: stable institution identity, immutable institution definition versions, effective-dated
  registrations/aliases/cohort memberships, immutable regulatory concepts, and concept/scope
  pairings. No real institution or concept definitions are seeded. Runtime `service_role` is
  SELECT-only. All seven production tables are empty.
- The deployed PR15 reported-fact schema implements `reported.reported_facts`: an append-only
  private exact regulatory fact table with composite source/identity/provenance FKs, database-owned
  SHA-256 locator and fact hashes, instant/duration economic time, raw value plus exact numeric
  parsed value, and append-only revision lineage that allows multiple observed successors. The
  production table currently has zero rows.
- The deployed PR15a review-decision schema implements `audit.review_decisions`: an
  append-only private event log of exactly 11 columns, with the decision vocabulary `ACCEPT`,
  `REJECT`, and `REVOKE`, the actor vocabulary `HUMAN` and `SYSTEM_POLICY`, a mandatory single
  `reason` text column, a strictly monotonic per-fact `(decided_at, review_decision_id)` event
  timeline enforced under a per-fact advisory lock, a `REVOKE` precondition requiring an
  effective `ACCEPT` head event, and audit-only correction lineage constrained to the same fact
  by a composite foreign key with no unique correction-target constraint.
  Review authority is never a mutable status on a reported fact. Effective review state is
  read through the `audit.effective_review_decisions` view and the
  `audit.effective_review_decisions_as_of(timestamptz)` function; a fact with no event is
  pending. PR15a deliberately adds no idempotency or request key, no quality-issue objects, and
  no fact-level current/publishable semantics. Production currently has zero review-decision
  rows, RLS enabled with zero policies, narrow `service_role` privileges, and no PR15a
  SECURITY DEFINER functions.
- One legacy initial migration creating `core`, `ops`, `analytics`, and the derived
  `public.bank_metrics` table with public read-only RLS.
- CI quality checks on Linux and PowerShell regression/full checks on Windows.
- CI migration validation uses a pinned Supabase CLI against an ephemeral local database: it
  rebuilds all repository migrations, lints the result, and runs a read-only legacy-schema smoke
  check without remote credentials or project linking.
- Local bootstrap and both CI platforms use CPython 3.12.14 and `uv` 0.12.6; locked checks fail
  on dependency drift without rewriting `uv.lock`.
- Production migration deployment remains manual and is hardened on `main` with a real
  main-only gate, serialized execution, pinned tooling, local integrity/destructive-DDL checks,
  structured-JSON remote-history and dry-run gates, Vault-free pending-only push, and read-only
  post-push verification. It never repairs history, resets remote, or forces out-of-order
  migrations. The workflow has been used successfully for the verified PR10, PR11, PR13, PR14,
  PR15, and PR15a deployments.
- The placeholder refresh schedule is disabled on `main`. The workflow remains available for manual
  database preflight; real `mbm refresh` is not implemented or enabled.
- PowerShell bootstrap, shared command, regression, and full-check scripts; the update flow is
  main-only, requires a clean tree tracking `origin/main`, rejects local/diverged history, and uses
  explicit fetch plus fast-forward.
- Streamlit placeholder dashboard; it does not yet consume regulatory data.
- A source-format spike document, but no real CNBV discovery, parser, facts ingestion, metric
  engine, backfill, or public v1 dataset.

## Architecture status

`Regulatory Data Core v1: APPROVED / IMPLEMENTATION STARTED — PR10 AND PR11 DEPLOYED /
VERIFIED; PR12 MERGED / COMPLETE; PR12 PRODUCTION STORAGE PROVISIONED / VERIFIED; PR13
MERGED / COMPLETE; PR13 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED; PR14 MERGED /
COMPLETE; PR14 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED; PR15 MERGED / COMPLETE;
PR15 PRODUCTION DEPLOYMENT COMPLETE / VERIFIED; PR15A MERGED / COMPLETE;
PR15A PRODUCTION DEPLOYMENT COMPLETE / VERIFIED`

Architecture ADRs 0003–0007 are accepted and frozen on `main`. They establish separate institution
and registration identity, temporal/review and supersession semantics, controlled reporting scope,
and Git/YAML editorial authority with Python as executable authority.

## Legacy status

- Schemas `core`, `ops`, and `analytics` are legacy and frozen for the v1 transition.
- `public.bank_metrics` is an existing legacy derived surface.
- The legacy initial migration remains immutable.
- The repository contains exactly seven migrations. They define the seven v1 responsibility
  schemas, the three deployed PR10 registry primitives, the five deployed PR11 evidence catalog
  relations, the deployed PR13 audit ingestion lifecycle, the deployed PR14 institution
  identity/taxonomy schema, the deployed PR15 reported-fact schema, and the deployed PR15a
  review-decision schema.
  Production has exactly seven migrations. No pending production migration remains. No v1 public
  contract exists, and there is no dual-write.
- `public.regulatory_bank_metrics_v1` remains absent.

## Operational state

- Development uses two laptops with independent Git clones outside OneDrive or other sync folders.
- GitHub synchronizes code, branches, and migrations.
- Both laptops and GitHub jobs may use one shared remote Supabase backend.
- The mandatory read-only remote inventory is complete. The remote was classified as pristine
  before bootstrap.
- Production migration history is exactly:
  - `202608250001 / initial_schema`
  - `20260827223312 / data_core_schema_primitives`
  - `20260828164124 / evidence_catalog_schema`
  - `20260830234552 / ingestion_run_lifecycle`
  - `20260916202900 / institution_identity_schema`
  - `20260919143000 / reported_fact_schema`
  - `20260919180000 / review_decision_events`
- The legacy objects remain intact and frozen, and all 10 legacy tables remain empty.
- `mbm doctor --database` passes against the legacy baseline, and the final production migration
  dry-run is a no-op.
- The remote contains the seven v1 responsibility schemas: `evidence`, `registry`, `reported`,
  `semantic`, `metrics`, `audit`, and `serving`.
- The remote contains `registry.measurement_units`, `registry.reporting_scopes`, and
  `registry.reporting_scope_versions`; all three tables are empty. Production `registry` has
  exactly ten ordinary tables. `btree_gist` is installed in schema `extensions`.
- Production contains exactly five PR11 evidence catalog tables: `evidence.regulators`,
  `evidence.sources`, `evidence.source_definition_versions`, `evidence.source_releases`, and
  `evidence.source_artifacts`; all five tables are empty.
- PR12 production Storage provisioning workflow run `33358758863` completed successfully and was
  executed exactly once. Production has exactly one private `regulatory-artifacts` bucket, it
  contains zero objects, and no applicable public, `anon`, or `authenticated` Storage policy
  exposes it. No MIME-type restriction is configured.
- The repository intentionally has no explicit per-bucket file-size override. Production reports
  an effective/default `file_size_limit` of 52,428,800 bytes (50 MiB); this is accepted as the
  current platform/default/effective Storage capacity, not a repository-selected per-bucket
  restriction. No repair or second provisioning run was performed.
- PR12 made no SQL migration. PR13 production database deployment workflow run `35168042980`
  completed successfully and was executed exactly once. Production contains
  `audit.ingestion_runs` and `audit.ingestion_run_artifacts`; both tables are empty. RLS is
  enabled with no policies, `service_role` retains only the intended narrow privileges, and no
  SECURITY DEFINER functions were introduced.
- PR14 production database deployment workflow run `35235936358` completed successfully and was
  executed exactly once. Production contains `registry.institutions`,
  `registry.institution_definition_versions`, `registry.regulatory_registrations`,
  `registry.institution_aliases`, `registry.institution_cohorts`,
  `registry.regulatory_concepts`, and `registry.regulatory_concept_scopes`; all seven PR14
  tables exist and are empty. RLS is enabled on all seven with zero policies, `service_role`
  is SELECT-only, `public` / `anon` / `authenticated` have no table access, and no PR14
  SECURITY DEFINER functions exist. PR10, PR11, PR12, PR13, and legacy objects remain intact.
- PR15 production database deployment workflow run `35453698235` completed successfully and was
  executed exactly once. It applied only `20260919143000_reported_fact_schema.sql`. Production
  migration history is aligned at six, post-push pending is none, and the final dry-run was a
  no-op. Independent read-only verification confirmed `reported.reported_facts` exists with
  exactly 28 columns and zero rows. RLS is enabled with zero policies. `service_role` has SELECT
  and narrow column-level INSERT only, with no UPDATE or DELETE. The two PR15 functions are not
  SECURITY DEFINER. The predecessor column is not unique, so multiple observed successors remain
  possible. PR10–PR14 and legacy objects remain intact and empty.
- GitHub PR #24 merged PR15a at `b3a83c0f92ad5d22948e3453d62988e9c26ee2cc`. PR15a production
  database deployment workflow run `35467183915` completed successfully and was executed exactly
  once. It applied only `20260919180000_review_decision_events.sql`. Production migration
  history is aligned at seven, pending migrations are none, and the final production dry-run
  was a no-op. Independent secret-safe read-only verification confirmed production contains
  `audit.review_decisions`, `audit.effective_review_decisions`, and
  `audit.effective_review_decisions_as_of(timestamptz)`. `audit.review_decisions` exists with
  exactly 11 columns and zero rows. RLS is enabled with zero policies. The table is append-only
  with a strict per-fact timeline, decision vocabulary `ACCEPT` / `REJECT` / `REVOKE`, actor
  vocabulary `HUMAN` / `SYSTEM_POLICY`, same-fact correction lineage, and no unique
  correction-target constraint. `service_role` has SELECT and narrow column-level INSERT only,
  with no UPDATE, DELETE, or INSERT on `review_decision_id`. No PR15a SECURITY DEFINER
  functions exist. All PR10–PR15a runtime tables remain empty. Legacy objects remain intact
  and empty. `audit.quality_issues` remains absent. PR16 fact-level current/as-of objects
  remain absent. `public.regulatory_bank_metrics_v1` remains absent, and later `semantic` /
  `metrics` / `serving` implementation relations remain absent.
- The Vault-free production deployment hotfix is complete on `main`.
- PR10 v1 responsibility schemas, measurement units, and reporting scopes are merged, deployed,
  and verified in production.
- PR11 evidence catalog schema is merged, deployed, and verified in production.
- PR13 audit ingestion lifecycle is merged, deployed, and verified in production.
- PR14 institution identity and regulatory taxonomy schema is merged, deployed, and verified
  in production.
- PR15 reported-fact schema is merged, deployed, and independently verified in production.
- PR15a review-decision schema is merged, deployed, and independently verified in production.
- Each laptop keeps its own untracked `.env` and local `.venv`.
- Secrets live outside the repository; no secret values belong in this snapshot.
- The canonical rules are in `docs/operations/operational-contract.md`.

## Roadmap progress

- `PR1 chore/freeze-operational-contract` — MERGED / COMPLETE.
- `PR2 chore/pin-python-uv-toolchain` — MERGED / COMPLETE.
- `PR3 fix/harden-two-laptop-update` — MERGED / COMPLETE.
- `PR4 fix/harden-database-preflight` — MERGED / COMPLETE.
- `PR5 ci/validate-supabase-migrations` — MERGED / COMPLETE; ephemeral migration CI exists and
  passes on `main`.
- `PR6 ci/harden-production-migration-deploy` — MERGED / COMPLETE; the hardened production
  deployment workflow was used successfully for PR10.
- `PR7 chore/disable-placeholder-refresh-schedule` — MERGED / COMPLETE; the placeholder schedule is
  disabled while real `mbm refresh` remains unavailable.
- `PR8 docs/regulatory-core-architecture-v1` — MERGED / COMPLETE; architecture ADRs are frozen on
  `main`.
- `PR9 refactor/versioned-config-contracts` — MERGED / COMPLETE; typed editorial configuration
  contracts and semantic bundle validation are on `main`.
- `PR10 feat/data-core-schema-primitives` — MERGED / COMPLETE; production deployment is COMPLETE /
  VERIFIED.
- `PR11 feat/evidence-catalog-schema` — MERGED / COMPLETE; production deployment is COMPLETE /
  VERIFIED.
- `PR12 feat/artifact-storage-contract` — MERGED / COMPLETE; production Storage is PROVISIONED /
  VERIFIED.
- `PR13 feat/ingestion-run-lifecycle` — MERGED / COMPLETE; production deployment is COMPLETE /
  VERIFIED.
- `PR14 feat/institution-identity-schema` — MERGED / COMPLETE; production deployment is COMPLETE /
  VERIFIED.
- `PR15 feat/reported-fact-schema` — MERGED / COMPLETE; production deployment is COMPLETE /
  VERIFIED.
- `PR15a feat/review-decision-events` — MERGED / COMPLETE; production deployment is COMPLETE /
  VERIFIED.
- `PR16 feat/fact-current-as-of-queries` — NEXT; not started. PR16 may begin only after this
  production-state checkpoint is merged.
- Regulatory Data Core v1 schema work — STARTED / PR10 AND PR11 DEPLOYED / VERIFIED; PR12 MERGED /
  COMPLETE with production Storage PROVISIONED / VERIFIED; PR13 MERGED / COMPLETE with production
  deployment COMPLETE / VERIFIED; PR14 MERGED / COMPLETE with production deployment COMPLETE /
  VERIFIED; PR15 MERGED / COMPLETE with production deployment COMPLETE / VERIFIED; PR15a
  MERGED / COMPLETE with production deployment COMPLETE / VERIFIED.

## Known pending gates

- PR15 `feat/reported-fact-schema` is fully merged, deployed, and independently verified. PR15a
  `feat/review-decision-events` is MERGED / COMPLETE; production deployment is COMPLETE /
  VERIFIED. No `review_decisions` rows exist anywhere.
- Before the first at-least-once writer of review decisions exists, that writer PR must either
  guarantee exactly-once transactional decision insertion or add a client-supplied
  request/idempotency key with a `UNIQUE` contract. PR15a intentionally adds no such column and
  does not treat duplicate review events as harmless. `PR21 feat/cnbv-regulatory-slice` is the
  first roadmap PR expected to discharge this gate.
- Sibling successor arbitration remains open by design. PR15a permits competing `ACCEPT` events
  on two successors of the same predecessor and adds no per-predecessor acceptance uniqueness or
  competing-acceptance trigger. PR16 owns fact-level current/publishable semantics and their
  enforcement mechanism.
- Quality issues, quality blocker workflow, review queues, and automatic acceptance workflow
  remain PR24 work. `audit.quality_issues` does not exist.
- CNBV source discovery, exact source-contract confirmation, and parser implementation remain
  pending for later phases.
- Before PR19 / first real CNBV artifact ingestion, measure representative CNBV artifact sizes,
  verify that the current effective 50 MiB Storage capacity is sufficient, and evaluate standard-
  upload suitability for the real artifact sizes. If capacity or transport is insufficient, a
  separately reviewed Storage capacity/transport change is required. This gate must be satisfied
  before PR19 and does not block PR15a–PR18.

## How to update this file

After each PR that materially changes implementation or operational state, replace this snapshot
with the new truth. Do not append a diary, copy logs, duplicate ADRs, or preserve obsolete status.
