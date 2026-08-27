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
- General state: bootstrap/MVP foundation exists; the approved v1 architecture has not been built.

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
- Version-controlled YAML placeholders for sources, institutions, and metric descriptions; current
  validation checks file presence and `schema_version`, not the future typed contracts.
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
  structured-JSON remote-history and dry-run gates, pending-only push, and read-only post-push
  verification. It never repairs history, resets remote, or forces out-of-order migrations.
- The placeholder refresh schedule is disabled on `main`. The workflow remains available for manual
  database preflight; real `mbm refresh` is not implemented or enabled.
- PowerShell bootstrap, shared command, regression, and full-check scripts; the update flow is
  main-only, requires a clean tree tracking `origin/main`, rejects local/diverged history, and uses
  explicit fetch plus fast-forward.
- Streamlit placeholder dashboard; it does not yet consume regulatory data.
- A source-format spike document, but no real CNBV discovery, parser, facts ingestion, metric
  engine, backfill, or public v1 dataset.

## Architecture status

`Regulatory Data Core v1: APPROVED / NOT YET IMPLEMENTED`

## Legacy status

- Schemas `core`, `ops`, and `analytics` are legacy and frozen for the v1 transition.
- `public.bank_metrics` is an existing legacy derived surface.
- The single existing migration remains immutable.
- No v1 schema, v1 writer, or v1 public contract exists yet; there is no dual-write.

## Operational state

- Development uses two laptops with independent Git clones outside OneDrive or other sync folders.
- GitHub synchronizes code, branches, and migrations.
- Both laptops and GitHub jobs may use one shared remote Supabase backend.
- A read-only smoke test confirmed that the shared backend is reachable but currently lacks the
  representative legacy objects required by the database preflight. No migration or repair was
  executed; remote inventory and any migration-state reconciliation decision remain pending and
  outside PR4.
- PR6 implementation and review made no remote inspection, workflow dispatch, or production
  deployment, and the hardened production migration deploy has not been dispatched. The known
  remote mismatch remains unresolved.
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
  deployment workflow has not been dispatched.
- `PR7 chore/disable-placeholder-refresh-schedule` — MERGED / COMPLETE; the placeholder schedule is
  disabled while real `mbm refresh` remains unavailable.
- `PR8 docs/regulatory-core-architecture-v1` — IN PROGRESS; ADR contracts are being frozen on its
  documentation-only branch.
- `PR9 refactor/versioned-config-contracts` — NEXT.
- Regulatory Data Core v1 schema work — NOT STARTED.

## Known pending gates

- A read-only remote Supabase inventory is still pending. It must verify migration history,
  objects, dependencies, and relevant counts before the first PR that creates or deploys v1 schema.
  It does not block Phase 0 toolchain work.
- CNBV source discovery, exact source-contract confirmation, and parser implementation remain
  pending for later phases.
- Supabase Storage suitability/retention must be confirmed before artifact backfill.

## How to update this file

After each PR that materially changes implementation or operational state, replace this snapshot
with the new truth. Do not append a diary, copy logs, duplicate ADRs, or preserve obsolete status.
