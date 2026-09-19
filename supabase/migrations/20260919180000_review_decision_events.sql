begin;

set local search_path = public, extensions, pg_catalog;

create table audit.review_decisions (
    review_decision_id bigint generated always as identity primary key,
    reported_fact_id bigint not null,
    decision text not null,
    decided_at timestamptz not null,
    actor_kind text not null,
    human_actor_key text,
    policy_implementation_key text,
    policy_implementation_version text,
    policy_git_sha text,
    reason text not null,
    corrects_review_decision_id bigint,
    constraint review_decisions_fact_fkey
        foreign key (reported_fact_id)
        references reported.reported_facts (reported_fact_id),
    constraint review_decisions_id_fact_key
        unique (review_decision_id, reported_fact_id),
    constraint review_decisions_correction_fkey
        foreign key (corrects_review_decision_id, reported_fact_id)
        references audit.review_decisions (
            review_decision_id,
            reported_fact_id
        ),
    constraint review_decisions_decision_valid
        check (decision in ('ACCEPT', 'REJECT', 'REVOKE')),
    constraint review_decisions_actor_kind_valid
        check (actor_kind in ('HUMAN', 'SYSTEM_POLICY')),
    constraint review_decisions_actor_shape_valid
        check (
            (
                actor_kind = 'HUMAN'
                and human_actor_key is not null
                and policy_implementation_key is null
                and policy_implementation_version is null
                and policy_git_sha is null
            )
            or
            (
                actor_kind = 'SYSTEM_POLICY'
                and human_actor_key is null
                and policy_implementation_key is not null
                and policy_implementation_version is not null
                and policy_git_sha is not null
            )
        ),
    constraint review_decisions_human_actor_key_valid
        check (
            human_actor_key is null
            or (
                char_length(human_actor_key) <= 128
                and human_actor_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
            )
        ),
    constraint review_decisions_policy_key_valid
        check (
            policy_implementation_key is null
            or (
                char_length(policy_implementation_key) <= 128
                and policy_implementation_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
            )
        ),
    constraint review_decisions_policy_version_valid
        check (
            policy_implementation_version is null
            or (
                char_length(policy_implementation_version) <= 128
                and btrim(policy_implementation_version) <> ''
            )
        ),
    constraint review_decisions_policy_git_sha_full
        check (
            policy_git_sha is null
            or policy_git_sha ~ '^(?:[a-f0-9]{40}|[a-f0-9]{64})$'
        ),
    constraint review_decisions_reason_valid
        check (
            btrim(reason) <> ''
            and char_length(reason) <= 512
            and reason !~ '[[:cntrl:]]'
        ),
    constraint review_decisions_no_self_correction
        check (
            corrects_review_decision_id is null
            or corrects_review_decision_id <> review_decision_id
        )
);

create function audit.enforce_review_decision_insert()
returns trigger
language plpgsql
as $$
declare
    head_review_decision_id bigint;
    head_decided_at timestamptz;
    head_decision text;
begin
    if new.decided_at > pg_catalog.clock_timestamp() then
        raise exception 'review decision cannot be decided in the future';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(new.reported_fact_id);

    select
        head.review_decision_id,
        head.decided_at,
        head.decision
    into
        head_review_decision_id,
        head_decided_at,
        head_decision
    from audit.review_decisions as head
    where head.reported_fact_id = new.reported_fact_id
    order by head.decided_at desc, head.review_decision_id desc
    limit 1;

    if head_review_decision_id is not null
        and (new.decided_at, new.review_decision_id)
            <= (head_decided_at, head_review_decision_id)
    then
        raise exception
            'review decision must extend the fact timeline strictly after the head event';
    end if;

    if new.decision = 'REVOKE' and head_decision is distinct from 'ACCEPT' then
        raise exception 'REVOKE requires an effective ACCEPT head event';
    end if;

    return new;
end;
$$;

create trigger review_decisions_enforce_insert
before insert on audit.review_decisions
for each row execute function audit.enforce_review_decision_insert();

create function audit.reject_review_decision_mutation()
returns trigger
language plpgsql
as $$
begin
    raise exception 'review decisions are append-only';
end;
$$;

create trigger review_decisions_append_only
before update or delete on audit.review_decisions
for each row execute function audit.reject_review_decision_mutation();

create view audit.effective_review_decisions
with (security_invoker = true) as
select distinct on (decision_event.reported_fact_id)
    decision_event.reported_fact_id,
    decision_event.review_decision_id,
    decision_event.decision,
    decision_event.decided_at
from audit.review_decisions as decision_event
order by
    decision_event.reported_fact_id,
    decision_event.decided_at desc,
    decision_event.review_decision_id desc;

create function audit.effective_review_decisions_as_of(decision_cutoff timestamptz)
returns table (
    reported_fact_id bigint,
    review_decision_id bigint,
    decision text,
    decided_at timestamptz
)
language sql
stable
as $$
    select distinct on (decision_event.reported_fact_id)
        decision_event.reported_fact_id,
        decision_event.review_decision_id,
        decision_event.decision,
        decision_event.decided_at
    from audit.review_decisions as decision_event
    where decision_event.decided_at <= decision_cutoff
    order by
        decision_event.reported_fact_id,
        decision_event.decided_at desc,
        decision_event.review_decision_id desc;
$$;

create index review_decisions_fact_timeline_idx
    on audit.review_decisions (
        reported_fact_id,
        decided_at desc,
        review_decision_id desc
    );

create index review_decisions_corrects_idx
    on audit.review_decisions (corrects_review_decision_id)
    where corrects_review_decision_id is not null;

alter table audit.review_decisions enable row level security;

revoke all privileges
on audit.review_decisions
from public, anon, authenticated, service_role;

revoke all privileges
on sequence audit.review_decisions_review_decision_id_seq
from public, anon, authenticated, service_role;

revoke all privileges
on audit.effective_review_decisions
from public, anon, authenticated, service_role;

revoke all privileges
on function audit.enforce_review_decision_insert(),
            audit.reject_review_decision_mutation()
from public, anon, authenticated, service_role;

revoke all privileges
on function audit.effective_review_decisions_as_of(timestamptz)
from public, anon, authenticated, service_role;

grant select on audit.review_decisions to service_role;

grant insert (
    reported_fact_id,
    decision,
    decided_at,
    actor_kind,
    human_actor_key,
    policy_implementation_key,
    policy_implementation_version,
    policy_git_sha,
    reason,
    corrects_review_decision_id
)
on audit.review_decisions to service_role;

grant usage
on sequence audit.review_decisions_review_decision_id_seq
to service_role;

grant select on audit.effective_review_decisions to service_role;

grant execute
on function audit.effective_review_decisions_as_of(timestamptz)
to service_role;

commit;
