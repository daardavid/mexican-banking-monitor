# ADR 0003: Regulatory Data Core responsibilities and identifiers

- Status: Accepted
- Date: 2026-08-27

## Context

The legacy database groups MVP concerns into schemas whose identities and semantics cannot safely be
reinterpreted as the Regulatory Data Core v1. The v1 contracts also need durable identifiers and
exact financial values without coupling identity to a regulator's mutable coding scheme.

## Decision

The v1 database is divided by responsibility:

- `evidence`: regulators, sources, releases, and artifacts;
- `registry`: institutions, regulatory registrations, aliases, controlled reporting scopes,
  measurement units, and regulatory concepts;
- `reported`: immutable reported facts and their supersession chains;
- `semantic`: canonical concepts, mapping versions, and canonical observation views;
- `metrics`: metric definition versions, calculation runs, observations, and exact inputs;
- `audit`: ingestion runs, quality issues, and append-only review decisions;
- `serving`: explicit observed/publishable current and as-of contracts;
- `public`: explicitly versioned public read contracts.

The schemas `core`, `ops`, and `analytics` remain frozen legacy for the v1 transition. They are not
v1 authorities.

Durable identity and lineage entities use UUID v4. High-volume facts, observations, and issues use
`bigint identity`. Natural regulator/source codes are alternate `UNIQUE` keys, not durable primary
keys. A regulator registration identifier identifies a registration and is not institution
identity. UUIDv7 remains deferred while PostgreSQL 15 is the baseline.

Financial amounts and ratios use `Decimal` in Python and exact `numeric` in PostgreSQL. Financial
values never use `float`.

## Invariants

- A v1 writer writes only to v1 schemas; it never dual-writes to legacy.
- Legacy objects are not reinterpreted in place and legacy primary keys are not changed for
  convenience.
- Legacy remains available for logical rollback until an explicit consumer cutover and later
  retirement.
- A compatibility view is allowed only after semantic equivalence is demonstrated, tested, and
  documented.
- Public contracts are read surfaces, not evidence, fact, definition, or methodological authority.

## Consequences

Later schema PRs must create additive responsibility-based objects and preserve the distinction
between institution identity and regulatory registration. Identity migration and consumer cutover
require explicit reconciliation. This ADR defines no DDL.

## Rejected alternatives

- Extending legacy schemas as v1 authority: their semantics and lineage are insufficient.
- Dual-writing during transition: it creates competing truths and ambiguous rollback.
- Durable natural-code primary keys: regulator and source codes can change independently of the
  entity they describe.
- UUIDv7 on the PostgreSQL 15 baseline or financial `float`: neither is an approved v1 contract.
