begin;

create schema evidence;
create schema registry;
create schema reported;
create schema semantic;
create schema metrics;
create schema audit;
create schema serving;

revoke all privileges on schema evidence from public, anon, authenticated;
revoke all privileges on schema registry from public, anon, authenticated;
revoke all privileges on schema reported from public, anon, authenticated;
revoke all privileges on schema semantic from public, anon, authenticated;
revoke all privileges on schema metrics from public, anon, authenticated;
revoke all privileges on schema audit from public, anon, authenticated;
revoke all privileges on schema serving from public, anon, authenticated;

grant usage on schema evidence to service_role;
grant usage on schema registry to service_role;
grant usage on schema reported to service_role;
grant usage on schema semantic to service_role;
grant usage on schema metrics to service_role;
grant usage on schema audit to service_role;
grant usage on schema serving to service_role;

create table registry.measurement_units (
    unit_code text primary key,
    dimension text not null,
    currency_code text,
    multiplier numeric not null,
    constraint measurement_units_unit_code_not_blank
        check (btrim(unit_code) <> ''),
    constraint measurement_units_dimension_not_blank
        check (btrim(dimension) <> ''),
    constraint measurement_units_currency_code_not_blank
        check (currency_code is null or btrim(currency_code) <> ''),
    constraint measurement_units_multiplier_positive
        check (multiplier > 0)
);

create table registry.reporting_scopes (
    reporting_scope_id uuid primary key default gen_random_uuid(),
    scope_code text not null unique,
    definition_version integer not null,
    label text not null,
    definition text not null,
    rationale text not null,
    definition_snapshot jsonb not null,
    definition_hash text not null,
    git_sha text not null,
    constraint reporting_scopes_scope_code_not_blank
        check (btrim(scope_code) <> ''),
    constraint reporting_scopes_definition_version_positive
        check (definition_version > 0),
    constraint reporting_scopes_label_not_blank
        check (btrim(label) <> ''),
    constraint reporting_scopes_definition_not_blank
        check (btrim(definition) <> ''),
    constraint reporting_scopes_rationale_not_blank
        check (btrim(rationale) <> ''),
    constraint reporting_scopes_definition_snapshot_object
        check (jsonb_typeof(definition_snapshot) = 'object'),
    constraint reporting_scopes_definition_hash_sha256
        check (definition_hash ~ '^[a-f0-9]{64}$'),
    constraint reporting_scopes_git_sha_full
        check (git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')
);

alter table registry.measurement_units enable row level security;
alter table registry.reporting_scopes enable row level security;

revoke all privileges
on registry.measurement_units, registry.reporting_scopes
from public, anon, authenticated;

grant select, insert
on registry.measurement_units, registry.reporting_scopes
to service_role;

commit;
