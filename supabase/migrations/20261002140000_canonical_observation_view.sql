begin;

set local search_path = public, extensions, pg_catalog;

create view semantic.canonical_observations_v1
with (security_invoker = true) as
select
    publishable.lineage_root_reported_fact_id,
    publishable.reported_fact_id,
    registration.institution_id,
    publishable.regulatory_registration_id,
    publishable.regulatory_concept_id,
    publishable.reporting_scope_id,
    canonical_concept.canonical_concept_id,
    canonical_concept.concept_code,
    canonical_version.canonical_concept_version_id,
    canonical_version.definition_version as canonical_definition_version,
    mapping.concept_mapping_id,
    mapping_version.concept_mapping_version_id,
    mapping_version.definition_version as mapping_definition_version,
    mapping_version.comparability,
    canonical_concept.data_nature,
    canonical_concept.period_kind,
    publishable.period_start,
    publishable.period_end,
    publishable.period_end as economic_date,
    canonical_concept.canonical_unit_code,
    publishable.parsed_value as canonical_value
from serving.current_publishable_facts as publishable
join registry.regulatory_registrations as registration
    on registration.regulatory_registration_id = publishable.regulatory_registration_id
    and registration.validity @> publishable.period_end
join registry.regulatory_concepts as regulatory_concept
    on regulatory_concept.regulatory_concept_id = publishable.regulatory_concept_id
    and regulatory_concept.lifecycle = 'active'
    and regulatory_concept.valid_from <= publishable.period_end
    and (
        regulatory_concept.valid_to is null
        or publishable.period_end <= regulatory_concept.valid_to
    )
join semantic.concept_mappings as mapping
    on mapping.regulatory_concept_id = publishable.regulatory_concept_id
    and mapping.reporting_scope_id = publishable.reporting_scope_id
join semantic.concept_mapping_versions as mapping_version
    on mapping_version.concept_mapping_id = mapping.concept_mapping_id
    and mapping_version.validity @> publishable.period_end
    and not exists (
        select 1
        from semantic.concept_mapping_versions as higher_mapping_version
        where higher_mapping_version.concept_mapping_id = mapping_version.concept_mapping_id
            and higher_mapping_version.validity @> publishable.period_end
            and higher_mapping_version.definition_version
                > mapping_version.definition_version
    )
    and mapping_version.lifecycle = 'active'
    and mapping_version.comparability in ('EXACT', 'HARMONIZED', 'PROXY')
    and mapping_version.transformation_key is null
join semantic.canonical_concept_versions as canonical_version
    on canonical_version.canonical_concept_version_id
        = mapping_version.canonical_concept_version_id
    and not exists (
        select 1
        from semantic.canonical_concept_versions as higher_canonical_version
        where higher_canonical_version.canonical_concept_id
                = canonical_version.canonical_concept_id
            and higher_canonical_version.definition_version
                > canonical_version.definition_version
    )
    and canonical_version.lifecycle = 'active'
join semantic.canonical_concept_version_scopes as canonical_scope
    on canonical_scope.canonical_concept_version_id
        = canonical_version.canonical_concept_version_id
    and canonical_scope.reporting_scope_id = publishable.reporting_scope_id
join semantic.canonical_concepts as canonical_concept
    on canonical_concept.canonical_concept_id = canonical_version.canonical_concept_id
    and canonical_concept.canonical_concept_id = mapping.canonical_concept_id
    and publishable.period_kind = canonical_concept.period_kind
    and publishable.unit_code = canonical_concept.canonical_unit_code
where publishable.dimensions = '{}'::jsonb;

revoke all privileges
on semantic.canonical_observations_v1
from public, anon, authenticated, service_role;

grant select
on semantic.canonical_observations_v1
to service_role;

commit;
