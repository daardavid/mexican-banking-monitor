\set ON_ERROR_STOP on

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
        ('registry', 'reporting_scope_versions', 'r')
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
        ('registry', 'reporting_scope_versions', 'r')
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
            where namespace.nspname in (
                'evidence', 'reported', 'semantic', 'metrics', 'audit', 'serving'
            )
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
