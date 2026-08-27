# ADR 0007: Editorial authority and definition versioning

- Status: Accepted
- Date: 2026-08-27

## Context

Sources, identity curation, concepts, mappings, and metric contracts evolve. Reproducibility requires
one editorial authority, one executable authority, and immutable queryable records of every
published definition used to produce a result.

## Decision

Git/YAML is editorial authority for sources; institutions, regulatory registrations, aliases, and
cohorts; reporting scopes; canonical concepts; mappings; and metric metadata/contracts.

The database stores queryable immutable definition snapshots/projections plus observed evidence,
facts, runs, decisions, and results. Every published definition preserves its normalized snapshot,
definition/config hash, Git SHA, and, where applicable, implementation key/version. Production
definition snapshots are inserted by the publishing process and are never edited manually.

Python is executable authority for parsers, transformations selected by implementation key, and
metric calculations. Formula text in YAML or the database is descriptive and is never executed.
There is no second executable implementation of the same definition in YAML, SQL text stored as
data, or database formula text.

Regulatory taxonomy and canonical taxonomy remain separate. A versioned mapping is their explicit
bridge. Canonical observations begin as reproducible views over reported facts and mapping versions,
not as a duplicate physical fact table.

Mapping comparability uses exactly `EXACT`, `HARMONIZED`, `PROXY`, and `NOT_COMPARABLE`. Definition
lifecycle uses exactly `draft`, `active`, `review_required`, and `retired`. Strict rankings use
`EXACT` by default; `PROXY` never enters a strict ranking silently.

## Invariants

- Git/YAML changes become queryable only through immutable, hashed, Git-identified snapshots.
- Python implementations are selected by a validated implementation key/version, not arbitrary
  executable text.
- A regulatory concept is never silently treated as a canonical concept.
- A public or serving projection is rebuildable and is not definition or methodological authority.
- Historical results retain the exact definition and implementation provenance used to produce
  them.

## Consequences

PR9 will define typed, cross-referenced editorial contracts, and later PRs will implement definition
publishing and execution. Recalculations can select explicit historical versions without mutating
their definitions or reported inputs.

## Rejected alternatives

- Executing YAML/DB formula strings: it creates an unsafe competing runtime and weak provenance.
- Manually editing production snapshots: it breaks reproducibility and Git review authority.
- Combining regulatory and canonical taxonomies: it erases the source-to-product semantic decision.
- Physically copying canonical facts first: it creates duplicate fact authority before measured
  need.
