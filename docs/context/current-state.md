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
- General state: bootstrap/MVP foundation and PR1–PR10 are complete; PR10 deployed and verified the
  first additive v1 schema primitives in production.

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
- Version-controlled YAML editorial definitions for sources, institutions/cohorts, controlled
  reporting scopes, canonical/source concepts, mappings, and metric metadata, with strict Pydantic
  contracts, duplicate-safe YAML loading, and whole-bundle cross-validation.
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
  migrations. The workflow has been successfully dispatched for the verified PR10 deployment.
- The placeholder refresh schedule is disabled on `main`. The workflow remains available for manual
  database preflight; real `mbm refresh` is not implemented or enabled.
- PowerShell bootstrap, shared command, regression, and full-check scripts; the update flow is
  main-only, requires a clean tree tracking `origin/main`, rejects local/diverged history, and uses
  explicit fetch plus fast-forward.
- Streamlit placeholder dashboard; it does not yet consume regulatory data.
- A source-format spike document, but no real CNBV discovery, parser, facts ingestion, metric
  engine, backfill, or public v1 dataset.

## Architecture status

`Regulatory Data Core v1: APPROVED / IMPLEMENTATION STARTED — PR10 DEPLOYED; LATER LAYERS PENDING`

Architecture ADRs 0003–0007 are accepted and frozen on `main`. They establish separate institution
and registration identity, temporal/review and supersession semantics, controlled reporting scope,
and Git/YAML editorial authority with Python as executable authority.

## Legacy status

- Schemas `core`, `ops`, and `analytics` are legacy and frozen for the v1 transition.
- `public.bank_metrics` is an existing legacy derived surface.
- The legacy initial migration remains immutable.
- The seven v1 responsibility schemas and only the three PR10 registry primitive tables now exist;
  no v1 writer or v1 public contract exists yet, and there is no dual-write.
- `public.regulatory_bank_metrics_v1` remains absent.

## Operational state

- Development uses two laptops with independent Git clones outside OneDrive or other sync folders.
- GitHub synchronizes code, branches, and migrations.
- Both laptops and GitHub jobs may use one shared remote Supabase backend.
- The mandatory read-only remote inventory is complete. The remote was classified as pristine
  before bootstrap.
- Production migration history is aligned at exactly `202608250001 / initial_schema` and
  `20260827223312 / data_core_schema_primitives`.
- The legacy objects remain intact and frozen, and all 10 legacy tables remain empty.
- `mbm doctor --database` passes against the legacy baseline, and the final production migration
  dry-run is a no-op.
- The remote contains the seven v1 responsibility schemas: `evidence`, `registry`, `reported`,
  `semantic`, `metrics`, `audit`, and `serving`.
- The remote contains `registry.measurement_units`, `registry.reporting_scopes`, and
  `registry.reporting_scope_versions`; all three tables are empty.
- No later-roadmap v1 objects exist, and `public.regulatory_bank_metrics_v1` remains absent.
- The Vault-free production deployment hotfix is complete on `main`.
- PR10 v1 responsibility schemas, measurement units, and reporting scopes are merged, deployed,
  and verified in production.
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
- `PR11 feat/evidence-catalog-schema` — NEXT.
- Regulatory Data Core v1 schema work — STARTED / PR10 DEPLOYED; later layers remain pending.

## Known pending gates

- CNBV source discovery, exact source-contract confirmation, and parser implementation remain
  pending for later phases.
- Supabase Storage suitability/retention must be confirmed before artifact backfill.

## How to update this file

After each PR that materially changes implementation or operational state, replace this snapshot
with the new truth. Do not append a diary, copy logs, duplicate ADRs, or preserve obsolete status.
