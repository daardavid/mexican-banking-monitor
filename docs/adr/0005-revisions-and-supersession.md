# ADR 0005: Reported-fact revisions and supersession

- Status: Accepted
- Date: 2026-08-27

## Context

Regulators revise publications, parsers are corrected, and identity resolution can improve. These
changes must preserve the original reported payload and explain why a successor exists without
confusing succession with review acceptance.

## Decision

A reported-fact successor uses exactly one of these reasons:

- `SOURCE_REVISION`: a new or revised official release, artifact, or other official evidence changes
  the reported result;
- `EXTRACTION_CORRECTION`: the same evidence/artifact is reprocessed by a corrected parser or config
  and produces a different result;
- `IDENTITY_CORRECTION`: MONITOR corrects institution or regulatory-registration resolution for the
  same evidence/locator.

`METHODOLOGY_CORRECTION` is invalid for reported facts. A methodological change creates a new
mapping version or metric-definition version and never rewrites a reported fact.

Reported-fact identity includes regulatory registration, regulatory concept, economic period,
reporting scope, currency, unit, and dimensions.

For the same artifact and a new parser/config:

- the same result creates no fact and records an audited no-change reprocessing outcome;
- a different result creates an `EXTRACTION_CORRECTION`, a quality issue, and requires review;
- the same parser version producing a different result is a determinism blocker.

## Invariants

- A fact without a predecessor has no supersession reason; a fact with a predecessor must have one.
- `SOURCE_REVISION` requires new or revised official evidence, release, or artifact.
- `EXTRACTION_CORRECTION` retains the same artifact and identifies the corrected parser/config.
- `IDENTITY_CORRECTION` identifies the corrected institution/registration resolution.
- Supersession chains are acyclic.
- Supersession explains a correction; a separate effective review decision controls
  publicability.
- A pending or rejected successor does not displace the last accepted publishable fact.

## Consequences

Reprocessing is idempotent when output is unchanged. Changed output remains fully traceable to old
and new provenance, and methodology evolves independently from immutable source reporting.

## Rejected alternatives

- An unrestricted reason string: it prevents deterministic validation and audit grouping.
- Encoding methodology changes as reported-fact corrections: it alters what the source reported.
- Treating every reparse as a new fact: it creates duplicates without new information.
- Treating supersession as automatic acceptance: it could replace reviewed data with ambiguity.
