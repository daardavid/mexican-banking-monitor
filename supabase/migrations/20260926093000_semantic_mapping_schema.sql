begin;

set local search_path = public, extensions, pg_catalog;

create table semantic.canonical_concepts (
    canonical_concept_id uuid primary key default gen_random_uuid(),
    concept_code text not null,
    data_nature text not null,
    period_kind text not null,
    canonical_unit_code text not null,
    constraint canonical_concepts_concept_code_key
        unique (concept_code),
    constraint canonical_concepts_unit_fkey
        foreign key (canonical_unit_code)
        references registry.measurement_units(unit_code),
    constraint canonical_concepts_concept_code_identifier
        check (concept_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
    constraint canonical_concepts_period_semantics
        check (
            (data_nature = 'stock' and period_kind = 'instant')
            or (data_nature = 'flow_ytd' and period_kind = 'duration')
        )
);

create table semantic.canonical_concept_versions (
    canonical_concept_version_id uuid primary key default gen_random_uuid(),
    canonical_concept_id uuid not null,
    definition_version integer not null,
    label text not null,
    definition text not null,
    lifecycle text not null,
    definition_snapshot jsonb not null,
    definition_hash text not null,
    git_sha text not null,
    constraint canonical_concept_versions_concept_fkey
        foreign key (canonical_concept_id)
        references semantic.canonical_concepts(canonical_concept_id),
    constraint canonical_concept_versions_concept_definition_key
        unique (canonical_concept_id, definition_version),
    constraint canonical_concept_versions_identity_key
        unique (canonical_concept_version_id, canonical_concept_id),
    constraint canonical_concept_versions_definition_version_positive
        check (definition_version > 0),
    constraint canonical_concept_versions_label_not_blank
        check (btrim(label) <> ''),
    constraint canonical_concept_versions_definition_not_blank
        check (btrim(definition) <> ''),
    constraint canonical_concept_versions_lifecycle_valid
        check (lifecycle in ('draft', 'active', 'review_required', 'retired')),
    constraint canonical_concept_versions_definition_snapshot_object
        check (jsonb_typeof(definition_snapshot) = 'object'),
    constraint canonical_concept_versions_definition_hash_sha256
        check (definition_hash ~ '^[a-f0-9]{64}$'),
    constraint canonical_concept_versions_git_sha_full
        check (git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')
);

create table semantic.canonical_concept_version_scopes (
    canonical_concept_version_id uuid not null,
    reporting_scope_id uuid not null,
    constraint canonical_concept_version_scopes_pkey
        primary key (canonical_concept_version_id, reporting_scope_id),
    constraint canonical_concept_version_scopes_version_fkey
        foreign key (canonical_concept_version_id)
        references semantic.canonical_concept_versions(canonical_concept_version_id),
    constraint canonical_concept_version_scopes_scope_fkey
        foreign key (reporting_scope_id)
        references registry.reporting_scopes(reporting_scope_id)
);

create table semantic.concept_mappings (
    concept_mapping_id uuid primary key default gen_random_uuid(),
    regulatory_concept_id uuid not null,
    reporting_scope_id uuid not null,
    canonical_concept_id uuid not null,
    constraint concept_mappings_identity_key
        unique (
            regulatory_concept_id,
            reporting_scope_id,
            canonical_concept_id
        ),
    constraint concept_mappings_pin_key
        unique (
            concept_mapping_id,
            canonical_concept_id,
            reporting_scope_id
        ),
    constraint concept_mappings_regulatory_scope_fkey
        foreign key (regulatory_concept_id, reporting_scope_id)
        references registry.regulatory_concept_scopes (
            regulatory_concept_id,
            reporting_scope_id
        ),
    constraint concept_mappings_canonical_concept_fkey
        foreign key (canonical_concept_id)
        references semantic.canonical_concepts(canonical_concept_id)
);

create table semantic.concept_mapping_versions (
    concept_mapping_version_id uuid primary key default gen_random_uuid(),
    concept_mapping_id uuid not null,
    canonical_concept_id uuid not null,
    reporting_scope_id uuid not null,
    canonical_concept_version_id uuid not null,
    definition_version integer not null,
    valid_from date not null,
    valid_to date,
    validity daterange generated always as (
        daterange(valid_from, valid_to, '[]')
    ) stored not null,
    transformation_key text,
    comparability text not null,
    lifecycle text not null,
    methodology_notes text not null,
    provenance text not null,
    definition_snapshot jsonb not null,
    definition_hash text not null,
    git_sha text not null,
    constraint concept_mapping_versions_mapping_pin_fkey
        foreign key (
            concept_mapping_id,
            canonical_concept_id,
            reporting_scope_id
        )
        references semantic.concept_mappings (
            concept_mapping_id,
            canonical_concept_id,
            reporting_scope_id
        ),
    constraint concept_mapping_versions_canonical_version_pin_fkey
        foreign key (canonical_concept_version_id, canonical_concept_id)
        references semantic.canonical_concept_versions (
            canonical_concept_version_id,
            canonical_concept_id
        ),
    constraint concept_mapping_versions_version_scope_fkey
        foreign key (canonical_concept_version_id, reporting_scope_id)
        references semantic.canonical_concept_version_scopes (
            canonical_concept_version_id,
            reporting_scope_id
        ),
    constraint concept_mapping_versions_mapping_definition_key
        unique (concept_mapping_id, definition_version),
    constraint concept_mapping_versions_definition_version_positive
        check (definition_version > 0),
    constraint concept_mapping_versions_validity_ordered
        check (valid_to is null or valid_from <= valid_to),
    constraint concept_mapping_versions_transformation_key_valid
        check (
            transformation_key is null
            or (
                char_length(transformation_key) <= 128
                and transformation_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
            )
        ),
    constraint concept_mapping_versions_comparability_valid
        check (comparability in ('EXACT', 'HARMONIZED', 'PROXY', 'NOT_COMPARABLE')),
    constraint concept_mapping_versions_lifecycle_valid
        check (lifecycle in ('draft', 'active', 'review_required', 'retired')),
    constraint concept_mapping_versions_methodology_notes_not_blank
        check (btrim(methodology_notes) <> ''),
    constraint concept_mapping_versions_provenance_not_blank
        check (btrim(provenance) <> ''),
    constraint concept_mapping_versions_definition_snapshot_object
        check (jsonb_typeof(definition_snapshot) = 'object'),
    constraint concept_mapping_versions_definition_hash_sha256
        check (definition_hash ~ '^[a-f0-9]{64}$'),
    constraint concept_mapping_versions_git_sha_full
        check (git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')
);

alter table semantic.canonical_concepts enable row level security;
alter table semantic.canonical_concept_versions enable row level security;
alter table semantic.canonical_concept_version_scopes enable row level security;
alter table semantic.concept_mappings enable row level security;
alter table semantic.concept_mapping_versions enable row level security;

revoke all privileges
on semantic.canonical_concepts,
   semantic.canonical_concept_versions,
   semantic.canonical_concept_version_scopes,
   semantic.concept_mappings,
   semantic.concept_mapping_versions
from public, anon, authenticated, service_role;

grant select
on semantic.canonical_concepts,
   semantic.canonical_concept_versions,
   semantic.canonical_concept_version_scopes,
   semantic.concept_mappings,
   semantic.concept_mapping_versions
to service_role;

commit;
