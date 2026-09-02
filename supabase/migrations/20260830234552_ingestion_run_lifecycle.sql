begin;

create table audit.ingestion_runs (
    ingestion_run_id uuid primary key default gen_random_uuid(),
    source_id uuid not null,
    source_definition_version integer not null,
    trigger_kind text not null,
    parameters jsonb not null default '{}'::jsonb,
    parser_implementation_key text,
    parser_implementation_version text,
    identity_definition_hash text,
    git_sha text not null,
    status text not null default 'pending',
    created_at timestamptz not null default clock_timestamp(),
    started_at timestamptz,
    completed_at timestamptz,
    artifacts_observed_count bigint not null default 0,
    artifacts_new_count bigint not null default 0,
    artifacts_reused_count bigint not null default 0,
    artifacts_revised_count bigint not null default 0,
    artifacts_failed_count bigint not null default 0,
    error_code text,
    error_summary text,
    restart_of_ingestion_run_id uuid,
    constraint ingestion_runs_source_fkey
        foreign key (source_id)
        references evidence.sources(source_id),
    constraint ingestion_runs_source_definition_fkey
        foreign key (source_id, source_definition_version)
        references evidence.source_definition_versions(source_id, definition_version),
    constraint ingestion_runs_run_source_key
        unique (ingestion_run_id, source_id),
    constraint ingestion_runs_restart_fkey
        foreign key (restart_of_ingestion_run_id, source_id)
        references audit.ingestion_runs(ingestion_run_id, source_id),
    constraint ingestion_runs_source_definition_version_positive
        check (source_definition_version > 0),
    constraint ingestion_runs_trigger_kind_valid
        check (trigger_kind in ('manual', 'schedule', 'backfill', 'test')),
    constraint ingestion_runs_parameters_object
        check (jsonb_typeof(parameters) = 'object'),
    constraint ingestion_runs_parser_pair_valid
        check (
            (parser_implementation_key is null) =
            (parser_implementation_version is null)
        ),
    constraint ingestion_runs_parser_key_valid
        check (
            parser_implementation_key is null
            or (
                char_length(parser_implementation_key) <= 128
                and parser_implementation_key
                    ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
            )
        ),
    constraint ingestion_runs_parser_version_valid
        check (
            parser_implementation_version is null
            or (
                char_length(parser_implementation_version) <= 128
                and btrim(parser_implementation_version) <> ''
            )
        ),
    constraint ingestion_runs_identity_definition_hash_sha256
        check (
            identity_definition_hash is null
            or identity_definition_hash ~ '^[a-f0-9]{64}$'
        ),
    constraint ingestion_runs_git_sha_full
        check (git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$'),
    constraint ingestion_runs_status_valid
        check (status in ('pending', 'running', 'succeeded', 'failed', 'no_change')),
    constraint ingestion_runs_timestamps_match_status
        check (
            (
                status = 'pending'
                and started_at is null
                and completed_at is null
            )
            or
            (
                status = 'running'
                and started_at is not null
                and completed_at is null
                and created_at <= started_at
            )
            or
            (
                status in ('succeeded', 'failed', 'no_change')
                and started_at is not null
                and completed_at is not null
                and created_at <= started_at
                and started_at <= completed_at
            )
        ),
    constraint ingestion_runs_counters_nonnegative
        check (
            artifacts_observed_count >= 0
            and artifacts_new_count >= 0
            and artifacts_reused_count >= 0
            and artifacts_revised_count >= 0
            and artifacts_failed_count >= 0
        ),
    constraint ingestion_runs_counters_sum
        check (
            artifacts_observed_count =
                artifacts_new_count
                + artifacts_reused_count
                + artifacts_revised_count
                + artifacts_failed_count
        ),
    constraint ingestion_runs_active_counters_zero
        check (
            status not in ('pending', 'running')
            or artifacts_observed_count = 0
        ),
    constraint ingestion_runs_no_change_has_no_new_or_revised
        check (
            status <> 'no_change'
            or (
                artifacts_new_count = 0
                and artifacts_revised_count = 0
            )
        ),
    constraint ingestion_runs_error_shape
        check (
            (
                status = 'failed'
                and error_code is not null
                and char_length(error_code) <= 64
                and error_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
                and error_summary is not null
                and btrim(error_summary) <> ''
                and char_length(error_summary) <= 512
                and error_summary !~ '[[:cntrl:]]'
            )
            or
            (
                status <> 'failed'
                and error_code is null
                and error_summary is null
            )
        ),
    constraint ingestion_runs_no_direct_self_restart
        check (
            restart_of_ingestion_run_id is null
            or restart_of_ingestion_run_id <> ingestion_run_id
        )
);

create table audit.ingestion_run_artifacts (
    ingestion_run_artifact_id bigint generated always as identity primary key,
    ingestion_run_id uuid not null,
    source_artifact_id uuid,
    observed_url text not null,
    final_url text,
    observed_at timestamptz not null,
    http_status_code smallint,
    http_etag text,
    http_last_modified text,
    http_content_length bigint,
    result text not null,
    error_code text,
    error_summary text,
    constraint ingestion_run_artifacts_run_fkey
        foreign key (ingestion_run_id)
        references audit.ingestion_runs(ingestion_run_id),
    constraint ingestion_run_artifacts_artifact_fkey
        foreign key (source_artifact_id)
        references evidence.source_artifacts(source_artifact_id),
    constraint ingestion_run_artifacts_observed_url_not_blank
        check (btrim(observed_url) <> ''),
    constraint ingestion_run_artifacts_final_url_not_blank
        check (final_url is null or btrim(final_url) <> ''),
    constraint ingestion_run_artifacts_http_status_valid
        check (
            http_status_code is null
            or http_status_code between 100 and 599
        ),
    constraint ingestion_run_artifacts_http_etag_valid
        check (
            http_etag is null
            or (
                btrim(http_etag) <> ''
                and char_length(http_etag) <= 1024
                and http_etag !~ '[[:cntrl:]]'
            )
        ),
    constraint ingestion_run_artifacts_http_last_modified_valid
        check (
            http_last_modified is null
            or (
                btrim(http_last_modified) <> ''
                and char_length(http_last_modified) <= 128
                and http_last_modified !~ '[[:cntrl:]]'
            )
        ),
    constraint ingestion_run_artifacts_http_content_length_nonnegative
        check (http_content_length is null or http_content_length >= 0),
    constraint ingestion_run_artifacts_result_valid
        check (result in ('new', 'reused', 'revised', 'failed')),
    constraint ingestion_run_artifacts_result_shape
        check (
            (
                result in ('new', 'reused', 'revised')
                and source_artifact_id is not null
                and final_url is not null
                and error_code is null
                and error_summary is null
            )
            or
            (
                result = 'failed'
                and source_artifact_id is null
                and error_code is not null
                and char_length(error_code) <= 64
                and error_code ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
                and error_summary is not null
                and btrim(error_summary) <> ''
                and char_length(error_summary) <= 512
                and error_summary !~ '[[:cntrl:]]'
            )
        )
);

create function audit.enforce_ingestion_run_lifecycle()
returns trigger
language plpgsql
as $$
declare
    predecessor_status text;
begin
    if tg_op = 'INSERT' then
        if new.status <> 'pending'
            or new.started_at is not null
            or new.completed_at is not null
            or new.artifacts_observed_count <> 0
            or new.artifacts_new_count <> 0
            or new.artifacts_reused_count <> 0
            or new.artifacts_revised_count <> 0
            or new.artifacts_failed_count <> 0
            or new.error_code is not null
            or new.error_summary is not null
        then
            raise exception 'ingestion run must be inserted in canonical pending state';
        end if;

        new.created_at := clock_timestamp();

        if new.restart_of_ingestion_run_id is not null then
            select predecessor.status
            into predecessor_status
            from audit.ingestion_runs as predecessor
            where predecessor.ingestion_run_id = new.restart_of_ingestion_run_id
              and predecessor.source_id = new.source_id;

            if predecessor_status is distinct from 'failed' then
                raise exception 'restart predecessor must be a failed run for the same source';
            end if;
        end if;

        return new;
    end if;

    if old.status in ('succeeded', 'failed', 'no_change') then
        raise exception 'terminal ingestion run is immutable';
    end if;

    if row(
        new.ingestion_run_id,
        new.source_id,
        new.source_definition_version,
        new.trigger_kind,
        new.parameters,
        new.parser_implementation_key,
        new.parser_implementation_version,
        new.identity_definition_hash,
        new.git_sha,
        new.created_at,
        new.restart_of_ingestion_run_id
    ) is distinct from row(
        old.ingestion_run_id,
        old.source_id,
        old.source_definition_version,
        old.trigger_kind,
        old.parameters,
        old.parser_implementation_key,
        old.parser_implementation_version,
        old.identity_definition_hash,
        old.git_sha,
        old.created_at,
        old.restart_of_ingestion_run_id
    ) then
        raise exception 'ingestion run creation fields are immutable';
    end if;

    if old.status = 'pending' and new.status = 'running' then
        new.started_at := clock_timestamp();
        new.completed_at := null;
        new.artifacts_observed_count := 0;
        new.artifacts_new_count := 0;
        new.artifacts_reused_count := 0;
        new.artifacts_revised_count := 0;
        new.artifacts_failed_count := 0;
        new.error_code := null;
        new.error_summary := null;
        return new;
    end if;

    if old.status = 'running'
        and new.status in ('succeeded', 'failed', 'no_change')
    then
        new.started_at := old.started_at;
        new.completed_at := clock_timestamp();

        select
            count(*),
            count(*) filter (where artifact.result = 'new'),
            count(*) filter (where artifact.result = 'reused'),
            count(*) filter (where artifact.result = 'revised'),
            count(*) filter (where artifact.result = 'failed')
        into
            new.artifacts_observed_count,
            new.artifacts_new_count,
            new.artifacts_reused_count,
            new.artifacts_revised_count,
            new.artifacts_failed_count
        from audit.ingestion_run_artifacts as artifact
        where artifact.ingestion_run_id = old.ingestion_run_id;

        return new;
    end if;

    raise exception 'invalid ingestion run status transition';
end;
$$;

create trigger ingestion_runs_lifecycle
before insert or update on audit.ingestion_runs
for each row execute function audit.enforce_ingestion_run_lifecycle();

create function audit.enforce_ingestion_run_artifact_insert()
returns trigger
language plpgsql
as $$
declare
    parent_status text;
    parent_source_id uuid;
    artifact_source_id uuid;
    superseded_release_id uuid;
begin
    select run.status, run.source_id
    into parent_status, parent_source_id
    from audit.ingestion_runs as run
    where run.ingestion_run_id = new.ingestion_run_id
    for update;

    if parent_status is distinct from 'running' then
        raise exception 'artifact observation requires a running ingestion run';
    end if;

    if new.result in ('new', 'reused', 'revised') then
        select release.source_id, release.supersedes_source_release_id
        into artifact_source_id, superseded_release_id
        from evidence.source_artifacts as artifact
        join evidence.source_releases as release
          on release.source_release_id = artifact.source_release_id
        where artifact.source_artifact_id = new.source_artifact_id;

        if artifact_source_id is null then
            raise exception 'successful artifact observation requires catalog evidence';
        end if;

        if artifact_source_id <> parent_source_id then
            raise exception 'artifact observation source does not match ingestion run source';
        end if;

        if new.result = 'revised' and superseded_release_id is null then
            raise exception 'revised artifact observation requires source release lineage';
        end if;

        if new.result = 'new' and superseded_release_id is not null then
            raise exception 'new artifact observation cannot use a superseding source release';
        end if;
    end if;

    return new;
end;
$$;

create trigger ingestion_run_artifacts_insert_guard
before insert on audit.ingestion_run_artifacts
for each row execute function audit.enforce_ingestion_run_artifact_insert();

create function audit.reject_ingestion_run_artifact_mutation()
returns trigger
language plpgsql
as $$
begin
    raise exception 'ingestion run artifact observations are append-only';
end;
$$;

create trigger ingestion_run_artifacts_append_only
before update or delete on audit.ingestion_run_artifacts
for each row execute function audit.reject_ingestion_run_artifact_mutation();

create index ingestion_runs_source_created_idx
    on audit.ingestion_runs (source_id, created_at desc);

create index ingestion_runs_status_created_idx
    on audit.ingestion_runs (status, created_at desc);

create index ingestion_runs_restart_of_idx
    on audit.ingestion_runs (restart_of_ingestion_run_id)
    where restart_of_ingestion_run_id is not null;

create index ingestion_run_artifacts_run_idx
    on audit.ingestion_run_artifacts (
        ingestion_run_id,
        ingestion_run_artifact_id
    );

create index ingestion_run_artifacts_artifact_idx
    on audit.ingestion_run_artifacts (
        source_artifact_id,
        ingestion_run_artifact_id
    )
    where source_artifact_id is not null;

alter table audit.ingestion_runs enable row level security;
alter table audit.ingestion_run_artifacts enable row level security;

revoke all privileges
on audit.ingestion_runs, audit.ingestion_run_artifacts
from public, anon, authenticated, service_role;

revoke all privileges
on sequence audit.ingestion_run_artifacts_ingestion_run_artifact_id_seq
from public, anon, authenticated, service_role;

revoke all privileges
on function audit.enforce_ingestion_run_lifecycle(),
            audit.enforce_ingestion_run_artifact_insert(),
            audit.reject_ingestion_run_artifact_mutation()
from public, anon, authenticated, service_role;

grant select on audit.ingestion_runs to service_role;

grant insert (
    source_id,
    source_definition_version,
    trigger_kind,
    parameters,
    parser_implementation_key,
    parser_implementation_version,
    identity_definition_hash,
    git_sha,
    restart_of_ingestion_run_id
)
on audit.ingestion_runs to service_role;

grant update (status, error_code, error_summary)
on audit.ingestion_runs to service_role;

grant select on audit.ingestion_run_artifacts to service_role;

grant insert (
    ingestion_run_id,
    source_artifact_id,
    observed_url,
    final_url,
    observed_at,
    http_status_code,
    http_etag,
    http_last_modified,
    http_content_length,
    result,
    error_code,
    error_summary
)
on audit.ingestion_run_artifacts to service_role;

grant usage
on sequence audit.ingestion_run_artifacts_ingestion_run_artifact_id_seq
to service_role;

commit;
