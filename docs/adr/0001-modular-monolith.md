# ADR 0001: Modular monolith with a central Postgres database

- Status: Accepted
- Date: 2026-08-25

## Context

The product is initially maintained by one developer on two Windows laptops. It ingests public
CNBV releases, applies accounting and banking definitions, validates results, stores observations,
and serves a public analytical dashboard. Most changes to ingestion, normalization, calculations,
and publication must be released together.

## Decision

Build one Python application in one Git repository as a modular monolith. The modules are:

- `ingestion`: source discovery, download, validation, and parsing;
- `domain`: periods, institutions, releases, facts, and exact formulas;
- `analytics`: rolling calculations and cohort aggregation;
- `persistence`: Supabase/Postgres adapters;
- `dashboard`: the Streamlit presentation layer.

Use light domain-driven design:

- immutable domain values for reporting period, source artifact, institution, and financial fact;
- business formulas kept independent from files, SQL, Streamlit, and HTTP;
- adapters isolate CNBV and Postgres-specific behavior;
- versioned configuration records editorial choices and metric definitions.

Supabase provides one central Postgres database. Raw CNBV files remain outside Postgres; the database
stores normalized facts, calculated metrics, release hashes, and operational audit records.

## Consequences

- Both laptops reproduce the same environment from Git plus a local `.env`.
- A CNBV layout change is isolated in an ingestion adapter.
- Supabase can be replaced without rewriting metric rules.
- Deployment and debugging remain simple enough for one maintainer.
- Modules may be extracted later if independent scaling or ownership actually appears.

## Rejected alternatives

- **Unstructured monolith:** fastest for the first week but likely to become a set of corrective
  scripts with hidden coupling.
- **Microservices:** adds multiple deployments, contracts, secrets, queues, and distributed failure
  modes before there is enough traffic, team size, or independent scaling to justify them.
- **Full tactical DDD in every module:** adds aggregates and abstractions without enough domain
  behavior. Only rules that protect financial meaning receive domain types.
