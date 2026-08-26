# Mexico Banking Monitor

An auditable data pipeline and interactive monitor for Mexico's regulated banking system. It turns
monthly CNBV disclosures into comparable growth, profitability, asset-quality, funding, and capital
metrics for traditional banks and digital-first challengers.

## Why this project exists

Public regulatory data is valuable but operationally awkward: releases arrive on different dates,
files may be revised, labels change, result statements are often year-to-date, and legal entities do
not always match consumer brands. This project treats those details as part of the analysis rather
than hiding them behind charts.

## Initial scope

- Banca multiple from January 2022 onward.
- Monthly loan and deposit growth.
- NIM, ROA, ROE, ICAP, NPL/IMOR, coverage/ICOR, cost of risk, and loans-to-deposits.
- Release-level lineage, exact source hashes, calculation versions, and quality issues.
- Streamlit and Plotly dashboard.
- Automatic release detection with GitHub Actions.

## Architecture

The application is a modular Python monolith backed by Supabase/Postgres. The repository currently
contains an MVP/bootstrap schema; the approved Regulatory Data Core v1 target is documented but not
yet implemented:

```text
CNBV files -> ingestion -> normalized facts -> metric engine -> publication table -> dashboard
                       \-> lineage and quality issues -> operational audit
```

Business formulas are independent from HTTP, Postgres, and Streamlit. Raw CNBV artifacts are not
stored in the application database; only normalized facts, release metadata, hashes, and published
metrics are persisted.

See [ADR 0001](docs/adr/0001-modular-monolith.md),
[ADR 0002](docs/adr/0002-supabase-and-automation.md), and the
[Regulatory Data Core v1 roadmap](docs/roadmap/regulatory-data-core-v1.md).

## Development setup

Requirements: Git and uv. Docker is optional during the first phase.

```bash
uv python install 3.12
uv sync --locked --all-groups
cp .env.example .env
uv run mbm validate-config
uv run pytest
```

Run the bootstrap dashboard:

```bash
uv run streamlit run src/mx_bank_monitor/dashboard/app.py
```

Check the current machine:

```bash
uv run mbm doctor
uv run mbm doctor --database
```

Windows and two-laptop instructions are in
[docs/two-laptop-workflow.md](docs/two-laptop-workflow.md).
The canonical migration, cutover, and recovery rules are in
[docs/operations/operational-contract.md](docs/operations/operational-contract.md).

## Security

- `.env` is ignored and must exist separately on each laptop.
- GitHub Actions secrets belong to the protected `production` environment.
- The dashboard may use only Supabase's publishable key and a read-only RLS policy.
- The Supabase secret key and database password are server-side secrets.
- No source parser may silently replace, reinterpret, or drop an institution or period.

## Current status

Bootstrap foundation exists: package, exact domain formulas, basic configuration, one legacy SQL
schema, audit primitives, a read-only legacy publication surface, tests, CI, scheduled-job shell,
and a placeholder dashboard. Regulatory Data Core v1 is approved but not yet implemented. See the
compact [current-state snapshot](docs/context/current-state.md) for what exists and what comes next;
the later CNBV source-format work remains described in [docs/source-spike.md](docs/source-spike.md).

## License

MIT
