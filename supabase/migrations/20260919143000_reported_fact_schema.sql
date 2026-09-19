begin;

set local search_path = public, extensions, pg_catalog;

alter table evidence.sources
    add constraint sources_id_regulator_key
        unique (source_id, regulator_id);

alter table evidence.source_releases
    add constraint source_releases_id_source_key
        unique (source_release_id, source_id);

alter table evidence.source_artifacts
    add constraint source_artifacts_id_release_key
        unique (source_artifact_id, source_release_id);

alter table registry.regulatory_registrations
    add constraint regulatory_registrations_id_regulator_key
        unique (regulatory_registration_id, regulator_id);

alter table registry.regulatory_concepts
    add constraint regulatory_concepts_id_source_key
        unique (regulatory_concept_id, source_id);

alter table audit.ingestion_runs
    add constraint ingestion_runs_fact_provenance_key
        unique (
            ingestion_run_id,
            source_id,
            source_definition_version,
            parser_implementation_key,
            parser_implementation_version,
            identity_definition_hash
        );

create table reported.reported_facts (
    reported_fact_id bigint generated always as identity primary key,
    regulatory_registration_id uuid not null,
    regulator_id uuid not null,
    regulatory_concept_id uuid not null,
    source_id uuid not null,
    reporting_scope_id uuid not null,
    source_artifact_id uuid not null,
    source_release_id uuid not null,
    ingestion_run_id uuid not null,
    source_definition_version integer not null,
    parser_implementation_key text not null,
    parser_implementation_version text not null,
    identity_definition_hash text not null,
    period_kind text not null,
    period_start date,
    period_end date not null,
    unit_code text not null,
    dimensions jsonb not null default '{}'::jsonb,
    raw_value text not null,
    parsed_value numeric not null,
    raw_label text,
    locator_kind text not null,
    source_locator jsonb not null,
    locator_hash text not null,
    fact_key_hash text not null,
    first_observed_at timestamptz not null,
    predecessor_reported_fact_id bigint,
    supersession_reason text,
    constraint reported_facts_concept_scope_fkey
        foreign key (regulatory_concept_id, reporting_scope_id)
        references registry.regulatory_concept_scopes (
            regulatory_concept_id,
            reporting_scope_id
        ),
    constraint reported_facts_concept_source_fkey
        foreign key (regulatory_concept_id, source_id)
        references registry.regulatory_concepts (
            regulatory_concept_id,
            source_id
        ),
    constraint reported_facts_registration_regulator_fkey
        foreign key (regulatory_registration_id, regulator_id)
        references registry.regulatory_registrations (
            regulatory_registration_id,
            regulator_id
        ),
    constraint reported_facts_source_regulator_fkey
        foreign key (source_id, regulator_id)
        references evidence.sources (source_id, regulator_id),
    constraint reported_facts_artifact_release_fkey
        foreign key (source_artifact_id, source_release_id)
        references evidence.source_artifacts (
            source_artifact_id,
            source_release_id
        ),
    constraint reported_facts_release_source_fkey
        foreign key (source_release_id, source_id)
        references evidence.source_releases (source_release_id, source_id),
    constraint reported_facts_run_provenance_fkey
        foreign key (
            ingestion_run_id,
            source_id,
            source_definition_version,
            parser_implementation_key,
            parser_implementation_version,
            identity_definition_hash
        )
        references audit.ingestion_runs (
            ingestion_run_id,
            source_id,
            source_definition_version,
            parser_implementation_key,
            parser_implementation_version,
            identity_definition_hash
        ),
    constraint reported_facts_unit_fkey
        foreign key (unit_code)
        references registry.measurement_units (unit_code),
    constraint reported_facts_predecessor_fkey
        foreign key (predecessor_reported_fact_id)
        references reported.reported_facts (reported_fact_id),
    constraint reported_facts_extraction_identity_key
        unique (
            source_artifact_id,
            locator_hash,
            source_definition_version,
            parser_implementation_key,
            parser_implementation_version,
            fact_key_hash
        ),
    constraint reported_facts_source_definition_version_positive
        check (source_definition_version > 0),
    constraint reported_facts_parser_key_valid
        check (
            char_length(parser_implementation_key) <= 128
            and parser_implementation_key
                ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
        ),
    constraint reported_facts_parser_version_valid
        check (
            char_length(parser_implementation_version) <= 128
            and btrim(parser_implementation_version) <> ''
        ),
    constraint reported_facts_identity_definition_hash_sha256
        check (identity_definition_hash ~ '^[a-f0-9]{64}$'),
    constraint reported_facts_period_kind_valid
        check (period_kind in ('instant', 'duration')),
    constraint reported_facts_period_bounds_valid
        check (
            (
                period_kind = 'instant'
                and period_start is null
                and period_end is not null
            )
            or
            (
                period_kind = 'duration'
                and period_start is not null
                and period_end is not null
                and period_start <= period_end
            )
        ),
    constraint reported_facts_dimensions_object
        check (jsonb_typeof(dimensions) = 'object'),
    constraint reported_facts_raw_value_not_blank
        check (btrim(raw_value) <> ''),
    constraint reported_facts_parsed_value_finite
        check (
            parsed_value <> 'NaN'::numeric
            and parsed_value <> 'Infinity'::numeric
            and parsed_value <> '-Infinity'::numeric
        ),
    constraint reported_facts_raw_label_not_blank
        check (raw_label is null or btrim(raw_label) <> ''),
    constraint reported_facts_locator_kind_valid
        check (locator_kind in ('excel', 'csv', 'json', 'pdf')),
    constraint reported_facts_source_locator_object
        check (
            jsonb_typeof(source_locator) = 'object'
            and source_locator <> '{}'::jsonb
        ),
    constraint reported_facts_locator_hash_sha256
        check (locator_hash ~ '^[a-f0-9]{64}$'),
    constraint reported_facts_fact_key_hash_sha256
        check (fact_key_hash ~ '^[a-f0-9]{64}$'),
    constraint reported_facts_supersession_reason_valid
        check (
            supersession_reason is null
            or supersession_reason in (
                'SOURCE_REVISION',
                'EXTRACTION_CORRECTION',
                'IDENTITY_CORRECTION'
            )
        ),
    constraint reported_facts_supersession_pair_valid
        check (
            (predecessor_reported_fact_id is null) = (supersession_reason is null)
        ),
    constraint reported_facts_no_direct_self_predecessor
        check (
            predecessor_reported_fact_id is null
            or predecessor_reported_fact_id <> reported_fact_id
        )
);

create function reported.prepare_reported_fact_insert()
returns trigger
language plpgsql
as $$
declare
    predecessor reported.reported_facts%rowtype;
    parser_changed boolean;
    config_changed boolean;
begin
    new.locator_hash := encode(
        sha256(
            convert_to(
                jsonb_build_object(
                    'locator_kind', new.locator_kind,
                    'source_locator', new.source_locator
                )::text,
                'UTF8'
            )
        ),
        'hex'
    );

    new.fact_key_hash := encode(
        sha256(
            convert_to(
                jsonb_build_object(
                    'dimensions', new.dimensions,
                    'period_end', (new.period_end - date '0001-01-01'),
                    'period_kind', new.period_kind,
                    'period_start',
                    case
                        when new.period_start is null then null
                        else (new.period_start - date '0001-01-01')
                    end,
                    'regulatory_concept_id', new.regulatory_concept_id,
                    'regulatory_registration_id', new.regulatory_registration_id,
                    'reporting_scope_id', new.reporting_scope_id,
                    'unit_code', new.unit_code
                )::text,
                'UTF8'
            )
        ),
        'hex'
    );

    if new.predecessor_reported_fact_id is not null
        and new.predecessor_reported_fact_id = new.reported_fact_id
    then
        raise exception 'reported fact cannot precede itself';
    end if;

    if new.predecessor_reported_fact_id is null then
        if new.supersession_reason is not null then
            raise exception 'root reported fact must not have a supersession reason';
        end if;
        return new;
    end if;

    if new.supersession_reason is null then
        raise exception 'successor reported fact requires a supersession reason';
    end if;

    select *
    into predecessor
    from reported.reported_facts as existing
    where existing.reported_fact_id = new.predecessor_reported_fact_id;

    if not found then
        raise exception 'predecessor reported fact does not exist';
    end if;

    if predecessor.source_id is distinct from new.source_id then
        raise exception 'successor reported fact source does not match predecessor';
    end if;

    if new.supersession_reason = 'SOURCE_REVISION' then
        if new.source_artifact_id is not distinct from predecessor.source_artifact_id then
            raise exception 'SOURCE_REVISION requires a different source artifact';
        end if;
        return new;
    end if;

    if new.supersession_reason = 'EXTRACTION_CORRECTION' then
        if new.source_artifact_id is distinct from predecessor.source_artifact_id then
            raise exception 'EXTRACTION_CORRECTION requires the same source artifact';
        end if;

        parser_changed :=
            (new.parser_implementation_key, new.parser_implementation_version)
            is distinct from
            (
                predecessor.parser_implementation_key,
                predecessor.parser_implementation_version
            );
        config_changed :=
            new.source_definition_version
            is distinct from predecessor.source_definition_version;

        if not parser_changed and not config_changed then
            raise exception
                'EXTRACTION_CORRECTION requires a parser or source definition change';
        end if;
        return new;
    end if;

    if new.supersession_reason = 'IDENTITY_CORRECTION' then
        if new.source_artifact_id is distinct from predecessor.source_artifact_id then
            raise exception 'IDENTITY_CORRECTION requires the same source artifact';
        end if;
        if new.locator_kind is distinct from predecessor.locator_kind
            or new.source_locator is distinct from predecessor.source_locator
        then
            raise exception 'IDENTITY_CORRECTION requires the exact same source locator';
        end if;
        if new.regulatory_registration_id
            is not distinct from predecessor.regulatory_registration_id
        then
            raise exception 'IDENTITY_CORRECTION requires a different registration';
        end if;
        if new.identity_definition_hash
            is not distinct from predecessor.identity_definition_hash
        then
            raise exception 'IDENTITY_CORRECTION requires a different identity definition hash';
        end if;
        return new;
    end if;

    raise exception 'invalid reported fact supersession reason';
end;
$$;

create trigger reported_facts_prepare_insert
before insert on reported.reported_facts
for each row execute function reported.prepare_reported_fact_insert();

create function reported.reject_reported_fact_mutation()
returns trigger
language plpgsql
as $$
begin
    raise exception 'reported facts are append-only';
end;
$$;

create trigger reported_facts_append_only
before update or delete on reported.reported_facts
for each row execute function reported.reject_reported_fact_mutation();

create index reported_facts_predecessor_idx
    on reported.reported_facts (predecessor_reported_fact_id)
    where predecessor_reported_fact_id is not null;

create index reported_facts_logical_observed_idx
    on reported.reported_facts (fact_key_hash, first_observed_at desc);

create index reported_facts_registration_lookup_idx
    on reported.reported_facts (
        regulatory_registration_id,
        regulatory_concept_id,
        reporting_scope_id,
        period_end
    );

alter table reported.reported_facts enable row level security;

revoke all privileges
on reported.reported_facts
from public, anon, authenticated, service_role;

revoke all privileges
on sequence reported.reported_facts_reported_fact_id_seq
from public, anon, authenticated, service_role;

revoke all privileges
on function reported.prepare_reported_fact_insert(),
            reported.reject_reported_fact_mutation()
from public, anon, authenticated, service_role;

grant select on reported.reported_facts to service_role;

grant insert (
    regulatory_registration_id,
    regulator_id,
    regulatory_concept_id,
    source_id,
    reporting_scope_id,
    source_artifact_id,
    source_release_id,
    ingestion_run_id,
    source_definition_version,
    parser_implementation_key,
    parser_implementation_version,
    identity_definition_hash,
    period_kind,
    period_start,
    period_end,
    unit_code,
    dimensions,
    raw_value,
    parsed_value,
    raw_label,
    locator_kind,
    source_locator,
    first_observed_at,
    predecessor_reported_fact_id,
    supersession_reason
)
on reported.reported_facts to service_role;

grant usage
on sequence reported.reported_facts_reported_fact_id_seq
to service_role;

commit;
