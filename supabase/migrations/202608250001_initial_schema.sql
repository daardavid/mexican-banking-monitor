begin;

create schema if not exists core;
create schema if not exists analytics;
create schema if not exists ops;

revoke all on schema core from anon, authenticated;
revoke all on schema analytics from anon, authenticated;
revoke all on schema ops from anon, authenticated;

create table core.institutions (
    institution_id text primary key,
    legal_name text not null,
    display_name text not null,
    regulatory_sector text not null
        check (regulatory_sector in ('banca_multiple', 'sofipo')),
    active_from date,
    active_to date,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (active_to is null or active_from is null or active_to >= active_from)
);

create table core.institution_aliases (
    institution_id text not null references core.institutions(institution_id),
    alias text not null,
    valid_from date,
    valid_to date,
    primary key (institution_id, alias),
    check (valid_to is null or valid_from is null or valid_to >= valid_from)
);

create table core.institution_cohorts (
    institution_id text not null references core.institutions(institution_id),
    cohort text not null
        check (cohort in (
            'traditional_bank',
            'digital_bank',
            'niche_bank',
            'sofipo_digital'
        )),
    valid_from date not null,
    valid_to date,
    rationale text not null,
    primary key (institution_id, cohort, valid_from),
    check (valid_to is null or valid_to >= valid_from)
);

create table ops.pipeline_runs (
    pipeline_run_id bigint generated always as identity primary key,
    trigger_kind text not null
        check (trigger_kind in ('manual', 'schedule', 'backfill', 'test')),
    status text not null
        check (status in ('running', 'succeeded', 'failed', 'no_change')),
    started_at timestamptz not null default now(),
    finished_at timestamptz,
    code_version text,
    details jsonb not null default '{}'::jsonb,
    check (finished_at is null or finished_at >= started_at)
);

create table ops.source_releases (
    source_release_id bigint generated always as identity primary key,
    source_kind text not null
        check (source_kind in ('historical_series', 'monthly_bulletin', 'capitalization')),
    regulatory_sector text not null
        check (regulatory_sector in ('banca_multiple', 'sofipo')),
    reporting_period date not null,
    source_url text not null,
    source_sha256 text not null check (source_sha256 ~ '^[a-f0-9]{64}$'),
    published_at timestamptz,
    retrieved_at timestamptz not null default now(),
    parser_version text not null,
    metadata jsonb not null default '{}'::jsonb,
    unique (source_kind, regulatory_sector, reporting_period, source_sha256),
    check (reporting_period = date_trunc('month', reporting_period)::date)
);

create table core.financial_facts (
    financial_fact_id bigint generated always as identity primary key,
    institution_id text not null references core.institutions(institution_id),
    reporting_period date not null,
    concept_code text not null,
    value_mxn numeric(24, 6) not null,
    source_release_id bigint not null references ops.source_releases(source_release_id),
    created_at timestamptz not null default now(),
    unique (institution_id, reporting_period, concept_code, source_release_id),
    check (reporting_period = date_trunc('month', reporting_period)::date)
);

create index financial_facts_lookup_idx
    on core.financial_facts (institution_id, reporting_period, concept_code);

create view core.current_financial_facts as
select distinct on (f.institution_id, f.reporting_period, f.concept_code)
    f.institution_id,
    f.reporting_period,
    f.concept_code,
    f.value_mxn,
    f.source_release_id
from core.financial_facts f
join ops.source_releases r using (source_release_id)
order by
    f.institution_id,
    f.reporting_period,
    f.concept_code,
    r.retrieved_at desc,
    r.source_release_id desc;

create table analytics.metric_definitions (
    metric_code text primary key,
    label text not null,
    formula_description text not null,
    calculation_version text not null,
    unit text not null check (unit in ('ratio', 'mxn', 'count')),
    created_at timestamptz not null default now()
);

create table analytics.metric_observations (
    institution_id text not null references core.institutions(institution_id),
    reporting_period date not null,
    metric_code text not null references analytics.metric_definitions(metric_code),
    calculation_version text not null,
    value numeric(24, 12),
    numerator numeric(24, 6),
    denominator numeric(24, 6),
    calculated_at timestamptz not null default now(),
    quality_status text not null default 'valid'
        check (quality_status in ('valid', 'insufficient_history', 'not_applicable', 'warning')),
    primary key (institution_id, reporting_period, metric_code, calculation_version),
    check (reporting_period = date_trunc('month', reporting_period)::date)
);

create table ops.pipeline_issues (
    pipeline_issue_id bigint generated always as identity primary key,
    pipeline_run_id bigint not null references ops.pipeline_runs(pipeline_run_id),
    severity text not null check (severity in ('info', 'warning', 'error')),
    issue_code text not null,
    institution_id text,
    reporting_period date,
    details jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

-- Denormalized, read-only publication surface for a public dashboard.
create table public.bank_metrics (
    institution_id text not null,
    institution_name text not null,
    regulatory_sector text not null,
    cohort text not null,
    reporting_period date not null,
    total_assets_mxn numeric(24, 2),
    gross_loans_mxn numeric(24, 2),
    traditional_deposits_mxn numeric(24, 2),
    loan_growth_yoy numeric(18, 12),
    deposit_growth_yoy numeric(18, 12),
    nim numeric(18, 12),
    roa numeric(18, 12),
    roe numeric(18, 12),
    icap numeric(18, 12),
    npl_ratio numeric(18, 12),
    coverage_ratio numeric(18, 12),
    cost_of_risk numeric(18, 12),
    loans_to_deposits numeric(18, 12),
    calculation_version text not null,
    published_at timestamptz not null default now(),
    primary key (institution_id, reporting_period, calculation_version),
    check (reporting_period = date_trunc('month', reporting_period)::date)
);

alter table public.bank_metrics enable row level security;

create policy "Public metrics are readable"
on public.bank_metrics
for select
to anon, authenticated
using (true);

revoke insert, update, delete, truncate, references, trigger
on public.bank_metrics
from anon, authenticated;

grant select on public.bank_metrics to anon, authenticated;

commit;
