\set ON_ERROR_STOP on

begin;

-- Report each required relation before evaluating the aggregate gate.
with expected_relations (schema_name, relation_name, expected_kind) as (
    values
        ('core', 'institutions', 'r'),
        ('core', 'current_financial_facts', 'v'),
        ('ops', 'pipeline_runs', 'r'),
        ('analytics', 'metric_definitions', 'r'),
        ('public', 'bank_metrics', 'r'),
        ('registry', 'measurement_units', 'r'),
        ('registry', 'reporting_scopes', 'r'),
        ('registry', 'reporting_scope_versions', 'r'),
        ('evidence', 'regulators', 'r'),
        ('evidence', 'sources', 'r'),
        ('evidence', 'source_definition_versions', 'r'),
        ('evidence', 'source_releases', 'r'),
        ('evidence', 'source_artifacts', 'r'),
        ('audit', 'ingestion_runs', 'r'),
        ('audit', 'ingestion_run_artifacts', 'r'),
        ('audit', 'ingestion_run_artifacts_ingestion_run_artifact_id_seq', 'S'),
        ('registry', 'institutions', 'r'),
        ('registry', 'institution_definition_versions', 'r'),
        ('registry', 'regulatory_registrations', 'r'),
        ('registry', 'institution_aliases', 'r'),
        ('registry', 'institution_cohorts', 'r'),
        ('registry', 'regulatory_concepts', 'r'),
        ('registry', 'regulatory_concept_scopes', 'r')
)
select
    format('%I.%I', expected.schema_name, expected.relation_name) as relation_name,
    expected.expected_kind,
    actual.relkind as actual_kind,
    actual.oid is not null and actual.relkind = expected.expected_kind::"char" as valid
from expected_relations expected
left join pg_catalog.pg_namespace namespace
    on namespace.nspname = expected.schema_name
left join pg_catalog.pg_class actual
    on actual.relnamespace = namespace.oid
    and actual.relname = expected.relation_name
order by expected.schema_name, expected.relation_name;

with expected_relations (schema_name, relation_name, expected_kind) as (
    values
        ('core', 'institutions', 'r'),
        ('core', 'current_financial_facts', 'v'),
        ('ops', 'pipeline_runs', 'r'),
        ('analytics', 'metric_definitions', 'r'),
        ('public', 'bank_metrics', 'r'),
        ('registry', 'measurement_units', 'r'),
        ('registry', 'reporting_scopes', 'r'),
        ('registry', 'reporting_scope_versions', 'r'),
        ('evidence', 'regulators', 'r'),
        ('evidence', 'sources', 'r'),
        ('evidence', 'source_definition_versions', 'r'),
        ('evidence', 'source_releases', 'r'),
        ('evidence', 'source_artifacts', 'r'),
        ('audit', 'ingestion_runs', 'r'),
        ('audit', 'ingestion_run_artifacts', 'r'),
        ('audit', 'ingestion_run_artifacts_ingestion_run_artifact_id_seq', 'S'),
        ('registry', 'institutions', 'r'),
        ('registry', 'institution_definition_versions', 'r'),
        ('registry', 'regulatory_registrations', 'r'),
        ('registry', 'institution_aliases', 'r'),
        ('registry', 'institution_cohorts', 'r'),
        ('registry', 'regulatory_concepts', 'r'),
        ('registry', 'regulatory_concept_scopes', 'r')
), relation_gate as (
    select bool_and(actual.oid is not null and actual.relkind = expected.expected_kind::"char")
        as valid
    from expected_relations expected
    left join pg_catalog.pg_namespace namespace
        on namespace.nspname = expected.schema_name
    left join pg_catalog.pg_class actual
        on actual.relnamespace = namespace.oid
        and actual.relname = expected.relation_name
), schema_gate as (
    select bool_and(pg_catalog.to_regnamespace(required_schema) is not null) as valid
    from unnest(array[
        'core', 'ops', 'analytics', 'evidence', 'registry',
        'reported', 'semantic', 'metrics', 'audit', 'serving'
    ]) as required_schema
), primitive_columns_gate as (
    select
        count(*) = 16
        and (
            select count(*) = 16
            from information_schema.columns
            where table_schema = 'registry'
              and table_name in (
                  'measurement_units', 'reporting_scopes', 'reporting_scope_versions'
              )
        ) as valid
    from (values
        ('measurement_units', 'unit_code', 'text', 'NO'),
        ('measurement_units', 'dimension', 'text', 'NO'),
        ('measurement_units', 'currency_code', 'text', 'YES'),
        ('measurement_units', 'multiplier', 'numeric', 'NO'),
        ('reporting_scopes', 'reporting_scope_id', 'uuid', 'NO'),
        ('reporting_scopes', 'scope_code', 'text', 'NO'),
        ('reporting_scope_versions', 'reporting_scope_version_id', 'uuid', 'NO'),
        ('reporting_scope_versions', 'reporting_scope_id', 'uuid', 'NO'),
        ('reporting_scope_versions', 'definition_version', 'integer', 'NO'),
        ('reporting_scope_versions', 'label', 'text', 'NO'),
        ('reporting_scope_versions', 'definition', 'text', 'NO'),
        ('reporting_scope_versions', 'rationale', 'text', 'NO'),
        ('reporting_scope_versions', 'lifecycle', 'text', 'NO'),
        ('reporting_scope_versions', 'definition_snapshot', 'jsonb', 'NO'),
        ('reporting_scope_versions', 'definition_hash', 'text', 'NO'),
        ('reporting_scope_versions', 'git_sha', 'text', 'NO')
    ) as expected(table_name, column_name, data_type, is_nullable)
    join information_schema.columns actual
      on actual.table_schema = 'registry'
     and actual.table_name = expected.table_name
     and actual.column_name = expected.column_name
     and actual.data_type = expected.data_type
     and actual.is_nullable = expected.is_nullable
), primitive_constraints_gate as (
    select
        count(*) = 19
        and (
            select count(*) = 19
            from pg_catalog.pg_constraint all_constraints
            join pg_catalog.pg_class constrained_relation
              on constrained_relation.oid = all_constraints.conrelid
            join pg_catalog.pg_namespace constrained_namespace
              on constrained_namespace.oid = constrained_relation.relnamespace
            where constrained_namespace.nspname = 'registry'
              and constrained_relation.relname in (
                  'measurement_units', 'reporting_scopes', 'reporting_scope_versions'
              )
        ) as valid
    from (values
        ('measurement_units', 'measurement_units_pkey', 'p', 'PRIMARY KEY (unit_code)'),
        ('measurement_units', 'measurement_units_unit_code_not_blank', 'c', null),
        ('measurement_units', 'measurement_units_dimension_not_blank', 'c', null),
        ('measurement_units', 'measurement_units_currency_code_not_blank', 'c', null),
        ('measurement_units', 'measurement_units_multiplier_positive', 'c', null),
        ('reporting_scopes', 'reporting_scopes_pkey', 'p',
            'PRIMARY KEY (reporting_scope_id)'),
        ('reporting_scopes', 'reporting_scopes_scope_code_key', 'u', 'UNIQUE (scope_code)'),
        ('reporting_scopes', 'reporting_scopes_scope_code_not_blank', 'c', null),
        ('reporting_scope_versions', 'reporting_scope_versions_pkey', 'p',
            'PRIMARY KEY (reporting_scope_version_id)'),
        ('reporting_scope_versions', 'reporting_scope_versions_scope_fkey', 'f',
            'FOREIGN KEY (reporting_scope_id) REFERENCES registry.reporting_scopes(reporting_scope_id)'),
        ('reporting_scope_versions', 'reporting_scope_versions_scope_definition_key', 'u',
            'UNIQUE (reporting_scope_id, definition_version)'),
        ('reporting_scope_versions',
            'reporting_scope_versions_definition_version_positive', 'c', null),
        ('reporting_scope_versions', 'reporting_scope_versions_label_not_blank', 'c', null),
        ('reporting_scope_versions', 'reporting_scope_versions_definition_not_blank', 'c', null),
        ('reporting_scope_versions', 'reporting_scope_versions_rationale_not_blank', 'c', null),
        ('reporting_scope_versions', 'reporting_scope_versions_lifecycle_valid', 'c', null),
        ('reporting_scope_versions',
            'reporting_scope_versions_definition_snapshot_object', 'c', null),
        ('reporting_scope_versions',
            'reporting_scope_versions_definition_hash_sha256', 'c', null),
        ('reporting_scope_versions', 'reporting_scope_versions_git_sha_full', 'c', null)
    ) as expected(table_name, constraint_name, constraint_kind, constraint_definition)
    join pg_catalog.pg_namespace namespace on namespace.nspname = 'registry'
    join pg_catalog.pg_class relation
      on relation.relnamespace = namespace.oid
     and relation.relname = expected.table_name
    join pg_catalog.pg_constraint actual
      on actual.conrelid = relation.oid
     and actual.conname = expected.constraint_name
     and actual.contype = expected.constraint_kind::"char"
     and (
         expected.constraint_definition is null
         or pg_catalog.pg_get_constraintdef(actual.oid) = expected.constraint_definition
     )
), scope_versioning_gate as (
    select
        count(*) = 2
        and not exists (
            select 1
            from pg_catalog.pg_constraint identity_only_unique
            join pg_catalog.pg_class version_relation
              on version_relation.oid = identity_only_unique.conrelid
            join pg_catalog.pg_namespace version_namespace
              on version_namespace.oid = version_relation.relnamespace
            where version_namespace.nspname = 'registry'
              and version_relation.relname = 'reporting_scope_versions'
              and identity_only_unique.contype = 'u'
              and pg_catalog.pg_get_constraintdef(identity_only_unique.oid)
                  = 'UNIQUE (reporting_scope_id)'
        ) as valid
    from (values
        ('reporting_scope_versions_scope_fkey', 'f',
            'FOREIGN KEY (reporting_scope_id) REFERENCES registry.reporting_scopes(reporting_scope_id)'),
        ('reporting_scope_versions_scope_definition_key', 'u',
            'UNIQUE (reporting_scope_id, definition_version)')
    ) as expected(constraint_name, constraint_kind, constraint_definition)
    join pg_catalog.pg_namespace namespace on namespace.nspname = 'registry'
    join pg_catalog.pg_class relation
      on relation.relnamespace = namespace.oid
     and relation.relname = 'reporting_scope_versions'
    join pg_catalog.pg_constraint actual
      on actual.conrelid = relation.oid
     and actual.conname = expected.constraint_name
     and actual.contype = expected.constraint_kind::"char"
     and pg_catalog.pg_get_constraintdef(actual.oid) = expected.constraint_definition
), uuid_gate as (
    select count(*) = 2 and bool_and(column_default = 'gen_random_uuid()') as valid
    from (values
        ('reporting_scopes', 'reporting_scope_id'),
        ('reporting_scope_versions', 'reporting_scope_version_id')
    ) as expected(table_name, column_name)
    join information_schema.columns actual
      on actual.table_schema = 'registry'
     and actual.table_name = expected.table_name
     and actual.column_name = expected.column_name
), access_gate as (
    select
        (
            select bool_and(
                not pg_catalog.has_schema_privilege(role_name, schema_name, 'USAGE')
                and not pg_catalog.has_schema_privilege(role_name, schema_name, 'CREATE')
            )
            from unnest(array['anon', 'authenticated']) as role_name
            cross join unnest(array[
                'evidence', 'registry', 'reported', 'semantic', 'metrics', 'audit', 'serving'
            ]) as schema_name
        )
        and (
            select bool_and(not pg_catalog.has_table_privilege(
                role_name,
                format('registry.%I', table_name),
                'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
            ))
            from unnest(array['anon', 'authenticated']) as role_name
            cross join unnest(array[
                'measurement_units', 'reporting_scopes', 'reporting_scope_versions'
            ]) as table_name
        )
        and (
            select bool_and(
                pg_catalog.has_schema_privilege('service_role', schema_name, 'USAGE')
                and not pg_catalog.has_schema_privilege('service_role', schema_name, 'CREATE')
            )
            from unnest(array[
                'evidence', 'registry', 'reported', 'semantic', 'metrics', 'audit', 'serving'
            ]) as schema_name
        )
        and (
            select bool_and(
                pg_catalog.has_table_privilege(
                    'service_role', format('registry.%I', table_name), 'SELECT'
                )
                and pg_catalog.has_table_privilege(
                    'service_role', format('registry.%I', table_name), 'INSERT'
                )
                and not pg_catalog.has_table_privilege(
                    'service_role',
                    format('registry.%I', table_name),
                    'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
                )
            )
            from unnest(array[
                'measurement_units', 'reporting_scopes', 'reporting_scope_versions'
            ]) as table_name
        )
        and not exists (
            select 1
            from pg_catalog.pg_policies
            where schemaname = 'registry'
              and tablename in (
                  'measurement_units', 'reporting_scopes', 'reporting_scope_versions'
              )
        ) as valid
), primitive_state_gate as (
    select
        count(*) = 3
        and bool_and(relation.relrowsecurity)
        and not exists (select 1 from registry.measurement_units)
        and not exists (select 1 from registry.reporting_scopes)
        and not exists (select 1 from registry.reporting_scope_versions) as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'registry'
      and relation.relname in (
          'measurement_units', 'reporting_scopes', 'reporting_scope_versions'
      )
), scope_boundary_gate as (
    select
        not exists (
            select 1
            from pg_catalog.pg_class relation
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname in ('reported', 'semantic', 'metrics', 'serving')
              and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and (
            select
                count(*) = 3
                and bool_and((relation.relname, relation.relkind::text) in (
                    ('ingestion_runs', 'r'),
                    ('ingestion_run_artifacts', 'r'),
                    ('ingestion_run_artifacts_ingestion_run_artifact_id_seq', 'S')
                ))
            from pg_catalog.pg_class relation
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname = 'audit'
              and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and not exists (
            select 1
            from pg_catalog.pg_class relation
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname = 'registry'
              and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
              and relation.relname not in (
                  'measurement_units',
                  'reporting_scopes',
                  'reporting_scope_versions',
                  'institutions',
                  'institution_definition_versions',
                  'regulatory_registrations',
                  'institution_aliases',
                  'institution_cohorts',
                  'regulatory_concepts',
                  'regulatory_concept_scopes'
              )
        )
        and pg_catalog.to_regclass('public.regulatory_bank_metrics_v1') is null as valid
), rls_gate as (
    select relation.relrowsecurity as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'bank_metrics'
), policy_gate as (
    select exists (
        select 1
        from pg_catalog.pg_policies
        where schemaname = 'public'
          and tablename = 'bank_metrics'
          and policyname = 'Public metrics are readable'
          and cmd = 'SELECT'
          and roles @> array['anon', 'authenticated']::name[]
          and qual = 'true'
    ) as valid
)
select
    relation_gate.valid
    and schema_gate.valid
    and primitive_columns_gate.valid
    and primitive_constraints_gate.valid
    and scope_versioning_gate.valid
    and uuid_gate.valid
    and access_gate.valid
    and primitive_state_gate.valid
    and scope_boundary_gate.valid
    and coalesce(rls_gate.valid, false)
    and policy_gate.valid as migration_smoke_passed
from relation_gate
cross join schema_gate
cross join primitive_columns_gate
cross join primitive_constraints_gate
cross join scope_versioning_gate
cross join uuid_gate
cross join access_gate
cross join primitive_state_gate
cross join scope_boundary_gate
cross join policy_gate
left join rls_gate on true
\gset

\if :migration_smoke_passed
\echo 'Migration schema smoke passed.'
\else
\echo 'Migration schema smoke failed.'
do $$
begin
    raise exception 'Migration schema smoke gate failed.';
end
$$;
\endif

with evidence_columns_gate as (
    select
        count(*) = 43
        and (
            select count(*) = 43
            from information_schema.columns
            where table_schema = 'evidence'
              and table_name in (
                  'regulators',
                  'sources',
                  'source_definition_versions',
                  'source_releases',
                  'source_artifacts'
              )
        ) as valid
    from (values
        ('regulators', 'regulator_id', 'uuid', 'NO'),
        ('regulators', 'regulator_code', 'text', 'NO'),
        ('regulators', 'name', 'text', 'NO'),
        ('regulators', 'country', 'text', 'NO'),
        ('sources', 'source_id', 'uuid', 'NO'),
        ('sources', 'regulator_id', 'uuid', 'NO'),
        ('sources', 'source_code', 'text', 'NO'),
        ('source_definition_versions', 'source_definition_version_id', 'uuid', 'NO'),
        ('source_definition_versions', 'source_id', 'uuid', 'NO'),
        ('source_definition_versions', 'definition_version', 'integer', 'NO'),
        ('source_definition_versions', 'label', 'text', 'NO'),
        ('source_definition_versions', 'country', 'text', 'NO'),
        ('source_definition_versions', 'sector', 'text', 'NO'),
        ('source_definition_versions', 'adapter_key', 'text', 'NO'),
        ('source_definition_versions', 'methodological_role', 'text', 'NO'),
        ('source_definition_versions', 'lifecycle', 'text', 'NO'),
        ('source_definition_versions', 'definition_snapshot', 'jsonb', 'NO'),
        ('source_definition_versions', 'config_hash', 'text', 'NO'),
        ('source_definition_versions', 'git_sha', 'text', 'NO'),
        ('source_releases', 'source_release_id', 'uuid', 'NO'),
        ('source_releases', 'source_id', 'uuid', 'NO'),
        ('source_releases', 'release_family_key', 'text', 'NO'),
        ('source_releases', 'revision', 'text', 'YES'),
        ('source_releases', 'covered_period_start', 'date', 'YES'),
        ('source_releases', 'covered_period_end', 'date', 'YES'),
        ('source_releases', 'published_at', 'timestamp with time zone', 'YES'),
        ('source_releases', 'first_observed_at', 'timestamp with time zone', 'NO'),
        ('source_releases', 'release_identity_hash', 'text', 'NO'),
        ('source_releases', 'metadata', 'jsonb', 'NO'),
        ('source_releases', 'supersedes_source_release_id', 'uuid', 'YES'),
        ('source_artifacts', 'source_artifact_id', 'uuid', 'NO'),
        ('source_artifacts', 'source_release_id', 'uuid', 'NO'),
        ('source_artifacts', 'filename', 'text', 'NO'),
        ('source_artifacts', 'original_url', 'text', 'NO'),
        ('source_artifacts', 'final_url', 'text', 'NO'),
        ('source_artifacts', 'mime_type', 'text', 'NO'),
        ('source_artifacts', 'byte_length', 'bigint', 'NO'),
        ('source_artifacts', 'sha256', 'text', 'NO'),
        ('source_artifacts', 'artifact_role', 'text', 'NO'),
        ('source_artifacts', 'storage_backend', 'text', 'NO'),
        ('source_artifacts', 'storage_bucket', 'text', 'YES'),
        ('source_artifacts', 'storage_key', 'text', 'NO'),
        ('source_artifacts', 'first_observed_at', 'timestamp with time zone', 'NO')
    ) as expected(table_name, column_name, data_type, is_nullable)
    join information_schema.columns actual
      on actual.table_schema = 'evidence'
     and actual.table_name = expected.table_name
     and actual.column_name = expected.column_name
     and actual.data_type = expected.data_type
     and actual.is_nullable = expected.is_nullable
), evidence_constraints_gate as (
    select
        count(*) = 46
        and (
            select count(*) = 46
            from pg_catalog.pg_constraint all_constraints
            join pg_catalog.pg_class constrained_relation
              on constrained_relation.oid = all_constraints.conrelid
            join pg_catalog.pg_namespace constrained_namespace
              on constrained_namespace.oid = constrained_relation.relnamespace
            where constrained_namespace.nspname = 'evidence'
              and constrained_relation.relname in (
                  'regulators',
                  'sources',
                  'source_definition_versions',
                  'source_releases',
                  'source_artifacts'
              )
        ) as valid
    from (values
        ('regulators', 'regulators_pkey', 'p'),
        ('regulators', 'regulators_regulator_code_key', 'u'),
        ('regulators', 'regulators_regulator_code_identifier', 'c'),
        ('regulators', 'regulators_name_not_blank', 'c'),
        ('regulators', 'regulators_country_code', 'c'),
        ('sources', 'sources_pkey', 'p'),
        ('sources', 'sources_source_code_key', 'u'),
        ('sources', 'sources_regulator_fkey', 'f'),
        ('sources', 'sources_source_code_identifier', 'c'),
        ('source_definition_versions', 'source_definition_versions_pkey', 'p'),
        ('source_definition_versions', 'source_definition_versions_source_fkey', 'f'),
        ('source_definition_versions', 'source_definition_versions_source_definition_key', 'u'),
        ('source_definition_versions',
            'source_definition_versions_definition_version_positive', 'c'),
        ('source_definition_versions', 'source_definition_versions_label_not_blank', 'c'),
        ('source_definition_versions', 'source_definition_versions_country_code', 'c'),
        ('source_definition_versions', 'source_definition_versions_sector_identifier', 'c'),
        ('source_definition_versions',
            'source_definition_versions_adapter_key_identifier', 'c'),
        ('source_definition_versions',
            'source_definition_versions_methodological_role_valid', 'c'),
        ('source_definition_versions', 'source_definition_versions_lifecycle_valid', 'c'),
        ('source_definition_versions',
            'source_definition_versions_definition_snapshot_object', 'c'),
        ('source_definition_versions',
            'source_definition_versions_config_hash_sha256', 'c'),
        ('source_definition_versions', 'source_definition_versions_git_sha_full', 'c'),
        ('source_releases', 'source_releases_pkey', 'p'),
        ('source_releases', 'source_releases_source_fkey', 'f'),
        ('source_releases', 'source_releases_source_family_identity_key', 'u'),
        ('source_releases', 'source_releases_lineage_target_key', 'u'),
        ('source_releases', 'source_releases_supersedes_fkey', 'f'),
        ('source_releases', 'source_releases_release_family_key_not_blank', 'c'),
        ('source_releases', 'source_releases_revision_not_blank', 'c'),
        ('source_releases', 'source_releases_covered_period_pair_valid', 'c'),
        ('source_releases', 'source_releases_identity_hash_sha256', 'c'),
        ('source_releases', 'source_releases_metadata_object', 'c'),
        ('source_releases', 'source_releases_no_direct_self_supersession', 'c'),
        ('source_artifacts', 'source_artifacts_pkey', 'p'),
        ('source_artifacts', 'source_artifacts_release_fkey', 'f'),
        ('source_artifacts', 'source_artifacts_release_role_sha256_key', 'u'),
        ('source_artifacts', 'source_artifacts_filename_not_blank', 'c'),
        ('source_artifacts', 'source_artifacts_original_url_not_blank', 'c'),
        ('source_artifacts', 'source_artifacts_final_url_not_blank', 'c'),
        ('source_artifacts', 'source_artifacts_mime_type_not_blank', 'c'),
        ('source_artifacts', 'source_artifacts_byte_length_positive', 'c'),
        ('source_artifacts', 'source_artifacts_sha256_valid', 'c'),
        ('source_artifacts', 'source_artifacts_role_not_blank', 'c'),
        ('source_artifacts', 'source_artifacts_storage_backend_not_blank', 'c'),
        ('source_artifacts', 'source_artifacts_storage_bucket_not_blank', 'c'),
        ('source_artifacts', 'source_artifacts_storage_key_not_blank', 'c')
    ) as expected(table_name, constraint_name, constraint_kind)
    join pg_catalog.pg_namespace namespace on namespace.nspname = 'evidence'
    join pg_catalog.pg_class relation
      on relation.relnamespace = namespace.oid
     and relation.relname = expected.table_name
    join pg_catalog.pg_constraint actual
      on actual.conrelid = relation.oid
     and actual.conname = expected.constraint_name
     and actual.contype = expected.constraint_kind::"char"
), evidence_relationship_gate as (
    select count(*) = 7 as valid
    from (values
        ('sources_regulator_fkey', 'f',
            'FOREIGN KEY (regulator_id) REFERENCES evidence.regulators(regulator_id)'),
        ('source_definition_versions_source_fkey', 'f',
            'FOREIGN KEY (source_id) REFERENCES evidence.sources(source_id)'),
        ('source_definition_versions_source_definition_key', 'u',
            'UNIQUE (source_id, definition_version)'),
        ('source_releases_source_fkey', 'f',
            'FOREIGN KEY (source_id) REFERENCES evidence.sources(source_id)'),
        ('source_releases_source_family_identity_key', 'u',
            'UNIQUE (source_id, release_family_key, release_identity_hash)'),
        ('source_releases_supersedes_fkey', 'f',
            'FOREIGN KEY (supersedes_source_release_id, source_id, release_family_key) '
            'REFERENCES evidence.source_releases(source_release_id, source_id, release_family_key)'),
        ('source_artifacts_release_role_sha256_key', 'u',
            'UNIQUE (source_release_id, artifact_role, sha256)')
    ) as expected(constraint_name, constraint_kind, constraint_definition)
    join pg_catalog.pg_constraint actual
      on actual.conname = expected.constraint_name
     and actual.contype = expected.constraint_kind::"char"
     and pg_catalog.pg_get_constraintdef(actual.oid) = expected.constraint_definition
), evidence_defaults_gate as (
    select
        count(*) = 5
        and bool_and(column_default = 'gen_random_uuid()')
        and not exists (
            select 1
            from information_schema.columns
            where table_schema = 'evidence'
              and column_name = 'first_observed_at'
              and column_default is not null
        ) as valid
    from (values
        ('regulators', 'regulator_id'),
        ('sources', 'source_id'),
        ('source_definition_versions', 'source_definition_version_id'),
        ('source_releases', 'source_release_id'),
        ('source_artifacts', 'source_artifact_id')
    ) as expected(table_name, column_name)
    join information_schema.columns actual
      on actual.table_schema = 'evidence'
     and actual.table_name = expected.table_name
     and actual.column_name = expected.column_name
), evidence_indexes_gate as (
    select
        count(*) = 2
        and bool_and(index_relation.relname in (
            'source_releases_supersedes_idx',
            'source_artifacts_sha256_idx'
        )) as valid
    from pg_catalog.pg_index index_definition
    join pg_catalog.pg_class index_relation
      on index_relation.oid = index_definition.indexrelid
    join pg_catalog.pg_class table_relation
      on table_relation.oid = index_definition.indrelid
    join pg_catalog.pg_namespace namespace
      on namespace.oid = table_relation.relnamespace
    where namespace.nspname = 'evidence'
      and not exists (
          select 1
          from pg_catalog.pg_constraint backing_constraint
          where backing_constraint.conindid = index_definition.indexrelid
      )
), evidence_access_state_gate as (
    select
        count(*) = 5
        and bool_and(relation.relrowsecurity)
        and not exists (
            select 1 from pg_catalog.pg_policies where schemaname = 'evidence'
        )
        and not exists (select 1 from evidence.regulators)
        and not exists (select 1 from evidence.sources)
        and not exists (select 1 from evidence.source_definition_versions)
        and not exists (select 1 from evidence.source_releases)
        and not exists (select 1 from evidence.source_artifacts)
        and pg_catalog.has_schema_privilege('service_role', 'evidence', 'USAGE')
        and not pg_catalog.has_schema_privilege('service_role', 'evidence', 'CREATE')
        and (
            select bool_and(
                pg_catalog.has_table_privilege(
                    'service_role', format('evidence.%I', table_name), 'SELECT'
                )
                and pg_catalog.has_table_privilege(
                    'service_role', format('evidence.%I', table_name), 'INSERT'
                )
                and not pg_catalog.has_table_privilege(
                    'service_role',
                    format('evidence.%I', table_name),
                    'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
                )
            )
            from unnest(array[
                'regulators',
                'sources',
                'source_definition_versions',
                'source_releases',
                'source_artifacts'
            ]) as table_name
        )
        and (
            select bool_and(not pg_catalog.has_table_privilege(
                role_name,
                format('evidence.%I', table_name),
                'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
            ))
            from unnest(array['anon', 'authenticated']) as role_name
            cross join unnest(array[
                'regulators',
                'sources',
                'source_definition_versions',
                'source_releases',
                'source_artifacts'
            ]) as table_name
        )
        and not exists (
            select 1
            from pg_catalog.pg_class public_relation
            join pg_catalog.pg_namespace public_namespace
              on public_namespace.oid = public_relation.relnamespace
            cross join lateral pg_catalog.aclexplode(
                coalesce(
                    public_relation.relacl,
                    acldefault('r', public_relation.relowner)
                )
            ) as table_acl
            where public_namespace.nspname = 'evidence'
              and public_relation.relname in (
                  'regulators',
                  'sources',
                  'source_definition_versions',
                  'source_releases',
                  'source_artifacts'
              )
              and table_acl.grantee = 0
        ) as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'evidence'
      and relation.relname in (
          'regulators',
          'sources',
          'source_definition_versions',
          'source_releases',
          'source_artifacts'
      )
), evidence_boundary_gate as (
    select
        count(*) = 5
        and bool_and(relation.relname in (
            'regulators',
            'sources',
            'source_definition_versions',
            'source_releases',
            'source_artifacts'
        ))
        and not exists (
            select 1
            from pg_catalog.pg_class later_relation
            join pg_catalog.pg_namespace later_namespace
              on later_namespace.oid = later_relation.relnamespace
            where later_namespace.nspname in ('reported', 'semantic', 'metrics', 'serving')
              and later_relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and (
            select
                count(*) = 3
                and bool_and((audit_relation.relname, audit_relation.relkind::text) in (
                    ('ingestion_runs', 'r'),
                    ('ingestion_run_artifacts', 'r'),
                    ('ingestion_run_artifacts_ingestion_run_artifact_id_seq', 'S')
                ))
            from pg_catalog.pg_class audit_relation
            join pg_catalog.pg_namespace audit_namespace
              on audit_namespace.oid = audit_relation.relnamespace
            where audit_namespace.nspname = 'audit'
              and audit_relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and pg_catalog.to_regclass('public.regulatory_bank_metrics_v1') is null as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'evidence'
      and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
), legacy_table_gate as (
    select count(*) = 10 as valid
    from (values
        ('core', 'institutions'),
        ('core', 'institution_aliases'),
        ('core', 'institution_cohorts'),
        ('core', 'financial_facts'),
        ('ops', 'pipeline_runs'),
        ('ops', 'source_releases'),
        ('ops', 'pipeline_issues'),
        ('analytics', 'metric_definitions'),
        ('analytics', 'metric_observations'),
        ('public', 'bank_metrics')
    ) as expected(schema_name, table_name)
    join pg_catalog.pg_namespace namespace on namespace.nspname = expected.schema_name
    join pg_catalog.pg_class relation
      on relation.relnamespace = namespace.oid
     and relation.relname = expected.table_name
     and relation.relkind = 'r'
)
select
    evidence_columns_gate.valid
    and evidence_constraints_gate.valid
    and evidence_relationship_gate.valid
    and evidence_defaults_gate.valid
    and evidence_indexes_gate.valid
    and evidence_access_state_gate.valid
    and evidence_boundary_gate.valid
    and legacy_table_gate.valid as pr11_schema_passed
from evidence_columns_gate
cross join evidence_constraints_gate
cross join evidence_relationship_gate
cross join evidence_defaults_gate
cross join evidence_indexes_gate
cross join evidence_access_state_gate
cross join evidence_boundary_gate
cross join legacy_table_gate
\gset

\if :pr11_schema_passed
\echo 'PR11 evidence catalog schema contract passed.'
\else
\echo 'PR11 evidence catalog schema contract failed.'
do $$
begin
    raise exception 'PR11 evidence catalog schema gate failed.';
end
$$;
\endif

insert into evidence.regulators (regulator_id, regulator_code, name, country)
values ('00000000-0000-4000-8000-000000000001', 'test_regulator', 'Test Regulator', 'MX');

insert into evidence.sources (source_id, regulator_id, source_code)
values
    (
        '00000000-0000-4000-8000-000000000011',
        '00000000-0000-4000-8000-000000000001',
        'test_source'
    ),
    (
        '00000000-0000-4000-8000-000000000012',
        '00000000-0000-4000-8000-000000000001',
        'test_source_2'
    );

insert into evidence.source_definition_versions (
    source_definition_version_id,
    source_id,
    definition_version,
    label,
    country,
    sector,
    adapter_key,
    methodological_role,
    lifecycle,
    definition_snapshot,
    config_hash,
    git_sha
)
values (
    '00000000-0000-4000-8000-000000000021',
    '00000000-0000-4000-8000-000000000011',
    1,
    'Test source',
    'MX',
    'banca_multiple',
    'test_source',
    'primary',
    'draft',
    '{"code":"test_source"}'::jsonb,
    repeat('1', 64),
    repeat('2', 40)
);

insert into evidence.source_releases (
    source_release_id,
    source_id,
    release_family_key,
    revision,
    covered_period_start,
    covered_period_end,
    published_at,
    first_observed_at,
    release_identity_hash,
    metadata,
    supersedes_source_release_id
)
values
    (
        '00000000-0000-4000-8000-000000000101',
        '00000000-0000-4000-8000-000000000011',
        'monthly_2026_01',
        null,
        null,
        null,
        null,
        '2026-08-28T12:00:00Z',
        repeat('a', 64),
        '{}'::jsonb,
        null
    ),
    (
        '00000000-0000-4000-8000-000000000102',
        '00000000-0000-4000-8000-000000000011',
        'monthly_2026_01',
        'revision_2',
        '2026-01-01',
        '2026-01-31',
        null,
        '2026-08-28T13:00:00Z',
        repeat('b', 64),
        '{}'::jsonb,
        '00000000-0000-4000-8000-000000000101'
    );

insert into evidence.source_artifacts (
    source_artifact_id,
    source_release_id,
    filename,
    original_url,
    final_url,
    mime_type,
    byte_length,
    sha256,
    artifact_role,
    storage_backend,
    storage_bucket,
    storage_key,
    first_observed_at
)
values
    (
        '00000000-0000-4000-8000-000000000201',
        '00000000-0000-4000-8000-000000000101',
        'release.csv',
        'https://example.test/release.csv',
        'https://example.test/release.csv',
        'text/csv',
        10,
        repeat('d', 64),
        'primary',
        'local',
        null,
        'sha256/dd/dddddd',
        '2026-08-28T12:00:00Z'
    ),
    (
        '00000000-0000-4000-8000-000000000202',
        '00000000-0000-4000-8000-000000000102',
        'release-revised.csv',
        'https://example.test/release-revised.csv',
        'https://example.test/release-revised.csv',
        'text/csv',
        10,
        repeat('d', 64),
        'primary',
        'local',
        null,
        'sha256/dd/dddddd',
        '2026-08-28T13:00:00Z'
    ),
    (
        '00000000-0000-4000-8000-000000000203',
        '00000000-0000-4000-8000-000000000101',
        'release-supplement.csv',
        'https://example.test/release-supplement.csv',
        'https://example.test/release-supplement.csv',
        'text/csv',
        10,
        repeat('d', 64),
        'supplement',
        'local',
        null,
        'sha256/dd/dddddd',
        '2026-08-28T12:00:00Z'
    );

do $$
declare
    rejected boolean;
    violated_constraint text;
begin
    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_releases (
            source_id, release_family_key, first_observed_at, release_identity_hash, metadata
        ) values (
            '00000000-0000-4000-8000-000000000011',
            'monthly_2026_01',
            '2026-08-28T14:00:00Z',
            repeat('a', 64),
            '{}'::jsonb
        );
    exception when unique_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_releases_source_family_identity_key';
    end;
    if not rejected then
        raise exception 'duplicate release identity was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_artifacts (
            source_release_id, filename, original_url, final_url, mime_type, byte_length,
            sha256, artifact_role, storage_backend, storage_key, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000101',
            'duplicate.csv',
            'https://example.test/duplicate.csv',
            'https://example.test/duplicate.csv',
            'text/csv',
            10,
            repeat('d', 64),
            'primary',
            'local',
            'sha256/dd/dddddd',
            '2026-08-28T14:00:00Z'
        );
    exception when unique_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_artifacts_release_role_sha256_key';
    end;
    if not rejected then
        raise exception 'duplicate artifact membership was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_releases (
            source_release_id, source_id, release_family_key, first_observed_at,
            release_identity_hash, metadata, supersedes_source_release_id
        ) values (
            '00000000-0000-4000-8000-000000000103',
            '00000000-0000-4000-8000-000000000011',
            'different_family',
            '2026-08-28T14:00:00Z',
            repeat('e', 64),
            '{}'::jsonb,
            '00000000-0000-4000-8000-000000000101'
        );
    exception when foreign_key_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_releases_supersedes_fkey';
    end;
    if not rejected then
        raise exception 'cross-family predecessor was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_releases (
            source_release_id, source_id, release_family_key, first_observed_at,
            release_identity_hash, metadata, supersedes_source_release_id
        ) values (
            '00000000-0000-4000-8000-000000000105',
            '00000000-0000-4000-8000-000000000012',
            'monthly_2026_01',
            '2026-08-28T14:00:00Z',
            repeat('6', 64),
            '{}'::jsonb,
            '00000000-0000-4000-8000-000000000101'
        );
    exception when foreign_key_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_releases_supersedes_fkey';
    end;
    if not rejected then
        raise exception 'cross-source predecessor was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_releases (
            source_release_id, source_id, release_family_key, first_observed_at,
            release_identity_hash, metadata, supersedes_source_release_id
        ) values (
            '00000000-0000-4000-8000-000000000104',
            '00000000-0000-4000-8000-000000000011',
            'self_family',
            '2026-08-28T14:00:00Z',
            repeat('f', 64),
            '{}'::jsonb,
            '00000000-0000-4000-8000-000000000104'
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_releases_no_direct_self_supersession';
    end;
    if not rejected then
        raise exception 'direct self-supersession was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_releases (
            source_id, release_family_key, covered_period_end, first_observed_at,
            release_identity_hash, metadata
        ) values (
            '00000000-0000-4000-8000-000000000011',
            'invalid_end_only',
            '2026-01-31',
            '2026-08-28T14:00:00Z',
            repeat('3', 64),
            '{}'::jsonb
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_releases_covered_period_pair_valid';
    end;
    if not rejected then
        raise exception 'end-only covered period was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_releases (
            source_id, release_family_key, covered_period_start, first_observed_at,
            release_identity_hash, metadata
        ) values (
            '00000000-0000-4000-8000-000000000011',
            'invalid_start_only',
            '2026-01-01',
            '2026-08-28T14:00:00Z',
            repeat('4', 64),
            '{}'::jsonb
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_releases_covered_period_pair_valid';
    end;
    if not rejected then
        raise exception 'start-only covered period was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_releases (
            source_id, release_family_key, covered_period_start, covered_period_end,
            first_observed_at, release_identity_hash, metadata
        ) values (
            '00000000-0000-4000-8000-000000000011',
            'invalid_reversed',
            '2026-02-01',
            '2026-01-31',
            '2026-08-28T14:00:00Z',
            repeat('5', 64),
            '{}'::jsonb
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_releases_covered_period_pair_valid';
    end;
    if not rejected then
        raise exception 'reversed covered period was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_releases (
            source_id, release_family_key, first_observed_at, release_identity_hash, metadata
        ) values (
            '00000000-0000-4000-8000-000000000011',
            'invalid_hash',
            '2026-08-28T14:00:00Z',
            repeat('A', 64),
            '{}'::jsonb
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_releases_identity_hash_sha256';
    end;
    if not rejected then
        raise exception 'uppercase release hash was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_releases (
            source_id, release_family_key, first_observed_at, release_identity_hash, metadata
        ) values (
            '00000000-0000-4000-8000-000000000011',
            'short_hash',
            '2026-08-28T14:00:00Z',
            repeat('6', 63),
            '{}'::jsonb
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_releases_identity_hash_sha256';
    end;
    if not rejected then
        raise exception 'short release hash was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into evidence.source_artifacts (
            source_release_id, filename, original_url, final_url, mime_type, byte_length,
            sha256, artifact_role, storage_backend, storage_key, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000101',
            'invalid-hash.csv',
            'https://example.test/invalid-hash.csv',
            'https://example.test/invalid-hash.csv',
            'text/csv',
            10,
            repeat('D', 64),
            'invalid_hash',
            'local',
            'sha256/dd/dddddd',
            '2026-08-28T14:00:00Z'
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'source_artifacts_sha256_valid';
    end;
    if not rejected then
        raise exception 'uppercase artifact hash was accepted';
    end if;
end
$$;

select
    (select count(*) = 2 from evidence.source_releases)
    and (select bool_and(published_at is null) from evidence.source_releases)
    and (select count(*) = 3 from evidence.source_artifacts)
    and (
        select count(*) = 3
        from evidence.source_artifacts
        where sha256 = repeat('d', 64)
    ) as pr11_behavior_passed
\gset


with audit_columns_gate as (
    select
        count(*) = 34
        and (
            select count(*) = 34
            from information_schema.columns
            where table_schema = 'audit'
              and table_name in ('ingestion_runs', 'ingestion_run_artifacts')
        ) as valid
    from (values
        ('ingestion_runs', 'ingestion_run_id', 'uuid', 'NO'),
        ('ingestion_runs', 'source_id', 'uuid', 'NO'),
        ('ingestion_runs', 'source_definition_version', 'integer', 'NO'),
        ('ingestion_runs', 'trigger_kind', 'text', 'NO'),
        ('ingestion_runs', 'parameters', 'jsonb', 'NO'),
        ('ingestion_runs', 'parser_implementation_key', 'text', 'YES'),
        ('ingestion_runs', 'parser_implementation_version', 'text', 'YES'),
        ('ingestion_runs', 'identity_definition_hash', 'text', 'YES'),
        ('ingestion_runs', 'git_sha', 'text', 'NO'),
        ('ingestion_runs', 'status', 'text', 'NO'),
        ('ingestion_runs', 'created_at', 'timestamp with time zone', 'NO'),
        ('ingestion_runs', 'started_at', 'timestamp with time zone', 'YES'),
        ('ingestion_runs', 'completed_at', 'timestamp with time zone', 'YES'),
        ('ingestion_runs', 'artifacts_observed_count', 'bigint', 'NO'),
        ('ingestion_runs', 'artifacts_new_count', 'bigint', 'NO'),
        ('ingestion_runs', 'artifacts_reused_count', 'bigint', 'NO'),
        ('ingestion_runs', 'artifacts_revised_count', 'bigint', 'NO'),
        ('ingestion_runs', 'artifacts_failed_count', 'bigint', 'NO'),
        ('ingestion_runs', 'error_code', 'text', 'YES'),
        ('ingestion_runs', 'error_summary', 'text', 'YES'),
        ('ingestion_runs', 'restart_of_ingestion_run_id', 'uuid', 'YES'),
        ('ingestion_run_artifacts', 'ingestion_run_artifact_id', 'bigint', 'NO'),
        ('ingestion_run_artifacts', 'ingestion_run_id', 'uuid', 'NO'),
        ('ingestion_run_artifacts', 'source_artifact_id', 'uuid', 'YES'),
        ('ingestion_run_artifacts', 'observed_url', 'text', 'NO'),
        ('ingestion_run_artifacts', 'final_url', 'text', 'YES'),
        ('ingestion_run_artifacts', 'observed_at', 'timestamp with time zone', 'NO'),
        ('ingestion_run_artifacts', 'http_status_code', 'smallint', 'YES'),
        ('ingestion_run_artifacts', 'http_etag', 'text', 'YES'),
        ('ingestion_run_artifacts', 'http_last_modified', 'text', 'YES'),
        ('ingestion_run_artifacts', 'http_content_length', 'bigint', 'YES'),
        ('ingestion_run_artifacts', 'result', 'text', 'NO'),
        ('ingestion_run_artifacts', 'error_code', 'text', 'YES'),
        ('ingestion_run_artifacts', 'error_summary', 'text', 'YES')
    ) as expected(table_name, column_name, data_type, is_nullable)
    join information_schema.columns actual
      on actual.table_schema = 'audit'
     and actual.table_name = expected.table_name
     and actual.column_name = expected.column_name
     and actual.data_type = expected.data_type
     and actual.is_nullable = expected.is_nullable
), audit_object_gate as (
    select
        (
            select count(*) = 2 and bool_and(relation.relrowsecurity)
            from pg_catalog.pg_class relation
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname = 'audit'
              and relation.relname in ('ingestion_runs', 'ingestion_run_artifacts')
              and relation.relkind = 'r'
        )
        and (
            select count(*) = 3
            from pg_catalog.pg_trigger trigger
            join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname = 'audit'
              and relation.relname in ('ingestion_runs', 'ingestion_run_artifacts')
              and not trigger.tgisinternal
        )
        and (
            select count(*) = 5
            from pg_catalog.pg_indexes
            where schemaname = 'audit'
              and indexname in (
                  'ingestion_runs_source_created_idx',
                  'ingestion_runs_status_created_idx',
                  'ingestion_runs_restart_of_idx',
                  'ingestion_run_artifacts_run_idx',
                  'ingestion_run_artifacts_artifact_idx'
              )
        )
        and not exists (
            select 1
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname = 'audit'
              and function.proname in (
                  'enforce_ingestion_run_lifecycle',
                  'enforce_ingestion_run_artifact_insert',
                  'reject_ingestion_run_artifact_mutation'
              )
              and function.prosecdef
        )
        and not exists (
            select 1
            from pg_catalog.pg_policies
            where schemaname = 'audit'
              and tablename in ('ingestion_runs', 'ingestion_run_artifacts')
        ) as valid
), audit_access_gate as (
    select
        pg_catalog.has_schema_privilege('service_role', 'audit', 'USAGE')
        and not pg_catalog.has_schema_privilege('service_role', 'audit', 'CREATE')
        and pg_catalog.has_table_privilege(
            'service_role', 'audit.ingestion_runs', 'SELECT'
        )
        and not pg_catalog.has_table_privilege(
            'service_role', 'audit.ingestion_runs',
            'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
        )
        and pg_catalog.has_column_privilege(
            'service_role', 'audit.ingestion_runs', 'source_id', 'INSERT'
        )
        and pg_catalog.has_column_privilege(
            'service_role', 'audit.ingestion_runs', 'status', 'UPDATE'
        )
        and not pg_catalog.has_column_privilege(
            'service_role', 'audit.ingestion_runs', 'started_at', 'UPDATE'
        )
        and not pg_catalog.has_column_privilege(
            'service_role', 'audit.ingestion_runs', 'completed_at', 'UPDATE'
        )
        and not pg_catalog.has_column_privilege(
            'service_role', 'audit.ingestion_runs', 'artifacts_observed_count', 'UPDATE'
        )
        and pg_catalog.has_table_privilege(
            'service_role', 'audit.ingestion_run_artifacts', 'SELECT'
        )
        and not pg_catalog.has_table_privilege(
            'service_role', 'audit.ingestion_run_artifacts',
            'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
        )
        and pg_catalog.has_column_privilege(
            'service_role', 'audit.ingestion_run_artifacts', 'result', 'INSERT'
        )
        and pg_catalog.has_sequence_privilege(
            'service_role',
            'audit.ingestion_run_artifacts_ingestion_run_artifact_id_seq',
            'USAGE'
        )
        and not pg_catalog.has_sequence_privilege(
            'service_role',
            'audit.ingestion_run_artifacts_ingestion_run_artifact_id_seq',
            'SELECT, UPDATE'
        )
        and (
            select bool_and(
                not pg_catalog.has_table_privilege(
                    role_name,
                    format('audit.%I', table_name),
                    'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
                )
            )
            from unnest(array['anon', 'authenticated']) as role_name
            cross join unnest(array['ingestion_runs', 'ingestion_run_artifacts']) as table_name
        ) as valid
), audit_boundary_gate as (
    select
        count(*) = 3
        and bool_and((relation.relname, relation.relkind::text) in (
            ('ingestion_runs', 'r'),
            ('ingestion_run_artifacts', 'r'),
            ('ingestion_run_artifacts_ingestion_run_artifact_id_seq', 'S')
        ))
        and pg_catalog.to_regclass('audit.quality_issues') is null
        and pg_catalog.to_regclass('audit.review_decisions') is null
        and pg_catalog.to_regclass('registry.institutions') is not null
        and pg_catalog.to_regclass('public.regulatory_bank_metrics_v1') is null as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'audit'
      and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
), legacy_table_gate as (
    select count(*) = 10 as valid
    from (values
        ('core', 'institutions'),
        ('core', 'institution_aliases'),
        ('core', 'institution_cohorts'),
        ('core', 'financial_facts'),
        ('ops', 'pipeline_runs'),
        ('ops', 'source_releases'),
        ('ops', 'pipeline_issues'),
        ('analytics', 'metric_definitions'),
        ('analytics', 'metric_observations'),
        ('public', 'bank_metrics')
    ) as expected(schema_name, table_name)
    join pg_catalog.pg_namespace namespace on namespace.nspname = expected.schema_name
    join pg_catalog.pg_class relation
      on relation.relnamespace = namespace.oid
     and relation.relname = expected.table_name
     and relation.relkind = 'r'
)
select
    audit_columns_gate.valid
    and audit_object_gate.valid
    and audit_access_gate.valid
    and audit_boundary_gate.valid
    and legacy_table_gate.valid as pr13_schema_passed
from audit_columns_gate
cross join audit_object_gate
cross join audit_access_gate
cross join audit_boundary_gate
cross join legacy_table_gate
\gset

\if :pr13_schema_passed
\echo 'PR13 ingestion lifecycle schema contract passed.'
\else
\echo 'PR13 ingestion lifecycle schema contract failed.'
do $$
begin
    raise exception 'PR13 ingestion lifecycle schema gate failed.';
end
$$;
\endif

insert into evidence.regulators (regulator_id, regulator_code, name, country)
values ('00000000-0000-4000-8000-000000000301', 'audit_test', 'Audit Test', 'MX');

insert into evidence.sources (source_id, regulator_id, source_code)
values
    (
        '00000000-0000-4000-8000-000000000311',
        '00000000-0000-4000-8000-000000000301',
        'audit_source'
    ),
    (
        '00000000-0000-4000-8000-000000000312',
        '00000000-0000-4000-8000-000000000301',
        'other_audit_source'
    );

insert into evidence.source_definition_versions (
    source_definition_version_id, source_id, definition_version, label, country, sector,
    adapter_key, methodological_role, lifecycle, definition_snapshot, config_hash, git_sha
)
values
    (
        '00000000-0000-4000-8000-000000000321',
        '00000000-0000-4000-8000-000000000311',
        1, 'Audit source', 'MX', 'banca_multiple', 'audit_source', 'primary', 'draft',
        '{"code":"audit_source"}'::jsonb, repeat('1', 64), repeat('2', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000322',
        '00000000-0000-4000-8000-000000000312',
        1, 'Other source', 'MX', 'banca_multiple', 'other_audit_source', 'primary', 'draft',
        '{"code":"other_audit_source"}'::jsonb, repeat('3', 64), repeat('4', 40)
    );

insert into evidence.source_releases (
    source_release_id, source_id, release_family_key, revision, first_observed_at,
    release_identity_hash, metadata, supersedes_source_release_id
)
values
    (
        '00000000-0000-4000-8000-000000000401',
        '00000000-0000-4000-8000-000000000311',
        'audit_release', null, '2026-08-30T10:00:00Z', repeat('a', 64), '{}'::jsonb, null
    ),
    (
        '00000000-0000-4000-8000-000000000402',
        '00000000-0000-4000-8000-000000000311',
        'audit_release', 'revision_2', '2026-08-30T11:00:00Z', repeat('b', 64),
        '{}'::jsonb, '00000000-0000-4000-8000-000000000401'
    ),
    (
        '00000000-0000-4000-8000-000000000403',
        '00000000-0000-4000-8000-000000000312',
        'other_release', null, '2026-08-30T10:00:00Z', repeat('c', 64), '{}'::jsonb, null
    );

insert into evidence.source_artifacts (
    source_artifact_id, source_release_id, filename, original_url, final_url, mime_type,
    byte_length, sha256, artifact_role, storage_backend, storage_key, first_observed_at
)
values
    (
        '00000000-0000-4000-8000-000000000501',
        '00000000-0000-4000-8000-000000000401',
        'audit.csv', 'https://example.test/audit.csv', 'https://example.test/audit.csv',
        'text/csv', 10, repeat('d', 64), 'primary', 'local', 'sha256/dd/audit',
        '2026-08-30T10:00:00Z'
    ),
    (
        '00000000-0000-4000-8000-000000000502',
        '00000000-0000-4000-8000-000000000402',
        'audit-revised.csv', 'https://example.test/revised.csv',
        'https://example.test/revised.csv', 'text/csv', 11, repeat('e', 64), 'primary',
        'local', 'sha256/ee/revised', '2026-08-30T11:00:00Z'
    ),
    (
        '00000000-0000-4000-8000-000000000503',
        '00000000-0000-4000-8000-000000000403',
        'other.csv', 'https://example.test/other.csv', 'https://example.test/other.csv',
        'text/csv', 12, repeat('f', 64), 'primary', 'local', 'sha256/ff/other',
        '2026-08-30T10:00:00Z'
    );

do $$
declare
    rejected boolean;
begin
    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            parameters, git_sha, status
        ) values (
            '00000000-0000-4000-8000-000000000601',
            '00000000-0000-4000-8000-000000000311',
            1, 'manual', '{}'::jsonb, repeat('1', 40), 'running'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'direct running run insert was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            parameters, git_sha, status, started_at, completed_at
        ) values (
            '00000000-0000-4000-8000-000000000602',
            '00000000-0000-4000-8000-000000000311',
            1, 'manual', '{}'::jsonb, repeat('1', 40), 'succeeded',
            clock_timestamp(), clock_timestamp()
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'direct terminal run insert was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            parameters, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000603',
            '00000000-0000-4000-8000-000000000311',
            1, 'restart', '{}'::jsonb, repeat('1', 40)
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'invalid trigger kind was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            parameters, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000604',
            '00000000-0000-4000-8000-000000000311',
            1, 'manual', '[]'::jsonb, repeat('1', 40)
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'non-object run parameters were accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            parameters, parser_implementation_key, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000605',
            '00000000-0000-4000-8000-000000000311',
            1, 'manual', '{}'::jsonb, 'test_parser', repeat('1', 40)
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'unpaired parser provenance was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            parameters, identity_definition_hash, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000606',
            '00000000-0000-4000-8000-000000000311',
            1, 'manual', '{}'::jsonb, repeat('A', 64), repeat('1', 40)
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'invalid identity hash was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            parameters, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000607',
            '00000000-0000-4000-8000-000000000311',
            1, 'manual', '{}'::jsonb, repeat('g', 40)
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'invalid Git SHA was accepted';
    end if;
end
$$;

insert into audit.ingestion_runs (
    ingestion_run_id, source_id, source_definition_version, trigger_kind, parameters,
    parser_implementation_key, parser_implementation_version, identity_definition_hash,
    git_sha
)
values (
    '00000000-0000-4000-8000-000000000610',
    '00000000-0000-4000-8000-000000000311',
    1, 'manual', '{"period":"2026-06"}'::jsonb,
    'test_parser', '1.0.0', repeat('5', 64), repeat('6', 40)
);

select
    status = 'pending'
    and started_at is null
    and completed_at is null
    and artifacts_observed_count = 0
    and artifacts_failed_count = 0 as pr13_pending_valid
from audit.ingestion_runs
where ingestion_run_id = '00000000-0000-4000-8000-000000000610'
\gset

\if :pr13_pending_valid
\else
\echo 'Canonical pending run state failed.'
do $$
begin
    raise exception 'PR13 canonical pending run gate failed.';
end
$$;
\endif

with changed as (update audit.ingestion_runs
set status = 'running'
where ingestion_run_id = '00000000-0000-4000-8000-000000000610'
returning 1) select count(*) from changed;

insert into audit.ingestion_run_artifacts (
    ingestion_run_id, source_artifact_id, observed_url, final_url, observed_at,
    http_status_code, http_etag, http_last_modified, http_content_length, result,
    error_code, error_summary
)
values
    (
        '00000000-0000-4000-8000-000000000610',
        '00000000-0000-4000-8000-000000000501',
        'https://example.test/repeated.csv', 'https://example.test/audit.csv',
        '2026-08-30T12:00:00Z', 200, '"audit"', 'Sun, 30 Aug 2026 12:00:00 GMT', 10,
        'new', null, null
    ),
    (
        '00000000-0000-4000-8000-000000000610',
        null, 'https://example.test/repeated.csv', 'https://example.test/audit.csv',
        '2026-08-30T12:00:01Z', 503, null, null, 0, 'failed',
        'http_unavailable', 'Transient upstream response.'
    ),
    (
        '00000000-0000-4000-8000-000000000610',
        '00000000-0000-4000-8000-000000000501',
        'https://example.test/repeated.csv', 'https://example.test/audit.csv',
        '2026-08-30T12:00:02Z', 200, null, null, 10, 'reused', null, null
    ),
    (
        '00000000-0000-4000-8000-000000000610',
        '00000000-0000-4000-8000-000000000502',
        'https://example.test/revised.csv', 'https://example.test/revised.csv',
        '2026-08-30T12:00:03Z', 200, null, null, 11, 'revised', null, null
    );

select
    status = 'running'
    and started_at is not null
    and completed_at is null
    and artifacts_observed_count = 0
    and artifacts_new_count = 0
    and artifacts_reused_count = 0
    and artifacts_revised_count = 0
    and artifacts_failed_count = 0 as pr13_running_summary_zero
from audit.ingestion_runs
where ingestion_run_id = '00000000-0000-4000-8000-000000000610'
\gset

\if :pr13_running_summary_zero
\else
\echo 'Running counters were not zero.'
do $$
begin
    raise exception 'PR13 running counter ownership gate failed.';
end
$$;
\endif

with changed as (update audit.ingestion_runs
set status = 'succeeded'
where ingestion_run_id = '00000000-0000-4000-8000-000000000610'
returning 1) select count(*) from changed;

select
    status = 'succeeded'
    and created_at <= started_at
    and started_at <= completed_at
    and artifacts_observed_count = 4
    and artifacts_new_count = 1
    and artifacts_reused_count = 1
    and artifacts_revised_count = 1
    and artifacts_failed_count = 1
    and artifacts_observed_count = artifacts_new_count + artifacts_reused_count
        + artifacts_revised_count + artifacts_failed_count
    and error_code is null
    and error_summary is null as pr13_success_aggregated
from audit.ingestion_runs
where ingestion_run_id = '00000000-0000-4000-8000-000000000610'
\gset

\if :pr13_success_aggregated
\else
\echo 'Succeeded run did not aggregate recovered attempt outcomes.'
do $$
begin
    raise exception 'PR13 succeeded-run aggregation gate failed.';
end
$$;
\endif

insert into audit.ingestion_runs (
    ingestion_run_id, source_id, source_definition_version, trigger_kind, git_sha
)
values
    (
        '00000000-0000-4000-8000-000000000611',
        '00000000-0000-4000-8000-000000000311',
        1, 'schedule', repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000612',
        '00000000-0000-4000-8000-000000000311',
        1, 'backfill', repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000613',
        '00000000-0000-4000-8000-000000000311',
        1, 'test', repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000620',
        '00000000-0000-4000-8000-000000000312',
        1, 'manual', repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000630',
        '00000000-0000-4000-8000-000000000311',
        1, 'manual', repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000640',
        '00000000-0000-4000-8000-000000000311',
        1, 'manual', repeat('1', 40)
    );

with changed as (update audit.ingestion_runs
set status = 'running'
where ingestion_run_id in (
    '00000000-0000-4000-8000-000000000611',
    '00000000-0000-4000-8000-000000000612',
    '00000000-0000-4000-8000-000000000613',
    '00000000-0000-4000-8000-000000000620',
    '00000000-0000-4000-8000-000000000640'
)
returning 1) select count(*) from changed;

insert into audit.ingestion_run_artifacts (
    ingestion_run_id, source_artifact_id, observed_url, final_url, observed_at,
    http_status_code, result, error_code, error_summary
)
values
    (
        '00000000-0000-4000-8000-000000000611', null,
        'https://example.test/retry.csv', 'https://example.test/retry.csv',
        '2026-08-30T13:00:00Z', 503, 'failed',
        'http_unavailable', 'Recovered transient response.'
    ),
    (
        '00000000-0000-4000-8000-000000000611',
        '00000000-0000-4000-8000-000000000501',
        'https://example.test/retry.csv', 'https://example.test/audit.csv',
        '2026-08-30T13:00:01Z', 200, 'reused', null, null
    ),
    (
        '00000000-0000-4000-8000-000000000612',
        '00000000-0000-4000-8000-000000000501',
        'https://example.test/audit.csv', 'https://example.test/audit.csv',
        '2026-08-30T13:10:00Z', 200, 'reused', null, null
    ),
    (
        '00000000-0000-4000-8000-000000000613',
        '00000000-0000-4000-8000-000000000501',
        'https://example.test/audit.csv', 'https://example.test/audit.csv',
        '2026-08-30T13:20:00Z', 200, 'new', null, null
    ),
    (
        '00000000-0000-4000-8000-000000000613', null,
        'https://example.test/late.csv', null,
        '2026-08-30T13:20:01Z', null, 'failed',
        'transport_error', 'Connection ended before a response.'
    ),
    (
        '00000000-0000-4000-8000-000000000640',
        '00000000-0000-4000-8000-000000000501',
        'https://example.test/new.csv', 'https://example.test/audit.csv',
        '2026-08-30T13:30:00Z', 200, 'new', null, null
    );

with changed as (update audit.ingestion_runs
set status = 'no_change'
where ingestion_run_id = '00000000-0000-4000-8000-000000000611'
returning 1) select count(*) from changed;

with changed as (update audit.ingestion_runs
set status = 'succeeded'
where ingestion_run_id = '00000000-0000-4000-8000-000000000612'
returning 1) select count(*) from changed;

with changed as (update audit.ingestion_runs
set status = 'failed',
    error_code = 'run_aborted',
    error_summary = 'Run stopped after a persistent source failure.'
where ingestion_run_id = '00000000-0000-4000-8000-000000000613'
returning 1) select count(*) from changed;

select
    (
        select status = 'no_change'
            and artifacts_observed_count = 2
            and artifacts_new_count = 0
            and artifacts_reused_count = 1
            and artifacts_revised_count = 0
            and artifacts_failed_count = 1
        from audit.ingestion_runs
        where ingestion_run_id = '00000000-0000-4000-8000-000000000611'
    )
    and (
        select status = 'succeeded'
            and artifacts_observed_count = 1
            and artifacts_new_count = 0
            and artifacts_reused_count = 1
            and artifacts_revised_count = 0
            and artifacts_failed_count = 0
        from audit.ingestion_runs
        where ingestion_run_id = '00000000-0000-4000-8000-000000000612'
    )
    and (
        select status = 'failed'
            and artifacts_observed_count = 2
            and artifacts_new_count = 1
            and artifacts_failed_count = 1
            and error_code = 'run_aborted'
        from audit.ingestion_runs
        where ingestion_run_id = '00000000-0000-4000-8000-000000000613'
    ) as pr13_terminal_outcomes_valid
\gset

\if :pr13_terminal_outcomes_valid
\else
\echo 'PR13 terminal outcome semantics failed.'
do $$
begin
    raise exception 'PR13 terminal outcome gate failed.';
end
$$;
\endif

do $$
declare
    rejected boolean;
begin
    rejected := false;
    begin
        execute $statement$update audit.ingestion_runs
            set status = 'running'
            where ingestion_run_id = '00000000-0000-4000-8000-000000000610'$statement$;
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'terminal run was reopened';
    end if;

    rejected := false;
    begin
        execute $statement$update audit.ingestion_runs
            set status = 'no_change'
            where ingestion_run_id = '00000000-0000-4000-8000-000000000640'$statement$;
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'no-change run accepted a new artifact observation';
    end if;

    rejected := false;
    begin
        execute $statement$update audit.ingestion_runs
            set status = 'failed'
            where ingestion_run_id = '00000000-0000-4000-8000-000000000620'$statement$;
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'failed run without safe error was accepted';
    end if;

    rejected := false;
    begin
        execute $statement$update audit.ingestion_runs
            set status = 'succeeded',
                error_code = 'unexpected_error',
                error_summary = 'This must be rejected.'
            where ingestion_run_id = '00000000-0000-4000-8000-000000000620'$statement$;
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'nonfailed run accepted run-level error fields';
    end if;

    rejected := false;
    begin
        execute $statement$update audit.ingestion_runs
            set status = 'succeeded'
            where ingestion_run_id = '00000000-0000-4000-8000-000000000630'$statement$;
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'pending run skipped running state';
    end if;
end
$$;


do $$
declare
    rejected boolean;
begin
    rejected := false;
    begin
        insert into audit.ingestion_run_artifacts (
            ingestion_run_id, source_artifact_id, observed_url, final_url,
            observed_at, result
        ) values (
            '00000000-0000-4000-8000-000000000620',
            '00000000-0000-4000-8000-000000000501',
            'https://example.test/cross-source.csv',
            'https://example.test/cross-source.csv',
            '2026-08-30T14:00:00Z', 'reused'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'cross-source artifact observation was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_run_artifacts (
            ingestion_run_id, source_artifact_id, observed_url, final_url,
            observed_at, result
        ) values (
            '00000000-0000-4000-8000-000000000620',
            '00000000-0000-4000-8000-000000000503',
            'https://example.test/not-revised.csv',
            'https://example.test/not-revised.csv',
            '2026-08-30T14:00:01Z', 'revised'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'revised result without release lineage was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_run_artifacts (
            ingestion_run_id, source_artifact_id, observed_url, final_url,
            observed_at, result
        ) values (
            '00000000-0000-4000-8000-000000000640',
            '00000000-0000-4000-8000-000000000502',
            'https://example.test/revision-as-new.csv',
            'https://example.test/revision-as-new.csv',
            '2026-08-30T14:00:02Z', 'new'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'new result accepted a superseding release';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_run_artifacts (
            ingestion_run_id, observed_url, final_url, observed_at, result
        ) values (
            '00000000-0000-4000-8000-000000000620',
            'https://example.test/missing-artifact.csv',
            'https://example.test/missing-artifact.csv',
            '2026-08-30T14:00:03Z', 'reused'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'successful observation without artifact was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_run_artifacts (
            ingestion_run_id, source_artifact_id, observed_url, observed_at,
            result, error_code, error_summary
        ) values (
            '00000000-0000-4000-8000-000000000620',
            '00000000-0000-4000-8000-000000000503',
            'https://example.test/failed-with-artifact.csv',
            '2026-08-30T14:00:04Z', 'failed',
            'transport_error', 'This shape is invalid.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'failed observation with artifact was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_run_artifacts (
            ingestion_run_id, observed_url, observed_at, result
        ) values (
            '00000000-0000-4000-8000-000000000620',
            'https://example.test/failed-without-error.csv',
            '2026-08-30T14:00:05Z', 'failed'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'failed observation without safe error was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_run_artifacts (
            ingestion_run_id, source_artifact_id, observed_url, final_url,
            observed_at, result
        ) values (
            '00000000-0000-4000-8000-000000000620',
            '00000000-0000-4000-8000-000000000503',
            'https://example.test/invalid-result.csv',
            'https://example.test/invalid-result.csv',
            '2026-08-30T14:00:06Z', 'stored'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'invalid artifact result was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_run_artifacts (
            ingestion_run_id, observed_url, observed_at, result,
            error_code, error_summary
        ) values (
            '00000000-0000-4000-8000-000000000630',
            'https://example.test/pending.csv',
            '2026-08-30T14:00:07Z', 'failed',
            'not_started', 'Parent has not started.'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'artifact observation before running was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_run_artifacts (
            ingestion_run_id, source_artifact_id, observed_url, final_url,
            observed_at, result
        ) values (
            '00000000-0000-4000-8000-000000000612',
            '00000000-0000-4000-8000-000000000501',
            'https://example.test/terminal.csv',
            'https://example.test/terminal.csv',
            '2026-08-30T14:00:08Z', 'reused'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'artifact observation after terminal state was accepted';
    end if;

    rejected := false;
    begin
        execute $statement$update audit.ingestion_run_artifacts
            set observed_url = 'https://example.test/mutated.csv'
            where ingestion_run_id = '00000000-0000-4000-8000-000000000610'$statement$;
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'artifact observation update was accepted';
    end if;

    rejected := false;
    begin
        execute $statement$delete from audit.ingestion_run_artifacts
            where ingestion_run_id = '00000000-0000-4000-8000-000000000610'$statement$;
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'artifact observation delete was accepted';
    end if;
end
$$;

insert into audit.ingestion_runs (
    ingestion_run_id, source_id, source_definition_version, trigger_kind,
    git_sha, restart_of_ingestion_run_id
)
values
    (
        '00000000-0000-4000-8000-000000000614',
        '00000000-0000-4000-8000-000000000311',
        1, 'manual', repeat('1', 40),
        '00000000-0000-4000-8000-000000000613'
    ),
    (
        '00000000-0000-4000-8000-000000000615',
        '00000000-0000-4000-8000-000000000311',
        1, 'schedule', repeat('1', 40),
        '00000000-0000-4000-8000-000000000613'
    );

do $$
declare
    rejected boolean;
begin
    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            git_sha, restart_of_ingestion_run_id
        ) values (
            '00000000-0000-4000-8000-000000000616',
            '00000000-0000-4000-8000-000000000311',
            1, 'manual', repeat('1', 40),
            '00000000-0000-4000-8000-000000000612'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'restart from nonfailed run was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            git_sha, restart_of_ingestion_run_id
        ) values (
            '00000000-0000-4000-8000-000000000617',
            '00000000-0000-4000-8000-000000000312',
            1, 'manual', repeat('1', 40),
            '00000000-0000-4000-8000-000000000613'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'cross-source restart was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.ingestion_runs (
            ingestion_run_id, source_id, source_definition_version, trigger_kind,
            git_sha, restart_of_ingestion_run_id
        ) values (
            '00000000-0000-4000-8000-000000000618',
            '00000000-0000-4000-8000-000000000311',
            1, 'manual', repeat('1', 40),
            '00000000-0000-4000-8000-000000000618'
        );
    exception when raise_exception or check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'direct self restart was accepted';
    end if;
end
$$;

select count(*) = 2 as pr13_multiple_restart_children
from audit.ingestion_runs
where restart_of_ingestion_run_id = '00000000-0000-4000-8000-000000000613'
\gset

\if :pr13_multiple_restart_children
\else
\echo 'Multiple restart children were not preserved.'
do $$
begin
    raise exception 'PR13 restart lineage gate failed.';
end
$$;
\endif

set local role service_role;

insert into audit.ingestion_runs (
    source_id, source_definition_version, trigger_kind, parameters,
    parser_implementation_key, parser_implementation_version,
    identity_definition_hash, git_sha, restart_of_ingestion_run_id
)
values (
    '00000000-0000-4000-8000-000000000311',
    1, 'test', '{}'::jsonb, null, null, null, repeat('7', 40), null
)
returning ingestion_run_id as service_run_id
\gset

do $$
declare
    target_run_id uuid;
    rejected boolean;
begin
    select ingestion_run_id into target_run_id
    from audit.ingestion_runs
    where git_sha = repeat('7', 40) and status = 'pending';

    rejected := false;
    begin
        execute 'update audit.ingestion_runs set started_at = clock_timestamp() '
            'where ingestion_run_id = $1' using target_run_id;
    exception when insufficient_privilege then rejected := true;
    end;
    if not rejected then raise exception 'service role directly updated started_at';
    end if;

    rejected := false;
    begin
        execute 'update audit.ingestion_runs set artifacts_observed_count = 1, '
            'artifacts_failed_count = 1 where ingestion_run_id = $1' using target_run_id;
    exception when insufficient_privilege then rejected := true;
    end;
    if not rejected then raise exception 'service role directly updated counters';
    end if;
end
$$;

with changed as (update audit.ingestion_runs
set status = 'running'
where ingestion_run_id = :'service_run_id'::uuid
returning 1) select count(*) from changed;

insert into audit.ingestion_run_artifacts (
    ingestion_run_id, source_artifact_id, observed_url, final_url, observed_at,
    http_status_code, http_etag, http_last_modified, http_content_length,
    result, error_code, error_summary
)
values (
    :'service_run_id'::uuid, null,
    'https://example.test/service-role.csv', 'https://example.test/service-role.csv',
    '2026-08-30T15:00:00Z', 429, null, null, 0,
    'failed', 'rate_limited', 'Transient rate limit was recovered.'
);

with changed as (update audit.ingestion_runs
set status = 'no_change'
where ingestion_run_id = :'service_run_id'::uuid
returning 1) select count(*) from changed;

reset role;

select
    status = 'no_change'
    and created_at <= started_at
    and started_at <= completed_at
    and artifacts_observed_count = 1
    and artifacts_new_count = 0
    and artifacts_reused_count = 0
    and artifacts_revised_count = 0
    and artifacts_failed_count = 1 as pr13_service_role_contract
from audit.ingestion_runs
where ingestion_run_id = :'service_run_id'::uuid
\gset

\if :pr13_service_role_contract
\else
\echo 'Service-role lifecycle contract failed.'
do $$
begin
    raise exception 'PR13 service-role lifecycle gate failed.';
end
$$;
\endif

select
    (select count(*) = 4
     from audit.ingestion_run_artifacts
     where ingestion_run_id = '00000000-0000-4000-8000-000000000610')
    and (select count(*) = 3
         from audit.ingestion_run_artifacts
         where ingestion_run_id = '00000000-0000-4000-8000-000000000610'
           and observed_url = 'https://example.test/repeated.csv')
    and (select count(*) = 2
         from audit.ingestion_runs
         where restart_of_ingestion_run_id = '00000000-0000-4000-8000-000000000613')
    as pr13_behavior_passed
\gset

\if :pr13_behavior_passed
\else
\echo 'PR13 aggregate behavioral smoke failed.'
do $$
begin
    raise exception 'PR13 aggregate behavioral gate failed.';
end
$$;
\endif

\echo PR14 diagnostic uuid defaults
select
    actual.table_name,
    actual.column_name,
    actual.column_default
from (values
    ('institutions', 'institution_id'),
    ('institution_definition_versions', 'institution_definition_version_id'),
    ('regulatory_registrations', 'regulatory_registration_id'),
    ('institution_aliases', 'institution_alias_id'),
    ('institution_cohorts', 'institution_cohort_id'),
    ('regulatory_concepts', 'regulatory_concept_id')
) as expected(table_name, column_name)
join information_schema.columns actual
  on actual.table_schema = 'registry'
 and actual.table_name = expected.table_name
 and actual.column_name = expected.column_name
order by actual.table_name, actual.column_name;

with pr14_extension_gate as (
    select
        count(*) = 1
        and bool_and(namespace.nspname = 'extensions') as valid
    from pg_catalog.pg_extension extension
    join pg_catalog.pg_namespace namespace
      on namespace.oid = extension.extnamespace
    where extension.extname = 'btree_gist'
), pr14_inventory_gate as (
    select
        count(*) = 10
        and bool_and(relation.relname in (
            'measurement_units',
            'reporting_scopes',
            'reporting_scope_versions',
            'institutions',
            'institution_definition_versions',
            'regulatory_registrations',
            'institution_aliases',
            'institution_cohorts',
            'regulatory_concepts',
            'regulatory_concept_scopes'
        ))
        and bool_and(relation.relkind = 'r') as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'registry'
      and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
), pr14_columns_gate as (
    select
        count(*) = 50
        and (
            select count(*) = 53
            from information_schema.columns
            where table_schema = 'registry'
              and table_name in (
                  'institutions',
                  'institution_definition_versions',
                  'regulatory_registrations',
                  'institution_aliases',
                  'institution_cohorts',
                  'regulatory_concepts',
                  'regulatory_concept_scopes'
              )
        ) as valid
    from (values
        ('institutions', 'institution_id', 'uuid', 'NO'),
        ('institutions', 'institution_code', 'text', 'NO'),
        ('institutions', 'country', 'text', 'NO'),
        ('institution_definition_versions', 'institution_definition_version_id', 'uuid', 'NO'),
        ('institution_definition_versions', 'institution_id', 'uuid', 'NO'),
        ('institution_definition_versions', 'definition_version', 'integer', 'NO'),
        ('institution_definition_versions', 'canonical_label', 'text', 'NO'),
        ('institution_definition_versions', 'lifecycle', 'text', 'NO'),
        ('institution_definition_versions', 'provenance', 'text', 'NO'),
        ('institution_definition_versions', 'definition_snapshot', 'jsonb', 'NO'),
        ('institution_definition_versions', 'definition_hash', 'text', 'NO'),
        ('institution_definition_versions', 'git_sha', 'text', 'NO'),
        ('regulatory_registrations', 'regulatory_registration_id', 'uuid', 'NO'),
        ('regulatory_registrations', 'institution_id', 'uuid', 'NO'),
        ('regulatory_registrations', 'institution_definition_version_id', 'uuid', 'NO'),
        ('regulatory_registrations', 'regulator_id', 'uuid', 'NO'),
        ('regulatory_registrations', 'registration_type', 'text', 'NO'),
        ('regulatory_registrations', 'registration_code', 'text', 'NO'),
        ('regulatory_registrations', 'valid_from', 'date', 'NO'),
        ('regulatory_registrations', 'valid_to', 'date', 'YES'),
        ('institution_aliases', 'institution_alias_id', 'uuid', 'NO'),
        ('institution_aliases', 'institution_id', 'uuid', 'NO'),
        ('institution_aliases', 'institution_definition_version_id', 'uuid', 'NO'),
        ('institution_aliases', 'source_id', 'uuid', 'NO'),
        ('institution_aliases', 'alias_value', 'text', 'NO'),
        ('institution_aliases', 'normalized_alias', 'text', 'NO'),
        ('institution_aliases', 'alias_type', 'text', 'NO'),
        ('institution_aliases', 'valid_from', 'date', 'NO'),
        ('institution_aliases', 'valid_to', 'date', 'YES'),
        ('institution_cohorts', 'institution_cohort_id', 'uuid', 'NO'),
        ('institution_cohorts', 'institution_id', 'uuid', 'NO'),
        ('institution_cohorts', 'institution_definition_version_id', 'uuid', 'NO'),
        ('institution_cohorts', 'cohort_code', 'text', 'NO'),
        ('institution_cohorts', 'valid_from', 'date', 'NO'),
        ('institution_cohorts', 'valid_to', 'date', 'YES'),
        ('institution_cohorts', 'rationale', 'text', 'NO'),
        ('regulatory_concepts', 'regulatory_concept_id', 'uuid', 'NO'),
        ('regulatory_concepts', 'source_id', 'uuid', 'NO'),
        ('regulatory_concepts', 'external_code', 'text', 'NO'),
        ('regulatory_concepts', 'definition_version', 'integer', 'NO'),
        ('regulatory_concepts', 'label', 'text', 'NO'),
        ('regulatory_concepts', 'definition', 'text', 'NO'),
        ('regulatory_concepts', 'lifecycle', 'text', 'NO'),
        ('regulatory_concepts', 'valid_from', 'date', 'NO'),
        ('regulatory_concepts', 'valid_to', 'date', 'YES'),
        ('regulatory_concepts', 'definition_snapshot', 'jsonb', 'NO'),
        ('regulatory_concepts', 'definition_hash', 'text', 'NO'),
        ('regulatory_concepts', 'git_sha', 'text', 'NO'),
        ('regulatory_concept_scopes', 'regulatory_concept_id', 'uuid', 'NO'),
        ('regulatory_concept_scopes', 'reporting_scope_id', 'uuid', 'NO')
    ) as expected(table_name, column_name, data_type, is_nullable)
    join information_schema.columns actual
      on actual.table_schema = 'registry'
     and actual.table_name = expected.table_name
     and actual.column_name = expected.column_name
     and actual.data_type = expected.data_type
     and actual.is_nullable = expected.is_nullable
), pr14_validity_gate as (
    select
        count(*) = 3
        and bool_and(actual.udt_name = 'daterange')
        and bool_and(actual.is_generated = 'ALWAYS')
        and bool_and(actual.generation_expression like '%daterange%')
        and bool_and(actual.generation_expression like '%[]%')
        as valid
    from (values
        ('regulatory_registrations'),
        ('institution_aliases'),
        ('institution_cohorts')
    ) as expected(table_name)
    join information_schema.columns actual
      on actual.table_schema = 'registry'
     and actual.table_name = expected.table_name
     and actual.column_name = 'validity'
), pr14_alias_normalization_gate as (
    select
        actual.is_generated = 'NEVER'
        and actual.generation_expression is null as valid
    from information_schema.columns actual
    where actual.table_schema = 'registry'
      and actual.table_name = 'institution_aliases'
      and actual.column_name = 'normalized_alias'
), pr14_relationship_gate as (
    select count(*) = 6 as valid
    from (values
        ('institution_definition_versions_identity_key', 'u',
            'UNIQUE (institution_definition_version_id, institution_id)'),
        ('regulatory_registrations_definition_institution_fkey', 'f',
            'FOREIGN KEY (institution_definition_version_id, institution_id) '
            'REFERENCES registry.institution_definition_versions(institution_definition_version_id, institution_id)'),
        ('institution_aliases_definition_institution_fkey', 'f',
            'FOREIGN KEY (institution_definition_version_id, institution_id) '
            'REFERENCES registry.institution_definition_versions(institution_definition_version_id, institution_id)'),
        ('institution_cohorts_definition_institution_fkey', 'f',
            'FOREIGN KEY (institution_definition_version_id, institution_id) '
            'REFERENCES registry.institution_definition_versions(institution_definition_version_id, institution_id)'),
        ('regulatory_registrations_regulator_fkey', 'f',
            'FOREIGN KEY (regulator_id) REFERENCES evidence.regulators(regulator_id)'),
        ('institution_aliases_source_fkey', 'f',
            'FOREIGN KEY (source_id) REFERENCES evidence.sources(source_id)')
    ) as expected(constraint_name, constraint_kind, constraint_definition)
    join pg_catalog.pg_constraint actual
      on actual.conname = expected.constraint_name
     and actual.contype = expected.constraint_kind::"char"
     and pg_catalog.pg_get_constraintdef(actual.oid) = expected.constraint_definition
), pr14_exclusion_gate as (
    select
        count(*) = 3
        and bool_and(actual.contype = 'x') as valid
    from (values
        ('regulatory_registrations_validity_excl'),
        ('institution_aliases_validity_excl'),
        ('institution_cohorts_validity_excl')
    ) as expected(constraint_name)
    join pg_catalog.pg_constraint actual
      on actual.conname = expected.constraint_name
), pr14_defaults_gate as (
    select
        count(*) = 6
        and bool_and(column_default in (
            'gen_random_uuid()',
            'pg_catalog.gen_random_uuid()',
            'extensions.gen_random_uuid()'
        )) as valid
    from (values
        ('institutions', 'institution_id'),
        ('institution_definition_versions', 'institution_definition_version_id'),
        ('regulatory_registrations', 'regulatory_registration_id'),
        ('institution_aliases', 'institution_alias_id'),
        ('institution_cohorts', 'institution_cohort_id'),
        ('regulatory_concepts', 'regulatory_concept_id')
    ) as expected(table_name, column_name)
    join information_schema.columns actual
      on actual.table_schema = 'registry'
     and actual.table_name = expected.table_name
     and actual.column_name = expected.column_name
), pr14_indexes_gate as (
    select
        count(*) = 3
        and bool_and(index_relation.relname in (
            'regulatory_registrations_lookup_idx',
            'institution_aliases_lookup_idx',
            'institution_cohorts_lookup_idx'
        )) as valid
    from pg_catalog.pg_index index_definition
    join pg_catalog.pg_class index_relation
      on index_relation.oid = index_definition.indexrelid
    join pg_catalog.pg_class table_relation
      on table_relation.oid = index_definition.indrelid
    join pg_catalog.pg_namespace namespace
      on namespace.oid = table_relation.relnamespace
    where namespace.nspname = 'registry'
      and table_relation.relname in (
          'institutions',
          'institution_definition_versions',
          'regulatory_registrations',
          'institution_aliases',
          'institution_cohorts',
          'regulatory_concepts',
          'regulatory_concept_scopes'
      )
      and not exists (
          select 1
          from pg_catalog.pg_constraint backing_constraint
          where backing_constraint.conindid = index_definition.indexrelid
      )
), pr14_access_state_gate as (
    select
        count(*) = 7
        and bool_and(relation.relrowsecurity)
        and not exists (
            select 1
            from pg_catalog.pg_policies
            where schemaname = 'registry'
              and tablename in (
                  'institutions',
                  'institution_definition_versions',
                  'regulatory_registrations',
                  'institution_aliases',
                  'institution_cohorts',
                  'regulatory_concepts',
                  'regulatory_concept_scopes'
              )
        )
        and not exists (select 1 from registry.institutions)
        and not exists (select 1 from registry.institution_definition_versions)
        and not exists (select 1 from registry.regulatory_registrations)
        and not exists (select 1 from registry.institution_aliases)
        and not exists (select 1 from registry.institution_cohorts)
        and not exists (select 1 from registry.regulatory_concepts)
        and not exists (select 1 from registry.regulatory_concept_scopes)
        and (
            select bool_and(
                pg_catalog.has_table_privilege(
                    'service_role', format('registry.%I', table_name), 'SELECT'
                )
                and not pg_catalog.has_table_privilege(
                    'service_role',
                    format('registry.%I', table_name),
                    'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
                )
            )
            from unnest(array[
                'institutions',
                'institution_definition_versions',
                'regulatory_registrations',
                'institution_aliases',
                'institution_cohorts',
                'regulatory_concepts',
                'regulatory_concept_scopes'
            ]) as table_name
        )
        and (
            select bool_and(not pg_catalog.has_table_privilege(
                role_name,
                format('registry.%I', table_name),
                'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
            ))
            from unnest(array['anon', 'authenticated']) as role_name
            cross join unnest(array[
                'institutions',
                'institution_definition_versions',
                'regulatory_registrations',
                'institution_aliases',
                'institution_cohorts',
                'regulatory_concepts',
                'regulatory_concept_scopes'
            ]) as table_name
        ) as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'registry'
      and relation.relname in (
          'institutions',
          'institution_definition_versions',
          'regulatory_registrations',
          'institution_aliases',
          'institution_cohorts',
          'regulatory_concepts',
          'regulatory_concept_scopes'
      )
), pr14_boundary_gate as (
    select
        pg_catalog.to_regclass('reported.reported_facts') is null
        and pg_catalog.to_regclass('semantic.canonical_concepts') is null
        and pg_catalog.to_regclass('metrics.metric_definitions') is null
        and pg_catalog.to_regclass('serving.current_publishable_facts') is null
        and pg_catalog.to_regclass('audit.quality_issues') is null
        and pg_catalog.to_regclass('audit.review_decisions') is null
        and pg_catalog.to_regclass('public.regulatory_bank_metrics_v1') is null as valid
)
select
    pr14_extension_gate.valid as pr14_extension_gate,
    pr14_inventory_gate.valid as pr14_inventory_gate,
    pr14_columns_gate.valid as pr14_columns_gate,
    pr14_validity_gate.valid as pr14_validity_gate,
    pr14_alias_normalization_gate.valid as pr14_alias_normalization_gate,
    pr14_relationship_gate.valid as pr14_relationship_gate,
    pr14_exclusion_gate.valid as pr14_exclusion_gate,
    pr14_defaults_gate.valid as pr14_defaults_gate,
    pr14_indexes_gate.valid as pr14_indexes_gate,
    pr14_access_state_gate.valid as pr14_access_state_gate,
    pr14_boundary_gate.valid as pr14_boundary_gate,
    (
        pr14_extension_gate.valid
        and pr14_inventory_gate.valid
        and pr14_columns_gate.valid
        and pr14_validity_gate.valid
        and pr14_alias_normalization_gate.valid
        and pr14_relationship_gate.valid
        and pr14_exclusion_gate.valid
        and pr14_defaults_gate.valid
        and pr14_indexes_gate.valid
        and pr14_access_state_gate.valid
        and pr14_boundary_gate.valid
    ) as pr14_schema_passed
from pr14_extension_gate
cross join pr14_inventory_gate
cross join pr14_columns_gate
cross join pr14_validity_gate
cross join pr14_alias_normalization_gate
cross join pr14_relationship_gate
cross join pr14_exclusion_gate
cross join pr14_defaults_gate
cross join pr14_indexes_gate
cross join pr14_access_state_gate
cross join pr14_boundary_gate
\gset

\echo PR14 gate extension: :pr14_extension_gate
\echo PR14 gate inventory: :pr14_inventory_gate
\echo PR14 gate columns: :pr14_columns_gate
\echo PR14 gate validity: :pr14_validity_gate
\echo PR14 gate alias_normalization: :pr14_alias_normalization_gate
\echo PR14 gate relationships: :pr14_relationship_gate
\echo PR14 gate exclusions: :pr14_exclusion_gate
\echo PR14 gate defaults: :pr14_defaults_gate
\echo PR14 gate indexes: :pr14_indexes_gate
\echo PR14 gate access_state: :pr14_access_state_gate
\echo PR14 gate boundary: :pr14_boundary_gate
\echo PR14 aggregate schema: :pr14_schema_passed

\echo PR14 diagnostic btree_gist
select
    extension.extname,
    namespace.nspname as extension_schema
from pg_catalog.pg_extension extension
join pg_catalog.pg_namespace namespace
  on namespace.oid = extension.extnamespace
where extension.extname = 'btree_gist';

\echo PR14 diagnostic column counts
select
    actual.table_name,
    count(*) as column_count
from information_schema.columns actual
where actual.table_schema = 'registry'
  and actual.table_name in (
      'institutions',
      'institution_definition_versions',
      'regulatory_registrations',
      'institution_aliases',
      'institution_cohorts',
      'regulatory_concepts',
      'regulatory_concept_scopes'
  )
group by actual.table_name
order by actual.table_name;

\echo PR14 diagnostic validity generation
select
    actual.table_name,
    actual.udt_name,
    actual.is_generated,
    actual.generation_expression
from information_schema.columns actual
where actual.table_schema = 'registry'
  and actual.column_name = 'validity'
  and actual.table_name in (
      'regulatory_registrations',
      'institution_aliases',
      'institution_cohorts'
  )
order by actual.table_name;

\echo PR14 diagnostic relationship constraintdefs
select
    expected.constraint_name,
    actual.contype::text as constraint_kind,
    pg_catalog.pg_get_constraintdef(actual.oid) as constraint_definition
from (values
    ('institution_definition_versions_identity_key'),
    ('regulatory_registrations_definition_institution_fkey'),
    ('institution_aliases_definition_institution_fkey'),
    ('institution_cohorts_definition_institution_fkey'),
    ('regulatory_registrations_regulator_fkey'),
    ('institution_aliases_source_fkey')
) as expected(constraint_name)
left join pg_catalog.pg_constraint actual
  on actual.conname = expected.constraint_name
order by expected.constraint_name;

\echo PR14 diagnostic non-constraint indexes
select
    table_relation.relname as table_name,
    index_relation.relname as index_name
from pg_catalog.pg_index index_definition
join pg_catalog.pg_class index_relation
  on index_relation.oid = index_definition.indexrelid
join pg_catalog.pg_class table_relation
  on table_relation.oid = index_definition.indrelid
join pg_catalog.pg_namespace namespace
  on namespace.oid = table_relation.relnamespace
where namespace.nspname = 'registry'
  and table_relation.relname in (
      'institutions',
      'institution_definition_versions',
      'regulatory_registrations',
      'institution_aliases',
      'institution_cohorts',
      'regulatory_concepts',
      'regulatory_concept_scopes'
  )
  and not exists (
      select 1
      from pg_catalog.pg_constraint backing_constraint
      where backing_constraint.conindid = index_definition.indexrelid
  )
order by table_relation.relname, index_relation.relname;

\echo PR14 diagnostic service_role privileges
select
    table_name,
    pg_catalog.has_table_privilege(
        'service_role', format('registry.%I', table_name), 'SELECT'
    ) as select_priv,
    pg_catalog.has_table_privilege(
        'service_role', format('registry.%I', table_name), 'INSERT'
    ) as insert_priv,
    pg_catalog.has_table_privilege(
        'service_role', format('registry.%I', table_name), 'UPDATE'
    ) as update_priv,
    pg_catalog.has_table_privilege(
        'service_role', format('registry.%I', table_name), 'DELETE'
    ) as delete_priv,
    pg_catalog.has_table_privilege(
        'service_role', format('registry.%I', table_name), 'TRUNCATE'
    ) as truncate_priv,
    pg_catalog.has_table_privilege(
        'service_role', format('registry.%I', table_name), 'REFERENCES'
    ) as references_priv,
    pg_catalog.has_table_privilege(
        'service_role', format('registry.%I', table_name), 'TRIGGER'
    ) as trigger_priv
from unnest(array[
    'institutions',
    'institution_definition_versions',
    'regulatory_registrations',
    'institution_aliases',
    'institution_cohorts',
    'regulatory_concepts',
    'regulatory_concept_scopes'
]) as table_name
order by table_name;

\if :pr14_schema_passed
\echo 'PR14 institution identity schema contract passed.'
\else
\echo 'PR14 institution identity schema contract failed.'
do $$
begin
    raise exception 'PR14 institution identity schema gate failed.';
end
$$;
\endif

insert into registry.institutions (institution_id, institution_code, country)
values
    ('00000000-0000-4000-8000-000000000701', 'test_bank_a', 'MX'),
    ('00000000-0000-4000-8000-000000000702', 'test_bank_b', 'MX');

insert into registry.institution_definition_versions (
    institution_definition_version_id, institution_id, definition_version,
    canonical_label, lifecycle, provenance, definition_snapshot, definition_hash, git_sha
)
values
    (
        '00000000-0000-4000-8000-000000000711',
        '00000000-0000-4000-8000-000000000701',
        1, 'Test Bank A', 'draft', 'Synthetic PR14 fixture.',
        '{"institution":{"code":"test_bank_a"},"referenced_cohort_definitions":[]}'::jsonb,
        repeat('1', 64), repeat('2', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000712',
        '00000000-0000-4000-8000-000000000701',
        2, 'Test Bank A Restated', 'active', 'Synthetic PR14 fixture.',
        '{"institution":{"code":"test_bank_a","definition_version":2},"referenced_cohort_definitions":[]}'::jsonb,
        repeat('3', 64), repeat('4', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000713',
        '00000000-0000-4000-8000-000000000702',
        1, 'Test Bank B', 'draft', 'Synthetic PR14 fixture.',
        '{"institution":{"code":"test_bank_b"},"referenced_cohort_definitions":[]}'::jsonb,
        repeat('5', 64), repeat('6', 40)
    );

insert into registry.reporting_scopes (reporting_scope_id, scope_code)
values ('00000000-0000-4000-8000-000000000761', 'test_individual_scope');

insert into registry.regulatory_registrations (
    regulatory_registration_id, institution_id, institution_definition_version_id,
    regulator_id, registration_type, registration_code, valid_from, valid_to
)
values
    (
        '00000000-0000-4000-8000-000000000721',
        '00000000-0000-4000-8000-000000000701',
        '00000000-0000-4000-8000-000000000711',
        '00000000-0000-4000-8000-000000000001',
        'test_registration', 'REG-A', '2026-01-01', '2026-05-31'
    ),
    (
        '00000000-0000-4000-8000-000000000722',
        '00000000-0000-4000-8000-000000000701',
        '00000000-0000-4000-8000-000000000711',
        '00000000-0000-4000-8000-000000000001',
        'test_registration', 'REG-A', '2026-06-01', null
    ),
    (
        '00000000-0000-4000-8000-000000000723',
        '00000000-0000-4000-8000-000000000701',
        '00000000-0000-4000-8000-000000000711',
        '00000000-0000-4000-8000-000000000001',
        'test_registration', 'REG-DAY', '2026-07-01', '2026-07-01'
    );

insert into registry.institution_aliases (
    institution_alias_id, institution_id, institution_definition_version_id,
    source_id, alias_value, normalized_alias, alias_type, valid_from, valid_to
)
values
    (
        '00000000-0000-4000-8000-000000000731',
        '00000000-0000-4000-8000-000000000701',
        '00000000-0000-4000-8000-000000000711',
        '00000000-0000-4000-8000-000000000011',
        'Banco Uno', 'banco uno', 'legal_name', '2026-01-01', '2026-05-31'
    ),
    (
        '00000000-0000-4000-8000-000000000732',
        '00000000-0000-4000-8000-000000000702',
        '00000000-0000-4000-8000-000000000713',
        '00000000-0000-4000-8000-000000000011',
        'Banco Uno', 'banco uno', 'source_label', '2026-06-01', null
    ),
    (
        '00000000-0000-4000-8000-000000000733',
        '00000000-0000-4000-8000-000000000701',
        '00000000-0000-4000-8000-000000000711',
        '00000000-0000-4000-8000-000000000012',
        'Banco Uno', 'banco uno', 'trade_name', '2026-01-01', null
    );

insert into registry.institution_cohorts (
    institution_cohort_id, institution_id, institution_definition_version_id,
    cohort_code, valid_from, valid_to, rationale
)
values
    (
        '00000000-0000-4000-8000-000000000741',
        '00000000-0000-4000-8000-000000000701',
        '00000000-0000-4000-8000-000000000711',
        'traditional_bank', '2026-01-01', null, 'Synthetic traditional membership.'
    ),
    (
        '00000000-0000-4000-8000-000000000742',
        '00000000-0000-4000-8000-000000000701',
        '00000000-0000-4000-8000-000000000711',
        'digital_bank', '2026-01-01', null, 'Synthetic overlapping other cohort.'
    );

insert into registry.regulatory_concepts (
    regulatory_concept_id, source_id, external_code, definition_version, label,
    definition, lifecycle, valid_from, valid_to, definition_snapshot, definition_hash, git_sha
)
values (
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '1401', 1, 'Gross loans source line', 'Synthetic source concept.',
    'draft', '2026-01-01', null,
    '{"source_code":"test_source","code":"1401"}'::jsonb,
    repeat('7', 64), repeat('8', 40)
);

insert into registry.regulatory_concept_scopes (
    regulatory_concept_id, reporting_scope_id
)
values (
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000761'
);

do $$
declare
    rejected boolean;
    violated_constraint text;
begin
    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.institutions (institution_code, country)
        values ('test_bank_a', 'MX');
    exception when unique_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'institutions_institution_code_key';
    end;
    if not rejected then
        raise exception 'duplicate institution_code was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.institution_definition_versions (
            institution_id, definition_version, canonical_label, lifecycle, provenance,
            definition_snapshot, definition_hash, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000701',
            1, 'Duplicate version', 'draft', 'Synthetic.',
            '{"institution":{"code":"test_bank_a"}}'::jsonb,
            repeat('9', 64), repeat('a', 40)
        );
    exception when unique_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'institution_definition_versions_institution_definition_key';
    end;
    if not rejected then
        raise exception 'duplicate institution definition version was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.institution_definition_versions (
            institution_id, definition_version, canonical_label, lifecycle, provenance,
            definition_snapshot, definition_hash, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000701',
            3, 'Bad hash', 'draft', 'Synthetic.',
            '{"institution":{"code":"test_bank_a"}}'::jsonb,
            repeat('A', 64), repeat('b', 40)
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'institution_definition_versions_definition_hash_sha256';
    end;
    if not rejected then
        raise exception 'uppercase definition hash was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.institution_definition_versions (
            institution_id, definition_version, canonical_label, lifecycle, provenance,
            definition_snapshot, definition_hash, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000701',
            3, 'Bad git', 'draft', 'Synthetic.',
            '{"institution":{"code":"test_bank_a"}}'::jsonb,
            repeat('c', 64), repeat('g', 40)
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'institution_definition_versions_git_sha_full';
    end;
    if not rejected then
        raise exception 'invalid Git SHA was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.regulatory_registrations (
            institution_id, institution_definition_version_id, regulator_id,
            registration_type, registration_code, valid_from, valid_to
        ) values (
            '00000000-0000-4000-8000-000000000701',
            '00000000-0000-4000-8000-000000000713',
            '00000000-0000-4000-8000-000000000001',
            'test_registration', 'REG-CROSS', '2026-01-01', null
        );
    exception when foreign_key_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'regulatory_registrations_definition_institution_fkey';
    end;
    if not rejected then
        raise exception 'cross-institution definition version was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.regulatory_registrations (
            institution_id, institution_definition_version_id, regulator_id,
            registration_type, registration_code, valid_from, valid_to
        ) values (
            '00000000-0000-4000-8000-000000000701',
            '00000000-0000-4000-8000-000000000711',
            '00000000-0000-4000-8000-000000000001',
            'test_registration', 'REG-A', '2026-05-31', '2026-06-30'
        );
    exception when exclusion_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'regulatory_registrations_validity_excl';
    end;
    if not rejected then
        raise exception 'overlapping inclusive registration range was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.regulatory_registrations (
            institution_id, institution_definition_version_id, regulator_id,
            registration_type, registration_code, valid_from, valid_to
        ) values (
            '00000000-0000-4000-8000-000000000701',
            '00000000-0000-4000-8000-000000000711',
            '00000000-0000-4000-8000-000000000001',
            'test_registration', 'REG-A', '2026-06-01', '2026-06-30'
        );
    exception when exclusion_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'regulatory_registrations_validity_excl';
    end;
    if not rejected then
        raise exception 'same-day registration boundary reuse was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.regulatory_registrations (
            institution_id, institution_definition_version_id, regulator_id,
            registration_type, registration_code, valid_from
        ) values (
            '00000000-0000-4000-8000-000000000701',
            '00000000-0000-4000-8000-000000000711',
            '00000000-0000-4000-8000-000000009999',
            'test_registration', 'REG-MISSING', '2026-01-01'
        );
    exception when foreign_key_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'regulatory_registrations_regulator_fkey';
    end;
    if not rejected then
        raise exception 'nonexistent regulator was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.institution_aliases (
            institution_id, institution_definition_version_id, source_id,
            alias_value, normalized_alias, alias_type, valid_from, valid_to
        ) values (
            '00000000-0000-4000-8000-000000000701',
            '00000000-0000-4000-8000-000000000711',
            '00000000-0000-4000-8000-000000000011',
            'Banco Uno', 'banco uno', 'legal_name', '2026-05-31', '2026-12-31'
        );
    exception when exclusion_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'institution_aliases_validity_excl';
    end;
    if not rejected then
        raise exception 'overlapping same-source alias was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.institution_cohorts (
            institution_id, institution_definition_version_id, cohort_code,
            valid_from, valid_to, rationale
        ) values (
            '00000000-0000-4000-8000-000000000701',
            '00000000-0000-4000-8000-000000000711',
            'traditional_bank', '2026-06-01', null, 'Overlapping same cohort.'
        );
    exception when exclusion_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'institution_cohorts_validity_excl';
    end;
    if not rejected then
        raise exception 'overlapping same-cohort membership was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.regulatory_concepts (
            source_id, external_code, definition_version, label, definition,
            lifecycle, valid_from, definition_snapshot, definition_hash, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000011',
            '1401', 1, 'Duplicate', 'Duplicate.', 'draft', '2026-01-01',
            '{"code":"1401"}'::jsonb, repeat('d', 64), repeat('e', 40)
        );
    exception when unique_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'regulatory_concepts_source_code_version_key';
    end;
    if not rejected then
        raise exception 'duplicate regulatory concept identity was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.regulatory_concepts (
            source_id, external_code, definition_version, label, definition,
            lifecycle, valid_from, definition_snapshot, definition_hash, git_sha
        ) values (
            '00000000-0000-4000-8000-000000000011',
            '1402', 1, 'Bad hash', 'Bad hash.', 'draft', '2026-01-01',
            '{"code":"1402"}'::jsonb, repeat('D', 64), repeat('f', 40)
        );
    exception when check_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'regulatory_concepts_definition_hash_sha256';
    end;
    if not rejected then
        raise exception 'uppercase regulatory concept hash was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.regulatory_concept_scopes (
            regulatory_concept_id, reporting_scope_id
        ) values (
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000009999'
        );
    exception when foreign_key_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'regulatory_concept_scopes_scope_fkey';
    end;
    if not rejected then
        raise exception 'invalid reporting scope pairing was accepted';
    end if;

    rejected := false;
    violated_constraint := null;
    begin
        insert into registry.regulatory_concept_scopes (
            regulatory_concept_id, reporting_scope_id
        ) values (
            '00000000-0000-4000-8000-000000009998',
            '00000000-0000-4000-8000-000000000761'
        );
    exception when foreign_key_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'regulatory_concept_scopes_concept_fkey';
    end;
    if not rejected then
        raise exception 'invalid regulatory concept pairing was accepted';
    end if;
end
$$;

with changed as (update registry.regulatory_registrations
    set valid_to = '2027-12-31',
        institution_definition_version_id = '00000000-0000-4000-8000-000000000712'
    where regulatory_registration_id = '00000000-0000-4000-8000-000000000722'
    returning regulatory_registration_id, valid_to, institution_definition_version_id
)
select
    count(*) = 1
    and bool_and(regulatory_registration_id = '00000000-0000-4000-8000-000000000722')
    and bool_and(valid_to = date '2027-12-31')
    and bool_and(institution_definition_version_id = '00000000-0000-4000-8000-000000000712')
    as pr14_projection_close_passed
from changed
\gset

\if :pr14_projection_close_passed
\else
\echo 'PR14 projection valid_to closure failed.'
do $$
begin
    raise exception 'PR14 projection maintenance gate failed.';
end
$$;
\endif

do $$
declare
    rejected boolean;
    violated_constraint text;
begin
    rejected := false;
    violated_constraint := null;
    begin
        execute $statement$update registry.regulatory_registrations
            set institution_definition_version_id = '00000000-0000-4000-8000-000000000713'
            where regulatory_registration_id = '00000000-0000-4000-8000-000000000722'$statement$;
    exception when foreign_key_violation then
        get stacked diagnostics violated_constraint = CONSTRAINT_NAME;
        rejected := violated_constraint = 'regulatory_registrations_definition_institution_fkey';
    end;
    if not rejected then
        raise exception 'projection retargeted to another institution version';
    end if;
end
$$;

set local role service_role;

select count(*) >= 2 as pr14_service_select_passed
from registry.institutions
\gset

\if :pr14_service_select_passed
\else
\echo 'PR14 service_role SELECT failed.'
do $$
begin
    raise exception 'PR14 service_role SELECT gate failed.';
end
$$;
\endif

do $$
declare
    rejected boolean;
begin
    rejected := false;
    begin
        insert into registry.institutions (institution_code, country)
        values ('service_role_bank', 'MX');
    exception when insufficient_privilege then
        rejected := true;
    end;
    if not rejected then
        raise exception 'service_role inserted an institution';
    end if;

    rejected := false;
    begin
        execute $statement$update registry.institution_definition_versions
            set canonical_label = 'Mutated'
            where institution_definition_version_id = '00000000-0000-4000-8000-000000000711'$statement$;
    exception when insufficient_privilege then
        rejected := true;
    end;
    if not rejected then
        raise exception 'service_role updated an institution definition snapshot';
    end if;

    rejected := false;
    begin
        execute $statement$update registry.regulatory_registrations
            set valid_to = '2028-12-31'
            where regulatory_registration_id = '00000000-0000-4000-8000-000000000722'$statement$;
    exception when insufficient_privilege then
        rejected := true;
    end;
    if not rejected then
        raise exception 'service_role updated a registration projection';
    end if;

    rejected := false;
    begin
        execute $statement$delete from registry.institutions
            where institution_id = '00000000-0000-4000-8000-000000000701'$statement$;
    exception when insufficient_privilege then
        rejected := true;
    end;
    if not rejected then
        raise exception 'service_role deleted an institution';
    end if;
end
$$;

reset role;

select
    (select count(*) = 2 from registry.institutions)
    and (select count(*) = 3 from registry.institution_definition_versions)
    and (select count(*) = 3 from registry.regulatory_registrations)
    and (select count(*) = 3 from registry.institution_aliases)
    and (select count(*) = 2 from registry.institution_cohorts)
    and (select count(*) = 1 from registry.regulatory_concepts)
    and (select count(*) = 1 from registry.regulatory_concept_scopes)
    and (
        select valid_to = date '2027-12-31'
            and institution_definition_version_id = '00000000-0000-4000-8000-000000000712'
        from registry.regulatory_registrations
        where regulatory_registration_id = '00000000-0000-4000-8000-000000000722'
    ) as pr14_behavior_passed
\gset

\if :pr14_behavior_passed
\else
\echo 'PR14 aggregate behavioral smoke failed.'
do $$
begin
    raise exception 'PR14 aggregate behavioral gate failed.';
end
$$;
\endif

rollback;

\if :pr11_behavior_passed
\echo 'PR11 evidence catalog behavioral smoke passed.'
\else
\echo 'PR11 evidence catalog behavioral smoke failed.'
do $$
begin
    raise exception 'PR11 evidence catalog behavioral gate failed.';
end
$$;
\endif

select
    not exists (select 1 from evidence.regulators)
    and not exists (select 1 from evidence.sources)
    and not exists (select 1 from evidence.source_definition_versions)
    and not exists (select 1 from evidence.source_releases)
    and not exists (select 1 from evidence.source_artifacts) as pr11_rollback_passed
\gset

\if :pr11_rollback_passed
\echo 'PR11 smoke fixtures rolled back cleanly.'
\else
\echo 'PR11 smoke fixtures persisted unexpectedly.'
do $$
begin
    raise exception 'PR11 rollback cleanliness gate failed.';
end
$$;
\endif


select
    not exists (select 1 from audit.ingestion_runs)
    and not exists (select 1 from audit.ingestion_run_artifacts)
    as pr13_rollback_passed
\gset

\if :pr13_rollback_passed
\echo 'PR13 smoke fixtures rolled back cleanly.'
\else
\echo 'PR13 smoke fixtures persisted unexpectedly.'
do $$
begin
    raise exception 'PR13 rollback cleanliness gate failed.';
end
$$;
\endif

select
    not exists (select 1 from registry.institutions)
    and not exists (select 1 from registry.institution_definition_versions)
    and not exists (select 1 from registry.regulatory_registrations)
    and not exists (select 1 from registry.institution_aliases)
    and not exists (select 1 from registry.institution_cohorts)
    and not exists (select 1 from registry.regulatory_concepts)
    and not exists (select 1 from registry.regulatory_concept_scopes)
    and not exists (
        select 1 from registry.reporting_scopes
        where reporting_scope_id = '00000000-0000-4000-8000-000000000761'
    )
    as pr14_rollback_passed
\gset

\if :pr14_rollback_passed
\echo 'PR14 smoke fixtures rolled back cleanly.'
\else
\echo 'PR14 smoke fixtures persisted unexpectedly.'
do $$
begin
    raise exception 'PR14 rollback cleanliness gate failed.';
end
$$;
\endif

\echo 'Migration smoke completed successfully.'
