# ADR 0010: CNBV release discovery and identity

- Status: Accepted
- Date: 2026-10-03

## Context

PR19 discovers releases of the `cnbv_portfolio` Serie Histórica for banca múltiple (sector 40)
without parsing facts. The PR19 design evidence, gathered by read-only requests to official CNBV
hosts, shows that:

- the post-IFRS9 Serie Histórica is published through an interactive report whose downloads are
  fixed files under
  `https://portafolioinfdoctos.cnbv.gob.mx/Documentacion/minfo/CSV/series_historicas/BM/`;
- the files are cumulative and overwritten in place at the same URL;
- CNBV exposes no enumerable release index, no official revision label, and no machine-readable
  publication time for those files;
- the catalogs and the data archive are updated at different times, so a package can be
  observed mid-update;
- the directory listing is forbidden, and the only machine path to the file links is an
  undocumented report API outside CNBV's domain.

The PR11 evidence catalog stores append-only source releases keyed by
`(source_id, release_family_key, release_identity_hash)`, with nullable `revision`,
`published_at`, and covered period, and same-family supersession. The PR13 audit lifecycle
records per-artifact `new`, `reused`, `revised`, and `failed` results, requires `revised` to
belong to a superseding release, and forbids `new` on one. Rows written later by PR21 are
permanent, so the identity and supersession meaning must be frozen before any row exists.

## Decision

### Discovery authority

Git/YAML artifact URLs are the editorial discovery authority. `config/sources.yml` declares, for
`cnbv_portfolio`, exactly three `artifact` endpoints with these roles and formats:

- `historical_series_data`: `zip` (`sh_datos_csv_40.zip`);
- `concept_catalog`: `csv` (`cat_conceptos_40.csv`);
- `institution_catalog`: `csv` (`cat_instituciones_40.csv`).

Discovery observes those configured official URLs. It does not crawl the landing page, scrape
the interactive report, call its API, or automate a browser. The landing page stays in YAML as
human provenance only.

XLSX is excluded from the required package. The `sh_data_export_40.xlsx` export, the notes
document, and the manual are not required artifacts and do not participate in identity.

### Release semantics

For `cnbv_portfolio`, a source release identity represents an exact observed snapshot of the
required cumulative artifact set `historical_series_data`, `concept_catalog`, and
`institution_catalog`.

A release identity does not assert that CNBV published the artifacts atomically, assigned a
release or revision identifier, or changed them simultaneously, and it does not make the snapshot
fit for fact publication. A mixed snapshot observed during a staggered CNBV update is still exact
evidence of what MONITOR observed and is classified with no special case.

The release family key is `serie_historica_banca_multiple_40`, a fixed cumulative family.

### Release identity

Release identity is the SHA-256 of canonical JSON over the identity scheme, source code, release
family key, a null revision, and the exact `(artifact_role, sha256)` pairs sorted by role.

- The identity scheme is `cnbv_portfolio.observed_artifact_set.v1`.
- The canonical payload is
  `{"identity_scheme", "source_code", "release_family_key", "revision": null,
  "artifacts": [{"role", "sha256"}, ...]}`, with artifacts sorted by role.
- It is serialized with `json.dumps(..., sort_keys=True, separators=(",", ":"),
  ensure_ascii=True)`, encoded as UTF-8, and hashed to lowercase hexadecimal SHA-256.

URLs, filenames, MIME types, HTTP headers, observation times, storage locations, and source
narrative text never participate in release identity. Byte length, the covered period, and the
source `definition_version` do not participate either.

`revision`, `published_at`, and the covered period remain NULL unless the regulator explicitly
exposes them; they are never inferred. In PR19 all three remain NULL.

### Classification and supersession

Classification is a pure function of the observed release and the complete caller-supplied
prior state of its family.

- With no prior release, the release is a first release and every role is `new`.
- When the observed identity equals the unique head, the release is unchanged and every role is
  `reused`.
- Otherwise the release is revised. Each role whose SHA-256 differs from the head is `revised`;
  each unchanged role is `reused`.

A new identity supersedes only the unique head of its release family; multiple heads,
reappearance of a superseded identity, or a changed role set fail closed. A lineage cycle, a
disconnected or dangling lineage, a stored identity that does not match its artifact set, and a
source or family mismatch also fail closed with `release_lineage_ambiguous`. No hidden winner is
ever chosen.

An A → B → A sequence fails closed under the current immutable identity and schema contract.
Identity A already exists as a superseded release, the catalog is unique on the identity hash,
and a release cannot be re-pointed or duplicated. Supporting regulator rollbacks requires a
future reviewed contract.

### Source lifecycle

PR19 performs no lifecycle or production-eligibility interpretation; that belongs to the
definitions publisher and orchestrator. The PR19 adapter does not read `lifecycle`, and adapter
construction does not mean the definition is approved for production ingestion.
`cnbv_portfolio` remains `draft`.

### Error taxonomy

Retrieval failures (transport, TLS, HTTP status, redirect, encoding, size) are distinct from
artifact content validation failures. Discovery errors fall into three branches: contract and
lineage errors, retrieval errors, and artifact content errors. None of them subclasses the legacy
`InvalidArtifactError`. Every code is snake_case and at most 64 characters, and every safe
summary is at most 512 characters with no control characters, matching the PR13 audit
constraints.

### Frozen retrieval requirements for the HTTP phase

These requirements are frozen now and implemented in a later PR19 phase:

- Automatic redirect following is forbidden for authority-sensitive CNBV retrieval; every
  request target must pass the CNBV authority policy before it is contacted. The policy is
  `https`, host exactly `portafolioinfdoctos.cnbv.gob.mx`, no userinfo, effective port 443, and
  empty query and fragment. A redirect to an unauthorized target raises
  `artifact_url_unofficial` before that target is contacted.
- Content-Encoding must be absent or identity; any other encoding fails closed until a reviewed
  contract supports it. Content-Length is compared with the received bytes only on the identity
  path.
- TLS verification is never disabled; trust is certifi plus one reviewed, pinned public
  intermediate.

### Ownership boundaries

- PR19 performs no database persistence and inserts no evidence or audit rows.
- PR19 makes no ArtifactStore calls.
- PR20 owns parsing, including periods, institutions, concepts, values, and the covered period.
- PR21 owns persistence and publication eligibility.
- Before facts from an observed snapshot are automatically accepted or published, PR21 must
  define and prove package consistency and publication eligibility. PR19 defines no quiet window
  and no consistency rule.

## Invariants

- A release is the exact observed required artifact set, not an assertion of atomic CNBV
  publication.
- Identity is content identity over role and SHA-256 pairs under
  `cnbv_portfolio.observed_artifact_set.v1`.
- Observation metadata never changes identity.
- `revision`, `published_at`, and the covered period are never inferred.
- Supersession targets only the unique head; every ambiguity fails closed.
- Discovery models hold no database identifiers, institution identifiers, concept identifiers,
  financial values, or mutable containers.

## Consequences

Repeated observation of unchanged bytes yields the same identity and an unchanged
classification, so PR21 can record a no-change run. Any byte change in any required artifact
yields a new identity that supersedes the head, with per-role `revised` and `reused` results
that satisfy the PR13 trigger. A CNBV URL move surfaces as a not-found, HTML, or layout failure
rather than as a silent change. Re-verifying the URLs then follows a manual procedure: a
reviewer confirms the new official links from the CNBV Serie Histórica report and changes
`config/sources.yml` through a reviewed PR. A regulator rollback to earlier bytes, or a CNBV
certificate renewal under a different intermediate, fails closed until a reviewed change lands.

## Rejected alternatives

- Identity from ETag, Last-Modified, report refresh text, URL, or filename.
- Synthesizing a revision label or a publication date from observation time or report text.
- Scraping the interactive report API, automating a browser, or crawling the landing page.
- Including the XLSX export in the required package.
- Treating an observed snapshot as an atomic publication or as automatically publishable.
- Selecting a winner among several heads by time or identifier.
- Re-pointing supersession or reusing a superseded identity for an A → B → A sequence.
- Interpreting source lifecycle inside the PR19 adapter.
- Persisting releases or calling the ArtifactStore in PR19.
