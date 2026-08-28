# Plan maestro — Regulatory Data Core v1

> **Planning status:** this document describes the approved target architecture and roadmap, not
> necessarily what is already implemented. Read `docs/context/current-state.md` and inspect the
> code, migrations, and tests to establish current reality. Later ADRs may formalize individual
> decisions; this roadmap is not an executable implementation specification by itself.

Status: **APPROVED**
Initial product scope: **MONITOR BANCARIO — Mexican Banking Intelligence / Mexico / banca multiple**

## 1. Summary and boundaries

Evolve the MVP through additive migrations and small PRs until every published result has complete
lineage:

```text
CNBV → release → artifact → reported fact → mapping → canonical observation
     → versioned metric → serving → dashboard/API/research
```

Keep Python 3.12, `uv`, PostgreSQL/Supabase, Supabase CLI migrations, GitHub Actions, Ruff, Mypy,
Pytest, and the modular monolith. Do not add another warehouse, ORM, broker, cache, or microservice.

The remote Supabase database is potentially applied and contains data. Existing migrations are
immutable. Evolution is forward-only, additive, and non-destructive. The v1 core uses new schemas
by responsibility so it is not constrained by incompatible MVP objects.

The architecture is internally extensible to financial-institutions intelligence, but v1 does not
expand beyond Mexico/banca multiple. Multi-country, insurance, securities, generic macro/news,
crypto, and other sectors remain out of scope.

## 2. Baseline that informed the plan

### Existing strengths

- Modular Python monolith with exact `Decimal` domain formulas.
- PostgreSQL/Supabase, one versioned SQL migration, CI on Linux/Windows, and PowerShell scripts.
- HTTP retry/hash and artifact-validation primitives.
- Basic YAML for sources, institutions, and metrics.
- Legacy long-form facts, operations/audit primitives, metric tables, a derived public table, and
  public read-only RLS.

### Partial or placeholder capabilities

- Settings and `doctor --database` provide connectivity/ping, not the future schema preflight.
- YAML validation checks only file presence and `schema_version`.
- `institutions.yml` is empty and metric definitions are not an executable versioned engine.
- The Postgres repository only provides `ping()`.
- The Streamlit dashboard is a placeholder.
- Scheduled refresh performs a database doctor check while real ingestion remains disabled.
- The manual migration workflow exists but is not yet hardened to the v1 contract.

### Missing capabilities

- CNBV discovery and parsers.
- Private artifact storage and an evidence catalog.
- Regulatory registrations, controlled reporting scopes, regulatory/canonical concepts, mappings,
  explicit revision/review events, point-in-time queries, metric inputs, publication, and backfill.

### Critical debt

1. Legacy `ops.source_releases` mixes release and artifact concerns.
2. `core.financial_facts.value_mxn` loses raw value, unit, currency, source locator, scope, and exact
   source taxonomy.
3. `institution_id text` can be mistaken for a regulator identifier.
4. Monthly periods use the first day without distinguishing instant, flow, or YTD.
5. Legacy “current” is retrieval-recency, not an accepted publication decision.
6. Regulatory and canonical concepts are not separated.
7. YAML, Python, and SQL definitions can diverge.
8. Metric observations do not reference immutable definition versions and input lineage.
9. Primary evidence is not stored.
10. Partial metric coverage can be hidden by aggregation helpers.
11. Transaction-pooler compatibility and safe database preflight remain to be hardened.
12. Migration CI/deploy pinning, dry-run, serialization, drift detection, and verification remain to
    be hardened.

## 3. Target architecture

### Responsibility map

```text
evidence   → regulators, sources, releases, artifacts
registry   → institutions, registrations, aliases, controlled scopes, units, source concepts
reported   → reported facts and supersession chains
semantic   → canonical concepts, mapping versions, canonical observation views
metrics    → definition versions, runs, observations, inputs
audit      → ingestion runs, quality issues, append-only review decisions
serving    → observed/publishable current and as-of datasets
public     → explicitly versioned public contracts
```

```text
Versioned Git definitions
├── sources.yml
├── institutions.yml
├── reporting_scopes.yml
├── concepts.yml
├── mappings/*.yml
├── metrics.yml
└── Python parser/metric implementations
          │ definition/config hashes + Git SHA
          ▼
CNBV / regulator
  │
  ▼
SourceAdapter ─────────────────┐
  │ discovery/download         │
  ▼                            ▼
SOURCE RELEASE           INGESTION RUN ─── QUALITY ISSUE
  │                            │                 │
  ▼                            │                 ▼
SOURCE ARTIFACT ───────────────┘          REVIEW DECISION
  │ metadata/catalog
  ├──────────► private Supabase Storage / local filesystem
  ▼
REPORTED FACT
  │ exact source taxonomy, raw value, locator, economic time, scope, provenance
  ├──► supersession chain and observed/publishable as-of views
  ▼
CONCEPT MAPPING VERSION
  ▼
CANONICAL OBSERVATION VIEW
  ▼
METRIC ENGINE
  │ Git implementation + immutable DB definition snapshot
  ▼
METRIC OBSERVATION ─── METRIC OBSERVATION INPUTS
  ▼
SERVING VIEWS/CACHE
  ├──► versioned public RLS contract
  ├──► Streamlit
  └──► future reports/alerts
```

Lineage must always be traversable backward from any public result to exact metric inputs, mapping
and definition versions, reported facts, parser/config provenance, source locator, and artifact
SHA-256/location.

### Technical decisions

| Topic | Approved decision |
|---|---|
| Identifiers | UUID v4 for durable identity/lineage entities; `bigint identity` for high-volume facts, observations, and issues; natural codes are alternate `UNIQUE` keys. UUIDv7 is deferred while PostgreSQL 15 is the baseline. |
| Financial values | `Decimal` in Python; `raw_value text` and exact `parsed_value numeric` in reported facts; `numeric(38,18)` for canonical/metric values. Reject NaN and infinities. Never use `float`. |
| Evidence | Separate logical release from exact artifact. Preserve the artifact SHA-256, bytes, MIME, URL metadata, role, location, and observation time. |
| Economic time | `period_kind=instant/duration`, real `period_start`/`period_end`, and frequency. Instant stocks have no `period_start`; flow/YTD facts use an explicit range. |
| Knowledge/review time | `published_at`, `first_observed_at`, and append-only `decided_at` are separate; none substitutes for another. |
| Source locator | Relational `locator_kind` plus validated `source_locator jsonb` discriminated by Pydantic and a stable `locator_hash`. Do not add GIN indexes without measured need. |
| Revisions | Fact payloads and review decisions are append-only. Supersession and acceptance are separate. A new ambiguous revision remains pending while the previous accepted fact stays publishable. |
| Reporting scope | Controlled registry, never free text. Scope participates in fact identity, mappings, metric inputs, and publication. |
| Mappings | Git/YAML is editorial authority; DB stores immutable version/hash/Git-SHA snapshots. |
| Comparability | `EXACT`, `HARMONIZED`, `PROXY`, `NOT_COMPARABLE`; lifecycle `draft`, `active`, `review_required`, `retired`. Strict rankings use `EXACT` by default. |
| Metrics | YAML describes; Python executes; DB preserves the immutable definition snapshot and exact inputs. Never execute formula text from YAML/DB. |
| Canonical observations | Initially reproducible views over reported facts plus mapping versions, not a duplicated physical fact table. |
| Artifact storage | Private `regulatory-artifacts` bucket, content-addressed by SHA-256 with no overwrite; equivalent local `data/raw/` contract. Do not rely on bucket object-version overwrite behavior. |
| Migrations | Supabase CLI SQL migrations only, imperative/reviewed/versioned and forward-only. Do not introduce Alembic/SQLAlchemy or a second history. |
| Environments | Independent local Supabase/test DB per laptop, ephemeral DB in CI, and one shared remote Supabase. Hosted staging is deferred. |
| Derived data | Persist product metrics; exploratory calculations may remain on demand. Public tables/caches are rebuildable, never primary authority. |
| Materialization | Normal views first. Add materialized views only after measured need; require a unique index and refresh only after successful publication. |

### Editorial authority

- `config/institutions.yml`: curated institutions, registrations, aliases, and effective cohorts.
  DB is the queryable projection; unknown identities create issues rather than auto-creation.
- `config/sources.yml`: source codes, regulator, adapter, non-secret endpoints, formats, and
  methodological role. Observed releases/artifacts live in DB.
- `config/reporting_scopes.yml`: controlled scope definitions proven by real sources.
- `config/concepts.yml`: stable canonical definitions.
- `config/mappings/*.yml`: versioned mappings, validity, transformations, scope, comparability.
- `config/metrics.yml`: metadata, inputs, scope rules, units, frequency, rounding, and
  `implementation_key`. Python remains the executable implementation.
- Publishing definitions inserts immutable DB snapshots by hash; definitions are never edited
  manually in production.
- Any future `seed.sql` contains synthetic local/test data only.

### Planned interfaces

- Preserve `mbm doctor` and `mbm validate-config`.
- Evolve toward:
  - `mbm doctor --database --schema`: read-only, secret-safe schema preflight;
  - `mbm definitions publish`: idempotent Git-to-DB definition snapshots;
  - `mbm refresh --source cnbv_portfolio [--period YYYY-MM]`;
  - `mbm backfill --source ... --from ... --to ... --resume`.
- Python contracts:
  - `SourceAdapter.discover/download/parse`;
  - `ArtifactStore.put_if_absent/get/verify`;
  - Pydantic `ExcelLocator`, `CsvLocator`, `JsonLocator`, and `PdfLocator`;
  - `MetricImplementation.calculate(context) -> MetricResult`;
  - repositories with explicit observed/publishable current and as-of queries.

## 4. Candidate data model

### Evidence, audit, and registry

| Object | Purpose and essential contract |
|---|---|
| `evidence.regulators` | UUID PK; unique regulator code, name, country. Git-versioned reference data. |
| `evidence.sources` | Stable UUID PK/FK regulator identity with a unique source code. |
| `evidence.source_definition_versions` | Immutable Git/YAML source-definition versions with queryable projections, normalized snapshot, config hash, and Git SHA. This ADR 0007 implementation refinement mirrors reporting-scope identity/version separation. |
| `evidence.source_releases` | UUID PK/FK source/self-supersedes; family key, revision, covered period, `published_at`, `first_observed_at`, identity hash, metadata. Append-only. |
| `evidence.source_artifacts` | UUID PK/FK release; filename, original/final URL, MIME, bytes, SHA-256, role, storage backend/bucket/key, first observed. Payload immutable. |
| `audit.ingestion_runs` | UUID PK/FK source; trigger, parameters, parser/config/identity/Git versions, status, times, explicit counters. Terminal state immutable. |
| `audit.ingestion_run_artifacts` | Bigint PK/FKs run/artifact; observed URL, HTTP metadata, result, new/reused/revised, safe error. Append-only. |
| `audit.quality_issues` | Bigint PK with optional run/artifact/fact/mapping/metric links; code, severity, immutable details, resolution lineage. |
| `audit.review_decisions` | Append-only decisions for a fact: `ACCEPT`, `REJECT`, `REVOKE`, decision time/reason, human or versioned system policy actor, optional issue, and self-superseding correction. |
| `registry.institutions` | UUID PK; unique internal code, canonical label, country. Identity stable, editorial label versionable. |
| `registry.regulatory_registrations` | UUID PK/FKs institution/regulator; type/code/sector and non-overlapping validity. Regulator codes are not institution PKs. |
| `registry.institution_aliases` | UUID PK/FKs institution/source; alias type, normalized alias, provenance, validity. A rename does not create a new institution. |
| `registry.institution_cohorts` | UUID PK/FK institution; code, validity, rationale, definition hash. Never silently inferred. |
| `registry.measurement_units` | Text code PK; dimension, optional currency, exact multiplier. Git-versioned reference. |
| `registry.reporting_scopes` | Stable UUID PK and unique scope code identity. Only source-proven scopes. |
| `registry.reporting_scope_versions` | UUID PK/FK scope; unique scope/definition version, label, definition, rationale, lifecycle, immutable snapshot/hash/Git SHA. |
| `registry.regulatory_concepts` | UUID PK/FKs source/unit; external code, raw label, taxonomy version, data nature, expected frequency, validity. New row for semantic change. |
| `registry.regulatory_concept_scopes` | Composite PK/FKs concept/scope; declares allowed source scopes. |
| `reported.reported_facts` | Bigint PK/FKs registration, concept, scope, artifact, run, predecessor; economic time, currency/unit/dimensions, raw/parsed values, raw label, locator/hash, parser/config/identity versions, fact-key hash, observed time, supersession reason. Payload append-only. |

Expected initial scale: fewer than `10^5` reference/release objects, roughly `10^6–10^7` facts, and
up to `10^6` audit records. Do not partition until tens of millions of facts and measured
vacuum/index/latency evidence justify it.

### Semantic, metrics, and serving

| Object | Purpose and essential contract |
|---|---|
| `semantic.canonical_concepts` | UUID PK; unique stable code, definition, data nature, canonical unit. Semantic breaks create a new code/version. |
| `semantic.concept_mappings` | UUID PK/FKs regulatory/canonical concepts; stable source-to-target mapping identity. |
| `semantic.concept_mapping_versions` | UUID PK/FK mapping and scope inputs/outputs; version, validity, requirements, transformation key/spec, comparability, notes, snapshot/hash/Git SHA. Append-only, no overlapping active ranges. |
| `semantic.canonical_observations_v1` | Reproducible view keyed by fact/mapping version with canonical entity, period, scope, value/unit, and lineage. |
| `metrics.metric_definitions` | UUID PK; unique logical metric code and stable label. |
| `metrics.metric_definition_versions` | UUID PK/FK metric; version, implementation key, input/scope contract, unit/frequency, annualization, denominator, rounding, snapshot/hash/Git SHA. Append-only. |
| `metrics.calculation_runs` | UUID PK; purpose, knowledge cutoff, code version, status/times. Terminal state immutable. |
| `metrics.metric_observations` | Bigint PK/FKs institution, scope, metric version, run, predecessor; period, exact value, quality, input-set hash, calculation/knowledge times. Append-only/idempotent. |
| `metrics.metric_observation_inputs` | Composite observation/role/ordinal PK; FKs reported fact and mapping version. Exact input lineage. |
| `serving.current_observed_facts` | Latest observed head of each fact chain, including pending/rejected versions. |
| `serving.current_publishable_facts` | Latest effectively accepted version; an unaccepted successor does not displace it. |
| `serving.observed_facts_as_of(cutoff)` | What MONITOR had observed by the cutoff, independent of later decisions. |
| `serving.publishable_facts_as_of(cutoff)` | What MONITOR would have considered valid/publicable by the cutoff. |
| `serving.current_metric_observations` | Latest valid metric per definition/entity/period/scope, respecting input quality and version. |
| `public.regulatory_bank_metrics_v1` | Versioned RLS/read-only contract. Rebuildable, not a methodological authority. |

## 5. Legacy collision strategy

Schemas `core`, `ops`, and `analytics` are frozen. No v1 writer dual-writes to them, no primary key
is changed for convenience, and no object becomes v1 authority merely to preserve its name.

### Collision map

| Legacy object | Treatment | v1 replacement and cutover |
|---|---|---|
| `core.institutions` | **SUPERSEDE → EVENTUAL RETIREMENT** | `registry.institutions`; keep text PK intact and migrate any data explicitly with reconciliation. |
| `core.institution_aliases` | **SUPERSEDE → EVENTUAL RETIREMENT** | `registry.institution_aliases`; do not extend the incomplete legacy identity/provenance model. |
| `core.institution_cohorts` | **SUPERSEDE → EVENTUAL RETIREMENT** | `registry.institution_cohorts`; preserve legacy rows while v1 uses UUID and definition snapshots. |
| `core.financial_facts` | **SUPERSEDE → EVENTUAL RETIREMENT** | `reported.reported_facts`; keep read-only and do not auto-promote data lacking raw value, locator, scope, and lineage. |
| `core.current_financial_facts` | **KEEP → EVENTUAL RETIREMENT** | `serving.current_publishable_facts`; do not redefine because retrieval-recency is not publicability. |
| `ops.pipeline_runs` | **SUPERSEDE → EVENTUAL RETIREMENT** | `audit.ingestion_runs` plus `metrics.calculation_runs`; do not keep mixed run semantics. |
| `ops.pipeline_issues` | **SUPERSEDE → EVENTUAL RETIREMENT** | `audit.quality_issues`; preserve historical issues while v1 adds lineage and auditable resolution. |
| `ops.source_releases` | **SUPERSEDE → EVENTUAL RETIREMENT** | `evidence.source_releases` plus artifacts; do not split the hybrid table in place. |
| `analytics.metric_definitions` | **SUPERSEDE → EVENTUAL RETIREMENT** | `metrics.metric_definitions` plus immutable versions; do not reinterpret `calculation_version`. |
| `analytics.metric_observations` | **SUPERSEDE → EVENTUAL RETIREMENT** | `metrics.metric_observations` plus inputs; do not promote results without definition/input lineage. |
| `public.bank_metrics` | **KEEP / EVOLVE SAFELY → COMPATIBILITY VIEW EVENTUAL** | New consumers use `public.regulatory_bank_metrics_v1`. Substitute a compatibility view only after exact equivalence is proven. |

### Coexistence and cutover

1. Inventory remote migration history, schemas, dependencies, consumers, permissions, and relevant
   counts read-only.
2. Create v1 schemas/objects without altering legacy PKs, columns, data, or semantics.
3. Write new data exclusively to v1.
4. Run and reconcile the v1 vertical slice without changing consumers.
5. Migrate every consumer explicitly to a versioned v1 contract.
6. Keep legacy available for logical rollback.
7. Create compatibility views only for demonstrated semantic equivalence.
8. Retire legacy in a future separate PR after proving zero consumers and preserving reconciliation
   evidence.

Rollback disables affected v1 writers/readers and temporarily restores a legacy reader when viable.
Keep v1 schema/data for diagnosis and correct forward. Never delete production, reset remote, or
rewrite migration history.

## 6. Temporal and review semantics

### Four distinct times

- **Economic time:** the instant or duration represented by the fact.
- **Published time:** `evidence.source_releases.published_at`, when the source claims publication;
  nullable when unverifiable and never inferred from retrieval.
- **Observed time:** immutable `first_observed_at`, when MONITOR first obtained the evidence/fact.
- **Review decision time:** `audit.review_decisions.decided_at`, when MONITOR accepted, rejected, or
  revoked acceptance for one version.

`audit.review_decisions` is append-only and includes target fact, `ACCEPT`/`REJECT`/`REVOKE`, time,
reason code/text, `HUMAN` or `SYSTEM_POLICY` actor, actor reference or policy version, optional quality
issue, and an optional predecessor decision when correcting a prior decision.

`needs_review` is the absence of an effective acceptance plus a quality issue, not a mutable fact
status. A clean fact may receive an `ACCEPT` event from a versioned policy in the same transaction;
ambiguous revisions cannot auto-accept.

### Current and as-of

Unqualified `current` is forbidden in internal APIs:

- `current_observed`: latest observed chain head, even if pending/rejected.
- `current_publishable`: latest fact with an effective `ACCEPT` that has not been displaced by a
  later accepted version.
- Serving/dashboard `current` always means `current_publishable`.
- `observed_as_of(cutoff)`: facts with `first_observed_at <= cutoff`; ignores later decisions and can
  expose the observed head/history.
- `publishable_as_of(cutoff)`: facts observed by cutoff with an effective acceptance decision by
  cutoff and no rejection/revocation effective by cutoff; select the latest accepted chain version.

Example:

```text
10-Jul: revision B observed; pending review.
12-Jul: observed_as_of = B; publishable_as_of = accepted version A.
14-Jul: B accepted.
15-Jul: observed_as_of = B; publishable_as_of = B.
```

Backtests store `knowledge_cutoff_at` and `calculated_at`; a later calculation never claims it was
performed historically.

## 7. Revision and supersession model

`reported.reported_facts` stores predecessor, reason, artifact, parser/config/identity provenance,
ingestion run, and observation time.

| `supersession_reason` | Meaning |
|---|---|
| `SOURCE_REVISION` | The source published a different artifact/release or explicit official revision. |
| `EXTRACTION_CORRECTION` | Same artifact, but a new parser/config corrects extraction, dimensions, or parsed value. |
| `IDENTITY_CORRECTION` | Same evidence/locator, but MONITOR corrects institution or registration resolution. |
| `METHODOLOGY_CORRECTION` | Reserved for mapping or metric-definition versions; invalid on reported facts. |

Invariants:

- No predecessor means no reason; a predecessor requires a reason.
- `SOURCE_REVISION` requires new official evidence/release or artifact.
- `EXTRACTION_CORRECTION` requires the same artifact and changed parser/config.
- `IDENTITY_CORRECTION` may change the logical fact key through registration.
- A methodological change creates a mapping/metric version, never a reported fact.
- Chains are acyclic; only an accepted successor effectively displaces its predecessor.
- Fact identity includes registration, concept, economic period, scope, currency, unit, and
  dimensions.
- Supersession describes what is corrected; a separate review decision governs publicability.

For `same artifact + new parser version`:

- same output: create no fact; record reprocess/no-change on the new run;
- different output: create `EXTRACTION_CORRECTION`, open a quality issue, require review;
- same parser version with different output: determinism blocker.

Issues preserve old/new fact and artifact, supersession reason, old/new parser/config, raw/parsed or
identity/dimension differences, timestamps, and run.

## 8. Controlled reporting scope

Git/YAML is editorial authority through future `config/reporting_scopes.yml`. Seed only scopes
demonstrated by an actual source. The v1 baseline is `individual_legal_entity`; add `consolidated`
only after the CNBV source contract confirms it. Do not pre-seed `regulatory_perimeter`,
`financial_group`, or speculative scopes.

- Python uses a `ReportingScopeCode` value object validated against the loaded registry.
- Parsers translate source labels to registered scopes; unknown scope blocks fact creation and
  publication.
- Config validation cross-checks scopes in sources, concepts, mappings, and metrics.
- DB uses `registry.reporting_scopes` plus `registry.regulatory_concept_scopes`.
- Scope FK is mandatory on reported facts, mapping versions, and metric observations.
- Scope participates in fact key, revision/current grouping, idempotency, mapping selection, metric
  identity, and input validation.
- Same institution/concept/period with different scopes represents distinct facts.

Default v1 metric compatibility is exact scope equality; there is no implicit compatibility matrix.
`loans_to_deposits` requires the same regulatory entity, period, scope, and compatible units/currency
for numerator and denominator. A mismatch creates an issue and no metric. Any future scope
transformation requires a new declared mapping/metric version.

## 9. Operational and methodological policies

### Release/artifact identity

- Same logical release and same SHA: reuse artifact; run is `no_change`.
- Same filename and different SHA: new release revision/artifact; initially needs review.
- Distinct official republication with identical content: new release may reuse the content-addressed
  blob.
- New period/logical key: new release even if bytes match.
- Filename or SHA alone never identifies a release.

### Idempotency

- Release: source + release family + revision fingerprint.
- Artifact: release + role + SHA-256.
- Fact: artifact + locator hash + parser version + logical fact-key hash.
- Metric: definition version + entity + period/scope + input-set hash.
- Every rerun creates run audit but does not duplicate evidence, facts, or metrics.
- Catalog/storage completes before facts are inserted; process one artifact transactionally.

### Quality policy

Block/quarantine:

- empty/HTML/unexpected signature or MIME;
- checksum/storage mismatch;
- schema drift or period mismatch;
- ambiguous institution, registration, concept, or scope;
- conflicting fact or determinism failure;
- unexpected unit/currency for a required concept;
- non-finite numeric or transformation failure.

Require review before affected publication:

- unmapped concept;
- changed revision;
- proxy or not-comparable mapping;
- material balance/reconciliation mismatch;
- ambiguous institutional, scope, or methodological change.

Warnings:

- missing optional concept;
- a gap that invalidates only one metric;
- unavailable `published_at`;
- identical republication/no-change.

### Metrics

- First metric: `loans_to_deposits`.
- It uses two instant stocks for the same entity, period, and exact reporting scope.
- Calculate using `Decimal`; store `numeric(38,18)`.
- Metric version declares `ROUND_HALF_EVEN`; presentation may show percent to two decimals.
- CNBV-published ICAP remains a reported fact; MONITOR ICAP remains a derived metric; their
  difference would be a separate derived observation.
- Strict rankings exclude `PROXY` and expose coverage/comparability.

## 10. Roadmap by phase

PR size: **XS** documentation/workflow (about ≤200 lines), **S** one small interface/migration
(about ≤400), **M** one complete vertical behavior (about ≤700). No mega-PRs.

### Phase 0 — Operational foundation

- **Goal:** reproducible laptops, CI, preflight, and migrations before core schema.
- **Scope:** operational contract; pin Python 3.12.14, uv 0.12.6, Supabase CLI 2.115.0; harden
  two-laptop scripts, DB preflight, migration CI/deploy; disable placeholder cron.
- **DB:** no mutation; read-only remote inventory of history, objects, dependencies, and counts.
- **Acceptance:** consistent local/CI checks; stale lock fails; transaction-pooler compatibility;
  migrations rebuild ephemeral DB; main-only serialized dry-run/deploy/verify.
- **Recovery:** stop on tooling/drift; never automatically repair/reset remote.
- **Non-goals:** parser, v1 schema, Storage, product features.
- **Size/dependency:** 7 XS/S PRs; blocks schema work.

### Phase 1 — Architecture contract and schema primitives

- **Goal:** freeze language, IDs, four-time semantics, review events, supersession, scope, and
  editorial authority.
- **Dependencies:** Phase 0.
- **Scope:** ADRs, Pydantic config contracts/cross-validation, new responsibility schemas, units,
  reporting scopes.
- **DB:** additive v1 primitives; legacy remains intact/frozen.
- **Acceptance:** typed/cross-referenced YAML, migration reset/lint, no duplicate executable
  definition authority.
- **Non-goals:** real artifacts, facts, parsers.
- **Size:** 3 S PRs.

### Phase 2 — Evidence/source layer

- **Goal:** preserve evidence before interpretation.
- **Dependencies:** Phase 1.
- **Scope:** regulator/source/release/artifact, ingestion runs, local/Supabase ArtifactStore, hashes,
  parser/config/identity provenance.
- **Acceptance:** no-overwrite upload, rerun reuse, verifiable hash/bytes/MIME, failed/restart/
  no-change run lifecycle.
- **Recovery:** content addressing plus server-only permissions; failed runs preserve reusable
  artifacts.
- **Non-goals:** financial parsing.
- **Size:** 3 S/M PRs.

### Phase 3 — Identity, scopes, regulatory facts, and decisions

- **Goal:** represent exact entity/registration/scope/reported value and auditable publicability.
- **Dependencies:** Phase 2.
- **Scope:** institutions, registrations, aliases, units, concept-scope contracts, reported facts,
  locators, revision chains, review decisions, observed/publishable queries.
- **DB:** new `registry`, `reported`, `audit`, and `serving` objects; legacy receives no new writes.
- **Acceptance:** rename does not create an entity; regulator code is not a PK; exact instant/
  flow/YTD, raw value, scope, locator, provenance; no floats; decision-time scenarios pass.
- **Recovery:** ambiguous identity/scope is quarantined, never auto-created; fix forward.
- **Non-goals:** canonical taxonomy or metrics.
- **Size:** 4 S/M PRs including PR15a.

### Phase 4 — Semantic mapping layer

- **Goal:** separate source taxonomy from MONITOR canonical concepts.
- **Dependencies:** Phase 3.
- **Scope:** concepts, mapping versions, scope, comparability, canonical observation view.
- **Acceptance:** `EXACT` reproduces value/unit/scope; validity selects correct version; unmapped opens
  an issue; proxy excluded from strict ranking.
- **Recovery:** ambiguous methodology stays draft and produces no canonical observation.
- **Non-goals:** materialized views and complex aggregating mappings.
- **Size:** 2 M PRs.

### Phase 5 — Small CNBV vertical slice

- **Goal:** validate architecture with real evidence before volume.
- **Dependencies:** Phase 4.
- **Source/sample:** `cnbv_portfolio`, Serie Histórica Banca Múltiple, June 2026 release; 30-Apr,
  31-May, 30-Jun 2026; official registrations for BBVA México, Banco Mercantil del Norte, Banco
  Azteca, and Banco Regional.
- **Concepts:** gross loans, traditional deposits, net income YTD; discover exact source codes, do
  not invent them.
- **Acceptance:** artifact→fact→canonical lineage; exact registrations; validated scope; instant and
  duration facts; reproducible YTD-to-month; clean automatic acceptance plus pending/accepted
  revision; rerun creates zero facts; ambiguity blocks.
- **Recovery:** retain metadata and stop on layout/endpoints drift; disable adapter by config.
- **Non-goals:** ten years, all banks, ROE/NIM, dashboard.
- **Size:** 3 M PRs.

### Phase 6 — Metric engine

- **Goal:** first versioned/reproducible metric.
- **Dependencies:** Phase 5.
- **Scope:** metric definitions/versions, Python registry, scope rules, calculation runs,
  observations, inputs; first metric `loans_to_deposits`.
- **Acceptance:** exact result/scope; definition hash/Git SHA and inputs reconstructable;
  definition+inputs rerun does not duplicate; reported/derived remain distinct.
- **Recovery:** CI rejects implementation change without a version/hash contract update.
- **Non-goals:** ROA, ROE, NIM, cohorts, rankings.
- **Size:** 2 M PRs.

### Phase 7 — Quality, revisions, and idempotency

- **Goal:** deliberately prove methodological failure behavior.
- **Dependencies:** Phases 5–6.
- **Scope:** quality/review workflow, restart/checkpoints, observed/publishable time travel,
  supersession reasons, parser correction, scope mismatch.
- **Acceptance:** identical artifact; changed artifact; same artifact/new parser same/different result;
  unknown concept/institution/scope; missing fact; unit change; source/identity revision; review
  acceptance/rejection/revocation; as-of before/after; no partial publication.
- **Recovery:** false-positive revision never displaces the prior publishable version.
- **Non-goals:** review administration UI.
- **Size:** 2 M PRs; blocks scheduled ingestion/public serving.

### Phase 8 — Serving layer

- **Goal:** expose data without deforming the core.
- **Dependencies:** Phase 7.
- **Scope:** repositories, observed/publishable current/as-of, `public.regulatory_bank_metrics_v1`,
  first data-backed dashboard.
- **Acceptance:** read-only RLS; no secret in dashboard; lineage/scope/quality/comparability visible;
  pending/rejected absent; representative queries under one second.
- **Recovery:** atomic publish and full cache rebuild.
- **Non-goals:** separate API, Redis, alerts, advanced visual design.
- **Size:** 2 M PRs.

### Phase 9 — Historical backfill Mexico

- **Goal:** scale only after semantic validation.
- **Dependencies:** Phase 8.
- **Order:** 13-month pilot → 2025–2026 → 2024 → 2023 → 2022.
- **Scope:** resumable batches/checkpoints and reconciliation; mappings evolve through reviewed PRs,
  while data loads are operational runs rather than commits.
- **Acceptance:** resume/rerun without duplicates, counts/hashes per period, explicit gaps, QA report
  before each expansion.
- **Recovery:** quarantine by period and resume after taxonomy/layout correction.
- **Non-goals:** pre-2022 data or other regulated sectors.

### Phase 10 — Intelligence layer

- **Goal:** turn the core into explainable analytical product.
- **Dependencies:** reconciled backfill.
- **Scope:** growth, market share, peers, percentiles, comparable rankings, alerts, drivers.
- **Acceptance:** visible cohort coverage; no simple average of ratios; `PROXY` excluded; every output
  has versioned inputs/definition and explainable coverage/comparability.
- **Non-goals:** news, generic macro, stocks, crypto, recommendations.
- **Size:** one S/M capability per PR.

### Phase 11 — Multi-regulator readiness review

- **Goal:** test extensibility without implementing another country.
- **Dependencies:** complete core and one end-to-end slice.
- **Scope:** synthetic adapter contract and ADR of gaps; no DB changes unless a separately justified
  generic correction is indispensable.
- **Acceptance:** fictitious source/regulator uses the same core by adding adapter, concepts, and
  mappings only.
- **Non-goals:** real second regulator/country, insurance, productive multi-currency.
- **Size:** 1 XS/S PR; does not block Mexico operations.

## 11. Test strategy

### Cross-cutting baseline

1. Fresh DB: all migrations apply from zero and database lint passes.
2. Existing DB: sentinel rows, PKs, views, grants, and legacy objects remain intact.
3. Legacy writers: v1 never writes `core`, `ops`, or `analytics`; logical rollback changes readers
   without deleting v1; reject drop/truncate/legacy-PK changes.
4. RLS: `anon`/`authenticated` read only approved versioned serving data.
5. Artifact: valid XLSX/PDF/CSV, HTML, empty, MIME/signature mismatch, redirect, timeout, retry,
   checksum.
6. Storage: put-if-absent, no overwrite, local/Supabase contract parity.
7. Identity: aliases, renames, registration validity, unknowns, identity corrections.
8. Facts: exact `Decimal`, unit/currency/scope, format-specific locator, instant/flow/YTD.
9. Mappings: validity, transformation, unknowns, comparability, and explicit scope.
10. Metrics: version/hash, missing/zero denominator, rounding, inputs, idempotency, scope equality.
11. Quality: blocker/warning/manual review and no silent fallback.
12. Vertical slice: real artifact → canonical facts → `loans_to_deposits`.
13. Backfill: checkpoint, resume, rerun, reconciliation.
14. Serving: atomic publication, RLS, and no secret exposure.

### Review time

15. Revision observed 10-Jul and accepted 14-Jul: observed as-of 12-Jul returns new revision;
    publishable as-of 12-Jul returns prior version; publishable as-of 15-Jul returns new version.
16. Rejected revision never displaces accepted data.
17. Revoked acceptance ceases to be publishable at decision time.
18. Decision correction creates a new event and preserves the prior event.
19. Fact without effective acceptance is absent from serving.

### Supersession

20. New artifact/hash yields `SOURCE_REVISION`.
21. Same artifact + new parser + same result yields no-change.
22. Same artifact + new parser + different result yields `EXTRACTION_CORRECTION` and review.
23. Same artifact + same parser version + different result is a determinism blocker.
24. Registration reassignment yields `IDENTITY_CORRECTION`.
25. Mapping/formula change creates semantic/metric version, never reported fact.
26. Predecessor/reason constraints, cycle prevention, and at most one effective accepted successor.

### Controlled scope

27. Unregistered scope blocks the fact.
28. Facts identical except scope are distinct, not duplicates.
29. Source concept outside an allowed scope is rejected.
30. Wrong-scope mapping produces no canonical observation.
31. `loans_to_deposits` with mismatched scopes produces an issue/no metric; exact matching scope
    produces a result.
32. New config scope requires valid definition/hash and cross-references.

Initial coverage gate freezes the real 60% baseline against regression, rises to 75% after the
vertical slice, and to 80% after Phase 7, prioritizing meaningful scenarios over line chasing.

## 12. Decisions frozen now

1. Modular Python monolith over PostgreSQL/Supabase.
2. GitHub `main` is code authority; Git migrations are schema history.
3. Supabase CLI SQL migrations are forward-only and immutable after merge/application.
4. One schema PR in flight and one serialized remote deploy; merge→deploy→verify before the next.
5. Legacy `core`, `ops`, and `analytics` are frozen; v1 uses new responsibility schemas and never
   dual-writes or changes legacy PKs in place.
6. Architecture is evidence → registry/reported → semantic → metrics → serving/public.
7. Private, content-addressed artifact storage; PostgreSQL is evidence catalog/lineage.
8. UUID for durable entities, bigint for high-volume facts/audit; natural codes are alternate keys.
9. Exact `Decimal`/`numeric`, never financial `float`.
10. Economic, published, observed, and review-decision time are distinct.
11. Facts and review decisions are append-only; every supersession has a controlled reason.
12. Institution, regulatory registration, alias, and reporting scope are separate controlled
    dimensions; scope is never free text.
13. Regulatory and canonical concepts remain separate.
14. Git/YAML is editorial authority for sources, identity curation, scopes, concepts, mappings, and
    metrics; DB stores snapshots; Python executes metrics.
15. Canonical observations begin as reproducible views.
16. Serving consumes publishable facts only: effective acceptance, compatible scope, permitted
    mapping, and no quality blocker.
17. Ambiguous or `PROXY` data is not published or included in strict rankings.

## 13. Decisions deferred

- Partitioning; materialized views; external caches.
- Hosted staging; UUIDv7.
- Complex institution groups/mergers beyond evidence required for 2022+.
- Complex many-to-many canonical mappings.
- Review/mapping administration UI.
- External WORM archive.
- Separate API/microservice; Redis, Kafka, warehouse, search engine.
- Multi-country, insurance, securities, SOFIPO expansion, generic macro/news, crypto/stocks.
- FX conversion and productive multi-currency analytics.
- Full academic bitemporality.
- Final dashboard design.

## 14. Risks and open questions

1. Read-only remote inventory must confirm migration history, objects, dependencies, consumers,
   permissions, and relevant counts before the first schema PR. The plan remains additive regardless.
2. The source spike must confirm stable regulator codes and actually available publication/revision
   metadata; do not invent them.
3. Confirm artifact retention, size, quota, and terms before mass Supabase Storage backfill.
4. If `published_at` is unreliable, keep it nullable; never estimate it from retrieval.
5. IFRS 9 taxonomy changes or institutional succession in 2022+ may require additional mappings/
   relationships without changing immutable reported facts.
6. Unexpected remote drift blocks schema work and requires an explicit decision, never automatic
   repair.

## 15. Exact recommended PR sequence

There are 37 ordered PRs when PR15a is counted. Do not renumber or implement later PRs early.

| # | Branch | Purpose | Prerequisites | Acceptance summary |
|---:|---|---|---|---|
| 1 | `chore/freeze-operational-contract` | Persist roadmap/context; freeze topology, secrets, separate v1 schemas, legacy/no-dual-write, cutover, and recovery. | Clean clone outside OneDrive. | Canonical docs contain no secrets; no code/schema/workflow change. |
| 2 | `chore/pin-python-uv-toolchain` | Pin Python 3.12.14, uv 0.12.6, reproducible lock/check. | PR1. | Linux/Windows use identical versions; stale lock fails. |
| 3 | `fix/harden-two-laptop-update` | Reject dirty tree, wrong branch/upstream, and local divergence. | PR2. | PowerShell tests use temporary repos. |
| 4 | `fix/harden-database-preflight` | Secret-safe settings, timeouts, pooler compatibility, read-only schema checks. | PR2. | No DSN leak; transaction-pooler prepared statements disabled. |
| 5 | `ci/validate-supabase-migrations` | Ephemeral DB reset/lint/smoke validation. | PR2. | Invalid migration fails CI without remote secrets. |
| 6 | `ci/harden-production-migration-deploy` | Pin CLI; main-only/concurrency; dry-run/list/push/verify; detect drift, collisions, dependencies, destructive DDL. | PR1, PR5. | Stops on drift; never auto-repairs/retires; no `--include-all`. |
| 7 | `chore/disable-placeholder-refresh-schedule` | Stop cron that does not ingest. | PR4. | Refresh stays manual until real `mbm refresh`. |
| 8 | `docs/regulatory-core-architecture-v1` | ADRs for schema map, IDs, four times, review, supersession, scope, authority. | Phase 0. | Contracts approved/consistent. |
| 9 | `refactor/versioned-config-contracts` | Pydantic sources/institutions/reporting scopes/concepts/mappings/metrics. | PR8. | Cross-references, enums, duplicates, vocabularies, implementation keys validated. |
| 10 | `feat/data-core-schema-primitives` | Create responsibility schemas, units, scopes, primitives additively. | PR5, PR8. | Fresh reset; legacy intact; no legacy schema reuse. |
| 11 | `feat/evidence-catalog-schema` | Regulators, stable sources, immutable source-definition versions, releases, artifacts, and source revision lineage. | PR10. | Identity/version/revision constraints verified; legacy releases untouched. |
| 12 | `feat/artifact-storage-contract` | Local/Supabase content-addressed ArtifactStore. | PR11. | Put-if-absent/no overwrite. |
| 13 | `feat/ingestion-run-lifecycle` | Runs, run-artifacts, counters, restart, parser/config/identity provenance. | PR11–12. | Failed/no-change/success observable and idempotent. |
| 14 | `feat/institution-identity-schema` | `registry` institutions, registrations, aliases, cohorts, scope/concept constraints. | PR10. | Regulator IDs separated; valid effective ranges/scopes. |
| 15 | `feat/reported-fact-schema` | `reported` facts, locators, periods, scope fact-key, supersession reasons/provenance. | PR11, PR14. | Exact append-only payload and constraints. |
| 15a | `feat/review-decision-events` | Append-only acceptance/rejection/revocation and effective-decision query contract. | PR15. | Decision corrections preserve history; no mutable status authority. |
| 16 | `feat/fact-current-as-of-queries` | Observed/publishable current and as-of semantics. | PR15a. | Before/after review scenarios correct. |
| 17 | `feat/semantic-mapping-schema` | Canonical concepts and scoped mapping versions. | PR9, PR15. | Validity/comparability/scope/hashes intact. |
| 18 | `feat/canonical-observation-view` | Reproducible fact+mapping view preserving scope. | PR17. | `EXACT` transforms without physical duplication. |
| 19 | `feat/cnbv-release-discovery` | Real Serie Histórica discovery. | PR12–13. | Detects releases/artifacts/revisions without facts parsing. |
| 20 | `feat/cnbv-three-period-parser` | Parser for Apr–Jun 2026 with validated scope/provenance. | PR19. | Four entities, three concepts, locators/raw values. |
| 21 | `feat/cnbv-regulatory-slice` | Persist end-to-end slice; clean auto-accept and pending/accepted revision. | PR16, PR18, PR20. | Complete lineage; rerun creates zero duplicates. |
| 22 | `feat/versioned-metric-engine-schema` | Scoped metric versions, runs, observations, inputs. | PR21. | Definition hash/Git SHA/input contracts required. |
| 23 | `feat/metric-loans-to-deposits` | First metric with exact scope equality. | PR22. | Exact result and complete lineage. |
| 24 | `feat/quality-review-workflow` | Issues plus review decisions govern publication. | PR21–23. | No mutable fact status; blockers control serving. |
| 25 | `test/revisions-idempotency-point-in-time` | Full failures/revisions/review/parser-correction/scope matrix. | PR24. | All Phase 7 scenarios pass. |
| 26 | `feat/serving-query-layer` | Publishable queries and `public.regulatory_bank_metrics_v1`. | PR25. | Atomic publication/RLS; legacy public table preserved. |
| 27 | `feat/dashboard-first-regulatory-slice` | Minimal v1-contract consumer showing lineage/quality/scope. | PR26. | No secrets; methodology/comparability visible. |
| 28 | `feat/cnbv-backfill-runner` | Resumable backfill/checkpoints. | PR25. | Resume/rerun without duplicates. |
| 29 | `feat/cnbv-backfill-pilot-13-months` | Pilot window enabling YoY/TTM. | PR28. | QA/reconciliation before expansion. |
| 30 | `feat/cnbv-historical-mappings-2025-2026` | First historical mapping batch. | PR29. | No ambiguous concept active. |
| 31 | `feat/cnbv-historical-mappings-2022-2024` | Complete initial historical scope. | PR30. | Per-year backfill with QA reports. |
| 32 | `feat/market-share-metrics` | Versioned market share. | PR31. | Auditable numerators, denominators, scope, coverage. |
| 33 | `feat/growth-and-percentiles` | Growth and percentiles. | PR31. | Minimum 13 months; explicit gaps. |
| 34 | `feat/comparable-bank-rankings` | Strict comparable rankings. | PR32–33. | `EXACT` by default; coverage visible. |
| 35 | `feat/banking-alerts-and-drivers` | Deterministic alerts/explanations. | PR34. | Every alert has versioned definition/inputs. |
| 36 | `docs/multi-regulator-readiness-review` | Synthetic extensibility review without another country. | PR23, PR31. | Adapter does not alter the core. |

Every PR starts from updated `main`, has one purpose, includes appropriate tests, runs
`.\scripts\check.ps1`, documents migrations, and leaves the repository usable. A second schema PR
cannot begin until the prior one is merged, deployed, and verified.

## 16. GO / next action

**GO for PR1: `chore/freeze-operational-contract`.**

The read-only remote Supabase inventory remains mandatory before the first v1 schema PR, but it does
not block documentation-only PR1. No other critical architectural blocker remains.
