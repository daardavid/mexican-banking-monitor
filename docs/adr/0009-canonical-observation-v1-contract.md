# ADR 0009: Canonical observation v1 contract

- Status: Accepted
- Date: 2026-10-02

## Context

PR16 decides which reported facts are currently publishable. PR17 stores canonical concept
identity, immutable canonical versions, versioned scope support, stable mapping identity, and
immutable mapping versions, and it freezes effectiveness in ADR 0008. Neither PR creates a
canonical observation.

PR18 adds one private ordinary view, `semantic.canonical_observations_v1`. Production migrations
forbid `CREATE OR REPLACE VIEW` and `DROP VIEW`, so this view cannot be silently replaced in
place. The contract below is the permanent v1 meaning of that object.

## Decision

### Fact input

The sole fact input is `serving.current_publishable_facts`. `serving` has two logical roles:
fact-publishability contracts, which exist before this semantic projection, and later product
serving after metrics. `semantic` may depend on the fact-publishability contract. That read does
not create an object cycle: PR16 objects do not reference `semantic`, and this view does not
redefine them.

PR18 is not review authority. It does not duplicate PR16 revision, review, or accepted-frontier
logic. The view does not read `reported.reported_facts`, `audit.review_decisions`,
`audit.effective_review_decisions`, `serving.current_observed_facts`, or
`serving.reported_fact_revision_ancestry`.

The name `semantic.canonical_observations_v1` means current-publishable canonical observations.
Point-in-time and as-of semantic views are outside PR18.

### Dimensionless v1

A fact is eligible only when `dimensions = '{}'::jsonb`. This is an explicit v1 limitation. PR18
does not interpret, normalize, aggregate, remove, or transform dimensions. A fact with any other
dimensions emits nothing. A later dimensional contract requires an explicit dimensional mapping
and a new observation version.

### Economic date

For v1, `economic_date = period_end`. This is the projection convention used to evaluate
registration, regulatory, and mapping validity. It is not a claim that CNBV economic time is
universally `period_end`. Real CNBV evidence must confirm this convention and registration-period
behavior before PR21 publishes real facts through v1. If that evidence contradicts the
convention, PR21 must not publish real facts through this view.

### Registration and institution

The view joins the exact `registry.regulatory_registrations` row pinned by
`regulatory_registration_id`. That registration is usable only when its inclusive `validity`
contains `economic_date`. The exposed `institution_id` is that registration's institution.
PR18 does not evaluate `institution_definition_versions` and does not invent an
institution-definition head or lifecycle rule. A regulatory registration identifier remains a
registration, and `institution_id` is the durable institution identity.

### Exact regulatory row

Eligibility uses only the regulatory concept row pinned by `regulatory_concept_id`. That row must
have `lifecycle = active`, `valid_from <= economic_date`, and `valid_to` null or
`economic_date <= valid_to`. A higher regulatory `definition_version` does not displace the
pinned row. PR18 has no regulatory-head rule.

### Decisive mapping version

Mapping selection implements ADR 0008. Mapping identity remains the ADR 0008 triple
`(regulatory_concept_id, reporting_scope_id, canonical_concept_id)`. For one publishable fact,
candidate mapping identities are found by matching the fact's `regulatory_concept_id` and
`reporting_scope_id`. Different `canonical_concept_id` values therefore remain distinct mapping
identities and may legitimately fan out. Candidate versions are the versions of one
`concept_mapping_id` whose inclusive `validity` contains `economic_date`. Lifecycle,
comparability, and `transformation_key` stay unfiltered until the decisive version is known. The decisive version
is the covering version with the highest `definition_version`, identified by a `NOT EXISTS`
anti-join against any higher covering version of the same mapping. That decisive version is
usable only when its `lifecycle` is `active`. There is no fallback to an older version. A higher
`draft`, `review_required`, or `retired` covering version therefore suppresses an older `active`
version.

### Comparability

A decisive `active` version emits when `comparability` is `EXACT`, `HARMONIZED`, or `PROXY`. The
output preserves that label. `PROXY` and `HARMONIZED` remain private output and do not become
strict or public product data. `NOT_COMPARABLE` emits nothing.

### Transformations

A decisive version emits only when `transformation_key` is null. The emitted value is then the
fact's parsed value, unchanged. A non-null decisive `transformation_key` emits nothing and does
not fall back to an older mapping version. Python remains the execution authority for
transformations. PR18 does not execute a transformation and does not store formula text.

### Decisive canonical head and re-pin

The view joins the canonical concept version pinned by `canonical_concept_version_id` on the
decisive mapping version. That pin is usable only when no higher `definition_version` exists for
the same `canonical_concept_id`. The comparison covers every stored canonical version of that
concept, of any lifecycle, and it does not depend on `economic_date`. The pinned version must
also have `lifecycle = active`. There is no fallback to a different canonical version. A newer
canonical version of any lifecycle fail-closes an older pin. Restoring a row requires a new
mapping version that pins the new decisive `active` canonical version.

The pinned canonical version must support the fact's exact `reporting_scope_id` through
`semantic.canonical_concept_version_scopes`.

### Period and unit

`period_kind` must equal `semantic.canonical_concepts.period_kind`. `unit_code` must equal
`canonical_unit_code`. PR18 performs no unit conversion and does not consult
`registry.measurement_units.multiplier`.

### Value

`canonical_value` is unconstrained PostgreSQL `numeric` and equals `parsed_value`. The view
applies no cast, no `numeric(38,18)` coercion, no rounding, and no float. Persisted metric
observations may later impose `numeric(38,18)` with explicit precision rules. This projection
does not.

### Grain

One current publishable fact may match more than one mapping identity and therefore more than
one canonical concept. That fan-out is legitimate. The expected grain is
`(reported_fact_id, concept_mapping_id)`. Mapping identity includes `canonical_concept_id`, so
the same fact also yields at most one row per canonical concept when mapping identity is unique.
The view does not use `DISTINCT` to hide unexpected duplicates. It does not choose a winner among
rows that share an institution, canonical concept, scope, and period. Later metric calculation
must fail closed on an unresolved economic-key collision.

### Security and permanence

The view is `security_invoker`. `service_role` has `SELECT` only. `PUBLIC`, `anon`, and
`authenticated` have no privilege on the view. PR18 adds no table, function, policy, index,
trigger, sequence, extension, or security-definer object, and it inserts no seed rows.

Material semantic changes to this contract require a future versioned observation contract.
They are not made by silently reinterpreting `semantic.canonical_observations_v1`.

## Invariants

- The only PR18 database object is the ordinary view `semantic.canonical_observations_v1`.
- Every input fact comes from `serving.current_publishable_facts`.
- Only `dimensions = '{}'::jsonb` is eligible.
- `economic_date` is `period_end` for v1.
- The pinned registration must contain `economic_date`, and `institution_id` comes from that
  registration.
- The pinned regulatory row must be `active` and inclusively valid at `economic_date`.
- The highest covering mapping `definition_version` is decisive before lifecycle, comparability,
  and transformation are applied.
- The highest stored canonical `definition_version` is decisive across every lifecycle and is not
  selected by economic date.
- `EXACT`, `HARMONIZED`, and `PROXY` may emit privately. `NOT_COMPARABLE` emits nothing.
- A non-null decisive `transformation_key` emits nothing.
- `canonical_value` equals `parsed_value` with no cast.
- Economic-key collisions remain visible.
- PR18 has no point-in-time semantic view, no public contract, and no seeds.

## Consequences

Readers of `semantic.canonical_observations_v1` see the current publishable frontier after the
ADR 0008 mapping and canonical-head rules, registration validity, and the exact regulatory row.
Private `PROXY` and `HARMONIZED` rows stay labeled. Any failed decisive predicate removes the
fact from v1 output. PR21 must not publish real facts through v1 until CNBV evidence confirms
the `period_end` convention and registration-period behavior. Metric calculation in PR22 and
PR23 must fail closed when an economic key still has more than one visible observation. A
point-in-time semantic contract remains later work.

## Rejected alternatives

- Reading `reported` or `audit` directly, or reimplementing the PR16 frontier in this view.
- Propagating non-empty `dimensions` through a concept mapping that has no dimensional semantics.
- Casting `canonical_value` to `numeric(38,18)` inside an identity pass-through.
- Selecting the highest regulatory `definition_version` instead of the pinned row.
- Treating `period_end` as confirmed CNBV economic time before the PR21 evidence gate.
- Filtering mapping versions to `active` before the highest covering version is chosen.
- Falling back to an older mapping version or an older canonical pin when the decisive row is
  not usable.
- Emitting `NOT_COMPARABLE`, or executing a non-null `transformation_key` in SQL.
- Arbitrating institution, canonical concept, scope, and period collisions in the view.
- Choosing winners with `DISTINCT`, `DISTINCT ON`, `LIMIT`, ordering, or window functions.
- Adding a point-in-time view, a public contract, or seeds in PR18.
- Changing v1 semantics by replacing this view in place.
