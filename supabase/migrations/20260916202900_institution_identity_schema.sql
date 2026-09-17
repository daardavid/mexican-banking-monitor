begin;

set local search_path = public, extensions, pg_catalog;

create extension if not exists btree_gist with schema extensions;

create table registry.institutions (
    institution_id uuid primary key default gen_random_uuid(),
    institution_code text not null unique,
    country text not null,
    constraint institutions_institution_code_identifier
        check (institution_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
    constraint institutions_country_code
        check (country ~ '^[A-Z]{2}$')
);

create table registry.institution_definition_versions (
    institution_definition_version_id uuid primary key default gen_random_uuid(),
    institution_id uuid not null,
    definition_version integer not null,
    canonical_label text not null,
    lifecycle text not null,
    provenance text not null,
    definition_snapshot jsonb not null,
    definition_hash text not null,
    git_sha text not null,
    constraint institution_definition_versions_institution_fkey
        foreign key (institution_id)
        references registry.institutions(institution_id),
    constraint institution_definition_versions_institution_definition_key
        unique (institution_id, definition_version),
    constraint institution_definition_versions_identity_key
        unique (institution_definition_version_id, institution_id),
    constraint institution_definition_versions_definition_version_positive
        check (definition_version > 0),
    constraint institution_definition_versions_canonical_label_not_blank
        check (btrim(canonical_label) <> ''),
    constraint institution_definition_versions_lifecycle_valid
        check (lifecycle in ('draft', 'active', 'review_required', 'retired')),
    constraint institution_definition_versions_provenance_not_blank
        check (btrim(provenance) <> ''),
    constraint institution_definition_versions_definition_snapshot_object
        check (jsonb_typeof(definition_snapshot) = 'object'),
    constraint institution_definition_versions_definition_hash_sha256
        check (definition_hash ~ '^[a-f0-9]{64}$'),
    constraint institution_definition_versions_git_sha_full
        check (git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')
);

create table registry.regulatory_registrations (
    regulatory_registration_id uuid primary key default gen_random_uuid(),
    institution_id uuid not null,
    institution_definition_version_id uuid not null,
    regulator_id uuid not null,
    registration_type text not null,
    registration_code text not null,
    valid_from date not null,
    valid_to date,
    validity daterange generated always as (
        daterange(valid_from, valid_to, '[]')
    ) stored not null,
    constraint regulatory_registrations_institution_fkey
        foreign key (institution_id)
        references registry.institutions(institution_id),
    constraint regulatory_registrations_definition_institution_fkey
        foreign key (institution_definition_version_id, institution_id)
        references registry.institution_definition_versions (
            institution_definition_version_id,
            institution_id
        ),
    constraint regulatory_registrations_regulator_fkey
        foreign key (regulator_id)
        references evidence.regulators(regulator_id),
    constraint regulatory_registrations_registration_type_identifier
        check (registration_type ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
    constraint regulatory_registrations_registration_code_not_blank
        check (btrim(registration_code) <> ''),
    constraint regulatory_registrations_validity_ordered
        check (valid_to is null or valid_from <= valid_to),
    constraint regulatory_registrations_validity_excl
        exclude using gist (
            regulator_id with =,
            registration_type with =,
            registration_code with =,
            validity with &&
        )
);

create index regulatory_registrations_lookup_idx
    on registry.regulatory_registrations (
        regulator_id,
        registration_type,
        registration_code,
        valid_from
    );

create table registry.institution_aliases (
    institution_alias_id uuid primary key default gen_random_uuid(),
    institution_id uuid not null,
    institution_definition_version_id uuid not null,
    source_id uuid not null,
    alias_value text not null,
    normalized_alias text not null,
    alias_type text not null,
    valid_from date not null,
    valid_to date,
    validity daterange generated always as (
        daterange(valid_from, valid_to, '[]')
    ) stored not null,
    constraint institution_aliases_institution_fkey
        foreign key (institution_id)
        references registry.institutions(institution_id),
    constraint institution_aliases_definition_institution_fkey
        foreign key (institution_definition_version_id, institution_id)
        references registry.institution_definition_versions (
            institution_definition_version_id,
            institution_id
        ),
    constraint institution_aliases_source_fkey
        foreign key (source_id)
        references evidence.sources(source_id),
    constraint institution_aliases_alias_value_not_blank
        check (btrim(alias_value) <> ''),
    constraint institution_aliases_normalized_alias_not_blank
        check (btrim(normalized_alias) <> ''),
    constraint institution_aliases_alias_type_valid
        check (alias_type in ('legal_name', 'trade_name', 'source_label')),
    constraint institution_aliases_validity_ordered
        check (valid_to is null or valid_from <= valid_to),
    constraint institution_aliases_validity_excl
        exclude using gist (
            source_id with =,
            normalized_alias with =,
            validity with &&
        )
);

create index institution_aliases_lookup_idx
    on registry.institution_aliases (
        source_id,
        normalized_alias,
        valid_from
    );

create table registry.institution_cohorts (
    institution_cohort_id uuid primary key default gen_random_uuid(),
    institution_id uuid not null,
    institution_definition_version_id uuid not null,
    cohort_code text not null,
    valid_from date not null,
    valid_to date,
    validity daterange generated always as (
        daterange(valid_from, valid_to, '[]')
    ) stored not null,
    rationale text not null,
    constraint institution_cohorts_institution_fkey
        foreign key (institution_id)
        references registry.institutions(institution_id),
    constraint institution_cohorts_definition_institution_fkey
        foreign key (institution_definition_version_id, institution_id)
        references registry.institution_definition_versions (
            institution_definition_version_id,
            institution_id
        ),
    constraint institution_cohorts_cohort_code_identifier
        check (cohort_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
    constraint institution_cohorts_rationale_not_blank
        check (btrim(rationale) <> ''),
    constraint institution_cohorts_validity_ordered
        check (valid_to is null or valid_from <= valid_to),
    constraint institution_cohorts_validity_excl
        exclude using gist (
            institution_id with =,
            cohort_code with =,
            validity with &&
        )
);

create index institution_cohorts_lookup_idx
    on registry.institution_cohorts (
        institution_id,
        cohort_code,
        valid_from
    );

create table registry.regulatory_concepts (
    regulatory_concept_id uuid primary key default gen_random_uuid(),
    source_id uuid not null,
    external_code text not null,
    definition_version integer not null,
    label text not null,
    definition text not null,
    lifecycle text not null,
    valid_from date not null,
    valid_to date,
    definition_snapshot jsonb not null,
    definition_hash text not null,
    git_sha text not null,
    constraint regulatory_concepts_source_fkey
        foreign key (source_id)
        references evidence.sources(source_id),
    constraint regulatory_concepts_source_code_version_key
        unique (source_id, external_code, definition_version),
    constraint regulatory_concepts_external_code_not_blank
        check (btrim(external_code) <> ''),
    constraint regulatory_concepts_definition_version_positive
        check (definition_version > 0),
    constraint regulatory_concepts_label_not_blank
        check (btrim(label) <> ''),
    constraint regulatory_concepts_definition_not_blank
        check (btrim(definition) <> ''),
    constraint regulatory_concepts_lifecycle_valid
        check (lifecycle in ('draft', 'active', 'review_required', 'retired')),
    constraint regulatory_concepts_validity_ordered
        check (valid_to is null or valid_from <= valid_to),
    constraint regulatory_concepts_definition_snapshot_object
        check (jsonb_typeof(definition_snapshot) = 'object'),
    constraint regulatory_concepts_definition_hash_sha256
        check (definition_hash ~ '^[a-f0-9]{64}$'),
    constraint regulatory_concepts_git_sha_full
        check (git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')
);

create table registry.regulatory_concept_scopes (
    regulatory_concept_id uuid not null,
    reporting_scope_id uuid not null,
    constraint regulatory_concept_scopes_pkey
        primary key (regulatory_concept_id, reporting_scope_id),
    constraint regulatory_concept_scopes_concept_fkey
        foreign key (regulatory_concept_id)
        references registry.regulatory_concepts(regulatory_concept_id),
    constraint regulatory_concept_scopes_scope_fkey
        foreign key (reporting_scope_id)
        references registry.reporting_scopes(reporting_scope_id)
);

alter table registry.institutions enable row level security;
alter table registry.institution_definition_versions enable row level security;
alter table registry.regulatory_registrations enable row level security;
alter table registry.institution_aliases enable row level security;
alter table registry.institution_cohorts enable row level security;
alter table registry.regulatory_concepts enable row level security;
alter table registry.regulatory_concept_scopes enable row level security;

revoke all privileges
on registry.institutions,
   registry.institution_definition_versions,
   registry.regulatory_registrations,
   registry.institution_aliases,
   registry.institution_cohorts,
   registry.regulatory_concepts,
   registry.regulatory_concept_scopes
from public, anon, authenticated, service_role;

grant select
on registry.institutions,
   registry.institution_definition_versions,
   registry.regulatory_registrations,
   registry.institution_aliases,
   registry.institution_cohorts,
   registry.regulatory_concepts,
   registry.regulatory_concept_scopes
to service_role;

commit;
