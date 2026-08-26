# Codex project map

## Project identity

- Product: **MONITOR BANCARIO — Mexican Banking Intelligence**.
- Internal target: an auditable regulatory/financial-institutions intelligence core.
- Current product scope: Mexico / banca multiple.
- Do not expand sectors, countries, or products without an explicit decision.

## Context hierarchy

1. `AGENTS.md` — map, invariants, and working rules.
2. `docs/context/current-state.md` — compact snapshot of what exists and what is next.
3. `docs/roadmap/regulatory-data-core-v1.md` — approved target and ordered roadmap.
4. `docs/adr/` and focused docs — durable decision rationale and operating contracts.
5. Code, migrations, and tests — what is actually implemented.

Planned architecture is not implemented architecture. Verify the repository before making claims.

## Sources of truth

- GitHub `main`: approved code and documentation.
- Git migrations: schema evolution; the remote database is not the code authority.
- Git/YAML: future editorial authority for sources, identity curation, concepts, mappings,
  metrics, and reporting scopes.
- Remote Supabase: shared backend, potentially applied and containing data.
- Regulatory artifacts plus reported facts: evidence and data lineage when implemented.

## Global invariants

- Keep a modular Python monolith backed by PostgreSQL/Supabase.
- Migrations are forward-only; never edit a merged or applied migration.
- Legacy schemas `core`, `ops`, and `analytics` are frozen for the v1 transition.
- Build v1 in new responsibility-based schemas; do not reinterpret legacy objects in place.
- Never dual-write between legacy and v1.
- Allow only one schema PR in flight: merge, deploy, and verify before the next.
- Every production schema change must be represented by a versioned Git migration.
- Never put secrets in Git, logs, docs, fixtures, screenshots, or command output.
- Financial amounts and ratios use exact `Decimal`/PostgreSQL `numeric`, never `float`.
- Methodological, identity, scope, or source ambiguity blocks processing/publication; do not
  apply a silent fallback.

## Context-loading protocol

For every new task:

1. Read this file.
2. Read `docs/context/current-state.md`.
3. Identify the requested PR or roadmap item.
4. Read only its relevant section in `docs/roadmap/regulatory-data-core-v1.md`.
5. Read the relevant ADRs, focused docs, and files affected by the task.
6. Inspect real code, migrations, and tests before assuming a capability exists.

> Do not load or summarize the entire roadmap unless the task requires it. Read the smallest relevant context set first.

## Task discipline

- One purpose and one small, reviewable PR per task.
- Start from clean, updated `main`; use an independent clone outside synchronized folders.
- Preserve the requested non-goals and do not implement later roadmap items early.
- Avoid lateral refactors and unrelated fixes.
- Add tests appropriate to the change and run `.\scripts\check.ps1`.
- Update `docs/context/current-state.md` when a PR materially changes the project state.
- Do not commit, push, deploy, or mutate remote systems unless the task explicitly authorizes it.

## Stop conditions

Stop and report the blocker instead of improvising if the task would require:

- an unapproved destructive migration or remote repair/reset;
- a required secret that is unavailable;
- an architecture-changing discrepancy between roadmap and repository;
- an ambiguous financial, methodological, identity, or reporting-scope decision;
- unexpected remote schema drift;
- editing a migration already merged or applied.
