# ADR 0004: Temporal and review semantics

- Status: Accepted
- Date: 2026-08-27

## Context

A fact can describe one period, be published by its source later, be discovered by MONITOR later
still, and receive a review decision at another time. Collapsing these events into one timestamp or
one ambiguous `current` view makes revisions, audit, and historical analysis incorrect.

## Decision

V1 keeps four distinct temporal concepts:

1. **Economic time** is the instant or duration represented by a fact. An instant stock has
   `period_end` and does not fabricate `period_start`; a flow or YTD fact has an explicit
   `period_start`/`period_end` range.
2. **Published time** is the source-reported `published_at`. It is nullable when it cannot be
   verified and is never inferred from retrieval or observation time.
3. **Observed time** is immutable `first_observed_at`, when MONITOR first obtained the evidence or
   fact.
4. **Review decision time** is `decided_at`, when MONITOR accepts, rejects, or revokes acceptance.

`audit.review_decisions` is append-only. Its decision vocabulary is `ACCEPT`, `REJECT`, and
`REVOKE`; its actor vocabulary is `HUMAN` and `SYSTEM_POLICY`. Correcting a decision creates a new
event linked to the preceding decision. A mutable fact status is never review authority.

`needs_review` is derived from the absence of an effective acceptance together with relevant
quality issues; it is not a mutable fact boolean. A versioned system policy may accept an
unambiguous clean fact. Ambiguity never auto-accepts.

Internal APIs must distinguish `current_observed` from `current_publishable` and may not expose an
unqualified `current`. Serving and dashboard uses of `current` mean publishable. The as-of contracts
are `observed_as_of(cutoff)` and `publishable_as_of(cutoff)`.

```text
10-Jul: revision B is observed and pending; accepted revision A remains publishable.
12-Jul: observed_as_of = B; publishable_as_of = A.
14-Jul: B receives ACCEPT.
15-Jul: observed_as_of = B; publishable_as_of = B.
```

Calculation time cannot impersonate historical execution. Backtests preserve both
`knowledge_cutoff_at` and actual `calculated_at`.

## Invariants

- An unaccepted or rejected successor does not displace the last effectively accepted publishable
  fact.
- Observation does not imply publication, acceptance, or source publication time.
- Rejection or revocation is represented by a decision event, never a destructive fact update.
- As-of results use only observations and decisions effective by their cutoff.

## Consequences

Serving contracts and repositories must name the observed or publishable interpretation explicitly.
Review corrections retain their full audit history, and reproducible backtests distinguish what was
known from when a calculation actually ran.

## Rejected alternatives

- One `current` view: it silently confuses recency with publicability.
- Inferring `published_at`: retrieval cannot prove when the regulator published an item.
- Mutable reviewed/accepted flags: they erase decision history and actor provenance.
- Treating a later calculation as a historical run: it misstates execution history.
