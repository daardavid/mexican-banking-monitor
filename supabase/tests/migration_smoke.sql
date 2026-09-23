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
        ('audit', 'review_decisions', 'r'),
        ('audit', 'review_decisions_review_decision_id_seq', 'S'),
        ('audit', 'effective_review_decisions', 'v'),
        ('registry', 'institutions', 'r'),
        ('registry', 'institution_definition_versions', 'r'),
        ('registry', 'regulatory_registrations', 'r'),
        ('registry', 'institution_aliases', 'r'),
        ('registry', 'institution_cohorts', 'r'),
        ('registry', 'regulatory_concepts', 'r'),
        ('registry', 'regulatory_concept_scopes', 'r'),
        ('reported', 'reported_facts', 'r'),
        ('reported', 'reported_facts_reported_fact_id_seq', 'S')
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
        ('audit', 'review_decisions', 'r'),
        ('audit', 'review_decisions_review_decision_id_seq', 'S'),
        ('audit', 'effective_review_decisions', 'v'),
        ('registry', 'institutions', 'r'),
        ('registry', 'institution_definition_versions', 'r'),
        ('registry', 'regulatory_registrations', 'r'),
        ('registry', 'institution_aliases', 'r'),
        ('registry', 'institution_cohorts', 'r'),
        ('registry', 'regulatory_concepts', 'r'),
        ('registry', 'regulatory_concept_scopes', 'r'),
        ('reported', 'reported_facts', 'r'),
        ('reported', 'reported_facts_reported_fact_id_seq', 'S')
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
            where namespace.nspname in ('semantic', 'metrics')
              and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and (
            select
                count(*) = 3
                and bool_and((relation.relname, relation.relkind::text) in (
                    ('reported_fact_revision_ancestry', 'v'),
                    ('current_observed_facts', 'v'),
                    ('current_publishable_facts', 'v')
                ))
            from pg_catalog.pg_class relation
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname = 'serving'
              and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and (
            select
                count(*) = 2
                and bool_and((relation.relname, relation.relkind::text) in (
                    ('reported_facts', 'r'),
                    ('reported_facts_reported_fact_id_seq', 'S')
                ))
            from pg_catalog.pg_class relation
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname = 'reported'
              and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and (
            select
                count(*) = 6
                and bool_and((relation.relname, relation.relkind::text) in (
                    ('ingestion_runs', 'r'),
                    ('ingestion_run_artifacts', 'r'),
                    ('ingestion_run_artifacts_ingestion_run_artifact_id_seq', 'S'),
                    ('review_decisions', 'r'),
                    ('review_decisions_review_decision_id_seq', 'S'),
                    ('effective_review_decisions', 'v')
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
        count(*) = 49
        and (
            select count(*) = 49
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
        ('sources', 'sources_id_regulator_key', 'u'),
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
        ('source_releases', 'source_releases_id_source_key', 'u'),
        ('source_releases', 'source_releases_supersedes_fkey', 'f'),
        ('source_releases', 'source_releases_release_family_key_not_blank', 'c'),
        ('source_releases', 'source_releases_revision_not_blank', 'c'),
        ('source_releases', 'source_releases_covered_period_pair_valid', 'c'),
        ('source_releases', 'source_releases_identity_hash_sha256', 'c'),
        ('source_releases', 'source_releases_metadata_object', 'c'),
        ('source_releases', 'source_releases_no_direct_self_supersession', 'c'),
        ('source_artifacts', 'source_artifacts_pkey', 'p'),
        ('source_artifacts', 'source_artifacts_release_fkey', 'f'),
        ('source_artifacts', 'source_artifacts_id_release_key', 'u'),
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
    select count(*) = 10 as valid
    from (values
        ('sources_regulator_fkey', 'f',
            'FOREIGN KEY (regulator_id) REFERENCES evidence.regulators(regulator_id)'),
        ('sources_id_regulator_key', 'u',
            'UNIQUE (source_id, regulator_id)'),
        ('source_definition_versions_source_fkey', 'f',
            'FOREIGN KEY (source_id) REFERENCES evidence.sources(source_id)'),
        ('source_definition_versions_source_definition_key', 'u',
            'UNIQUE (source_id, definition_version)'),
        ('source_releases_source_fkey', 'f',
            'FOREIGN KEY (source_id) REFERENCES evidence.sources(source_id)'),
        ('source_releases_source_family_identity_key', 'u',
            'UNIQUE (source_id, release_family_key, release_identity_hash)'),
        ('source_releases_id_source_key', 'u',
            'UNIQUE (source_release_id, source_id)'),
        ('source_releases_supersedes_fkey', 'f',
            'FOREIGN KEY (supersedes_source_release_id, source_id, release_family_key) '
            'REFERENCES evidence.source_releases(source_release_id, source_id, release_family_key)'),
        ('source_artifacts_id_release_key', 'u',
            'UNIQUE (source_artifact_id, source_release_id)'),
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
            where later_namespace.nspname in ('semantic', 'metrics')
              and later_relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and (
            select
                count(*) = 3
                and bool_and((serving_relation.relname, serving_relation.relkind::text) in (
                    ('reported_fact_revision_ancestry', 'v'),
                    ('current_observed_facts', 'v'),
                    ('current_publishable_facts', 'v')
                ))
            from pg_catalog.pg_class serving_relation
            join pg_catalog.pg_namespace serving_namespace
              on serving_namespace.oid = serving_relation.relnamespace
            where serving_namespace.nspname = 'serving'
              and serving_relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and (
            select
                count(*) = 2
                and bool_and((reported_relation.relname, reported_relation.relkind::text) in (
                    ('reported_facts', 'r'),
                    ('reported_facts_reported_fact_id_seq', 'S')
                ))
            from pg_catalog.pg_class reported_relation
            join pg_catalog.pg_namespace reported_namespace
              on reported_namespace.oid = reported_relation.relnamespace
            where reported_namespace.nspname = 'reported'
              and reported_relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and (
            select
                count(*) = 6
                and bool_and((audit_relation.relname, audit_relation.relkind::text) in (
                    ('ingestion_runs', 'r'),
                    ('ingestion_run_artifacts', 'r'),
                    ('ingestion_run_artifacts_ingestion_run_artifact_id_seq', 'S'),
                    ('review_decisions', 'r'),
                    ('review_decisions_review_decision_id_seq', 'S'),
                    ('effective_review_decisions', 'v')
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
        count(*) = 6
        and bool_and((relation.relname, relation.relkind::text) in (
            ('ingestion_runs', 'r'),
            ('ingestion_run_artifacts', 'r'),
            ('ingestion_run_artifacts_ingestion_run_artifact_id_seq', 'S'),
            ('review_decisions', 'r'),
            ('review_decisions_review_decision_id_seq', 'S'),
            ('effective_review_decisions', 'v')
        ))
        and pg_catalog.to_regclass('audit.quality_issues') is null
        and pg_catalog.to_regclass('audit.review_decisions') is not null
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
    select count(*) = 8 as valid
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
        ('regulatory_registrations_id_regulator_key', 'u',
            'UNIQUE (regulatory_registration_id, regulator_id)'),
        ('institution_aliases_source_fkey', 'f',
            'FOREIGN KEY (source_id) REFERENCES evidence.sources(source_id)'),
        ('regulatory_concepts_id_source_key', 'u',
            'UNIQUE (regulatory_concept_id, source_id)')
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
        pg_catalog.to_regclass('reported.reported_facts') is not null
        and pg_catalog.to_regclass('semantic.canonical_concepts') is null
        and pg_catalog.to_regclass('metrics.metric_definitions') is null
        and pg_catalog.to_regclass('serving.current_publishable_facts') is not null
        and pg_catalog.to_regclass('audit.quality_issues') is null
        and pg_catalog.to_regclass('audit.review_decisions') is not null
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
    ('regulatory_registrations_id_regulator_key'),
    ('institution_aliases_source_fkey'),
    ('regulatory_concepts_id_source_key')
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

with pr15_columns_gate as (
    select
        count(*) = 28
        and (
            select count(*) = 28
            from information_schema.columns
            where table_schema = 'reported'
              and table_name = 'reported_facts'
        )
        and (
            select bool_and(actual.is_generated = 'NEVER')
            from information_schema.columns actual
            where actual.table_schema = 'reported'
              and actual.table_name = 'reported_facts'
              and actual.column_name in ('locator_hash', 'fact_key_hash')
        ) as valid
    from (values
        ('reported_fact_id', 'bigint', 'NO'),
        ('regulatory_registration_id', 'uuid', 'NO'),
        ('regulator_id', 'uuid', 'NO'),
        ('regulatory_concept_id', 'uuid', 'NO'),
        ('source_id', 'uuid', 'NO'),
        ('reporting_scope_id', 'uuid', 'NO'),
        ('source_artifact_id', 'uuid', 'NO'),
        ('source_release_id', 'uuid', 'NO'),
        ('ingestion_run_id', 'uuid', 'NO'),
        ('source_definition_version', 'integer', 'NO'),
        ('parser_implementation_key', 'text', 'NO'),
        ('parser_implementation_version', 'text', 'NO'),
        ('identity_definition_hash', 'text', 'NO'),
        ('period_kind', 'text', 'NO'),
        ('period_start', 'date', 'YES'),
        ('period_end', 'date', 'NO'),
        ('unit_code', 'text', 'NO'),
        ('dimensions', 'jsonb', 'NO'),
        ('raw_value', 'text', 'NO'),
        ('parsed_value', 'numeric', 'NO'),
        ('raw_label', 'text', 'YES'),
        ('locator_kind', 'text', 'NO'),
        ('source_locator', 'jsonb', 'NO'),
        ('locator_hash', 'text', 'NO'),
        ('fact_key_hash', 'text', 'NO'),
        ('first_observed_at', 'timestamp with time zone', 'NO'),
        ('predecessor_reported_fact_id', 'bigint', 'YES'),
        ('supersession_reason', 'text', 'YES')
    ) as expected(column_name, data_type, is_nullable)
    join information_schema.columns actual
      on actual.table_schema = 'reported'
     and actual.table_name = 'reported_facts'
     and actual.column_name = expected.column_name
     and actual.data_type = expected.data_type
     and actual.is_nullable = expected.is_nullable
), pr15_identity_gate as (
    select
        actual.is_identity = 'YES'
        and actual.identity_generation = 'ALWAYS'
        and actual.column_default is null as valid
    from information_schema.columns actual
    where actual.table_schema = 'reported'
      and actual.table_name = 'reported_facts'
      and actual.column_name = 'reported_fact_id'
), pr15_relationship_gate as (
    select count(*) = 16 as valid
    from (values
        ('sources_id_regulator_key', 'u',
            'UNIQUE (source_id, regulator_id)'),
        ('source_releases_id_source_key', 'u',
            'UNIQUE (source_release_id, source_id)'),
        ('source_artifacts_id_release_key', 'u',
            'UNIQUE (source_artifact_id, source_release_id)'),
        ('regulatory_registrations_id_regulator_key', 'u',
            'UNIQUE (regulatory_registration_id, regulator_id)'),
        ('regulatory_concepts_id_source_key', 'u',
            'UNIQUE (regulatory_concept_id, source_id)'),
        ('ingestion_runs_fact_provenance_key', 'u',
            'UNIQUE (ingestion_run_id, source_id, source_definition_version, parser_implementation_key, parser_implementation_version, identity_definition_hash)'),
        ('reported_facts_concept_scope_fkey', 'f',
            'FOREIGN KEY (regulatory_concept_id, reporting_scope_id) REFERENCES registry.regulatory_concept_scopes(regulatory_concept_id, reporting_scope_id)'),
        ('reported_facts_concept_source_fkey', 'f',
            'FOREIGN KEY (regulatory_concept_id, source_id) REFERENCES registry.regulatory_concepts(regulatory_concept_id, source_id)'),
        ('reported_facts_registration_regulator_fkey', 'f',
            'FOREIGN KEY (regulatory_registration_id, regulator_id) REFERENCES registry.regulatory_registrations(regulatory_registration_id, regulator_id)'),
        ('reported_facts_source_regulator_fkey', 'f',
            'FOREIGN KEY (source_id, regulator_id) REFERENCES evidence.sources(source_id, regulator_id)'),
        ('reported_facts_artifact_release_fkey', 'f',
            'FOREIGN KEY (source_artifact_id, source_release_id) REFERENCES evidence.source_artifacts(source_artifact_id, source_release_id)'),
        ('reported_facts_release_source_fkey', 'f',
            'FOREIGN KEY (source_release_id, source_id) REFERENCES evidence.source_releases(source_release_id, source_id)'),
        ('reported_facts_run_provenance_fkey', 'f',
            'FOREIGN KEY (ingestion_run_id, source_id, source_definition_version, parser_implementation_key, parser_implementation_version, identity_definition_hash) REFERENCES audit.ingestion_runs(ingestion_run_id, source_id, source_definition_version, parser_implementation_key, parser_implementation_version, identity_definition_hash)'),
        ('reported_facts_unit_fkey', 'f',
            'FOREIGN KEY (unit_code) REFERENCES registry.measurement_units(unit_code)'),
        ('reported_facts_predecessor_fkey', 'f',
            'FOREIGN KEY (predecessor_reported_fact_id) REFERENCES reported.reported_facts(reported_fact_id)'),
        ('reported_facts_extraction_identity_key', 'u',
            'UNIQUE (source_artifact_id, locator_hash, source_definition_version, parser_implementation_key, parser_implementation_version, fact_key_hash)')
    ) as expected(constraint_name, constraint_kind, constraint_definition)
    join pg_catalog.pg_constraint actual
      on actual.conname = expected.constraint_name
     and actual.contype = expected.constraint_kind::"char"
     and pg_catalog.pg_get_constraintdef(actual.oid) = expected.constraint_definition
), pr15_check_gate as (
    select
        count(*) = 17
        and not exists (
            select 1
            from pg_catalog.pg_constraint
            where conrelid = 'reported.reported_facts'::regclass
              and contype = 'u'
              and pg_catalog.pg_get_constraintdef(oid) like '%predecessor_reported_fact_id%'
        ) as valid
    from (values
        ('reported_facts_source_definition_version_positive'),
        ('reported_facts_parser_key_valid'),
        ('reported_facts_parser_version_valid'),
        ('reported_facts_identity_definition_hash_sha256'),
        ('reported_facts_period_kind_valid'),
        ('reported_facts_period_bounds_valid'),
        ('reported_facts_dimensions_object'),
        ('reported_facts_raw_value_not_blank'),
        ('reported_facts_parsed_value_finite'),
        ('reported_facts_raw_label_not_blank'),
        ('reported_facts_locator_kind_valid'),
        ('reported_facts_source_locator_object'),
        ('reported_facts_locator_hash_sha256'),
        ('reported_facts_fact_key_hash_sha256'),
        ('reported_facts_supersession_reason_valid'),
        ('reported_facts_supersession_pair_valid'),
        ('reported_facts_no_direct_self_predecessor')
    ) as expected(constraint_name)
    join pg_catalog.pg_constraint actual
      on actual.conname = expected.constraint_name
     and actual.contype = 'c'
     and actual.conrelid = 'reported.reported_facts'::regclass
), pr15_index_gate as (
    select
        count(*) = 3
        and bool_and(index_relation.relname in (
            'reported_facts_predecessor_idx',
            'reported_facts_logical_observed_idx',
            'reported_facts_registration_lookup_idx'
        ))
        and bool_and(not index_definition.indisunique)
        and (
            select not index_definition.indisunique
                and index_definition.indpred is not null
            from pg_catalog.pg_class index_relation
            join pg_catalog.pg_index index_definition
              on index_definition.indexrelid = index_relation.oid
            where index_relation.relname = 'reported_facts_predecessor_idx'
        )
        and not exists (
            select 1
            from pg_catalog.pg_class index_relation
            join pg_catalog.pg_index index_definition
              on index_definition.indexrelid = index_relation.oid
            join pg_catalog.pg_am access_method
              on access_method.oid = index_relation.relam
            join pg_catalog.pg_namespace namespace
              on namespace.oid = index_relation.relnamespace
            where namespace.nspname = 'reported'
              and access_method.amname = 'gin'
        ) as valid
    from pg_catalog.pg_index index_definition
    join pg_catalog.pg_class index_relation
      on index_relation.oid = index_definition.indexrelid
    join pg_catalog.pg_class table_relation
      on table_relation.oid = index_definition.indrelid
    join pg_catalog.pg_namespace namespace
      on namespace.oid = table_relation.relnamespace
    where namespace.nspname = 'reported'
      and table_relation.relname = 'reported_facts'
      and not exists (
          select 1
          from pg_catalog.pg_constraint backing_constraint
          where backing_constraint.conindid = index_definition.indexrelid
      )
), pr15_object_gate as (
    select
        (
            select count(*) = 2 and bool_and(not trigger.tgisinternal)
            from pg_catalog.pg_trigger trigger
            join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname = 'reported'
              and relation.relname = 'reported_facts'
              and not trigger.tgisinternal
              and trigger.tgname in (
                  'reported_facts_prepare_insert',
                  'reported_facts_append_only'
              )
        )
        and (
            select count(*) = 2
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname = 'reported'
              and function.proname in (
                  'prepare_reported_fact_insert',
                  'reject_reported_fact_mutation'
              )
              and not function.prosecdef
        )
        and not exists (
            select 1
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname = 'reported'
              and function.prosecdef
        ) as valid
), pr15_access_gate as (
    select
        relation.relrowsecurity
        and not exists (
            select 1 from pg_catalog.pg_policies where schemaname = 'reported'
        )
        and not exists (select 1 from reported.reported_facts)
        and pg_catalog.has_table_privilege(
            'service_role', 'reported.reported_facts', 'SELECT'
        )
        and not pg_catalog.has_table_privilege(
            'service_role', 'reported.reported_facts',
            'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
        )
        and pg_catalog.has_column_privilege(
            'service_role', 'reported.reported_facts', 'raw_value', 'INSERT'
        )
        and not pg_catalog.has_column_privilege(
            'service_role', 'reported.reported_facts', 'locator_hash', 'INSERT'
        )
        and not pg_catalog.has_column_privilege(
            'service_role', 'reported.reported_facts', 'fact_key_hash', 'INSERT'
        )
        and not pg_catalog.has_column_privilege(
            'service_role', 'reported.reported_facts', 'reported_fact_id', 'INSERT'
        )
        and pg_catalog.has_sequence_privilege(
            'service_role', 'reported.reported_facts_reported_fact_id_seq', 'USAGE'
        )
        and not pg_catalog.has_sequence_privilege(
            'service_role', 'reported.reported_facts_reported_fact_id_seq',
            'SELECT, UPDATE'
        )
        and (
            select bool_and(not pg_catalog.has_table_privilege(
                role_name,
                'reported.reported_facts',
                'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
            ))
            from unnest(array['anon', 'authenticated']) as role_name
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
            where public_namespace.nspname = 'reported'
              and public_relation.relname = 'reported_facts'
              and table_acl.grantee = 0
        )
        and (
            select bool_and(not pg_catalog.has_function_privilege(
                role_name,
                function_signature,
                'EXECUTE'
            ))
            from unnest(array['anon', 'authenticated', 'service_role']) as role_name
            cross join unnest(array[
                'reported.prepare_reported_fact_insert()',
                'reported.reject_reported_fact_mutation()'
            ]) as function_signature
        )
        and not exists (
            select 1
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            cross join lateral pg_catalog.aclexplode(
                coalesce(function.proacl, acldefault('f', function.proowner))
            ) as function_acl
            where namespace.nspname = 'reported'
              and function.proname in (
                  'prepare_reported_fact_insert',
                  'reject_reported_fact_mutation'
              )
              and function_acl.grantee = 0
        ) as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'reported'
      and relation.relname = 'reported_facts'
), pr15_boundary_gate as (
    select
        pg_catalog.to_regclass('audit.quality_issues') is null
        and pg_catalog.to_regclass('serving.current_observed_facts') is not null
        and pg_catalog.to_regclass('serving.current_publishable_facts') is not null
        and pg_catalog.to_regclass('semantic.canonical_concepts') is null
        and pg_catalog.to_regclass('metrics.metric_definitions') is null
        and pg_catalog.to_regclass('public.regulatory_bank_metrics_v1') is null as valid
)
select
    pr15_columns_gate.valid as pr15_columns_gate,
    pr15_identity_gate.valid as pr15_identity_gate,
    pr15_relationship_gate.valid as pr15_relationship_gate,
    pr15_check_gate.valid as pr15_check_gate,
    pr15_index_gate.valid as pr15_index_gate,
    pr15_object_gate.valid as pr15_object_gate,
    pr15_access_gate.valid as pr15_access_gate,
    pr15_boundary_gate.valid as pr15_boundary_gate,
    (
        pr15_columns_gate.valid
        and pr15_identity_gate.valid
        and pr15_relationship_gate.valid
        and pr15_check_gate.valid
        and pr15_index_gate.valid
        and pr15_object_gate.valid
        and pr15_access_gate.valid
        and pr15_boundary_gate.valid
    ) as pr15_schema_passed
from pr15_columns_gate
cross join pr15_identity_gate
cross join pr15_relationship_gate
cross join pr15_check_gate
cross join pr15_index_gate
cross join pr15_object_gate
cross join pr15_access_gate
cross join pr15_boundary_gate
\gset

\echo PR15 gate columns: :pr15_columns_gate
\echo PR15 gate identity: :pr15_identity_gate
\echo PR15 gate relationships: :pr15_relationship_gate
\echo PR15 gate checks: :pr15_check_gate
\echo PR15 gate indexes: :pr15_index_gate
\echo PR15 gate objects: :pr15_object_gate
\echo PR15 gate access: :pr15_access_gate
\echo PR15 gate boundary: :pr15_boundary_gate
\echo PR15 aggregate schema: :pr15_schema_passed

\if :pr15_schema_passed
\echo 'PR15 reported fact schema contract passed.'
\else
\echo 'PR15 reported fact schema contract failed.'
do $$
begin
    raise exception 'PR15 reported fact schema gate failed.';
end
$$;
\endif

with pr15a_columns_gate as (
    select
        count(*) = 11
        and (
            select count(*) = 11
            from information_schema.columns
            where table_schema = 'audit'
              and table_name = 'review_decisions'
        ) as valid
    from (values
        ('review_decision_id', 'bigint', 'NO'),
        ('reported_fact_id', 'bigint', 'NO'),
        ('decision', 'text', 'NO'),
        ('decided_at', 'timestamp with time zone', 'NO'),
        ('actor_kind', 'text', 'NO'),
        ('human_actor_key', 'text', 'YES'),
        ('policy_implementation_key', 'text', 'YES'),
        ('policy_implementation_version', 'text', 'YES'),
        ('policy_git_sha', 'text', 'YES'),
        ('reason', 'text', 'NO'),
        ('corrects_review_decision_id', 'bigint', 'YES')
    ) as expected(column_name, data_type, is_nullable)
    join information_schema.columns actual
      on actual.table_schema = 'audit'
     and actual.table_name = 'review_decisions'
     and actual.column_name = expected.column_name
     and actual.data_type = expected.data_type
     and actual.is_nullable = expected.is_nullable
), pr15a_identity_gate as (
    select
        actual.is_identity = 'YES'
        and actual.identity_generation = 'ALWAYS'
        and actual.column_default is null
        and (
            select column_default is null and is_generated = 'NEVER'
            from information_schema.columns
            where table_schema = 'audit'
              and table_name = 'review_decisions'
              and column_name = 'decided_at'
        ) as valid
    from information_schema.columns actual
    where actual.table_schema = 'audit'
      and actual.table_name = 'review_decisions'
      and actual.column_name = 'review_decision_id'
), pr15a_relationship_gate as (
    select count(*) = 4 as valid
    from (values
        ('review_decisions_pkey', 'p', 'PRIMARY KEY (review_decision_id)'),
        ('review_decisions_fact_fkey', 'f',
            'FOREIGN KEY (reported_fact_id) REFERENCES reported.reported_facts(reported_fact_id)'),
        ('review_decisions_id_fact_key', 'u',
            'UNIQUE (review_decision_id, reported_fact_id)'),
        ('review_decisions_correction_fkey', 'f',
            'FOREIGN KEY (corrects_review_decision_id, reported_fact_id) REFERENCES audit.review_decisions(review_decision_id, reported_fact_id)')
    ) as expected(constraint_name, constraint_kind, constraint_definition)
    join pg_catalog.pg_constraint actual
      on actual.conname = expected.constraint_name
     and actual.contype = expected.constraint_kind::"char"
     and actual.conrelid = 'audit.review_decisions'::regclass
     and pg_catalog.pg_get_constraintdef(actual.oid) = expected.constraint_definition
), pr15a_check_gate as (
    select
        count(*) = 9
        and not exists (
            select 1
            from pg_catalog.pg_constraint
            where conrelid = 'audit.review_decisions'::regclass
              and contype = 'u'
              and pg_catalog.pg_get_constraintdef(oid)
                  like '%corrects_review_decision_id%'
        ) as valid
    from (values
        ('review_decisions_decision_valid'),
        ('review_decisions_actor_kind_valid'),
        ('review_decisions_actor_shape_valid'),
        ('review_decisions_human_actor_key_valid'),
        ('review_decisions_policy_key_valid'),
        ('review_decisions_policy_version_valid'),
        ('review_decisions_policy_git_sha_full'),
        ('review_decisions_reason_valid'),
        ('review_decisions_no_self_correction')
    ) as expected(constraint_name)
    join pg_catalog.pg_constraint actual
      on actual.conname = expected.constraint_name
     and actual.contype = 'c'
     and actual.conrelid = 'audit.review_decisions'::regclass
), pr15a_vocabulary_gate as (
    select
        (
            select bool_and(definition like '%' || required_token || '%')
            from pg_catalog.pg_constraint
            cross join lateral (
                select pg_catalog.pg_get_constraintdef(oid) as definition
            ) as rendered
            cross join unnest(array['ACCEPT', 'REJECT', 'REVOKE']) as required_token
            where conrelid = 'audit.review_decisions'::regclass
              and conname = 'review_decisions_decision_valid'
        )
        and (
            select bool_and(definition like '%' || required_token || '%')
            from pg_catalog.pg_constraint
            cross join lateral (
                select pg_catalog.pg_get_constraintdef(oid) as definition
            ) as rendered
            cross join unnest(array['HUMAN', 'SYSTEM_POLICY']) as required_token
            where conrelid = 'audit.review_decisions'::regclass
              and conname = 'review_decisions_actor_kind_valid'
        )
        and (
            select bool_and(definition like '%' || required_token || '%')
            from pg_catalog.pg_constraint
            cross join lateral (
                select pg_catalog.pg_get_constraintdef(oid) as definition
            ) as rendered
            cross join unnest(array['btrim', '512', 'cntrl']) as required_token
            where conrelid = 'audit.review_decisions'::regclass
              and conname = 'review_decisions_reason_valid'
        )
        and (
            select bool_and(definition like '%' || required_token || '%')
            from pg_catalog.pg_constraint
            cross join lateral (
                select pg_catalog.pg_get_constraintdef(oid) as definition
            ) as rendered
            cross join unnest(array[
                '[a-f0-9]{40}', '[a-f0-9]{64}'
            ]) as required_token
            where conrelid = 'audit.review_decisions'::regclass
              and conname = 'review_decisions_policy_git_sha_full'
        ) as valid
), pr15a_index_gate as (
    select
        count(*) = 2
        and bool_and(index_relation.relname in (
            'review_decisions_fact_timeline_idx',
            'review_decisions_corrects_idx'
        ))
        and bool_and(not index_definition.indisunique)
        and (
            select not index_definition.indisunique
                and index_definition.indpred is not null
            from pg_catalog.pg_class index_relation
            join pg_catalog.pg_index index_definition
              on index_definition.indexrelid = index_relation.oid
            where index_relation.relname = 'review_decisions_corrects_idx'
        )
        and (
            select pg_catalog.pg_get_indexdef(index_definition.indexrelid)
                like '%(reported_fact_id, decided_at DESC, review_decision_id DESC)%'
            from pg_catalog.pg_class index_relation
            join pg_catalog.pg_index index_definition
              on index_definition.indexrelid = index_relation.oid
            where index_relation.relname = 'review_decisions_fact_timeline_idx'
        )
        and not exists (
            select 1
            from pg_catalog.pg_class index_relation
            join pg_catalog.pg_index index_definition
              on index_definition.indexrelid = index_relation.oid
            join pg_catalog.pg_am access_method
              on access_method.oid = index_relation.relam
            join pg_catalog.pg_class table_relation
              on table_relation.oid = index_definition.indrelid
            join pg_catalog.pg_namespace namespace
              on namespace.oid = table_relation.relnamespace
            where namespace.nspname = 'audit'
              and table_relation.relname = 'review_decisions'
              and access_method.amname <> 'btree'
        ) as valid
    from pg_catalog.pg_index index_definition
    join pg_catalog.pg_class index_relation
      on index_relation.oid = index_definition.indexrelid
    join pg_catalog.pg_class table_relation
      on table_relation.oid = index_definition.indrelid
    join pg_catalog.pg_namespace namespace
      on namespace.oid = table_relation.relnamespace
    where namespace.nspname = 'audit'
      and table_relation.relname = 'review_decisions'
      and not exists (
          select 1
          from pg_catalog.pg_constraint backing_constraint
          where backing_constraint.conindid = index_definition.indexrelid
      )
), pr15a_object_gate as (
    select
        (
            select count(*) = 2 and bool_and(not trigger.tgisinternal)
            from pg_catalog.pg_trigger trigger
            join pg_catalog.pg_class relation on relation.oid = trigger.tgrelid
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname = 'audit'
              and relation.relname = 'review_decisions'
              and not trigger.tgisinternal
              and trigger.tgname in (
                  'review_decisions_enforce_insert',
                  'review_decisions_append_only'
              )
        )
        and (
            select count(*) = 3
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname = 'audit'
              and function.proname in (
                  'enforce_review_decision_insert',
                  'reject_review_decision_mutation',
                  'effective_review_decisions_as_of'
              )
              and not function.prosecdef
        )
        and (
            select function.provolatile = 's' and function.prolang = (
                select oid from pg_catalog.pg_language where lanname = 'sql'
            )
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname = 'audit'
              and function.proname = 'effective_review_decisions_as_of'
        )
        and not exists (
            select 1
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname = 'audit'
              and function.prosecdef
        )
        and exists (
            select 1
            from pg_catalog.pg_class relation
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            cross join lateral unnest(
                coalesce(relation.reloptions, array[]::text[])
            ) as view_option
            where namespace.nspname = 'audit'
              and relation.relname = 'effective_review_decisions'
              and relation.relkind = 'v'
              and lower(view_option) in (
                  'security_invoker=true',
                  'security_invoker=on',
                  'security_invoker=1'
              )
        ) as valid
), pr15a_access_gate as (
    select
        relation.relrowsecurity
        and not exists (
            select 1
            from pg_catalog.pg_policies
            where schemaname = 'audit'
              and tablename in ('review_decisions', 'effective_review_decisions')
        )
        and not exists (select 1 from audit.review_decisions)
        and pg_catalog.has_table_privilege(
            'service_role', 'audit.review_decisions', 'SELECT'
        )
        and not pg_catalog.has_table_privilege(
            'service_role', 'audit.review_decisions',
            'UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
        )
        and (
            select bool_and(pg_catalog.has_column_privilege(
                'service_role', 'audit.review_decisions', writable_column, 'INSERT'
            ))
            from unnest(array[
                'reported_fact_id',
                'decision',
                'decided_at',
                'actor_kind',
                'human_actor_key',
                'policy_implementation_key',
                'policy_implementation_version',
                'policy_git_sha',
                'reason',
                'corrects_review_decision_id'
            ]) as writable_column
        )
        and not pg_catalog.has_column_privilege(
            'service_role', 'audit.review_decisions', 'review_decision_id', 'INSERT'
        )
        and pg_catalog.has_sequence_privilege(
            'service_role', 'audit.review_decisions_review_decision_id_seq', 'USAGE'
        )
        and not pg_catalog.has_sequence_privilege(
            'service_role',
            'audit.review_decisions_review_decision_id_seq',
            'SELECT, UPDATE'
        )
        and pg_catalog.has_table_privilege(
            'service_role', 'audit.effective_review_decisions', 'SELECT'
        )
        and not pg_catalog.has_table_privilege(
            'service_role', 'audit.effective_review_decisions',
            'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
        )
        and pg_catalog.has_function_privilege(
            'service_role',
            'audit.effective_review_decisions_as_of(timestamptz)',
            'EXECUTE'
        )
        and (
            select bool_and(not pg_catalog.has_table_privilege(
                role_name,
                audit_relation,
                'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
            ))
            from unnest(array['anon', 'authenticated']) as role_name
            cross join unnest(array[
                'audit.review_decisions',
                'audit.effective_review_decisions'
            ]) as audit_relation
        )
        and (
            select bool_and(not pg_catalog.has_function_privilege(
                role_name, function_signature, 'EXECUTE'
            ))
            from unnest(array['anon', 'authenticated', 'service_role']) as role_name
            cross join unnest(array[
                'audit.enforce_review_decision_insert()',
                'audit.reject_review_decision_mutation()'
            ]) as function_signature
        )
        and (
            select bool_and(not pg_catalog.has_function_privilege(
                role_name,
                'audit.effective_review_decisions_as_of(timestamptz)',
                'EXECUTE'
            ))
            from unnest(array['anon', 'authenticated']) as role_name
        )
        and not exists (
            select 1
            from pg_catalog.pg_class target
            join pg_catalog.pg_namespace namespace
              on namespace.oid = target.relnamespace
            cross join lateral pg_catalog.aclexplode(
                coalesce(
                    target.relacl,
                    acldefault(
                        (
                            case target.relkind
                                when 'S' then 's'
                                else 'r'
                            end
                        )::"char",
                        target.relowner
                    )
                )
            ) as target_acl
            where namespace.nspname = 'audit'
              and target.relname in (
                  'review_decisions',
                  'review_decisions_review_decision_id_seq',
                  'effective_review_decisions'
              )
              and target_acl.grantee = 0
        )
        and not exists (
            select 1
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            cross join lateral pg_catalog.aclexplode(
                coalesce(function.proacl, acldefault('f', function.proowner))
            ) as function_acl
            where namespace.nspname = 'audit'
              and function.proname in (
                  'enforce_review_decision_insert',
                  'reject_review_decision_mutation',
                  'effective_review_decisions_as_of'
              )
              and function_acl.grantee = 0
        ) as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'audit'
      and relation.relname = 'review_decisions'
), pr15a_boundary_gate as (
    select
        pg_catalog.to_regclass('audit.review_decisions') is not null
        and pg_catalog.to_regclass('audit.quality_issues') is null
        and pg_catalog.to_regclass('serving.reported_fact_revision_ancestry') is not null
        and pg_catalog.to_regclass('serving.current_observed_facts') is not null
        and pg_catalog.to_regclass('serving.current_publishable_facts') is not null
        and pg_catalog.to_regclass('semantic.canonical_concepts') is null
        and pg_catalog.to_regclass('metrics.metric_definitions') is null
        and pg_catalog.to_regclass('public.regulatory_bank_metrics_v1') is null
        and not exists (
            select 1
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname in ('semantic', 'metrics')
        )
        and (
            select count(*) = 2
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname = 'serving'
              and function.proname in (
                  'observed_facts_as_of',
                  'publishable_facts_as_of'
              )
        )
        and not exists (
            select 1
            from information_schema.columns
            where table_schema in ('audit', 'reported')
              and column_name in (
                  'current_observed',
                  'current_publishable',
                  'observed_as_of',
                  'publishable_as_of',
                  'quality_issue_id',
                  'review_status',
                  'idempotency_key',
                  'request_key'
              )
        ) as valid
)
select
    pr15a_columns_gate.valid as pr15a_columns_gate,
    pr15a_identity_gate.valid as pr15a_identity_gate,
    pr15a_relationship_gate.valid as pr15a_relationship_gate,
    pr15a_check_gate.valid as pr15a_check_gate,
    pr15a_vocabulary_gate.valid as pr15a_vocabulary_gate,
    pr15a_index_gate.valid as pr15a_index_gate,
    pr15a_object_gate.valid as pr15a_object_gate,
    pr15a_access_gate.valid as pr15a_access_gate,
    pr15a_boundary_gate.valid as pr15a_boundary_gate,
    (
        pr15a_columns_gate.valid
        and pr15a_identity_gate.valid
        and pr15a_relationship_gate.valid
        and pr15a_check_gate.valid
        and pr15a_vocabulary_gate.valid
        and pr15a_index_gate.valid
        and pr15a_object_gate.valid
        and pr15a_access_gate.valid
        and pr15a_boundary_gate.valid
    ) as pr15a_schema_passed
from pr15a_columns_gate
cross join pr15a_identity_gate
cross join pr15a_relationship_gate
cross join pr15a_check_gate
cross join pr15a_vocabulary_gate
cross join pr15a_index_gate
cross join pr15a_object_gate
cross join pr15a_access_gate
cross join pr15a_boundary_gate
\gset

\echo PR15a gate columns: :pr15a_columns_gate
\echo PR15a gate identity: :pr15a_identity_gate
\echo PR15a gate relationships: :pr15a_relationship_gate
\echo PR15a gate checks: :pr15a_check_gate
\echo PR15a gate vocabulary: :pr15a_vocabulary_gate
\echo PR15a gate indexes: :pr15a_index_gate
\echo PR15a gate objects: :pr15a_object_gate
\echo PR15a gate access: :pr15a_access_gate
\echo PR15a gate boundary: :pr15a_boundary_gate
\echo PR15a aggregate schema: :pr15a_schema_passed

\if :pr15a_schema_passed
\echo 'PR15a review decision schema contract passed.'
\else
\echo 'PR15a review decision schema contract failed.'
do $$
begin
    raise exception 'PR15a review decision schema gate failed.';
end
$$;
\endif

insert into registry.measurement_units (unit_code, dimension, currency_code, multiplier)
values ('MXN', 'currency', 'MXN', 1);

insert into evidence.source_definition_versions (
    source_definition_version_id, source_id, definition_version, label, country, sector,
    adapter_key, methodological_role, lifecycle, definition_snapshot, config_hash, git_sha
)
values (
    '00000000-0000-4000-8000-000000000022',
    '00000000-0000-4000-8000-000000000011',
    2, 'Test source v2', 'MX', 'banca_multiple', 'test_source', 'primary', 'draft',
    '{"code":"test_source","definition_version":2}'::jsonb, repeat('9', 64), repeat('a', 40)
);

insert into registry.reporting_scopes (reporting_scope_id, scope_code)
values
    ('00000000-0000-4000-8000-000000000762', 'test_unpaired_scope'),
    ('00000000-0000-4000-8000-000000000763', 'test_second_scope');

insert into registry.regulatory_concept_scopes (
    regulatory_concept_id, reporting_scope_id
)
values (
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000763'
);

insert into registry.regulatory_concepts (
    regulatory_concept_id, source_id, external_code, definition_version, label,
    definition, lifecycle, valid_from, valid_to, definition_snapshot, definition_hash, git_sha
)
values (
    '00000000-0000-4000-8000-000000000752',
    '00000000-0000-4000-8000-000000000012',
    '1402', 1, 'Other source concept', 'Synthetic other source concept.',
    'draft', '2026-01-01', null,
    '{"source_code":"test_source_2","code":"1402"}'::jsonb,
    repeat('b', 64), repeat('c', 40)
);

insert into registry.regulatory_concept_scopes (
    regulatory_concept_id, reporting_scope_id
)
values (
    '00000000-0000-4000-8000-000000000752',
    '00000000-0000-4000-8000-000000000761'
);

insert into registry.regulatory_registrations (
    regulatory_registration_id, institution_id, institution_definition_version_id,
    regulator_id, registration_type, registration_code, valid_from, valid_to
)
values (
    '00000000-0000-4000-8000-000000000724',
    '00000000-0000-4000-8000-000000000701',
    '00000000-0000-4000-8000-000000000711',
    '00000000-0000-4000-8000-000000000301',
    'audit_registration', 'REG-AUDIT', '2026-01-01', null
);

insert into audit.ingestion_runs (
    ingestion_run_id, source_id, source_definition_version, trigger_kind, parameters,
    parser_implementation_key, parser_implementation_version, identity_definition_hash, git_sha
)
values
    (
        '00000000-0000-4000-8000-000000000801',
        '00000000-0000-4000-8000-000000000011',
        1, 'test', '{}'::jsonb, 'test_parser', '1', repeat('a', 64), repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000802',
        '00000000-0000-4000-8000-000000000011',
        1, 'test', '{}'::jsonb, 'test_parser', '2', repeat('a', 64), repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000803',
        '00000000-0000-4000-8000-000000000011',
        2, 'test', '{}'::jsonb, 'test_parser', '1', repeat('a', 64), repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000804',
        '00000000-0000-4000-8000-000000000011',
        1, 'test', '{}'::jsonb, 'test_parser', '1', repeat('b', 64), repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000805',
        '00000000-0000-4000-8000-000000000011',
        1, 'test', '{}'::jsonb, null, null, repeat('a', 64), repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000806',
        '00000000-0000-4000-8000-000000000011',
        1, 'test', '{}'::jsonb, 'test_parser', '1', null, repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000807',
        '00000000-0000-4000-8000-000000000311',
        1, 'test', '{}'::jsonb, 'test_parser', '1', repeat('a', 64), repeat('1', 40)
    ),
    (
        '00000000-0000-4000-8000-000000000808',
        '00000000-0000-4000-8000-000000000011',
        1, 'test', '{}'::jsonb, 'test_parser', '1', repeat('a', 64), repeat('2', 40)
    );

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_start, period_end, unit_code,
    dimensions, raw_value, parsed_value, raw_label, locator_kind, source_locator,
    locator_hash, fact_key_hash, first_observed_at
)
values (
    '00000000-0000-4000-8000-000000000722',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000761',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000801',
    1, 'test_parser', '1', repeat('a', 64),
    'instant', null, '2026-06-30', 'MXN', '{}'::jsonb,
    '1234.50', 1234.50, 'Cartera vigente', 'csv', '{"row":1,"column":"C"}'::jsonb,
    repeat('e', 64), repeat('f', 64), '2026-09-19T12:00:00Z'
)
returning
    reported_fact_id as pr15_root_id,
    locator_hash as pr15_root_locator_hash,
    fact_key_hash as pr15_root_fact_key_hash,
    parsed_value as pr15_root_parsed_value
\gset

select
    :'pr15_root_locator_hash' = encode(
        sha256(
            convert_to(
                jsonb_build_object(
                    'locator_kind', 'csv',
                    'source_locator', '{"row":1,"column":"C"}'::jsonb
                )::text,
                'UTF8'
            )
        ),
        'hex'
    )
    and :'pr15_root_locator_hash' ~ '^[a-f0-9]{64}$'
    and :'pr15_root_locator_hash' <> repeat('e', 64)
    and :'pr15_root_fact_key_hash' = encode(
        sha256(
            convert_to(
                jsonb_build_object(
                    'dimensions', '{}'::jsonb,
                    'period_end', (date '2026-06-30' - date '0001-01-01'),
                    'period_kind', 'instant',
                    'period_start', null,
                    'regulatory_concept_id',
                        '00000000-0000-4000-8000-000000000751'::uuid,
                    'regulatory_registration_id',
                        '00000000-0000-4000-8000-000000000722'::uuid,
                    'reporting_scope_id',
                        '00000000-0000-4000-8000-000000000761'::uuid,
                    'unit_code', 'MXN'
                )::text,
                'UTF8'
            )
        ),
        'hex'
    )
    and :'pr15_root_fact_key_hash' <> repeat('f', 64)
    and :pr15_root_parsed_value = 1234.50 as pr15_root_hash_valid
\gset

\if :pr15_root_hash_valid
\else
\echo 'PR15 database hash computation failed.'
do $$
begin
    raise exception 'PR15 hash computation gate failed.';
end
$$;
\endif

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_start, period_end, unit_code,
    dimensions, raw_value, parsed_value, locator_kind, source_locator, first_observed_at
)
values (
    '00000000-0000-4000-8000-000000000722',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000761',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000801',
    1, 'test_parser', '1', repeat('a', 64),
    'duration', '2026-01-01', '2026-06-30', 'MXN', '{}'::jsonb,
    '0', 0, 'csv', '{"row":2,"column":"C"}'::jsonb, '2026-09-19T12:01:00Z'
);

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_start, period_end, unit_code,
    raw_value, parsed_value, locator_kind, source_locator, first_observed_at
)
values (
    '00000000-0000-4000-8000-000000000722',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000761',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000801',
    1, 'test_parser', '1', repeat('a', 64),
    'duration', '2026-06-30', '2026-06-30', 'MXN',
    '-12.5', -12.5, 'csv', '{"row":3,"column":"C"}'::jsonb, '2026-09-19T12:02:00Z'
);

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_end, unit_code,
    raw_value, parsed_value, locator_kind, source_locator, first_observed_at
)
values (
    '00000000-0000-4000-8000-000000000722',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000761',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000801',
    1, 'test_parser', '1', repeat('a', 64),
    'instant', '2026-06-30', 'MXN',
    '12345678901234567890.123456789012345678',
    12345678901234567890.123456789012345678,
    'csv', '{"row":4,"column":"C"}'::jsonb, '2026-09-19T12:03:00Z'
)
returning parsed_value as pr15_high_precision
\gset

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_end, unit_code,
    raw_value, parsed_value, locator_kind, source_locator,
    first_observed_at, predecessor_reported_fact_id, supersession_reason
)
values
    (
        '00000000-0000-4000-8000-000000000722',
        '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000751',
        '00000000-0000-4000-8000-000000000011',
        '00000000-0000-4000-8000-000000000761',
        '00000000-0000-4000-8000-000000000202',
        '00000000-0000-4000-8000-000000000102',
        '00000000-0000-4000-8000-000000000801',
        1, 'test_parser', '1', repeat('a', 64),
        'instant', '2026-06-30', 'MXN',
        '1234.50', 1234.50, 'csv', '{"row":1,"column":"C"}'::jsonb,
        '2026-09-19T12:04:00Z', :pr15_root_id, 'SOURCE_REVISION'
    ),
    (
        '00000000-0000-4000-8000-000000000722',
        '00000000-0000-4000-8000-000000000001',
        '00000000-0000-4000-8000-000000000751',
        '00000000-0000-4000-8000-000000000011',
        '00000000-0000-4000-8000-000000000761',
        '00000000-0000-4000-8000-000000000203',
        '00000000-0000-4000-8000-000000000101',
        '00000000-0000-4000-8000-000000000801',
        1, 'test_parser', '1', repeat('a', 64),
        'instant', '2026-06-30', 'MXN',
        '1234.50', 1234.50, 'csv', '{"row":9,"column":"C"}'::jsonb,
        '2026-09-19T12:05:00Z', :pr15_root_id, 'SOURCE_REVISION'
    );

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_end, unit_code,
    raw_value, parsed_value, locator_kind, source_locator,
    first_observed_at, predecessor_reported_fact_id, supersession_reason
)
values (
    '00000000-0000-4000-8000-000000000722',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000761',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000802',
    1, 'test_parser', '2', repeat('a', 64),
    'instant', '2026-06-30', 'MXN',
    '1234.51', 1234.51, 'csv', '{"row":1,"column":"C"}'::jsonb,
    '2026-09-19T12:06:00Z', :pr15_root_id, 'EXTRACTION_CORRECTION'
)
returning fact_key_hash as pr15_parser_correction_hash
\gset

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_end, unit_code,
    raw_value, parsed_value, locator_kind, source_locator,
    first_observed_at, predecessor_reported_fact_id, supersession_reason
)
values (
    '00000000-0000-4000-8000-000000000722',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000761',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000803',
    2, 'test_parser', '1', repeat('a', 64),
    'instant', '2026-06-30', 'MXN',
    '1234.52', 1234.52, 'csv', '{"row":1,"column":"C"}'::jsonb,
    '2026-09-19T12:07:00Z', :pr15_root_id, 'EXTRACTION_CORRECTION'
)
returning fact_key_hash as pr15_config_correction_hash
\gset

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_end, unit_code,
    raw_value, parsed_value, locator_kind, source_locator,
    first_observed_at, predecessor_reported_fact_id, supersession_reason
)
values (
    '00000000-0000-4000-8000-000000000721',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000761',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000804',
    1, 'test_parser', '1', repeat('b', 64),
    'instant', '2026-06-30', 'MXN',
    '1234.50', 1234.50, 'csv', '{"row":1,"column":"C"}'::jsonb,
    '2026-09-19T12:08:00Z', :pr15_root_id, 'IDENTITY_CORRECTION'
)
returning fact_key_hash as pr15_identity_correction_hash,
          locator_hash as pr15_identity_locator_hash
\gset

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_end, unit_code,
    raw_value, parsed_value, locator_kind, source_locator, first_observed_at
)
values (
    '00000000-0000-4000-8000-000000000722',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000763',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000801',
    1, 'test_parser', '1', repeat('a', 64),
    'instant', '2026-06-30', 'MXN',
    '1234.50', 1234.50, 'csv', '{"row":1,"column":"C"}'::jsonb, '2026-09-19T12:09:00Z'
)
returning fact_key_hash as pr15_other_scope_hash, locator_hash as pr15_other_scope_locator_hash
\gset

select
    :'pr15_parser_correction_hash' = :'pr15_root_fact_key_hash'
    and :'pr15_config_correction_hash' = :'pr15_root_fact_key_hash'
    and :'pr15_other_scope_hash' <> :'pr15_root_fact_key_hash'
    and :'pr15_identity_correction_hash' <> :'pr15_root_fact_key_hash'
    and :'pr15_identity_locator_hash' = :'pr15_root_locator_hash'
    and :'pr15_other_scope_locator_hash' = :'pr15_root_locator_hash'
    and (
        select locator_hash <> :'pr15_root_locator_hash'
        from reported.reported_facts
        where source_locator = '{"row":2,"column":"C"}'::jsonb
    )
    and (
        select parsed_value = 12345678901234567890.123456789012345678
        from reported.reported_facts
        where source_locator = '{"row":4,"column":"C"}'::jsonb
    )
    and (
        select count(*) = 2
        from reported.reported_facts
        where predecessor_reported_fact_id = :pr15_root_id
          and supersession_reason = 'SOURCE_REVISION'
    ) as pr15_hash_lineage_valid
\gset

\if :pr15_hash_lineage_valid
\else
\echo 'PR15 hash identity or lineage gate failed.'
do $$
begin
    raise exception 'PR15 hash identity or lineage gate failed.';
end
$$;
\endif

do $$
declare
    rejected boolean;
    root_id bigint;
    next_self_id bigint;
begin
    select reported_fact_id into strict root_id
    from reported.reported_facts
    where raw_label = 'Cartera vigente';

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_start, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":20,"column":"C"}'::jsonb, '2026-09-19T13:00:00Z'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'instant with period_start was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'duration', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":21,"column":"C"}'::jsonb, '2026-09-19T13:00:01Z'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'duration missing period_start was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_start, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'duration', '2026-07-01', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":22,"column":"C"}'::jsonb, '2026-09-19T13:00:02Z'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'reversed duration dates were accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 'NaN'::numeric, 'csv', '{"row":23,"column":"C"}'::jsonb,
            '2026-09-19T13:00:03Z'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'NaN parsed_value was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 'Infinity'::numeric, 'csv', '{"row":24,"column":"C"}'::jsonb,
            '2026-09-19T13:00:04Z'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'Infinity parsed_value was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', '-Infinity'::numeric, 'csv', '{"row":25,"column":"C"}'::jsonb,
            '2026-09-19T13:00:05Z'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception '-Infinity parsed_value was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '   ', 1, 'csv', '{"row":26,"column":"C"}'::jsonb, '2026-09-19T13:00:06Z'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'blank raw_value was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            null, 1, 'csv', '{"row":27,"column":"C"}'::jsonb, '2026-09-19T13:00:07Z'
        );
    exception when not_null_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'null raw_value was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', null, 'csv', '{"row":28,"column":"C"}'::jsonb, '2026-09-19T13:00:08Z'
        );
    exception when not_null_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'null parsed_value was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000762',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":29,"column":"C"}'::jsonb, '2026-09-19T13:00:09Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'unpaired concept/scope was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000752',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":30,"column":"C"}'::jsonb, '2026-09-19T13:00:10Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'wrong concept/source was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000724',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":31,"column":"C"}'::jsonb, '2026-09-19T13:00:11Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'wrong registration/regulator was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000401',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":32,"column":"C"}'::jsonb, '2026-09-19T13:00:12Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'wrong release/source was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000102',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":33,"column":"C"}'::jsonb, '2026-09-19T13:00:13Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'wrong artifact/release was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000807',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":34,"column":"C"}'::jsonb, '2026-09-19T13:00:14Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'wrong run/source provenance was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            2, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":35,"column":"C"}'::jsonb, '2026-09-19T13:00:15Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'mismatched source_definition_version was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '2', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":36,"column":"C"}'::jsonb, '2026-09-19T13:00:16Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'mismatched parser provenance was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('b', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":37,"column":"C"}'::jsonb, '2026-09-19T13:00:17Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'mismatched identity_definition_hash was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000805',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":38,"column":"C"}'::jsonb, '2026-09-19T13:00:18Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'null-parser run produced a fact';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000806',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":39,"column":"C"}'::jsonb, '2026-09-19T13:00:19Z'
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'null-identity-hash run produced a fact';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000808',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1234.50', 1234.50, 'csv', '{"row":1,"column":"C"}'::jsonb,
            '2026-09-19T13:00:20Z'
        );
    exception when unique_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'exact extraction rerun was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at,
            predecessor_reported_fact_id, supersession_reason
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":40,"column":"C"}'::jsonb, '2026-09-19T13:00:21Z',
            null, 'SOURCE_REVISION'
        );
    exception when check_violation or raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'root with supersession reason was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at,
            predecessor_reported_fact_id, supersession_reason
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000202',
            '00000000-0000-4000-8000-000000000102',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":41,"column":"C"}'::jsonb, '2026-09-19T13:00:22Z',
            root_id, null
        );
    exception when check_violation or raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'predecessor without reason was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at,
            predecessor_reported_fact_id, supersession_reason
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000202',
            '00000000-0000-4000-8000-000000000102',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":42,"column":"C"}'::jsonb, '2026-09-19T13:00:23Z',
            root_id, 'METHODOLOGY_CORRECTION'
        );
    exception when check_violation or raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'METHODOLOGY_CORRECTION was accepted';
    end if;

    next_self_id := nextval('reported.reported_facts_reported_fact_id_seq');
    rejected := false;
    begin
        insert into reported.reported_facts (
            reported_fact_id, regulatory_registration_id, regulator_id, regulatory_concept_id,
            source_id, reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at,
            predecessor_reported_fact_id, supersession_reason
        ) overriding system value values (
            next_self_id,
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000202',
            '00000000-0000-4000-8000-000000000102',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":43,"column":"C"}'::jsonb, '2026-09-19T13:00:24Z',
            next_self_id, 'SOURCE_REVISION'
        );
    exception when check_violation or raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'direct self predecessor was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at,
            predecessor_reported_fact_id, supersession_reason
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":44,"column":"C"}'::jsonb, '2026-09-19T13:00:25Z',
            root_id, 'SOURCE_REVISION'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'SOURCE_REVISION with same artifact was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at,
            predecessor_reported_fact_id, supersession_reason
        ) values (
            '00000000-0000-4000-8000-000000000722',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":45,"column":"C"}'::jsonb, '2026-09-19T13:00:26Z',
            root_id, 'EXTRACTION_CORRECTION'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'EXTRACTION_CORRECTION with unchanged parser/config was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at,
            predecessor_reported_fact_id, supersession_reason
        ) values (
            '00000000-0000-4000-8000-000000000721',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000801',
            1, 'test_parser', '1', repeat('a', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":1,"column":"C"}'::jsonb, '2026-09-19T13:00:27Z',
            root_id, 'IDENTITY_CORRECTION'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'IDENTITY_CORRECTION with same identity hash was accepted';
    end if;

    rejected := false;
    begin
        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at,
            predecessor_reported_fact_id, supersession_reason
        ) values (
            '00000000-0000-4000-8000-000000000721',
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            '00000000-0000-4000-8000-000000000804',
            1, 'test_parser', '1', repeat('b', 64),
            'instant', '2026-06-30', 'MXN',
            '1', 1, 'csv', '{"row":46,"column":"C"}'::jsonb, '2026-09-19T13:00:28Z',
            root_id, 'IDENTITY_CORRECTION'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'IDENTITY_CORRECTION with changed locator was accepted';
    end if;

    rejected := false;
    begin
        execute $statement$update reported.reported_facts
            set raw_value = 'mutated'
            where raw_label = 'Cartera vigente'$statement$;
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'table-owner UPDATE was accepted';
    end if;

    rejected := false;
    begin
        execute $statement$delete from reported.reported_facts
            where raw_label = 'Cartera vigente'$statement$;
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'table-owner DELETE was accepted';
    end if;
end
$$;

set local role service_role;

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_end, unit_code,
    raw_value, parsed_value, locator_kind, source_locator, first_observed_at
)
values (
    '00000000-0000-4000-8000-000000000722',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000761',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000801',
    1, 'test_parser', '1', repeat('a', 64),
    'instant', '2026-06-30', 'MXN',
    '99', 99, 'csv', '{"row":99,"column":"Z"}'::jsonb, '2026-09-19T13:01:00Z'
)
returning reported_fact_id as pr15_service_insert_id
\gset

select count(*) >= 1 as pr15_service_select_passed
from reported.reported_facts
\gset

\if :pr15_service_select_passed
\else
\echo 'PR15 service_role SELECT failed.'
do $$
begin
    raise exception 'PR15 service_role SELECT gate failed.';
end
$$;
\endif

do $$
declare
    rejected boolean;
begin
    rejected := false;
    begin
        execute $statement$update reported.reported_facts
            set raw_value = 'service mutated'$statement$;
    exception when insufficient_privilege then
        rejected := true;
    end;
    if not rejected then
        raise exception 'service_role updated a reported fact';
    end if;

    rejected := false;
    begin
        execute $statement$delete from reported.reported_facts$statement$;
    exception when insufficient_privilege then
        rejected := true;
    end;
    if not rejected then
        raise exception 'service_role deleted a reported fact';
    end if;
end
$$;

reset role;

select
    :'pr15_hash_lineage_valid'::boolean
    and :'pr15_service_select_passed'::boolean
    and :'pr15_service_insert_id'::bigint is not null
    and exists (
        select 1
        from reported.reported_facts
        where reported_fact_id = :'pr15_service_insert_id'::bigint
    ) as pr15_behavior_passed
\gset

\if :pr15_behavior_passed
\echo 'PR15 reported fact behavioral smoke passed.'
\else
\echo 'PR15 reported fact behavioral smoke failed.'
do $$
begin
    raise exception 'PR15 reported fact behavioral gate failed.';
end
$$;
\endif

insert into reported.reported_facts (
    regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
    reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
    source_definition_version, parser_implementation_key, parser_implementation_version,
    identity_definition_hash, period_kind, period_end, unit_code,
    raw_value, parsed_value, locator_kind, source_locator, first_observed_at
)
select
    '00000000-0000-4000-8000-000000000722',
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000751',
    '00000000-0000-4000-8000-000000000011',
    '00000000-0000-4000-8000-000000000761',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000801',
    1, 'test_parser', '1', repeat('a', 64),
    'instant', '2026-06-30', 'MXN',
    locator_row::text, locator_row, 'csv',
    jsonb_build_object('row', locator_row, 'column', 'C'),
    '2026-09-19T14:00:00Z'
from pg_catalog.generate_series(301, 314) as locator_row;

select
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 301, "column": "C"}'::jsonb
    ) as pr15a_fact_accept,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 302, "column": "C"}'::jsonb
    ) as pr15a_fact_reject,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 303, "column": "C"}'::jsonb
    ) as pr15a_fact_pending,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 304, "column": "C"}'::jsonb
    ) as pr15a_fact_accept_revoke,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 305, "column": "C"}'::jsonb
    ) as pr15a_fact_reject_revoke,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 306, "column": "C"}'::jsonb
    ) as pr15a_fact_accept_reject,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 307, "column": "C"}'::jsonb
    ) as pr15a_fact_timeline,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 308, "column": "C"}'::jsonb
    ) as pr15a_fact_tie,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 309, "column": "C"}'::jsonb
    ) as pr15a_fact_correction,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 310, "column": "C"}'::jsonb
    ) as pr15a_fact_cross,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 311, "column": "C"}'::jsonb
    ) as pr15a_fact_self,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 312, "column": "C"}'::jsonb
    ) as pr15a_fact_policy,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 313, "column": "C"}'::jsonb
    ) as pr15a_fact_reject_accept,
    (
        select reported_fact_id from reported.reported_facts
        where source_locator = '{"row": 314, "column": "C"}'::jsonb
    ) as pr15a_fact_service,
    (
        select reported_fact_id from reported.reported_facts
        where predecessor_reported_fact_id = :pr15_root_id
          and supersession_reason = 'SOURCE_REVISION'
          and source_artifact_id = '00000000-0000-4000-8000-000000000202'
    ) as pr15a_sibling_b,
    (
        select reported_fact_id from reported.reported_facts
        where predecessor_reported_fact_id = :pr15_root_id
          and supersession_reason = 'SOURCE_REVISION'
          and source_artifact_id = '00000000-0000-4000-8000-000000000203'
    ) as pr15a_sibling_c
\gset

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_accept, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
    'Synthetic first acceptance.'
)
returning review_decision_id as pr15a_accept_decision_id
\gset

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_reject, 'REJECT', '2026-07-01T01:00:00Z', 'HUMAN', 'lead_reviewer',
    'Synthetic first rejection without a prior acceptance.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_accept_revoke, 'ACCEPT', '2026-07-02T00:00:00Z', 'HUMAN',
    'lead_reviewer', 'Acceptance that is later revoked.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_accept_revoke, 'REVOKE', '2026-07-03T00:00:00Z', 'HUMAN',
    'lead_reviewer', 'Prospective withdrawal of the effective acceptance.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_reject_revoke, 'REJECT', '2026-07-02T00:00:00Z', 'HUMAN',
    'lead_reviewer', 'Rejection that must not be revocable.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_accept_reject, 'ACCEPT', '2026-07-02T00:00:00Z', 'HUMAN',
    'lead_reviewer', 'Acceptance later replaced by an explicit rejection.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_accept_reject, 'REJECT', '2026-07-04T00:00:00Z', 'HUMAN',
    'lead_reviewer', 'Explicit rejection after acceptance.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_timeline, 'ACCEPT', '2026-07-10T00:00:00Z', 'HUMAN',
    'lead_reviewer', 'Timeline counterexample acceptance.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_timeline, 'REVOKE', '2026-07-20T00:00:00Z', 'HUMAN',
    'lead_reviewer', 'Timeline counterexample revocation.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_tie, 'ACCEPT', '2026-07-05T12:00:00Z', 'HUMAN', 'lead_reviewer',
    'Equal-instant acceptance decided first.'
)
returning review_decision_id as pr15a_tie_first_id
\gset

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_tie, 'REJECT', '2026-07-05T12:00:00Z', 'HUMAN', 'lead_reviewer',
    'Equal-instant rejection decided second.'
)
returning review_decision_id as pr15a_tie_second_id
\gset

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_correction, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
    'Original acceptance that is later corrected twice.'
)
returning review_decision_id as pr15a_correction_root_id
\gset

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason,
    corrects_review_decision_id
)
values (
    :pr15a_fact_correction, 'REJECT', '2026-07-02T00:00:00Z', 'HUMAN', 'lead_reviewer',
    'First correction of the original acceptance.', :pr15a_correction_root_id
)
returning review_decision_id as pr15a_correction_first_id
\gset

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason,
    corrects_review_decision_id
)
values (
    :pr15a_fact_correction, 'ACCEPT', '2026-07-03T00:00:00Z', 'HUMAN', 'lead_reviewer',
    'Correction of the first correction.', :pr15a_correction_first_id
)
returning review_decision_id as pr15a_correction_second_id
\gset

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason,
    corrects_review_decision_id
)
values (
    :pr15a_fact_correction, 'REJECT', '2026-07-04T00:00:00Z', 'HUMAN', 'lead_reviewer',
    'Second later correction pointing at the same original event.',
    :pr15a_correction_root_id
)
returning review_decision_id as pr15a_correction_third_id
\gset

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_cross, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
    'Acceptance on an unrelated fact.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, policy_implementation_key,
    policy_implementation_version, policy_git_sha, reason
)
values (
    :pr15a_fact_policy, 'ACCEPT', '2026-07-01T00:00:00Z', 'SYSTEM_POLICY',
    'clean_fact_auto_accept', '3', repeat('d', 40),
    'Versioned system policy acceptance of an unambiguous fact.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_reject_accept, 'REJECT', '2026-07-01T00:00:00Z', 'HUMAN',
    'lead_reviewer', 'Initial rejection that is later superseded.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_reject_accept, 'ACCEPT', '2026-07-02T00:00:00Z', 'HUMAN',
    'lead_reviewer', 'Acceptance recorded after an earlier rejection.'
);

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values
    (
        :pr15a_sibling_b, 'ACCEPT', '2026-07-06T00:00:00Z', 'HUMAN', 'lead_reviewer',
        'Sibling successor B is accepted.'
    ),
    (
        :pr15a_sibling_c, 'ACCEPT', '2026-07-06T00:00:00Z', 'HUMAN', 'lead_reviewer',
        'Sibling successor C is also accepted; PR15a asserts no arbitration.'
    );

do $$
declare
    rejected boolean;
    fact_pending bigint;
    fact_reject_revoke bigint;
    fact_accept_revoke bigint;
    fact_accept_reject bigint;
    fact_timeline bigint;
    fact_correction bigint;
    fact_cross bigint;
    fact_self bigint;
    correction_root_id bigint;
begin
    select reported_fact_id into strict fact_pending
    from reported.reported_facts
    where source_locator = '{"row": 303, "column": "C"}'::jsonb;

    select reported_fact_id into strict fact_reject_revoke
    from reported.reported_facts
    where source_locator = '{"row": 305, "column": "C"}'::jsonb;

    select reported_fact_id into strict fact_accept_revoke
    from reported.reported_facts
    where source_locator = '{"row": 304, "column": "C"}'::jsonb;

    select reported_fact_id into strict fact_accept_reject
    from reported.reported_facts
    where source_locator = '{"row": 306, "column": "C"}'::jsonb;

    select reported_fact_id into strict fact_timeline
    from reported.reported_facts
    where source_locator = '{"row": 307, "column": "C"}'::jsonb;

    select reported_fact_id into strict fact_correction
    from reported.reported_facts
    where source_locator = '{"row": 309, "column": "C"}'::jsonb;

    select reported_fact_id into strict fact_cross
    from reported.reported_facts
    where source_locator = '{"row": 310, "column": "C"}'::jsonb;

    select reported_fact_id into strict fact_self
    from reported.reported_facts
    where source_locator = '{"row": 311, "column": "C"}'::jsonb;

    select review_decision_id into strict correction_root_id
    from audit.review_decisions
    where reported_fact_id = fact_correction
      and decided_at = '2026-07-01T00:00:00Z';

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_pending, 'APPROVE', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
            'Unapproved decision vocabulary.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'unapproved review decision vocabulary was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_pending, 'REVOKE', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
            'First event may not be a revocation.'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'first-event REVOKE was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_pending, 'ACCEPT', pg_catalog.clock_timestamp() + interval '1 hour',
            'HUMAN', 'lead_reviewer', 'Future decision time must be rejected.'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'future decided_at was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_reject_revoke, 'REVOKE', '2026-07-03T00:00:00Z', 'HUMAN',
            'lead_reviewer', 'REVOKE after REJECT must be rejected.'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'REVOKE after REJECT was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_accept_revoke, 'REVOKE', '2026-07-04T00:00:00Z', 'HUMAN',
            'lead_reviewer', 'REVOKE after REVOKE must be rejected.'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'REVOKE after REVOKE was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_accept_reject, 'REVOKE', '2026-07-05T00:00:00Z', 'HUMAN',
            'lead_reviewer', 'REVOKE after ACCEPT then REJECT must be rejected.'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'REVOKE after ACCEPT then REJECT was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_timeline, 'REJECT', '2026-07-15T00:00:00Z', 'HUMAN', 'lead_reviewer',
            'Backdated event behind the current head must be rejected.'
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'decision behind the current head was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason,
            corrects_review_decision_id
        ) values (
            fact_correction, 'ACCEPT', '2026-07-02T12:00:00Z', 'HUMAN', 'lead_reviewer',
            'Backdated correction must be rejected by the monotonic guard.',
            correction_root_id
        );
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'backdated correction behind the current head was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason,
            corrects_review_decision_id
        ) values (
            fact_cross, 'REJECT', '2026-07-05T00:00:00Z', 'HUMAN', 'lead_reviewer',
            'A correction may not reference another fact timeline.',
            correction_root_id
        );
    exception when foreign_key_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'cross-fact correction was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            review_decision_id, reported_fact_id, decision, decided_at, actor_kind,
            human_actor_key, reason, corrects_review_decision_id
        ) overriding system value values (
            987654321, fact_self, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN',
            'lead_reviewer', 'A decision may not correct itself.', 987654321
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'self-correction was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN',
            'HUMAN actor requires an actor key.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'HUMAN decision without an actor key was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key,
            policy_implementation_key, policy_implementation_version, policy_git_sha,
            reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
            'clean_fact_auto_accept', '3', repeat('d', 40),
            'HUMAN actor must not carry policy provenance.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'HUMAN decision with policy provenance was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind,
            policy_implementation_version, policy_git_sha, reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'SYSTEM_POLICY',
            '3', repeat('d', 40),
            'SYSTEM_POLICY requires an implementation key.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'SYSTEM_POLICY decision without an implementation key was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind,
            policy_implementation_key, policy_git_sha, reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'SYSTEM_POLICY',
            'clean_fact_auto_accept', repeat('d', 40),
            'SYSTEM_POLICY requires an implementation version.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'SYSTEM_POLICY decision without a version was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind,
            policy_implementation_key, policy_implementation_version, reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'SYSTEM_POLICY',
            'clean_fact_auto_accept', '3',
            'SYSTEM_POLICY requires a Git SHA.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'SYSTEM_POLICY decision without a Git SHA was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key,
            policy_implementation_key, policy_implementation_version, policy_git_sha,
            reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'SYSTEM_POLICY',
            'lead_reviewer', 'clean_fact_auto_accept', '3', repeat('d', 40),
            'SYSTEM_POLICY must not carry a human actor key.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'SYSTEM_POLICY decision with a human actor key was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind,
            policy_implementation_key, policy_implementation_version, policy_git_sha,
            reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'SYSTEM_POLICY',
            'clean_fact_auto_accept', '3', 'not-a-sha',
            'A malformed policy Git SHA must be rejected.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'malformed policy Git SHA was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'Lead Reviewer',
            'A malformed human actor key must be rejected.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'malformed human actor key was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
            null
        );
    exception when not_null_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'null review reason was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
            '   '
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'blank review reason was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
            'Reason with a control' || chr(10) || 'character.'
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'review reason with a control character was accepted';
    end if;

    rejected := false;
    begin
        insert into audit.review_decisions (
            reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
        ) values (
            fact_pending, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'lead_reviewer',
            repeat('r', 513)
        );
    exception when check_violation then
        rejected := true;
    end;
    if not rejected then
        raise exception 'oversized review reason was accepted';
    end if;

    rejected := false;
    begin
        execute $statement$update audit.review_decisions
            set reason = 'owner mutated'$statement$;
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'table-owner UPDATE of a review decision was accepted';
    end if;

    rejected := false;
    begin
        execute $statement$delete from audit.review_decisions$statement$;
    exception when raise_exception then
        rejected := true;
    end;
    if not rejected then
        raise exception 'table-owner DELETE of a review decision was accepted';
    end if;
end
$$;

set local role service_role;

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_service, 'ACCEPT', '2026-07-01T00:00:00Z', 'HUMAN', 'service_reviewer',
    'Runtime service_role acceptance.'
)
returning review_decision_id as pr15a_service_decision_id
\gset

insert into audit.review_decisions (
    reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
)
values (
    :pr15a_fact_service, 'REVOKE', '2026-07-02T00:00:00Z', 'HUMAN', 'service_reviewer',
    'Runtime service_role revocation that requires head visibility.'
);

select count(*) >= 1 as pr15a_service_select_passed
from audit.review_decisions
\gset

select count(*) >= 1 as pr15a_service_view_select_passed
from audit.effective_review_decisions
\gset

do $$
declare
    rejected boolean;
begin
    rejected := false;
    begin
        execute $statement$update audit.review_decisions
            set reason = 'service mutated'$statement$;
    exception when insufficient_privilege then
        rejected := true;
    end;
    if not rejected then
        raise exception 'service_role updated a review decision';
    end if;

    rejected := false;
    begin
        execute $statement$delete from audit.review_decisions$statement$;
    exception when insufficient_privilege then
        rejected := true;
    end;
    if not rejected then
        raise exception 'service_role deleted a review decision';
    end if;
end
$$;

reset role;

select
    (
        select count(*) = 1
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_accept
          and decision = 'ACCEPT'
          and review_decision_id = :pr15a_accept_decision_id
    )
    and (
        select decision = 'REJECT'
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_reject
    )
    and not exists (
        select 1
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_pending
    )
    and not exists (
        select 1
        from audit.effective_review_decisions_as_of(pg_catalog.clock_timestamp())
        where reported_fact_id = :pr15a_fact_pending
    )
    and (
        select decision = 'REVOKE'
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_accept_revoke
    )
    and (
        select decision = 'REJECT'
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_accept_reject
    )
    and (
        select decision = 'ACCEPT'
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_reject_accept
    )
    and (
        select decision = 'ACCEPT'
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_policy
    )
    and (
        select decision = 'REVOKE'
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_service
    )
    and (
        select
            decision = 'REJECT'
            and review_decision_id = :pr15a_tie_second_id
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_tie
    )
    and :pr15a_tie_second_id > :pr15a_tie_first_id
    and (
        select bool_and(decision = 'ACCEPT')
        from audit.effective_review_decisions
        where reported_fact_id in (:pr15a_sibling_b, :pr15a_sibling_c)
    )
    and (
        select count(*) = 2
        from audit.effective_review_decisions
        where reported_fact_id in (:pr15a_sibling_b, :pr15a_sibling_c)
    )
    and (
        select decision = 'ACCEPT'
        from audit.effective_review_decisions_as_of('2026-07-15T00:00:00Z')
        where reported_fact_id = :pr15a_fact_timeline
    )
    and (
        select decision = 'REVOKE'
        from audit.effective_review_decisions_as_of('2026-07-25T00:00:00Z')
        where reported_fact_id = :pr15a_fact_timeline
    )
    and not exists (
        select 1
        from audit.effective_review_decisions_as_of('2026-07-05T00:00:00Z')
        where reported_fact_id = :pr15a_fact_timeline
    )
    and (
        select
            review_decision_id = :pr15a_correction_root_id
            and decision = 'ACCEPT'
        from audit.effective_review_decisions_as_of('2026-07-01T12:00:00Z')
        where reported_fact_id = :pr15a_fact_correction
    )
    and (
        select
            review_decision_id = :pr15a_correction_first_id
            and decision = 'REJECT'
        from audit.effective_review_decisions_as_of('2026-07-02T12:00:00Z')
        where reported_fact_id = :pr15a_fact_correction
    )
    and (
        select
            review_decision_id = :pr15a_correction_third_id
            and decision = 'REJECT'
        from audit.effective_review_decisions
        where reported_fact_id = :pr15a_fact_correction
    )
    and (
        select count(*) = 2
        from audit.review_decisions
        where corrects_review_decision_id = :pr15a_correction_root_id
    )
    and (
        select count(*) = 1
        from audit.review_decisions
        where corrects_review_decision_id = :pr15a_correction_first_id
          and review_decision_id = :pr15a_correction_second_id
    )
    and (
        select
            decision = 'ACCEPT'
            and decided_at = '2026-07-01T00:00:00Z'::timestamptz
            and reason = 'Original acceptance that is later corrected twice.'
            and corrects_review_decision_id is null
        from audit.review_decisions
        where review_decision_id = :pr15a_correction_root_id
    )
    and (
        select count(*) = 4
        from audit.review_decisions
        where reported_fact_id = :pr15a_fact_correction
    )
    and (
        select count(*) = 1
        from audit.review_decisions
        where reported_fact_id = :pr15a_fact_reject_revoke
    )
    and (
        select count(*) = 1
        from audit.review_decisions
        where reported_fact_id = :pr15a_fact_cross
    )
    and not exists (
        select 1
        from audit.review_decisions
        where reported_fact_id = :pr15a_fact_self
    )
    and not exists (
        select 1
        from audit.review_decisions
        where reported_fact_id = :pr15a_fact_pending
    )
    and (
        select count(*) = 2
        from audit.review_decisions
        where reported_fact_id = :pr15a_fact_service
    )
    and :'pr15a_service_decision_id'::bigint is not null
    and :'pr15a_service_select_passed'::boolean
    and :'pr15a_service_view_select_passed'::boolean
    and not exists (
        select
            current_view.reported_fact_id,
            current_view.review_decision_id,
            current_view.decision,
            current_view.decided_at
        from audit.effective_review_decisions as current_view
        except
        select
            cutoff_view.reported_fact_id,
            cutoff_view.review_decision_id,
            cutoff_view.decision,
            cutoff_view.decided_at
        from audit.effective_review_decisions_as_of(
            pg_catalog.clock_timestamp()
        ) as cutoff_view
    )
    and not exists (
        select
            cutoff_view.reported_fact_id,
            cutoff_view.review_decision_id,
            cutoff_view.decision,
            cutoff_view.decided_at
        from audit.effective_review_decisions_as_of(
            pg_catalog.clock_timestamp()
        ) as cutoff_view
        except
        select
            current_view.reported_fact_id,
            current_view.review_decision_id,
            current_view.decision,
            current_view.decided_at
        from audit.effective_review_decisions as current_view
    ) as pr15a_behavior_passed
\gset

\if :pr15a_behavior_passed
\echo 'PR15a review decision behavioral smoke passed.'
\else
\echo 'PR15a review decision behavioral smoke failed.'
do $$
begin
    raise exception 'PR15a review decision behavioral gate failed.';
end
$$;
\endif

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

with pr16_relation_gate as (
    select
        count(*) = 3
        and bool_and(relation.relkind = 'v')
        and bool_and(relation.relname in (
            'reported_fact_revision_ancestry',
            'current_observed_facts',
            'current_publishable_facts'
        ))
        and not exists (
            select 1
            from pg_catalog.pg_class extra_relation
            join pg_catalog.pg_namespace extra_namespace
              on extra_namespace.oid = extra_relation.relnamespace
            where extra_namespace.nspname = 'serving'
              and extra_relation.relkind in ('r', 'p', 'm', 'S', 'f', 'i')
        )
        and pg_catalog.to_regclass('serving.current') is null
        and not exists (
            select 1
            from pg_catalog.pg_class named_current
            join pg_catalog.pg_namespace current_namespace
              on current_namespace.oid = named_current.relnamespace
            where current_namespace.nspname = 'serving'
              and named_current.relname = 'current'
        ) as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'serving'
      and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
), pr16_function_gate as (
    select
        count(*) = 2
        and bool_and(function.proname in (
            'observed_facts_as_of',
            'publishable_facts_as_of'
        ))
        and bool_and(not function.prosecdef)
        and bool_and(not function.proisstrict)
        and bool_and(function.provolatile = 's')
        and bool_and(function.pronargs = 1)
        and bool_and(function.proargtypes[0] = 'timestamptz'::regtype)
        and bool_and(function.prolang = (
            select language.oid
            from pg_catalog.pg_language language
            where language.lanname = 'sql'
        )) as valid
    from pg_catalog.pg_proc function
    join pg_catalog.pg_namespace namespace
      on namespace.oid = function.pronamespace
    where namespace.nspname = 'serving'
), pr16_security_invoker_gate as (
    select
        count(*) = 3
        and bool_and(exists (
            select 1
            from unnest(coalesce(relation.reloptions, array[]::text[])) as view_option
            where lower(view_option) in (
                'security_invoker=true',
                'security_invoker=on',
                'security_invoker=1'
            )
        )) as valid
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'serving'
      and relation.relkind = 'v'
      and relation.relname in (
          'reported_fact_revision_ancestry',
          'current_observed_facts',
          'current_publishable_facts'
      )
), pr16_helper_column_gate as (
    select not exists (
        select expected.ordinal, expected.column_name, expected.type_name
        from (
            values
                (1, 'reported_fact_id', 'bigint'),
                (2, 'ancestor_reported_fact_id', 'bigint'),
                (3, 'generations', 'integer')
        ) as expected(ordinal, column_name, type_name)
        except
        select
            attribute.attnum::integer,
            attribute.attname::text,
            pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.reported_fact_revision_ancestry'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
    )
    and not exists (
        select
            attribute.attnum::integer,
            attribute.attname::text,
            pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.reported_fact_revision_ancestry'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
        except
        select expected.ordinal, expected.column_name, expected.type_name
        from (
            values
                (1, 'reported_fact_id', 'bigint'),
                (2, 'ancestor_reported_fact_id', 'bigint'),
                (3, 'generations', 'integer')
        ) as expected(ordinal, column_name, type_name)
    ) as valid
), pr16_observed_column_gate as (
    select not exists (
        select expected.ordinal, expected.column_name, expected.type_name
        from (
            values
                (1, 'lineage_root_reported_fact_id', 'bigint'),
                (2, 'reported_fact_id', 'bigint'),
                (3, 'regulatory_registration_id', 'uuid'),
                (4, 'regulator_id', 'uuid'),
                (5, 'regulatory_concept_id', 'uuid'),
                (6, 'source_id', 'uuid'),
                (7, 'reporting_scope_id', 'uuid'),
                (8, 'source_artifact_id', 'uuid'),
                (9, 'source_release_id', 'uuid'),
                (10, 'ingestion_run_id', 'uuid'),
                (11, 'source_definition_version', 'integer'),
                (12, 'parser_implementation_key', 'text'),
                (13, 'parser_implementation_version', 'text'),
                (14, 'identity_definition_hash', 'text'),
                (15, 'period_kind', 'text'),
                (16, 'period_start', 'date'),
                (17, 'period_end', 'date'),
                (18, 'unit_code', 'text'),
                (19, 'dimensions', 'jsonb'),
                (20, 'raw_value', 'text'),
                (21, 'parsed_value', 'numeric'),
                (22, 'raw_label', 'text'),
                (23, 'locator_kind', 'text'),
                (24, 'source_locator', 'jsonb'),
                (25, 'locator_hash', 'text'),
                (26, 'fact_key_hash', 'text'),
                (27, 'first_observed_at', 'timestamp with time zone'),
                (28, 'predecessor_reported_fact_id', 'bigint'),
                (29, 'supersession_reason', 'text')
        ) as expected(ordinal, column_name, type_name)
        except
        select
            attribute.attnum::integer,
            attribute.attname::text,
            pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.current_observed_facts'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
    )
    and not exists (
        select
            attribute.attnum::integer,
            attribute.attname::text,
            pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.current_observed_facts'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
        except
        select expected.ordinal, expected.column_name, expected.type_name
        from (
            values
                (1, 'lineage_root_reported_fact_id', 'bigint'),
                (2, 'reported_fact_id', 'bigint'),
                (3, 'regulatory_registration_id', 'uuid'),
                (4, 'regulator_id', 'uuid'),
                (5, 'regulatory_concept_id', 'uuid'),
                (6, 'source_id', 'uuid'),
                (7, 'reporting_scope_id', 'uuid'),
                (8, 'source_artifact_id', 'uuid'),
                (9, 'source_release_id', 'uuid'),
                (10, 'ingestion_run_id', 'uuid'),
                (11, 'source_definition_version', 'integer'),
                (12, 'parser_implementation_key', 'text'),
                (13, 'parser_implementation_version', 'text'),
                (14, 'identity_definition_hash', 'text'),
                (15, 'period_kind', 'text'),
                (16, 'period_start', 'date'),
                (17, 'period_end', 'date'),
                (18, 'unit_code', 'text'),
                (19, 'dimensions', 'jsonb'),
                (20, 'raw_value', 'text'),
                (21, 'parsed_value', 'numeric'),
                (22, 'raw_label', 'text'),
                (23, 'locator_kind', 'text'),
                (24, 'source_locator', 'jsonb'),
                (25, 'locator_hash', 'text'),
                (26, 'fact_key_hash', 'text'),
                (27, 'first_observed_at', 'timestamp with time zone'),
                (28, 'predecessor_reported_fact_id', 'bigint'),
                (29, 'supersession_reason', 'text')
        ) as expected(ordinal, column_name, type_name)
    )
    and not exists (
        select
            attribute.attnum,
            attribute.attname,
            attribute.atttypid
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.current_observed_facts'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
        except
        select
            function_attribute.attnum,
            function_attribute.attname,
            function_attribute.atttypid
        from pg_catalog.pg_proc function
        join pg_catalog.pg_namespace namespace
          on namespace.oid = function.pronamespace
        join pg_catalog.pg_type return_type
          on return_type.oid = function.prorettype
        join pg_catalog.pg_attribute function_attribute
          on function_attribute.attrelid = return_type.typrelid
        where namespace.nspname = 'serving'
          and function.proname = 'observed_facts_as_of'
          and function_attribute.attnum > 0
          and not function_attribute.attisdropped
    )
    and not exists (
        select
            function_attribute.attnum,
            function_attribute.attname,
            function_attribute.atttypid
        from pg_catalog.pg_proc function
        join pg_catalog.pg_namespace namespace
          on namespace.oid = function.pronamespace
        join pg_catalog.pg_type return_type
          on return_type.oid = function.prorettype
        join pg_catalog.pg_attribute function_attribute
          on function_attribute.attrelid = return_type.typrelid
        where namespace.nspname = 'serving'
          and function.proname = 'observed_facts_as_of'
          and function_attribute.attnum > 0
          and not function_attribute.attisdropped
        except
        select
            attribute.attnum,
            attribute.attname,
            attribute.atttypid
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.current_observed_facts'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
    ) as valid
), pr16_publishable_column_gate as (
    select not exists (
        select expected.ordinal, expected.column_name, expected.type_name
        from (
            values
                (1, 'lineage_root_reported_fact_id', 'bigint'),
                (2, 'reported_fact_id', 'bigint'),
                (3, 'regulatory_registration_id', 'uuid'),
                (4, 'regulator_id', 'uuid'),
                (5, 'regulatory_concept_id', 'uuid'),
                (6, 'source_id', 'uuid'),
                (7, 'reporting_scope_id', 'uuid'),
                (8, 'source_artifact_id', 'uuid'),
                (9, 'source_release_id', 'uuid'),
                (10, 'ingestion_run_id', 'uuid'),
                (11, 'source_definition_version', 'integer'),
                (12, 'parser_implementation_key', 'text'),
                (13, 'parser_implementation_version', 'text'),
                (14, 'identity_definition_hash', 'text'),
                (15, 'period_kind', 'text'),
                (16, 'period_start', 'date'),
                (17, 'period_end', 'date'),
                (18, 'unit_code', 'text'),
                (19, 'dimensions', 'jsonb'),
                (20, 'raw_value', 'text'),
                (21, 'parsed_value', 'numeric'),
                (22, 'raw_label', 'text'),
                (23, 'locator_kind', 'text'),
                (24, 'source_locator', 'jsonb'),
                (25, 'locator_hash', 'text'),
                (26, 'fact_key_hash', 'text'),
                (27, 'first_observed_at', 'timestamp with time zone'),
                (28, 'predecessor_reported_fact_id', 'bigint'),
                (29, 'supersession_reason', 'text'),
                (30, 'effective_review_decision_id', 'bigint'),
                (31, 'effective_decision', 'text'),
                (32, 'effective_decided_at', 'timestamp with time zone')
        ) as expected(ordinal, column_name, type_name)
        except
        select
            attribute.attnum::integer,
            attribute.attname::text,
            pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.current_publishable_facts'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
    )
    and not exists (
        select
            attribute.attnum::integer,
            attribute.attname::text,
            pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.current_publishable_facts'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
        except
        select expected.ordinal, expected.column_name, expected.type_name
        from (
            values
                (1, 'lineage_root_reported_fact_id', 'bigint'),
                (2, 'reported_fact_id', 'bigint'),
                (3, 'regulatory_registration_id', 'uuid'),
                (4, 'regulator_id', 'uuid'),
                (5, 'regulatory_concept_id', 'uuid'),
                (6, 'source_id', 'uuid'),
                (7, 'reporting_scope_id', 'uuid'),
                (8, 'source_artifact_id', 'uuid'),
                (9, 'source_release_id', 'uuid'),
                (10, 'ingestion_run_id', 'uuid'),
                (11, 'source_definition_version', 'integer'),
                (12, 'parser_implementation_key', 'text'),
                (13, 'parser_implementation_version', 'text'),
                (14, 'identity_definition_hash', 'text'),
                (15, 'period_kind', 'text'),
                (16, 'period_start', 'date'),
                (17, 'period_end', 'date'),
                (18, 'unit_code', 'text'),
                (19, 'dimensions', 'jsonb'),
                (20, 'raw_value', 'text'),
                (21, 'parsed_value', 'numeric'),
                (22, 'raw_label', 'text'),
                (23, 'locator_kind', 'text'),
                (24, 'source_locator', 'jsonb'),
                (25, 'locator_hash', 'text'),
                (26, 'fact_key_hash', 'text'),
                (27, 'first_observed_at', 'timestamp with time zone'),
                (28, 'predecessor_reported_fact_id', 'bigint'),
                (29, 'supersession_reason', 'text'),
                (30, 'effective_review_decision_id', 'bigint'),
                (31, 'effective_decision', 'text'),
                (32, 'effective_decided_at', 'timestamp with time zone')
        ) as expected(ordinal, column_name, type_name)
    )
    and not exists (
        select
            attribute.attnum,
            attribute.attname,
            attribute.atttypid
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.current_publishable_facts'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
        except
        select
            function_attribute.attnum,
            function_attribute.attname,
            function_attribute.atttypid
        from pg_catalog.pg_proc function
        join pg_catalog.pg_namespace namespace
          on namespace.oid = function.pronamespace
        join pg_catalog.pg_type return_type
          on return_type.oid = function.prorettype
        join pg_catalog.pg_attribute function_attribute
          on function_attribute.attrelid = return_type.typrelid
        where namespace.nspname = 'serving'
          and function.proname = 'publishable_facts_as_of'
          and function_attribute.attnum > 0
          and not function_attribute.attisdropped
    )
    and not exists (
        select
            function_attribute.attnum,
            function_attribute.attname,
            function_attribute.atttypid
        from pg_catalog.pg_proc function
        join pg_catalog.pg_namespace namespace
          on namespace.oid = function.pronamespace
        join pg_catalog.pg_type return_type
          on return_type.oid = function.prorettype
        join pg_catalog.pg_attribute function_attribute
          on function_attribute.attrelid = return_type.typrelid
        where namespace.nspname = 'serving'
          and function.proname = 'publishable_facts_as_of'
          and function_attribute.attnum > 0
          and not function_attribute.attisdropped
        except
        select
            attribute.attnum,
            attribute.attname,
            attribute.atttypid
        from pg_catalog.pg_attribute attribute
        where attribute.attrelid = 'serving.current_publishable_facts'::regclass
          and attribute.attnum > 0
          and not attribute.attisdropped
    ) as valid
), pr16_definition_gate as (
    select
        position('recursive' in lower(helper_definition.definition)) > 0
        and position('union all' in lower(helper_definition.definition)) > 0
        and position('predecessor_reported_fact_id' in lower(helper_definition.definition)) > 0
        and position('fact_key_hash' in lower(helper_definition.definition)) = 0
        and position('generations <' in lower(helper_definition.definition)) = 0
        and position('< 32' in lower(helper_definition.definition)) = 0
        and position('< 64' in lower(helper_definition.definition)) = 0
        and position('< 128' in lower(helper_definition.definition)) = 0
        and position('< 256' in lower(helper_definition.definition)) = 0
        and position('review_decision' in lower(observed_definition.definition)) = 0
        and position('now()' in lower(observed_definition.definition)) = 0
        and position('clock_timestamp()' in lower(observed_definition.definition)) = 0
        and lower(observed_definition.definition) !~ 'select[[:space:]]+\*'
        and lower(observed_function.definition) ~ 'cutoff_eligible_facts'
        and lower(observed_function.definition)
            ~ 'ancestor\.first_observed_at[[:space:]]*>[[:space:]]*cutoff'
        and lower(observed_function.definition)
            ~ 'first_observed_at[[:space:]]*<=[[:space:]]*cutoff'
        and lower(observed_function.definition) ~ 'eligible_child'
        and lower(observed_function.definition) ~ 'cutoff is not null'
        and position('now()' in lower(observed_function.definition)) = 0
        and position('clock_timestamp()' in lower(observed_function.definition)) = 0
        and lower(observed_function.definition) !~ 'select[[:space:]]+\*'
        and lower(publishable_definition.definition) ~ 'audit\.effective_review_decisions'
        and position(
            'effective_review_decisions_as_of' in lower(publishable_definition.definition)
        ) = 0
        and lower(publishable_definition.definition)
            ~ 'decision[[:space:]]*=[[:space:]]*''accept'''
        and lower(publishable_definition.definition)
            ~ 'having[[:space:]]+\(?[[:space:]]*count\(\*\)[[:space:]]*=[[:space:]]*1'
        and lower(publishable_definition.definition)
            ~ 'group[[:space:]]+by[[:space:]]+frontier\.lineage_root_reported_fact_id'
        and lower(publishable_definition.definition) !~ 'group[[:space:]]+by[[:space:]]+fact_key_hash'
        and lower(publishable_definition.definition)
            !~ 'group[[:space:]]+by[[:space:]]+fact\.fact_key_hash'
        and position('order by' in lower(publishable_definition.definition)) = 0
        and position(
            'corrects_review_decision_id' in lower(publishable_definition.definition)
        ) = 0
        and position('now()' in lower(publishable_definition.definition)) = 0
        and position('clock_timestamp()' in lower(publishable_definition.definition)) = 0
        and lower(publishable_definition.definition) !~ 'select[[:space:]]+\*'
        and lower(publishable_function.definition) ~ 'cutoff_eligible_facts'
        and lower(publishable_function.definition) ~ 'eligible_descendant'
        and lower(publishable_function.definition) ~ 'effective_review_decisions_as_of'
        and lower(publishable_function.definition)
            ~ 'ancestor\.first_observed_at[[:space:]]*>[[:space:]]*cutoff'
        and lower(publishable_function.definition)
            ~ 'decision[[:space:]]*=[[:space:]]*''accept'''
        and lower(publishable_function.definition)
            ~ 'having[[:space:]]+\(?[[:space:]]*count\(\*\)[[:space:]]*=[[:space:]]*1'
        and lower(publishable_function.definition) !~ 'group[[:space:]]+by[[:space:]]+fact_key_hash'
        and position('order by' in lower(publishable_function.definition)) = 0
        and position(
            'corrects_review_decision_id' in lower(publishable_function.definition)
        ) = 0
        and position('now()' in lower(publishable_function.definition)) = 0
        and position('clock_timestamp()' in lower(publishable_function.definition)) = 0
        and lower(publishable_function.definition) !~ 'select[[:space:]]+\*'
        as valid
    from (
        select pg_catalog.pg_get_viewdef(
            'serving.reported_fact_revision_ancestry'::regclass
        ) as definition
    ) as helper_definition
    cross join (
        select pg_catalog.pg_get_viewdef(
            'serving.current_observed_facts'::regclass
        ) as definition
    ) as observed_definition
    cross join (
        select pg_catalog.pg_get_viewdef(
            'serving.current_publishable_facts'::regclass
        ) as definition
    ) as publishable_definition
    cross join (
        select pg_catalog.pg_get_functiondef(
            'serving.observed_facts_as_of(timestamptz)'::regprocedure
        ) as definition
    ) as observed_function
    cross join (
        select pg_catalog.pg_get_functiondef(
            'serving.publishable_facts_as_of(timestamptz)'::regprocedure
        ) as definition
    ) as publishable_function
), pr16_access_gate as (
    select
        pg_catalog.has_table_privilege(
            'service_role', 'serving.reported_fact_revision_ancestry', 'SELECT'
        )
        and pg_catalog.has_table_privilege(
            'service_role', 'serving.current_observed_facts', 'SELECT'
        )
        and pg_catalog.has_table_privilege(
            'service_role', 'serving.current_publishable_facts', 'SELECT'
        )
        and not pg_catalog.has_table_privilege(
            'service_role',
            'serving.reported_fact_revision_ancestry',
            'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
        )
        and not pg_catalog.has_table_privilege(
            'service_role',
            'serving.current_observed_facts',
            'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
        )
        and not pg_catalog.has_table_privilege(
            'service_role',
            'serving.current_publishable_facts',
            'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
        )
        and pg_catalog.has_function_privilege(
            'service_role',
            'serving.observed_facts_as_of(timestamptz)',
            'EXECUTE'
        )
        and pg_catalog.has_function_privilege(
            'service_role',
            'serving.publishable_facts_as_of(timestamptz)',
            'EXECUTE'
        )
        and (
            select bool_and(not pg_catalog.has_table_privilege(
                role_name,
                view_name,
                'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
            ))
            from unnest(array['anon', 'authenticated']) as role_name
            cross join unnest(array[
                'serving.reported_fact_revision_ancestry',
                'serving.current_observed_facts',
                'serving.current_publishable_facts'
            ]) as view_name
        )
        and (
            select bool_and(not pg_catalog.has_function_privilege(
                role_name,
                function_name,
                'EXECUTE'
            ))
            from unnest(array['anon', 'authenticated']) as role_name
            cross join unnest(array[
                'serving.observed_facts_as_of(timestamptz)',
                'serving.publishable_facts_as_of(timestamptz)'
            ]) as function_name
        )
        and not exists (
            select 1
            from pg_catalog.pg_class relation
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            cross join lateral pg_catalog.aclexplode(
                coalesce(relation.relacl, acldefault('r', relation.relowner))
            ) as relation_acl
            where namespace.nspname = 'serving'
              and relation.relname in (
                  'reported_fact_revision_ancestry',
                  'current_observed_facts',
                  'current_publishable_facts'
              )
              and relation_acl.grantee = 0
        )
        and not exists (
            select 1
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            cross join lateral pg_catalog.aclexplode(
                coalesce(function.proacl, acldefault('f', function.proowner))
            ) as function_acl
            where namespace.nspname = 'serving'
              and function.proname in (
                  'observed_facts_as_of',
                  'publishable_facts_as_of'
              )
              and function_acl.grantee = 0
        ) as valid
), pr16_boundary_gate as (
    select
        not exists (
            select 1
            from pg_catalog.pg_class relation
            join pg_catalog.pg_namespace namespace
              on namespace.oid = relation.relnamespace
            where namespace.nspname in ('semantic', 'metrics')
              and relation.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
        )
        and not exists (
            select 1
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname in ('semantic', 'metrics')
        )
        and pg_catalog.to_regclass('audit.quality_issues') is null
        and pg_catalog.to_regclass('semantic.canonical_concepts') is null
        and pg_catalog.to_regclass('semantic.concept_mappings') is null
        and pg_catalog.to_regclass('semantic.canonical_observations_v1') is null
        and pg_catalog.to_regclass('metrics.metric_definitions') is null
        and pg_catalog.to_regclass('metrics.metric_observations') is null
        and pg_catalog.to_regclass('public.regulatory_bank_metrics_v1') is null
        and not exists (
            select 1
            from pg_catalog.pg_policies
            where schemaname = 'serving'
        )
        and not exists (
            select 1
            from pg_catalog.pg_proc function
            join pg_catalog.pg_namespace namespace
              on namespace.oid = function.pronamespace
            where namespace.nspname = 'serving'
              and function.prosecdef
        )
        and not exists (
            select 1
            from pg_catalog.pg_index index_definition
            join pg_catalog.pg_class table_relation
              on table_relation.oid = index_definition.indrelid
            join pg_catalog.pg_namespace namespace
              on namespace.oid = table_relation.relnamespace
            where namespace.nspname = 'serving'
        )
        and (
            select count(*) = 3
            from pg_catalog.pg_index index_definition
            join pg_catalog.pg_class table_relation
              on table_relation.oid = index_definition.indrelid
            join pg_catalog.pg_namespace namespace
              on namespace.oid = table_relation.relnamespace
            where namespace.nspname = 'reported'
              and table_relation.relname = 'reported_facts'
              and not exists (
                  select 1
                  from pg_catalog.pg_constraint backing_constraint
                  where backing_constraint.conindid = index_definition.indexrelid
              )
        )
        and (
            select count(*) = 2
            from pg_catalog.pg_index index_definition
            join pg_catalog.pg_class table_relation
              on table_relation.oid = index_definition.indrelid
            join pg_catalog.pg_namespace namespace
              on namespace.oid = table_relation.relnamespace
            where namespace.nspname = 'audit'
              and table_relation.relname = 'review_decisions'
              and not exists (
                  select 1
                  from pg_catalog.pg_constraint backing_constraint
                  where backing_constraint.conindid = index_definition.indexrelid
              )
        ) as valid
)
select
    pr16_relation_gate.valid as pr16_relation_gate,
    pr16_function_gate.valid as pr16_function_gate,
    pr16_security_invoker_gate.valid as pr16_security_invoker_gate,
    pr16_helper_column_gate.valid as pr16_helper_column_gate,
    pr16_observed_column_gate.valid as pr16_observed_column_gate,
    pr16_publishable_column_gate.valid as pr16_publishable_column_gate,
    pr16_definition_gate.valid as pr16_definition_gate,
    pr16_access_gate.valid as pr16_access_gate,
    pr16_boundary_gate.valid as pr16_boundary_gate,
    (
        pr16_relation_gate.valid
        and pr16_function_gate.valid
        and pr16_security_invoker_gate.valid
        and pr16_helper_column_gate.valid
        and pr16_observed_column_gate.valid
        and pr16_publishable_column_gate.valid
        and pr16_definition_gate.valid
        and pr16_access_gate.valid
        and pr16_boundary_gate.valid
    ) as pr16_catalog_passed
from pr16_relation_gate
cross join pr16_function_gate
cross join pr16_security_invoker_gate
cross join pr16_helper_column_gate
cross join pr16_observed_column_gate
cross join pr16_publishable_column_gate
cross join pr16_definition_gate
cross join pr16_access_gate
cross join pr16_boundary_gate
\gset

\echo PR16 gate relations: :pr16_relation_gate
\echo PR16 gate functions: :pr16_function_gate
\echo PR16 gate security_invoker: :pr16_security_invoker_gate
\echo PR16 gate helper_columns: :pr16_helper_column_gate
\echo PR16 gate observed_columns: :pr16_observed_column_gate
\echo PR16 gate publishable_columns: :pr16_publishable_column_gate
\echo PR16 gate definitions: :pr16_definition_gate
\echo PR16 gate access: :pr16_access_gate
\echo PR16 gate boundary: :pr16_boundary_gate
\echo PR16 aggregate catalog: :pr16_catalog_passed

\if :pr16_catalog_passed
\echo 'PR16 fact query catalog contract passed.'
\else
\echo 'PR16 fact query catalog contract failed.'
do $$
begin
    raise exception 'PR16 fact query catalog gate failed.';
end
$$;
\endif

do $$
declare
    ids jsonb := '{}'::jsonb;
    fact_id bigint;
    predecessor_id bigint;
    registration_id uuid;
    identity_hash text;
    run_id uuid;
    definition_version integer;
    parser_version text;
    spec record;
    pend_accept bigint;
    acc_b_accept bigint;
    cacc_c_accept bigint;
    rev_a_accept bigint;
    ident_b_accept bigint;
    sibj_b_accept bigint;
    asof_a_accept bigint;
    asof_b_accept bigint;
    corr_accept bigint;
    sib_a_accept bigint;
    sib_b_accept bigint;
    sib_c_accept bigint;
    primary_registration uuid := '00000000-0000-4000-8000-000000000722';
    alternate_registration uuid := '00000000-0000-4000-8000-000000000723';
    hash_a text := repeat('a', 64);
    hash_b text := repeat('b', 64);
    run_v1 uuid := '00000000-0000-4000-8000-000000000801';
    run_v2 uuid := '00000000-0000-4000-8000-000000000802';
    run_def2 uuid := '00000000-0000-4000-8000-000000000803';
    run_identity uuid := '00000000-0000-4000-8000-000000000804';
    role_name text;
    statement_text text;
    denied boolean;
begin
    for spec in
        select *
        from (
            values
                ('obs_root'::text, null::text, 'pr16_obs_root'::text, 'root'::text,
                    '2026-07-01T00:00:00Z'::timestamptz, null::text, 'obs_root'::text),
                ('obs_ab_a', null, 'pr16_obs_ab', 'root',
                    '2026-07-01T00:00:00Z', null, 'obs_ab_a'),
                ('obs_ab_b', 'obs_ab_a', 'pr16_obs_ab', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'obs_ab_b'),
                ('obs_abc_a', null, 'pr16_obs_abc', 'root',
                    '2026-07-01T00:00:00Z', null, 'obs_abc_a'),
                ('obs_abc_b', 'obs_abc_a', 'pr16_obs_abc', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'obs_abc_b'),
                ('obs_abc_c', 'obs_abc_b', 'pr16_obs_abc', 'def2',
                    '2026-07-03T00:00:00Z', 'EXTRACTION_CORRECTION', 'obs_abc_c'),
                ('branch_a', null, 'pr16_obs_branch', 'root',
                    '2026-07-01T00:00:00Z', null, 'branch_a'),
                ('branch_c', 'branch_a', 'pr16_obs_branch', 'def2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'branch_c'),
                ('branch_b', 'branch_a', 'pr16_obs_branch', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'branch_b'),
                ('pend_a', null, 'pr16_pub_pending', 'root',
                    '2026-07-01T00:00:00Z', null, 'pend_a'),
                ('pend_b', 'pend_a', 'pr16_pub_pending', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'pend_b'),
                ('rej_a', null, 'pr16_pub_reject', 'root',
                    '2026-07-01T00:00:00Z', null, 'rej_a'),
                ('rej_b', 'rej_a', 'pr16_pub_reject', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'rej_b'),
                ('acc_a', null, 'pr16_pub_accept', 'root',
                    '2026-07-01T00:00:00Z', null, 'acc_a'),
                ('acc_b', 'acc_a', 'pr16_pub_accept', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'acc_b'),
                ('rev_a', null, 'pr16_pub_revoke', 'root',
                    '2026-07-01T00:00:00Z', null, 'rev_a'),
                ('rev_b', 'rev_a', 'pr16_pub_revoke', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'rev_b'),
                ('reja_a', null, 'pr16_pub_reject_after', 'root',
                    '2026-07-01T00:00:00Z', null, 'reja_a'),
                ('reja_b', 'reja_a', 'pr16_pub_reject_after', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'reja_b'),
                ('cpend_a', null, 'pr16_pub_c_pending', 'root',
                    '2026-07-01T00:00:00Z', null, 'cpend_a'),
                ('cpend_b', 'cpend_a', 'pr16_pub_c_pending', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'cpend_b'),
                ('cpend_c', 'cpend_b', 'pr16_pub_c_pending', 'def2',
                    '2026-07-03T00:00:00Z', 'EXTRACTION_CORRECTION', 'cpend_c'),
                ('cacc_a', null, 'pr16_pub_c_accept', 'root',
                    '2026-07-01T00:00:00Z', null, 'cacc_a'),
                ('cacc_b', 'cacc_a', 'pr16_pub_c_accept', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'cacc_b'),
                ('cacc_c', 'cacc_b', 'pr16_pub_c_accept', 'def2',
                    '2026-07-03T00:00:00Z', 'EXTRACTION_CORRECTION', 'cacc_c'),
                ('asof_a', null, 'pr16_asof', 'root',
                    '2026-07-01T00:00:00Z', null, 'asof_a'),
                ('asof_b', 'asof_a', 'pr16_asof', 'parser2',
                    '2026-07-10T00:00:00Z', 'EXTRACTION_CORRECTION', 'asof_b'),
                ('future_a', null, 'pr16_future', 'root',
                    '2026-07-10T00:00:00Z', null, 'future_a'),
                ('future_b', 'future_a', 'pr16_future', 'parser2',
                    '2026-07-05T00:00:00Z', 'EXTRACTION_CORRECTION', 'future_b'),
                ('corr_a', null, 'pr16_correction', 'root',
                    '2026-07-01T00:00:00Z', null, 'corr_a'),
                ('ident_a', null, 'pr16_identity', 'root',
                    '2026-07-01T00:00:00Z', null, 'shared'),
                ('ident_b', 'ident_a', 'pr16_identity', 'identity',
                    '2026-07-02T00:00:00Z', 'IDENTITY_CORRECTION', 'shared'),
                ('hash_left', null, 'pr16_same_hash', 'root',
                    '2026-07-01T00:00:00Z', null, 'hash_left'),
                ('hash_right', null, 'pr16_same_hash', 'root',
                    '2026-07-01T00:00:00Z', null, 'hash_right'),
                ('sib_a', null, 'pr16_sibling', 'root',
                    '2026-07-01T00:00:00Z', null, 'sib_a'),
                ('sib_c', 'sib_a', 'pr16_sibling', 'def2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'sib_c'),
                ('sib_b', 'sib_a', 'pr16_sibling', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'sib_b'),
                ('sibj_a', null, 'pr16_sibling_reject', 'root',
                    '2026-07-01T00:00:00Z', null, 'sibj_a'),
                ('sibj_c', 'sibj_a', 'pr16_sibling_reject', 'def2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'sibj_c'),
                ('sibj_b', 'sibj_a', 'pr16_sibling_reject', 'parser2',
                    '2026-07-02T00:00:00Z', 'EXTRACTION_CORRECTION', 'sibj_b')
        ) as fixture(
            fact_key,
            predecessor_key,
            lineage,
            variant,
            observed_at,
            reason,
            locator_member
        )
    loop
        predecessor_id := null;
        if spec.predecessor_key is not null then
            predecessor_id := (ids ->> spec.predecessor_key)::bigint;
            if predecessor_id is null then
                raise exception 'PR16 fixture predecessor % is missing', spec.predecessor_key;
            end if;
        end if;

        registration_id := primary_registration;
        identity_hash := hash_a;
        run_id := run_v1;
        definition_version := 1;
        parser_version := '1';
        if spec.variant = 'parser2' then
            run_id := run_v2;
            parser_version := '2';
        elsif spec.variant = 'def2' then
            run_id := run_def2;
            definition_version := 2;
        elsif spec.variant = 'identity' then
            run_id := run_identity;
            identity_hash := hash_b;
            registration_id := alternate_registration;
        elsif spec.variant <> 'root' then
            raise exception 'PR16 unknown fixture variant %', spec.variant;
        end if;

        insert into reported.reported_facts (
            regulatory_registration_id, regulator_id, regulatory_concept_id, source_id,
            reporting_scope_id, source_artifact_id, source_release_id, ingestion_run_id,
            source_definition_version, parser_implementation_key, parser_implementation_version,
            identity_definition_hash, period_kind, period_end, unit_code, dimensions,
            raw_value, parsed_value, locator_kind, source_locator, first_observed_at,
            predecessor_reported_fact_id, supersession_reason
        ) values (
            registration_id,
            '00000000-0000-4000-8000-000000000001',
            '00000000-0000-4000-8000-000000000751',
            '00000000-0000-4000-8000-000000000011',
            '00000000-0000-4000-8000-000000000761',
            '00000000-0000-4000-8000-000000000201',
            '00000000-0000-4000-8000-000000000101',
            run_id,
            definition_version,
            'test_parser',
            parser_version,
            identity_hash,
            'instant',
            date '2026-06-30',
            'MXN',
            jsonb_build_object('scenario', spec.lineage),
            '1',
            1,
            'csv',
            jsonb_build_object('lineage', spec.lineage, 'member', spec.locator_member),
            spec.observed_at,
            predecessor_id,
            spec.reason
        ) returning reported_fact_id into fact_id;

        ids := ids || jsonb_build_object(spec.fact_key, fact_id);
    end loop;

    if (select count(*) from jsonb_object_keys(ids)) <> 40 then
        raise exception 'PR16 fixture map does not contain 40 facts';
    end if;

    if not coalesce((
        select count(*) = 3
            and bool_or(link.ancestor_reported_fact_id = (ids->>'obs_abc_c')::bigint
                and link.generations = 0)
            and bool_or(link.ancestor_reported_fact_id = (ids->>'obs_abc_b')::bigint
                and link.generations = 1)
            and bool_or(link.ancestor_reported_fact_id = (ids->>'obs_abc_a')::bigint
                and link.generations = 2)
        from serving.reported_fact_revision_ancestry as link
        where link.reported_fact_id = (ids->>'obs_abc_c')::bigint
    ), false) then
        raise exception 'PR16 ancestry did not walk the predecessor chain to its root';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(observed.reported_fact_id = (ids->>'obs_root')::bigint)
            and bool_and(observed.lineage_root_reported_fact_id = (ids->>'obs_root')::bigint)
        from serving.current_observed_facts as observed
        where observed.lineage_root_reported_fact_id = (ids->>'obs_root')::bigint
    ), false) then
        raise exception 'PR16 root-only observed head failed';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(observed.reported_fact_id = (ids->>'obs_ab_b')::bigint)
        from serving.current_observed_facts as observed
        where observed.lineage_root_reported_fact_id = (ids->>'obs_ab_a')::bigint
    ), false) then
        raise exception 'PR16 linear observed A to B failed';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(observed.reported_fact_id = (ids->>'obs_abc_c')::bigint)
        from serving.current_observed_facts as observed
        where observed.lineage_root_reported_fact_id = (ids->>'obs_abc_a')::bigint
    ), false) then
        raise exception 'PR16 linear observed A to C failed';
    end if;

    if not coalesce((
        select count(*) = 2
            and bool_or(observed.reported_fact_id = (ids->>'branch_b')::bigint)
            and bool_or(observed.reported_fact_id = (ids->>'branch_c')::bigint)
        from serving.current_observed_facts as observed
        where observed.lineage_root_reported_fact_id = (ids->>'branch_a')::bigint
    ), false) then
        raise exception 'PR16 branching observed heads were collapsed';
    end if;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'pend_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    ) returning review_decision_id into pend_accept;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values
        ((ids->>'rej_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'),
        ((ids->>'rej_b')::bigint, 'REJECT', '2026-07-03T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 rejection.');

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'acc_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    );

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'acc_b')::bigint, 'ACCEPT', '2026-07-03T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    ) returning review_decision_id into acc_b_accept;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'rev_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    ) returning review_decision_id into rev_a_accept;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'rev_b')::bigint, 'ACCEPT', '2026-07-03T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    );

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'rev_b')::bigint, 'REVOKE', '2026-07-04T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 revocation.'
    );

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'reja_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    );

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'reja_b')::bigint, 'ACCEPT', '2026-07-03T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    );

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'reja_b')::bigint, 'REJECT', '2026-07-04T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 rejection.'
    );

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values
        ((ids->>'cpend_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'),
        ((ids->>'cpend_b')::bigint, 'ACCEPT', '2026-07-03T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.');

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values
        ((ids->>'cacc_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'),
        ((ids->>'cacc_b')::bigint, 'ACCEPT', '2026-07-03T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'),
        ((ids->>'cacc_c')::bigint, 'ACCEPT', '2026-07-04T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.');

    select review.review_decision_id
    into cacc_c_accept
    from audit.effective_review_decisions as review
    where review.reported_fact_id = (ids->>'cacc_c')::bigint;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'pend_a')::bigint)
            and bool_and(row.effective_decision = 'ACCEPT')
            and bool_and(row.effective_review_decision_id = pend_accept)
            and bool_and(row.effective_decided_at = '2026-07-02T00:00:00Z')
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'pend_a')::bigint
    ), false) then
        raise exception 'PR16 pending successor displaced an accepted ancestor';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'rej_a')::bigint)
            and bool_and(row.effective_decision = 'ACCEPT')
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'rej_a')::bigint
    ), false) then
        raise exception 'PR16 rejected successor displaced an accepted ancestor';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'acc_b')::bigint)
            and bool_and(row.effective_decision = 'ACCEPT')
            and bool_and(row.effective_review_decision_id = acc_b_accept)
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'acc_a')::bigint
    ), false) then
        raise exception 'PR16 accepted successor did not displace its ancestor';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'rev_a')::bigint)
            and bool_and(row.effective_decision = 'ACCEPT')
            and bool_and(row.effective_review_decision_id = rev_a_accept)
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'rev_a')::bigint
    ), false) then
        raise exception 'PR16 revocation did not restore the accepted ancestor';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'reja_a')::bigint)
            and bool_and(row.effective_decision = 'ACCEPT')
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'reja_a')::bigint
    ), false) then
        raise exception 'PR16 later rejection did not restore the accepted ancestor';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'cpend_b')::bigint)
            and bool_and(row.effective_decision = 'ACCEPT')
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'cpend_a')::bigint
    ), false) then
        raise exception 'PR16 pending grandchild displaced the accepted child';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'cacc_c')::bigint)
            and bool_and(row.effective_decision = 'ACCEPT')
            and bool_and(row.effective_review_decision_id = cacc_c_accept)
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'cacc_a')::bigint
    ), false) then
        raise exception 'PR16 accepted grandchild did not become the frontier';
    end if;

    if exists (
        select 1
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id in (
            (ids->>'obs_root')::bigint,
            (ids->>'obs_ab_a')::bigint,
            (ids->>'obs_abc_a')::bigint,
            (ids->>'branch_a')::bigint
        )
    ) then
        raise exception 'PR16 unaccepted observed lineage became publishable';
    end if;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'asof_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    ) returning review_decision_id into asof_a_accept;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'asof_b')::bigint, 'ACCEPT', '2026-07-14T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    ) returning review_decision_id into asof_b_accept;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'asof_b')::bigint, 'REVOKE', '2026-07-20T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 revocation.'
    );

    if not coalesce((
        select count(*) = 1
            and bool_and(observed.reported_fact_id = (ids->>'asof_a')::bigint)
        from serving.observed_facts_as_of('2026-07-05T00:00:00Z') as observed
        where observed.lineage_root_reported_fact_id = (ids->>'asof_a')::bigint
    ), false) then
        raise exception 'PR16 as-of observed head was displaced by a future child';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'asof_a')::bigint)
            and bool_and(row.effective_review_decision_id = asof_a_accept)
            and bool_and(row.effective_decision = 'ACCEPT')
        from serving.publishable_facts_as_of('2026-07-05T00:00:00Z') as row
        where row.lineage_root_reported_fact_id = (ids->>'asof_a')::bigint
    ), false) then
        raise exception 'PR16 as-of before the successor observation failed';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(observed.reported_fact_id = (ids->>'asof_b')::bigint)
        from serving.observed_facts_as_of('2026-07-10T00:00:00Z') as observed
        where observed.lineage_root_reported_fact_id = (ids->>'asof_a')::bigint
    ), false) then
        raise exception 'PR16 as-of observation cutoff was not inclusive';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'asof_a')::bigint)
            and bool_and(row.effective_review_decision_id = asof_a_accept)
        from serving.publishable_facts_as_of('2026-07-12T00:00:00Z') as row
        where row.lineage_root_reported_fact_id = (ids->>'asof_a')::bigint
    ), false)
    or not coalesce((
        select count(*) = 1
            and bool_and(observed.reported_fact_id = (ids->>'asof_b')::bigint)
        from serving.observed_facts_as_of('2026-07-12T00:00:00Z') as observed
        where observed.lineage_root_reported_fact_id = (ids->>'asof_a')::bigint
    ), false) then
        raise exception 'PR16 as-of after observation and before acceptance failed';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'asof_b')::bigint)
            and bool_and(row.effective_review_decision_id = asof_b_accept)
            and bool_and(row.effective_decided_at = '2026-07-14T00:00:00Z')
            and bool_and(row.effective_decision = 'ACCEPT')
        from serving.publishable_facts_as_of('2026-07-15T00:00:00Z') as row
        where row.lineage_root_reported_fact_id = (ids->>'asof_a')::bigint
    ), false) then
        raise exception 'PR16 as-of after acceptance was rewritten by a later revocation';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'asof_a')::bigint)
            and bool_and(row.effective_review_decision_id = asof_a_accept)
        from serving.publishable_facts_as_of('2026-07-21T00:00:00Z') as row
        where row.lineage_root_reported_fact_id = (ids->>'asof_a')::bigint
    ), false)
    or not coalesce((
        select count(*) = 1
            and bool_and(observed.reported_fact_id = (ids->>'asof_b')::bigint)
        from serving.observed_facts_as_of('2026-07-21T00:00:00Z') as observed
        where observed.lineage_root_reported_fact_id = (ids->>'asof_a')::bigint
    ), false) then
        raise exception 'PR16 as-of after revocation did not restore the accepted ancestor';
    end if;

    if exists (
        select 1
        from serving.observed_facts_as_of('2026-07-06T00:00:00Z') as observed
        where observed.reported_fact_id in (
                (ids->>'future_a')::bigint,
                (ids->>'future_b')::bigint
            )
           or observed.lineage_root_reported_fact_id in (
                (ids->>'future_a')::bigint,
                (ids->>'future_b')::bigint
            )
    ) or exists (
        select 1
        from serving.publishable_facts_as_of('2026-07-06T00:00:00Z') as row
        where row.reported_fact_id in (
                (ids->>'future_a')::bigint,
                (ids->>'future_b')::bigint
            )
           or row.lineage_root_reported_fact_id in (
                (ids->>'future_a')::bigint,
                (ids->>'future_b')::bigint
            )
    ) then
        raise exception 'PR16 future ancestry was visible before its root';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(observed.reported_fact_id = (ids->>'future_b')::bigint)
            and bool_and(observed.lineage_root_reported_fact_id = (ids->>'future_a')::bigint)
        from serving.observed_facts_as_of('2026-07-11T00:00:00Z') as observed
        where observed.reported_fact_id = (ids->>'future_b')::bigint
    ), false) then
        raise exception 'PR16 future ancestry did not recover after the root was visible';
    end if;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'corr_a')::bigint, 'ACCEPT', '2026-07-01T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    ) returning review_decision_id into corr_accept;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason,
        corrects_review_decision_id
    ) values (
        (ids->>'corr_a')::bigint, 'REJECT', '2026-07-10T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 correcting rejection.', corr_accept
    );

    if not coalesce((
        select count(*) = 1
            and bool_and(row.effective_review_decision_id = corr_accept)
            and bool_and(row.effective_decision = 'ACCEPT')
            and bool_and(row.effective_decided_at = '2026-07-01T00:00:00Z')
        from serving.publishable_facts_as_of('2026-07-05T00:00:00Z') as row
        where row.reported_fact_id = (ids->>'corr_a')::bigint
    ), false) then
        raise exception 'PR16 earlier cutoff lost the corrected acceptance';
    end if;

    if exists (
        select 1
        from serving.publishable_facts_as_of('2026-07-11T00:00:00Z') as row
        where row.lineage_root_reported_fact_id = (ids->>'corr_a')::bigint
    ) or exists (
        select 1
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'corr_a')::bigint
    ) then
        raise exception 'PR16 correcting rejection remained publishable';
    end if;

    if not coalesce((
        select count(*) = 1
            and bool_and(successor.fact_key_hash <> root_fact.fact_key_hash)
            and bool_and(
                successor.regulatory_registration_id
                    <> root_fact.regulatory_registration_id
            )
            and bool_and(successor.predecessor_reported_fact_id = root_fact.reported_fact_id)
        from reported.reported_facts as successor
        join reported.reported_facts as root_fact
          on root_fact.reported_fact_id = successor.predecessor_reported_fact_id
        where successor.reported_fact_id = (ids->>'ident_b')::bigint
          and root_fact.reported_fact_id = (ids->>'ident_a')::bigint
    ), false) then
        raise exception 'PR16 identity correction did not stay on one predecessor lineage';
    end if;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values
        ((ids->>'ident_a')::bigint, 'ACCEPT', '2026-07-03T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'),
        ((ids->>'ident_b')::bigint, 'ACCEPT', '2026-07-04T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.');

    select review.review_decision_id
    into ident_b_accept
    from audit.effective_review_decisions as review
    where review.reported_fact_id = (ids->>'ident_b')::bigint;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'ident_b')::bigint)
            and bool_and(row.lineage_root_reported_fact_id = (ids->>'ident_a')::bigint)
            and bool_and(row.effective_review_decision_id = ident_b_accept)
            and bool_and(row.effective_decision = 'ACCEPT')
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'ident_a')::bigint
    ), false) then
        raise exception 'PR16 accepted identity correction did not displace its root';
    end if;

    if not coalesce((
        select count(*) = 2
            and count(distinct observed.lineage_root_reported_fact_id) = 2
            and bool_and(observed.lineage_root_reported_fact_id = observed.reported_fact_id)
            and bool_and(left_fact.fact_key_hash = right_fact.fact_key_hash)
        from serving.current_observed_facts as observed
        join reported.reported_facts as left_fact
          on left_fact.reported_fact_id = (ids->>'hash_left')::bigint
        join reported.reported_facts as right_fact
          on right_fact.reported_fact_id = (ids->>'hash_right')::bigint
        where observed.reported_fact_id in (
            (ids->>'hash_left')::bigint,
            (ids->>'hash_right')::bigint
        )
    ), false) then
        raise exception 'PR16 same fact key collapsed independent predecessor roots';
    end if;

    if not coalesce((
        select count(*) = 2
            and bool_or(observed.reported_fact_id = (ids->>'sib_b')::bigint)
            and bool_or(observed.reported_fact_id = (ids->>'sib_c')::bigint)
        from serving.current_observed_facts as observed
        where observed.lineage_root_reported_fact_id = (ids->>'sib_a')::bigint
    ), false) then
        raise exception 'PR16 sibling observed branches were collapsed';
    end if;

    if (ids->>'sib_c')::bigint >= (ids->>'sib_b')::bigint then
        raise exception 'PR16 sibling fixture did not give C the smaller id';
    end if;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'sib_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    ) returning review_decision_id into sib_a_accept;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'sib_b')::bigint, 'ACCEPT', '2026-07-09T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    ) returning review_decision_id into sib_b_accept;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'sib_b')::bigint)
            and bool_and(row.effective_review_decision_id = sib_b_accept)
            and bool_and(row.effective_decision = 'ACCEPT')
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'sib_a')::bigint
    ), false) then
        raise exception 'PR16 one accepted sibling with a pending sibling failed';
    end if;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'sib_c')::bigint, 'ACCEPT', '2026-07-04T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'
    ) returning review_decision_id into sib_c_accept;

    if sib_c_accept = sib_b_accept
        or not exists (
            select 1
            from audit.review_decisions as decision_event
            where decision_event.review_decision_id = sib_c_accept
              and decision_event.decided_at = '2026-07-04T00:00:00Z'
        )
        or not exists (
            select 1
            from audit.review_decisions as decision_event
            where decision_event.review_decision_id = sib_b_accept
              and decision_event.decided_at = '2026-07-09T00:00:00Z'
        )
    then
        raise exception 'PR16 sibling timestamp and id ordering fixture failed';
    end if;

    if not coalesce((
        select count(*) = 2 and bool_and(review.decision = 'ACCEPT')
        from audit.effective_review_decisions as review
        where review.reported_fact_id in (
            (ids->>'sib_b')::bigint,
            (ids->>'sib_c')::bigint
        )
    ), false) or exists (
        select 1
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'sib_a')::bigint
           or row.reported_fact_id in (
                (ids->>'sib_a')::bigint,
                (ids->>'sib_b')::bigint,
                (ids->>'sib_c')::bigint
            )
    ) then
        raise exception 'PR16 sibling ACCEPT conflict returned a publishable row';
    end if;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'sib_c')::bigint, 'REVOKE', '2026-07-12T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 revocation.'
    );

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'sib_b')::bigint)
            and bool_and(row.effective_review_decision_id = sib_b_accept)
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'sib_a')::bigint
    ), false) then
        raise exception 'PR16 sibling revocation did not leave the sole frontier';
    end if;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values (
        (ids->>'sib_b')::bigint, 'REVOKE', '2026-07-13T00:00:00Z',
        'HUMAN', 'lead_reviewer', 'Synthetic PR16 revocation.'
    );

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'sib_a')::bigint)
            and bool_and(row.effective_review_decision_id = sib_a_accept)
            and bool_and(row.effective_decision = 'ACCEPT')
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'sib_a')::bigint
    ), false) then
        raise exception 'PR16 sibling recovery did not restore the accepted ancestor';
    end if;

    insert into audit.review_decisions (
        reported_fact_id, decision, decided_at, actor_kind, human_actor_key, reason
    ) values
        ((ids->>'sibj_a')::bigint, 'ACCEPT', '2026-07-02T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'),
        ((ids->>'sibj_b')::bigint, 'ACCEPT', '2026-07-08T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 acceptance.'),
        ((ids->>'sibj_c')::bigint, 'REJECT', '2026-07-03T00:00:00Z',
            'HUMAN', 'lead_reviewer', 'Synthetic PR16 rejection.');

    select review.review_decision_id
    into sibj_b_accept
    from audit.effective_review_decisions as review
    where review.reported_fact_id = (ids->>'sibj_b')::bigint;

    if not coalesce((
        select count(*) = 1
            and bool_and(row.reported_fact_id = (ids->>'sibj_b')::bigint)
            and bool_and(row.effective_review_decision_id = sibj_b_accept)
            and bool_and(row.effective_decision = 'ACCEPT')
        from serving.current_publishable_facts as row
        where row.lineage_root_reported_fact_id = (ids->>'sibj_a')::bigint
    ), false) then
        raise exception 'PR16 rejected sibling removed the accepted sibling';
    end if;

    if (select count(*) from serving.observed_facts_as_of(null)) <> 0
        or (select count(*) from serving.publishable_facts_as_of(null)) <> 0
    then
        raise exception 'PR16 null cutoff returned rows';
    end if;

    if exists (
        select
            observed.lineage_root_reported_fact_id,
            observed.reported_fact_id,
            observed.regulatory_registration_id,
            observed.regulator_id,
            observed.regulatory_concept_id,
            observed.source_id,
            observed.reporting_scope_id,
            observed.source_artifact_id,
            observed.source_release_id,
            observed.ingestion_run_id,
            observed.source_definition_version,
            observed.parser_implementation_key,
            observed.parser_implementation_version,
            observed.identity_definition_hash,
            observed.period_kind,
            observed.period_start,
            observed.period_end,
            observed.unit_code,
            observed.dimensions,
            observed.raw_value,
            observed.parsed_value,
            observed.raw_label,
            observed.locator_kind,
            observed.source_locator,
            observed.locator_hash,
            observed.fact_key_hash,
            observed.first_observed_at,
            observed.predecessor_reported_fact_id,
            observed.supersession_reason
        from serving.current_observed_facts as observed
        except
        select
            as_of_row.lineage_root_reported_fact_id,
            as_of_row.reported_fact_id,
            as_of_row.regulatory_registration_id,
            as_of_row.regulator_id,
            as_of_row.regulatory_concept_id,
            as_of_row.source_id,
            as_of_row.reporting_scope_id,
            as_of_row.source_artifact_id,
            as_of_row.source_release_id,
            as_of_row.ingestion_run_id,
            as_of_row.source_definition_version,
            as_of_row.parser_implementation_key,
            as_of_row.parser_implementation_version,
            as_of_row.identity_definition_hash,
            as_of_row.period_kind,
            as_of_row.period_start,
            as_of_row.period_end,
            as_of_row.unit_code,
            as_of_row.dimensions,
            as_of_row.raw_value,
            as_of_row.parsed_value,
            as_of_row.raw_label,
            as_of_row.locator_kind,
            as_of_row.source_locator,
            as_of_row.locator_hash,
            as_of_row.fact_key_hash,
            as_of_row.first_observed_at,
            as_of_row.predecessor_reported_fact_id,
            as_of_row.supersession_reason
        from serving.observed_facts_as_of('2099-01-01T00:00:00Z') as as_of_row
    ) or exists (
        select
            as_of_row.lineage_root_reported_fact_id,
            as_of_row.reported_fact_id,
            as_of_row.fact_key_hash,
            as_of_row.first_observed_at
        from serving.observed_facts_as_of('2099-01-01T00:00:00Z') as as_of_row
        except
        select
            observed.lineage_root_reported_fact_id,
            observed.reported_fact_id,
            observed.fact_key_hash,
            observed.first_observed_at
        from serving.current_observed_facts as observed
    ) then
        raise exception 'PR16 late cutoff observed set diverged from current';
    end if;

    if exists (
        select
            row.lineage_root_reported_fact_id,
            row.reported_fact_id,
            row.effective_review_decision_id,
            row.effective_decision,
            row.effective_decided_at
        from serving.current_publishable_facts as row
        except
        select
            as_of_row.lineage_root_reported_fact_id,
            as_of_row.reported_fact_id,
            as_of_row.effective_review_decision_id,
            as_of_row.effective_decision,
            as_of_row.effective_decided_at
        from serving.publishable_facts_as_of('2099-01-01T00:00:00Z') as as_of_row
    ) or exists (
        select
            as_of_row.lineage_root_reported_fact_id,
            as_of_row.reported_fact_id,
            as_of_row.effective_review_decision_id,
            as_of_row.effective_decision,
            as_of_row.effective_decided_at
        from serving.publishable_facts_as_of('2099-01-01T00:00:00Z') as as_of_row
        except
        select
            row.lineage_root_reported_fact_id,
            row.reported_fact_id,
            row.effective_review_decision_id,
            row.effective_decision,
            row.effective_decided_at
        from serving.current_publishable_facts as row
    ) then
        raise exception 'PR16 late cutoff publishable set diverged from current';
    end if;

    if exists (
        select 1
        from unnest(array[
            'serving.reported_fact_revision_ancestry',
            'serving.current_observed_facts',
            'serving.current_publishable_facts'
        ]) as view_name
        where pg_catalog.has_table_privilege(
            'service_role',
            view_name,
            'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
        )
    ) then
        raise exception 'service_role acquired a PR16 write privilege';
    end if;

    set local role service_role;
    perform count(*) from serving.current_observed_facts;
    perform count(*) from serving.current_publishable_facts;
    perform count(*) from serving.reported_fact_revision_ancestry;
    perform count(*) from serving.observed_facts_as_of('2099-01-01T00:00:00Z');
    perform count(*) from serving.publishable_facts_as_of('2099-01-01T00:00:00Z');
    reset role;

    foreach role_name in array array['anon', 'authenticated']
    loop
        execute format('set local role %I', role_name);
        foreach statement_text in array array[
            'select count(*) from serving.current_observed_facts',
            'select count(*) from serving.current_publishable_facts',
            'select count(*) from serving.reported_fact_revision_ancestry',
            'select count(*) from serving.observed_facts_as_of(''2099-01-01T00:00:00Z'')',
            'select count(*) from serving.publishable_facts_as_of(''2099-01-01T00:00:00Z'')'
        ]
        loop
            denied := false;
            begin
                execute statement_text;
            exception
                when insufficient_privilege then
                    denied := true;
            end;
            if not denied then
                raise exception 'PR16 allowed % to run %', role_name, statement_text;
            end if;
        end loop;
        reset role;
    end loop;
end
$$;

\echo 'PR16 fact query behavioral smoke passed.'

rollback;

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

select
    not exists (select 1 from reported.reported_facts)
    and not exists (
        select 1 from registry.measurement_units where unit_code = 'MXN'
    )
    and not exists (
        select 1 from registry.reporting_scopes
        where reporting_scope_id in (
            '00000000-0000-4000-8000-000000000762',
            '00000000-0000-4000-8000-000000000763'
        )
    ) as pr15_rollback_passed
\gset

\if :pr15_rollback_passed
\echo 'PR15 smoke fixtures rolled back cleanly.'
\else
\echo 'PR15 smoke fixtures persisted unexpectedly.'
do $$
begin
    raise exception 'PR15 rollback cleanliness gate failed.';
end
$$;
\endif

select
    not exists (select 1 from audit.review_decisions)
    and not exists (select 1 from audit.effective_review_decisions)
    as pr15a_rollback_passed
\gset

\if :pr15a_rollback_passed
\echo 'PR15a smoke fixtures rolled back cleanly.'
\else
\echo 'PR15a smoke fixtures persisted unexpectedly.'
do $$
begin
    raise exception 'PR15a rollback cleanliness gate failed.';
end
$$;
\endif

select
    not exists (select 1 from serving.reported_fact_revision_ancestry)
    and not exists (select 1 from serving.current_observed_facts)
    and not exists (select 1 from serving.current_publishable_facts)
    and not exists (
        select 1 from serving.observed_facts_as_of('2099-01-01T00:00:00Z')
    )
    and not exists (
        select 1 from serving.publishable_facts_as_of('2099-01-01T00:00:00Z')
    )
    and not exists (select 1 from reported.reported_facts)
    and not exists (select 1 from audit.review_decisions)
    as pr16_rollback_passed
\gset

\if :pr16_rollback_passed
\echo 'PR16 smoke fixtures rolled back cleanly.'
\else
\echo 'PR16 smoke fixtures persisted unexpectedly.'
do $$
begin
    raise exception 'PR16 rollback cleanliness gate failed.';
end
$$;
\endif

\echo 'Migration smoke completed successfully.'
