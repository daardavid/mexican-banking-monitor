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
        ('evidence', 'source_artifacts', 'r')
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
        ('evidence', 'source_artifacts', 'r')
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
            where namespace.nspname in ('reported', 'semantic', 'metrics', 'audit', 'serving')
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
                  'measurement_units', 'reporting_scopes', 'reporting_scope_versions'
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
\quit 1
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
            where later_namespace.nspname in ('reported', 'semantic', 'metrics', 'audit', 'serving')
              and later_relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
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
\quit 1
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

rollback;

\if :pr11_behavior_passed
\echo 'PR11 evidence catalog behavioral smoke passed.'
\else
\echo 'PR11 evidence catalog behavioral smoke failed.'
\quit 1
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
\quit 1
\endif
