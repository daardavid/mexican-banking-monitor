# ADR 0006: Controlled reporting scope

- Status: Accepted
- Date: 2026-08-27

## Context

The same institution, concept, and period can describe different legal or consolidation perimeters.
Free text, guessed defaults, or implicit compatibility would combine facts that are not necessarily
comparable.

## Decision

Reporting scope is a controlled dimension whose future editorial authority is
`config/reporting_scopes.yml`; it is never free text. The v1 baseline contains only
`individual_legal_entity`. Add `consolidated` only when an actual CNBV source demonstrates that
scope. Do not pre-seed speculative `regulatory_perimeter`, `financial_group`, or other unevidenced
scopes.

Scope is mandatory on reported facts and participates in fact identity, revision/current grouping,
idempotency, mapping selection, metric identity, metric input validation, and publication. The same
institution, concept, and economic period under different scopes represents different facts.

Default metric compatibility requires exact scope equality; no implicit compatibility matrix
exists. `loans_to_deposits` requires numerator and denominator from the same regulatory entity,
period, and scope, with compatible currency and units. A mismatch creates a quality issue and no
metric.

Any future cross-scope transformation requires an explicit mapping or metric-definition version. It
cannot be an implicit fallback.

## Invariants

- An unknown or ambiguous scope blocks fact creation and publication and produces a quality issue.
- Missing scope never silently becomes `individual_legal_entity`.
- Mappings and metric inputs declare and validate their scopes.
- Strict metric inputs use exact scope equality unless a later version explicitly contracts a
  source-proven transformation.

## Consequences

PR9 and later schema/runtime PRs must validate references to the controlled registry. Source
discovery, not speculation, determines whether additional scopes can be introduced.

## Rejected alternatives

- Free-text scope or parser-specific labels as stored authority: neither is cross-source stable.
- Pre-seeding plausible scopes: a plausible label is not evidence that CNBV reports that perimeter.
- Implicit scope coercion: it can produce financially invalid facts, metrics, and rankings.
- Publishing partial results after a scope mismatch: it hides a methodological blocker.
