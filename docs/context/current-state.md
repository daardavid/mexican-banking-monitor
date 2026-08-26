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
- Settings for local environment and Supabase connectivity, including secret-safe field repr.
- CLI commands `mbm validate-config` and `mbm doctor`; `doctor --database` performs a database
  connectivity ping when `MBM_DATABASE_URL` is configured.
- Exact domain models/formulas, YTD conversion, cohort helpers, and HTTP artifact validation/hash
  primitives with tests.
- Version-controlled YAML placeholders for sources, institutions, and metric descriptions; current
  validation checks file presence and `schema_version`, not the future typed contracts.
- One legacy initial migration creating `core`, `ops`, `analytics`, and the derived
  `public.bank_metrics` table with public read-only RLS.
- CI quality checks on Linux and PowerShell regression/full checks on Windows.
- Local bootstrap and both CI platforms use CPython 3.12.14 and `uv` 0.12.6; locked checks fail
  on dependency drift without rewriting `uv.lock`.
- Manual migration-deploy and scheduled refresh workflows exist, but their planned hardening and
  placeholder-schedule removal belong to later roadmap PRs.
- PowerShell bootstrap, update, shared command, regression, and full-check scripts.
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
- Each laptop keeps its own untracked `.env` and local `.venv`.
- Secrets live outside the repository; no secret values belong in this snapshot.
- The canonical rules are in `docs/operations/operational-contract.md`.

## Roadmap progress

- `PR1 chore/freeze-operational-contract` — MERGED / COMPLETE.
- `PR2 chore/pin-python-uv-toolchain` — IN PROGRESS.
- `PR3 fix/harden-two-laptop-update` — NEXT.
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
