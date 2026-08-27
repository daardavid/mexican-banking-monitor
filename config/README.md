# Editorial configuration

These `schema_version: 2` files are the Git-reviewed editorial authority for Regulatory Data Core
v1 definitions. Python remains executable authority; configuration never executes formulas, SQL,
templates, or arbitrary transformation text.

- `sources.yml` owns source metadata, non-secret endpoints, formats, roles, and symbolic adapters.
- `institutions.yml` keeps MONITOR identity separate from regulatory registrations, aliases, and
  explicit cohort memberships.
- `reporting_scopes.yml` owns the evidence-controlled scope registry.
- `concepts.yml` owns MONITOR canonical concepts, not source regulatory taxonomy.
- `mappings.yml` owns source concepts and their versioned bridge to canonical concepts.
- `metrics.yml` owns descriptive metric contracts and symbolic Python implementation keys.

Run `uv run --no-sync mbm validate-config` from the repository root to parse every required file
with duplicate-key-safe YAML, validate strict Pydantic contracts, and validate cross-references as
one deterministic bundle. Unsupported versions and unknown or extra fields fail closed.

Empty institutions, regulatory concepts, and mappings are intentional until source evidence is
curated. The current draft metric key is symbolic and does not claim an executable metric registry.
Validity endpoints are dates and are treated as inclusive for deterministic overlap validation.
Unit fields are opaque measurement-unit codes for the future registry; a unit record will separately
define its dimension, optional currency, and exact multiplier.

Regulator, country, and sector remain code fields; whole-bundle validation enforces the current
`cnbv` / `MX` / `banca_multiple` product boundary. Adapter, metric implementation, and mapping
transformation keys are reusable Python references, not editorial definition identities.
