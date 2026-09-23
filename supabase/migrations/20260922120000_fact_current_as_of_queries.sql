begin;

set local search_path = public, extensions, pg_catalog;

create view serving.reported_fact_revision_ancestry
with (security_invoker = true) as
with recursive ancestry (
    reported_fact_id,
    ancestor_reported_fact_id,
    generations
) as (
    select
        fact.reported_fact_id,
        fact.reported_fact_id,
        0
    from reported.reported_facts as fact
    union all
    select
        ancestry.reported_fact_id,
        parent.predecessor_reported_fact_id,
        ancestry.generations + 1
    from ancestry
    join reported.reported_facts as parent
        on parent.reported_fact_id = ancestry.ancestor_reported_fact_id
    where parent.predecessor_reported_fact_id is not null
)
select
    ancestry.reported_fact_id,
    ancestry.ancestor_reported_fact_id,
    ancestry.generations
from ancestry;

create view serving.current_observed_facts
with (security_invoker = true) as
select
    root_fact.reported_fact_id as lineage_root_reported_fact_id,
    fact.reported_fact_id,
    fact.regulatory_registration_id,
    fact.regulator_id,
    fact.regulatory_concept_id,
    fact.source_id,
    fact.reporting_scope_id,
    fact.source_artifact_id,
    fact.source_release_id,
    fact.ingestion_run_id,
    fact.source_definition_version,
    fact.parser_implementation_key,
    fact.parser_implementation_version,
    fact.identity_definition_hash,
    fact.period_kind,
    fact.period_start,
    fact.period_end,
    fact.unit_code,
    fact.dimensions,
    fact.raw_value,
    fact.parsed_value,
    fact.raw_label,
    fact.locator_kind,
    fact.source_locator,
    fact.locator_hash,
    fact.fact_key_hash,
    fact.first_observed_at,
    fact.predecessor_reported_fact_id,
    fact.supersession_reason
from reported.reported_facts as fact
join serving.reported_fact_revision_ancestry as root_link
    on root_link.reported_fact_id = fact.reported_fact_id
join reported.reported_facts as root_fact
    on root_fact.reported_fact_id = root_link.ancestor_reported_fact_id
    and root_fact.predecessor_reported_fact_id is null
where not exists (
    select 1
    from reported.reported_facts as child
    where child.predecessor_reported_fact_id = fact.reported_fact_id
);

create view serving.current_publishable_facts
with (security_invoker = true) as
with accepted as (
    select
        fact.reported_fact_id,
        root_fact.reported_fact_id as lineage_root_reported_fact_id,
        review.review_decision_id as effective_review_decision_id,
        review.decision as effective_decision,
        review.decided_at as effective_decided_at
    from reported.reported_facts as fact
    join audit.effective_review_decisions as review
        on review.reported_fact_id = fact.reported_fact_id
        and review.decision = 'ACCEPT'
    join serving.reported_fact_revision_ancestry as root_link
        on root_link.reported_fact_id = fact.reported_fact_id
    join reported.reported_facts as root_fact
        on root_fact.reported_fact_id = root_link.ancestor_reported_fact_id
        and root_fact.predecessor_reported_fact_id is null
),
frontier as (
    select
        accepted.reported_fact_id,
        accepted.lineage_root_reported_fact_id,
        accepted.effective_review_decision_id,
        accepted.effective_decision,
        accepted.effective_decided_at
    from accepted
    where not exists (
        select 1
        from accepted as accepted_descendant
        join serving.reported_fact_revision_ancestry as descendant_link
            on descendant_link.reported_fact_id = accepted_descendant.reported_fact_id
            and descendant_link.ancestor_reported_fact_id = accepted.reported_fact_id
            and descendant_link.generations > 0
    )
),
sole_frontier as (
    select frontier.lineage_root_reported_fact_id
    from frontier
    group by frontier.lineage_root_reported_fact_id
    having count(*) = 1
)
select
    frontier.lineage_root_reported_fact_id,
    fact.reported_fact_id,
    fact.regulatory_registration_id,
    fact.regulator_id,
    fact.regulatory_concept_id,
    fact.source_id,
    fact.reporting_scope_id,
    fact.source_artifact_id,
    fact.source_release_id,
    fact.ingestion_run_id,
    fact.source_definition_version,
    fact.parser_implementation_key,
    fact.parser_implementation_version,
    fact.identity_definition_hash,
    fact.period_kind,
    fact.period_start,
    fact.period_end,
    fact.unit_code,
    fact.dimensions,
    fact.raw_value,
    fact.parsed_value,
    fact.raw_label,
    fact.locator_kind,
    fact.source_locator,
    fact.locator_hash,
    fact.fact_key_hash,
    fact.first_observed_at,
    fact.predecessor_reported_fact_id,
    fact.supersession_reason,
    frontier.effective_review_decision_id,
    frontier.effective_decision,
    frontier.effective_decided_at
from frontier
join sole_frontier
    on sole_frontier.lineage_root_reported_fact_id = frontier.lineage_root_reported_fact_id
join reported.reported_facts as fact
    on fact.reported_fact_id = frontier.reported_fact_id;

create function serving.observed_facts_as_of(cutoff timestamptz)
returns table (
    lineage_root_reported_fact_id bigint,
    reported_fact_id bigint,
    regulatory_registration_id uuid,
    regulator_id uuid,
    regulatory_concept_id uuid,
    source_id uuid,
    reporting_scope_id uuid,
    source_artifact_id uuid,
    source_release_id uuid,
    ingestion_run_id uuid,
    source_definition_version integer,
    parser_implementation_key text,
    parser_implementation_version text,
    identity_definition_hash text,
    period_kind text,
    period_start date,
    period_end date,
    unit_code text,
    dimensions jsonb,
    raw_value text,
    parsed_value numeric,
    raw_label text,
    locator_kind text,
    source_locator jsonb,
    locator_hash text,
    fact_key_hash text,
    first_observed_at timestamptz,
    predecessor_reported_fact_id bigint,
    supersession_reason text
)
language sql
stable
as $$
    with cutoff_eligible_facts as (
        select fact.reported_fact_id
        from reported.reported_facts as fact
        where cutoff is not null
          and fact.first_observed_at <= cutoff
          and not exists (
              select 1
              from serving.reported_fact_revision_ancestry as ancestor_link
              join reported.reported_facts as ancestor
                  on ancestor.reported_fact_id = ancestor_link.ancestor_reported_fact_id
              where ancestor_link.reported_fact_id = fact.reported_fact_id
                and ancestor.first_observed_at > cutoff
          )
    )
    select
        root_fact.reported_fact_id as lineage_root_reported_fact_id,
        fact.reported_fact_id,
        fact.regulatory_registration_id,
        fact.regulator_id,
        fact.regulatory_concept_id,
        fact.source_id,
        fact.reporting_scope_id,
        fact.source_artifact_id,
        fact.source_release_id,
        fact.ingestion_run_id,
        fact.source_definition_version,
        fact.parser_implementation_key,
        fact.parser_implementation_version,
        fact.identity_definition_hash,
        fact.period_kind,
        fact.period_start,
        fact.period_end,
        fact.unit_code,
        fact.dimensions,
        fact.raw_value,
        fact.parsed_value,
        fact.raw_label,
        fact.locator_kind,
        fact.source_locator,
        fact.locator_hash,
        fact.fact_key_hash,
        fact.first_observed_at,
        fact.predecessor_reported_fact_id,
        fact.supersession_reason
    from cutoff_eligible_facts as eligible
    join reported.reported_facts as fact
        on fact.reported_fact_id = eligible.reported_fact_id
    join serving.reported_fact_revision_ancestry as root_link
        on root_link.reported_fact_id = fact.reported_fact_id
    join reported.reported_facts as root_fact
        on root_fact.reported_fact_id = root_link.ancestor_reported_fact_id
        and root_fact.predecessor_reported_fact_id is null
    where not exists (
        select 1
        from reported.reported_facts as child
        join cutoff_eligible_facts as eligible_child
            on eligible_child.reported_fact_id = child.reported_fact_id
        where child.predecessor_reported_fact_id = fact.reported_fact_id
    );
$$;

create function serving.publishable_facts_as_of(cutoff timestamptz)
returns table (
    lineage_root_reported_fact_id bigint,
    reported_fact_id bigint,
    regulatory_registration_id uuid,
    regulator_id uuid,
    regulatory_concept_id uuid,
    source_id uuid,
    reporting_scope_id uuid,
    source_artifact_id uuid,
    source_release_id uuid,
    ingestion_run_id uuid,
    source_definition_version integer,
    parser_implementation_key text,
    parser_implementation_version text,
    identity_definition_hash text,
    period_kind text,
    period_start date,
    period_end date,
    unit_code text,
    dimensions jsonb,
    raw_value text,
    parsed_value numeric,
    raw_label text,
    locator_kind text,
    source_locator jsonb,
    locator_hash text,
    fact_key_hash text,
    first_observed_at timestamptz,
    predecessor_reported_fact_id bigint,
    supersession_reason text,
    effective_review_decision_id bigint,
    effective_decision text,
    effective_decided_at timestamptz
)
language sql
stable
as $$
    with cutoff_eligible_facts as (
        select fact.reported_fact_id
        from reported.reported_facts as fact
        where cutoff is not null
          and fact.first_observed_at <= cutoff
          and not exists (
              select 1
              from serving.reported_fact_revision_ancestry as ancestor_link
              join reported.reported_facts as ancestor
                  on ancestor.reported_fact_id = ancestor_link.ancestor_reported_fact_id
              where ancestor_link.reported_fact_id = fact.reported_fact_id
                and ancestor.first_observed_at > cutoff
          )
    ),
    accepted as (
        select
            fact.reported_fact_id,
            root_fact.reported_fact_id as lineage_root_reported_fact_id,
            review.review_decision_id as effective_review_decision_id,
            review.decision as effective_decision,
            review.decided_at as effective_decided_at
        from cutoff_eligible_facts as eligible
        join reported.reported_facts as fact
            on fact.reported_fact_id = eligible.reported_fact_id
        join audit.effective_review_decisions_as_of(cutoff) as review
            on review.reported_fact_id = fact.reported_fact_id
            and review.decision = 'ACCEPT'
        join serving.reported_fact_revision_ancestry as root_link
            on root_link.reported_fact_id = fact.reported_fact_id
        join reported.reported_facts as root_fact
            on root_fact.reported_fact_id = root_link.ancestor_reported_fact_id
            and root_fact.predecessor_reported_fact_id is null
    ),
    frontier as (
        select
            accepted.reported_fact_id,
            accepted.lineage_root_reported_fact_id,
            accepted.effective_review_decision_id,
            accepted.effective_decision,
            accepted.effective_decided_at
        from accepted
        where not exists (
            select 1
            from accepted as accepted_descendant
            join cutoff_eligible_facts as eligible_descendant
                on eligible_descendant.reported_fact_id
                    = accepted_descendant.reported_fact_id
            join serving.reported_fact_revision_ancestry as descendant_link
                on descendant_link.reported_fact_id
                    = accepted_descendant.reported_fact_id
                and descendant_link.ancestor_reported_fact_id
                    = accepted.reported_fact_id
                and descendant_link.generations > 0
        )
    ),
    sole_frontier as (
        select frontier.lineage_root_reported_fact_id
        from frontier
        group by frontier.lineage_root_reported_fact_id
        having count(*) = 1
    )
    select
        frontier.lineage_root_reported_fact_id,
        fact.reported_fact_id,
        fact.regulatory_registration_id,
        fact.regulator_id,
        fact.regulatory_concept_id,
        fact.source_id,
        fact.reporting_scope_id,
        fact.source_artifact_id,
        fact.source_release_id,
        fact.ingestion_run_id,
        fact.source_definition_version,
        fact.parser_implementation_key,
        fact.parser_implementation_version,
        fact.identity_definition_hash,
        fact.period_kind,
        fact.period_start,
        fact.period_end,
        fact.unit_code,
        fact.dimensions,
        fact.raw_value,
        fact.parsed_value,
        fact.raw_label,
        fact.locator_kind,
        fact.source_locator,
        fact.locator_hash,
        fact.fact_key_hash,
        fact.first_observed_at,
        fact.predecessor_reported_fact_id,
        fact.supersession_reason,
        frontier.effective_review_decision_id,
        frontier.effective_decision,
        frontier.effective_decided_at
    from frontier
    join sole_frontier
        on sole_frontier.lineage_root_reported_fact_id
            = frontier.lineage_root_reported_fact_id
    join reported.reported_facts as fact
        on fact.reported_fact_id = frontier.reported_fact_id;
$$;

revoke all privileges
on serving.reported_fact_revision_ancestry,
    serving.current_observed_facts,
    serving.current_publishable_facts
from public, anon, authenticated, service_role;

revoke all privileges
on function serving.observed_facts_as_of(timestamptz),
    serving.publishable_facts_as_of(timestamptz)
from public, anon, authenticated, service_role;

grant select
on serving.reported_fact_revision_ancestry,
    serving.current_observed_facts,
    serving.current_publishable_facts
to service_role;

grant execute
on function serving.observed_facts_as_of(timestamptz),
    serving.publishable_facts_as_of(timestamptz)
to service_role;

commit;
