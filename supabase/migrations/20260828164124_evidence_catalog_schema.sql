begin;

create table evidence.regulators (
    regulator_id uuid primary key default gen_random_uuid(),
    regulator_code text not null unique,
    name text not null,
    country text not null,
    constraint regulators_regulator_code_identifier
        check (regulator_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
    constraint regulators_name_not_blank
        check (btrim(name) <> ''),
    constraint regulators_country_code
        check (country ~ '^[A-Z]{2}$')
);

create table evidence.sources (
    source_id uuid primary key default gen_random_uuid(),
    regulator_id uuid not null,
    source_code text not null unique,
    constraint sources_regulator_fkey
        foreign key (regulator_id)
        references evidence.regulators(regulator_id),
    constraint sources_source_code_identifier
        check (source_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$')
);

create table evidence.source_definition_versions (
    source_definition_version_id uuid primary key default gen_random_uuid(),
    source_id uuid not null,
    definition_version integer not null,
    label text not null,
    country text not null,
    sector text not null,
    adapter_key text not null,
    methodological_role text not null,
    lifecycle text not null,
    definition_snapshot jsonb not null,
    config_hash text not null,
    git_sha text not null,
    constraint source_definition_versions_source_fkey
        foreign key (source_id)
        references evidence.sources(source_id),
    constraint source_definition_versions_source_definition_key
        unique (source_id, definition_version),
    constraint source_definition_versions_definition_version_positive
        check (definition_version > 0),
    constraint source_definition_versions_label_not_blank
        check (btrim(label) <> ''),
    constraint source_definition_versions_country_code
        check (country ~ '^[A-Z]{2}$'),
    constraint source_definition_versions_sector_identifier
        check (sector ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
    constraint source_definition_versions_adapter_key_identifier
        check (adapter_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
    constraint source_definition_versions_methodological_role_valid
        check (methodological_role in (
            'primary',
            'reconciliation',
            'authoritative_icap'
        )),
    constraint source_definition_versions_lifecycle_valid
        check (lifecycle in ('draft', 'active', 'review_required', 'retired')),
    constraint source_definition_versions_definition_snapshot_object
        check (jsonb_typeof(definition_snapshot) = 'object'),
    constraint source_definition_versions_config_hash_sha256
        check (config_hash ~ '^[a-f0-9]{64}$'),
    constraint source_definition_versions_git_sha_full
        check (git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')
);

create table evidence.source_releases (
    source_release_id uuid primary key default gen_random_uuid(),
    source_id uuid not null,
    release_family_key text not null,
    revision text,
    covered_period_start date,
    covered_period_end date,
    published_at timestamptz,
    first_observed_at timestamptz not null,
    release_identity_hash text not null,
    metadata jsonb not null,
    supersedes_source_release_id uuid,
    constraint source_releases_source_fkey
        foreign key (source_id)
        references evidence.sources(source_id),
    constraint source_releases_source_family_identity_key
        unique (source_id, release_family_key, release_identity_hash),
    constraint source_releases_lineage_target_key
        unique (source_release_id, source_id, release_family_key),
    constraint source_releases_supersedes_fkey
        foreign key (
            supersedes_source_release_id,
            source_id,
            release_family_key
        )
        references evidence.source_releases(
            source_release_id,
            source_id,
            release_family_key
        ),
    constraint source_releases_release_family_key_not_blank
        check (btrim(release_family_key) <> ''),
    constraint source_releases_revision_not_blank
        check (revision is null or btrim(revision) <> ''),
    constraint source_releases_covered_period_pair_valid
        check (
            (
                covered_period_start is null
                and covered_period_end is null
            )
            or
            (
                covered_period_start is not null
                and covered_period_end is not null
                and covered_period_start <= covered_period_end
            )
        ),
    constraint source_releases_identity_hash_sha256
        check (release_identity_hash ~ '^[a-f0-9]{64}$'),
    constraint source_releases_metadata_object
        check (jsonb_typeof(metadata) = 'object'),
    constraint source_releases_no_direct_self_supersession
        check (
            supersedes_source_release_id is null
            or supersedes_source_release_id <> source_release_id
        )
);

create index source_releases_supersedes_idx
    on evidence.source_releases (supersedes_source_release_id);

create table evidence.source_artifacts (
    source_artifact_id uuid primary key default gen_random_uuid(),
    source_release_id uuid not null,
    filename text not null,
    original_url text not null,
    final_url text not null,
    mime_type text not null,
    byte_length bigint not null,
    sha256 text not null,
    artifact_role text not null,
    storage_backend text not null,
    storage_bucket text,
    storage_key text not null,
    first_observed_at timestamptz not null,
    constraint source_artifacts_release_fkey
        foreign key (source_release_id)
        references evidence.source_releases(source_release_id),
    constraint source_artifacts_release_role_sha256_key
        unique (source_release_id, artifact_role, sha256),
    constraint source_artifacts_filename_not_blank
        check (btrim(filename) <> ''),
    constraint source_artifacts_original_url_not_blank
        check (btrim(original_url) <> ''),
    constraint source_artifacts_final_url_not_blank
        check (btrim(final_url) <> ''),
    constraint source_artifacts_mime_type_not_blank
        check (btrim(mime_type) <> ''),
    constraint source_artifacts_byte_length_positive
        check (byte_length > 0),
    constraint source_artifacts_sha256_valid
        check (sha256 ~ '^[a-f0-9]{64}$'),
    constraint source_artifacts_role_not_blank
        check (btrim(artifact_role) <> ''),
    constraint source_artifacts_storage_backend_not_blank
        check (btrim(storage_backend) <> ''),
    constraint source_artifacts_storage_bucket_not_blank
        check (storage_bucket is null or btrim(storage_bucket) <> ''),
    constraint source_artifacts_storage_key_not_blank
        check (btrim(storage_key) <> '')
);

create index source_artifacts_sha256_idx
    on evidence.source_artifacts (sha256);

alter table evidence.regulators enable row level security;
alter table evidence.sources enable row level security;
alter table evidence.source_definition_versions enable row level security;
alter table evidence.source_releases enable row level security;
alter table evidence.source_artifacts enable row level security;

revoke all privileges
on evidence.regulators,
   evidence.sources,
   evidence.source_definition_versions,
   evidence.source_releases,
   evidence.source_artifacts
from public, anon, authenticated, service_role;

grant select, insert
on evidence.regulators,
   evidence.sources,
   evidence.source_definition_versions,
   evidence.source_releases,
   evidence.source_artifacts
to service_role;

commit;
