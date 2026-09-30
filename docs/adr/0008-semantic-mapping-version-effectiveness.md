# ADR 0008: Semantic mapping version effectiveness

- Status: Accepted
- Date: 2026-09-26

## Context

Reported regulatory concepts and canonical economic concepts are different taxonomies. PR17 is the
private semantic definition layer between `registry.regulatory_concepts` and the future
`semantic.canonical_observations_v1` view. It stores canonical concept identity, immutable
canonical definition versions, versioned scope support, stable mapping identity, and immutable
mapping versions.

PR17 does not create canonical observations, reported facts, or a definitions publisher, and it
does not seed definitions. Effectiveness rules are frozen here so a later publisher and PR18 can
implement them without rediscovering the contract.

## Decision

### Mapping identity and immutable versions

A mapping identity is the stable triple `(regulatory_concept_id, reporting_scope_id,
canonical_concept_id)`. Scope is part of that identity. There are no separate input and output
scope columns.

`semantic.concept_mappings` stores only that stable identity. `semantic.concept_mapping_versions`
stores append-only definition versions of one identity: validity, comparability, lifecycle,
methodology, provenance, a symbolic `transformation_key`, and the immutable snapshot, hash, and
Git SHA. `UNIQUE (concept_mapping_id, definition_version)` makes the version number decisive.

### Overlay effectiveness

Mapping versions may overlap. PR17 does not add an exclusion constraint, including no exclusion
of overlapping `active` versions.

For one `concept_mapping_id` and an economic date `d`, the covering versions are those whose
inclusive `validity` contains `d`. The decisive version is the covering version with the highest
`definition_version`. The mapping is usable for `d` only when that decisive version has
`lifecycle = active`.

A higher `draft`, `review_required`, or `retired` version therefore suppresses an older `active`
version while it covers `d`. Overlapping `active` versions are not repaired by the schema; the
higher `definition_version` wins.

### Decisive canonical version and re-pin

Canonical effectiveness is also derived, not stored as mutable current state. For one
`canonical_concept_id`, the decisive canonical version is the highest `definition_version`
currently stored. The canonical identity is usable only when that decisive version has
`lifecycle = active`.

A mapping version is currently usable only when its `canonical_concept_version_id` is that
decisive canonical version and the decisive lifecycle is `active`. A newer canonical version of
any lifecycle fail-closes older pins. Restoring usability requires a new mapping version that
pins the new decisive active canonical version. This is the canonical re-pin rule.

### Explicit retirement

Absence from current YAML is not retirement. Deleting a database row is not retirement. No
trigger infers retirement.

Retirement of a mapping identity or a canonical concept identity requires an explicit higher
definition version with `lifecycle = retired`. Current YAML keeps the head of every published
mapping identity and every published canonical concept identity, including a retired head. Older
non-head versions may disappear from current YAML after publication because Git history and the
immutable database snapshots preserve them. The future definitions publisher must fail closed
when a published identity head is missing.

### Comparability and lifecycle

Comparability is exactly `EXACT`, `HARMONIZED`, `PROXY`, or `NOT_COMPARABLE`. Lifecycle is
exactly `draft`, `active`, `review_required`, or `retired`.

`NOT_COMPARABLE` is stored negative semantic knowledge. Future PR18 does not emit it as a usable
canonical observation. `PROXY` may later appear in the private canonical observation layer with
comparability preserved. It must not silently become strict or public product data. PR17
implements no serving behavior.

### Inclusive validity and economic date

Mapping validity is `valid_from`, nullable `valid_to`, and a stored inclusive `daterange`
`[valid_from, valid_to]`. An omitted `valid_to` stays open-ended. The future economic date is a
single date `d`. PR17 does not encode `period_end` in schema logic. The initial PR18 candidate is
`d = reported fact period_end`, and real CNBV/YTD source evidence must confirm or replace that
candidate before PR21.

### Canonical structural identity

`data_nature`, `period_kind`, and `canonical_unit_code` are stable economic identity invariants.
They live only on `semantic.canonical_concepts`. `stock` pairs with `instant`, and `flow_ytd`
pairs with `duration`. They do not appear on canonical concept versions, and versions do not
carry validity dates.

### Mapping pins

Each mapping version pins three identities at once:

- the mapping identity, including its canonical concept and reporting scope;
- the canonical concept version of that same canonical concept;
- a scope supported by that canonical concept version.

Regulatory concept validity is not a subset constraint on mapping validity. PR17 does not modify
`registry.regulatory_concepts` and does not add a trigger that rejects a mapping whose validity
extends outside the referenced regulatory concept. Future PR18 must independently require that
regulatory concept validity contains `d` and that the decisive mapping validity contains `d`.

### Transformation and snapshots

A null `transformation_key` is the identity/pass-through candidate. A non-null key is only a
symbolic Python implementation name of at most 128 characters. PR17 stores no transformation
spec, formula text, SQL text, template text, or implementation version, and it does not implement
a Python transformation registry.

Only canonical concept versions and mapping versions carry `definition_snapshot`,
`definition_hash`, and `git_sha`. The hash is publisher-generated from normalized canonical JSON.
The database validates format only and does not implement a second JSON canonicalizer.

### PR21 definitions-publishing gate

Before PR21 performs any real definition or fact insertion, a reviewed definitions publisher must
exist. The default owner of that gate is the PR21 workstream. PR17 does not implement the
publisher and does not grant insert, update, or delete. Moving the gate to its own PR requires
an explicit roadmap amendment first. The roadmap is not renumbered by this decision.

## Invariants

- Five private semantic tables define the layer. `semantic.canonical_observations_v1` remains
  absent until PR18.
- Mapping and canonical effectiveness are predicates over immutable versions, not mutable
  current-state columns.
- The highest covering mapping `definition_version` is decisive even when it is not `active`.
- The highest stored canonical `definition_version` is decisive even when older pins remain.
- Retirement is an explicit higher `retired` version. YAML absence and row deletion are not
  retirement.
- `PROXY` stays distinct from strict/public product data. `NOT_COMPARABLE` is not usable
  observation output.
- Validity is inclusive. `period_end` is not a PR17 schema rule.
- Identity invariants are not restated on canonical concept versions.
- The database checks snapshot, hash, and Git SHA shape only.
- Runtime `service_role` is select-only on the five tables. No PR17 policy or security-definer
  object exists.

## Consequences

PR18 can build canonical observations as a reproducible view over reported facts and these
mapping versions without a physical observation table in PR17. The publisher that first inserts
real definitions has to preserve heads, hashes, Git SHAs, explicit retirement, and the re-pin
rule, and it has to fail closed on a missing published head. PR21 cannot insert real definitions
or facts until that publisher exists.

## Rejected alternatives

- An exclusion constraint on overlapping mapping validity: it would make a higher draft,
  `review_required`, or `retired` version unable to suppress an older active version.
- Treating YAML absence or row deletion as retirement: it destroys the explicit head and makes
  history ambiguous.
- Copying `data_nature`, `period_kind`, or `canonical_unit_code` onto every canonical version:
  it turns stable identity into versioned attributes.
- Encoding `period_end` as the PR17 economic date: source evidence has not confirmed it.
- A SQL JSON canonicalizer: the publisher owns one normalized hash input.
- Seeding canonical concepts or mappings in the migration: definitions remain editorial until
  the publisher gate.
- Granting mutation to `service_role` or adding policies: insertion belongs to the future
  publisher boundary.
- Creating `semantic.canonical_observations_v1` or the publisher in PR17: both are later work.
