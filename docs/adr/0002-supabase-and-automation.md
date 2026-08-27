# ADR 0002: Supabase for normalized data; GitHub Actions for orchestration

- Status: Accepted
- Date: 2026-08-25

## Decision

Use Supabase/Postgres for shared normalized data and published metrics. Use GitHub Actions for:

- code quality on every pull request;
- manual database migration deployment;
- weekday polling for new or revised CNBV releases;
- later, dashboard publication if a static frontend is added.

Do not use `pg_cron` for the Python ETL. The job downloads and parses external XLSX, CSV, and PDF
files, so GitHub Actions is easier to observe, retry, and reproduce. Reserve `pg_cron` for small
database-local maintenance tasks if they become necessary.

The first release uses one remote Supabase environment and local unit tests. Paid preview branches
or a second hosted project are deferred until schema change frequency or external users justify the
extra operational surface.

## Security rules

- No secret is committed to Git.
- Each laptop has its own untracked `.env`.
- GitHub stores production secrets in the `production` environment.
- The public dashboard receives only a publishable key and read-only RLS access.
- The Supabase secret key is available only to the ingestion job.
- Raw regulatory files, database passwords, access tokens, and Supabase secret keys are never exposed
  to the browser.

## Operational amendment — 2026-08-27

GitHub Actions remains the selected orchestrator, but the placeholder weekday schedule was disabled
after roadmap PR7 because it did not perform ingestion. Scheduled ingestion may be enabled again only
after the source adapter/parser, quality gates, and idempotency behavior for a real `mbm refresh` have
been implemented and validated. Until then, the refresh workflow is manual database preflight only.
