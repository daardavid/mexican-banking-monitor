from __future__ import annotations

import ast
import dataclasses
import json
import re
from collections.abc import Iterable, Iterator
from datetime import UTC, date, datetime, timedelta
from hashlib import sha256
from pathlib import Path
from typing import Any

import pytest

from mx_bank_monitor.config.models import SourceFormat
from mx_bank_monitor.ingestion import discovery
from mx_bank_monitor.ingestion.artifacts import ArtifactPayload
from mx_bank_monitor.ingestion.discovery import (
    ArtifactClassification,
    ArtifactContentEncodingError,
    ArtifactContentError,
    ArtifactHttpStatusError,
    ArtifactLengthMismatchError,
    ArtifactMetadata,
    ArtifactNotFoundHttpError,
    ArtifactObservationResult,
    ArtifactRedirectError,
    ArtifactRetrievalError,
    ArtifactSignatureError,
    ArtifactTlsUntrustedError,
    ArtifactTooLargeError,
    ArtifactTransportError,
    CatalogedRelease,
    ContractError,
    CsvTextStructure,
    DiscoveredArtifact,
    DiscoveredRelease,
    DiscoveryError,
    EmptyArtifactError,
    HtmlArtifactError,
    HttpObservation,
    ObservedRelease,
    PriorFamilyState,
    ReleaseChange,
    ReleaseClassification,
    ReleaseLineageAmbiguousError,
    ReleaseMetadata,
    SourceContractError,
    SourceLayoutDriftError,
    UnexpectedMediaTypeError,
    UnofficialArtifactUrlError,
    ValidatedArtifact,
    ZipMemberStructure,
    artifact_set_identity_hash,
    classify_release,
    release_identity_hash,
)
from mx_bank_monitor.ingestion.http import InvalidArtifactError

SOURCE_CODE = "cnbv_portfolio"
IDENTITY_SCHEME = "cnbv_portfolio.observed_artifact_set.v1"
FAMILY = "serie_historica_banca_multiple_40"
OBSERVED_AT = datetime(2026, 10, 4, 12, 0, tzinfo=UTC)
OFFICIAL_BASE = (
    "https://portafolioinfdoctos.cnbv.gob.mx/Documentacion/minfo/CSV/series_historicas/BM/"
)
FORMATS = {
    "concept_catalog": SourceFormat.CSV,
    "historical_series_data": SourceFormat.ZIP,
    "institution_catalog": SourceFormat.CSV,
}
FILENAMES = {
    "concept_catalog": "cat_conceptos_40.csv",
    "historical_series_data": "sh_datos_csv_40.zip",
    "institution_catalog": "cat_instituciones_40.csv",
}
CONTENT = {
    "concept_catalog": b"synthetic concept catalog v1",
    "historical_series_data": b"PK\x03\x04synthetic historical series v1",
    "institution_catalog": b"synthetic institution catalog v1",
}
FIXED_SHA_PAIRS = (
    ("concept_catalog", "a" * 64),
    ("historical_series_data", "b" * 64),
    ("institution_catalog", "c" * 64),
)
GOLDEN_FIXED_SHA_IDENTITY = "46e49ef8f926386871ea34c0234559f3bd51940f5fd45580a0c7040774966fa3"
GOLDEN_SYNTHETIC_CONTENT_IDENTITY = (
    "96dfc272835e3fc5943794b067d68342458e09631c36c4bc69d9d03b19f9ec7e"
)
AUDIT_ERROR_CODE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
CONTROL_CHARACTERS = re.compile("[\x00-\x1f\x7f-\x9f\u2028\u2029]")


def _identity(
    pairs: Iterable[tuple[str, str]],
    *,
    scheme: str = IDENTITY_SCHEME,
    source_code: str = SOURCE_CODE,
    family: str = FAMILY,
    revision: str | None = None,
) -> str:
    return artifact_set_identity_hash(
        identity_scheme=scheme,
        source_code=source_code,
        release_family_key=family,
        revision=revision,
        artifact_sha256_by_role=pairs,
    )


def _discovered(
    *,
    source_code: str = SOURCE_CODE,
    family: str = FAMILY,
    scheme: str = IDENTITY_SCHEME,
    version: int = 1,
    base_url: str = OFFICIAL_BASE,
    roles: tuple[str, ...] = tuple(FORMATS),
) -> DiscoveredRelease:
    return DiscoveredRelease(
        source_code=source_code,
        source_definition_version=version,
        release_family_key=family,
        identity_scheme=scheme,
        artifacts=tuple(
            DiscoveredArtifact(
                artifact_role=role,
                artifact_format=FORMATS.get(role, SourceFormat.CSV),
                original_url=base_url + FILENAMES.get(role, f"{role}.csv"),
            )
            for role in sorted(roles)
        ),
    )


def _structure(artifact_format: SourceFormat) -> ZipMemberStructure | CsvTextStructure:
    if artifact_format == SourceFormat.ZIP:
        return ZipMemberStructure(
            member_name="sh_datos_40.csv",
            member_uncompressed_size=584_795_606,
            header_sha256="d" * 64,
        )
    return CsvTextStructure(header_sha256="e" * 64, has_bom=False, line_terminator="crlf")


def _artifact(
    role: str,
    content: bytes,
    *,
    base_url: str = OFFICIAL_BASE,
    filename: str | None = None,
    observed_at: datetime = OBSERVED_AT,
    mime_type: str = "application/octet-stream",
    etag: str | None = '"765443abfe36dd1:0"',
    last_modified: str | None = "Thu, 27 Aug 2026 21:05:00 GMT",
) -> ValidatedArtifact:
    artifact_format = FORMATS.get(role, SourceFormat.CSV)
    url = base_url + FILENAMES.get(role, f"{role}.csv")
    return ValidatedArtifact(
        artifact_role=role,
        artifact_format=artifact_format,
        filename=filename or FILENAMES.get(role, f"{role}.csv"),
        catalog_mime_type=mime_type,
        sha256=sha256(content).hexdigest(),
        byte_length=len(content),
        content=content,
        http=HttpObservation(
            requested_url=url,
            final_url=url,
            redirect_chain=(),
            status_code=200,
            content_type=mime_type,
            content_length=len(content),
            content_encoding=None,
            etag=etag,
            last_modified=last_modified,
            content_disposition=None,
            observed_at=observed_at,
        ),
        structure=_structure(artifact_format),
    )


def _observe(
    content: dict[str, bytes] | None = None,
    *,
    discovered: DiscoveredRelease | None = None,
    **artifact_options: Any,
) -> ObservedRelease:
    selected = CONTENT if content is None else content
    return ObservedRelease.from_validated_artifacts(
        discovered or _discovered(roles=tuple(selected)),
        [_artifact(role, payload, **artifact_options) for role, payload in selected.items()],
    )


def _changed(**updates: bytes) -> dict[str, bytes]:
    return {**CONTENT, **updates}


def _cataloged(
    content: dict[str, bytes],
    supersedes: CatalogedRelease | None = None,
    *,
    source_code: str = SOURCE_CODE,
    family: str = FAMILY,
    scheme: str = IDENTITY_SCHEME,
) -> CatalogedRelease:
    pairs = tuple(sorted((role, sha256(payload).hexdigest()) for role, payload in content.items()))
    return CatalogedRelease(
        release_identity_hash=_identity(
            pairs, scheme=scheme, source_code=source_code, family=family
        ),
        supersedes_release_identity_hash=(
            supersedes.release_identity_hash if supersedes is not None else None
        ),
        artifact_sha256_by_role=pairs,
    )


def _prior(*releases: CatalogedRelease) -> PriorFamilyState:
    return PriorFamilyState(source_code=SOURCE_CODE, release_family_key=FAMILY, releases=releases)


def _results(classification: ReleaseClassification) -> dict[str, ArtifactObservationResult]:
    return {item.artifact_role: item.result for item in classification.artifacts}


# Identity


def test_canonical_identity_payload_matches_the_frozen_serialization() -> None:
    expected_payload = (
        '{"artifacts":['
        '{"role":"concept_catalog","sha256":"' + "a" * 64 + '"},'
        '{"role":"historical_series_data","sha256":"' + "b" * 64 + '"},'
        '{"role":"institution_catalog","sha256":"' + "c" * 64 + '"}],'
        '"identity_scheme":"cnbv_portfolio.observed_artifact_set.v1",'
        '"release_family_key":"serie_historica_banca_multiple_40",'
        '"revision":null,'
        '"source_code":"cnbv_portfolio"}'
    )

    identity = artifact_set_identity_hash(
        identity_scheme="cnbv_portfolio.observed_artifact_set.v1",
        source_code="cnbv_portfolio",
        release_family_key="serie_historica_banca_multiple_40",
        revision=None,
        artifact_sha256_by_role=FIXED_SHA_PAIRS,
    )

    assert sha256(expected_payload.encode("utf-8")).hexdigest() == GOLDEN_FIXED_SHA_IDENTITY
    assert identity == GOLDEN_FIXED_SHA_IDENTITY


def test_identical_observations_produce_the_identical_golden_hash() -> None:
    first = _observe()
    second = _observe()

    assert first.release_identity_hash == GOLDEN_SYNTHETIC_CONTENT_IDENTITY
    assert second.release_identity_hash == GOLDEN_SYNTHETIC_CONTENT_IDENTITY
    assert first == second


def test_role_ordering_does_not_change_the_hash() -> None:
    discovered = _discovered()
    artifacts = [_artifact(role, payload) for role, payload in CONTENT.items()]

    assert _identity(reversed(FIXED_SHA_PAIRS)) == GOLDEN_FIXED_SHA_IDENTITY
    assert release_identity_hash(discovered, artifacts) == release_identity_hash(
        discovered, list(reversed(artifacts))
    )
    assert (
        ObservedRelease.from_validated_artifacts(discovered, reversed(artifacts))
        == ObservedRelease.from_validated_artifacts(discovered, artifacts)
    )


def test_url_change_does_not_change_the_hash() -> None:
    other_base = "https://portafolioinfdoctos.cnbv.gob.mx/documentacion/MINFO/csv/BM/"
    moved = _observe(discovered=_discovered(base_url=other_base), base_url=other_base)

    assert moved.discovered != _observe().discovered
    assert moved.release_identity_hash == GOLDEN_SYNTHETIC_CONTENT_IDENTITY


def test_filename_change_does_not_change_the_hash() -> None:
    renamed = _observe(filename="renamed_artifact.bin")

    assert {item.filename for item in renamed.artifacts} == {"renamed_artifact.bin"}
    assert renamed.release_identity_hash == GOLDEN_SYNTHETIC_CONTENT_IDENTITY


def test_observation_time_does_not_change_the_hash() -> None:
    later = _observe(observed_at=OBSERVED_AT + timedelta(days=30))

    assert later.first_observed_at != _observe().first_observed_at
    assert later.release_identity_hash == GOLDEN_SYNTHETIC_CONTENT_IDENTITY


def test_source_definition_version_does_not_change_the_hash() -> None:
    reviewed = _observe(discovered=_discovered(version=2))

    assert reviewed.discovered.source_definition_version == 2
    assert reviewed.release_identity_hash == GOLDEN_SYNTHETIC_CONTENT_IDENTITY


def test_http_and_catalog_metadata_do_not_change_the_hash() -> None:
    varied = _observe(mime_type="application/zip", etag='"other:0"', last_modified=None)

    assert varied.release_identity_hash == GOLDEN_SYNTHETIC_CONTENT_IDENTITY


@pytest.mark.parametrize("role", sorted(CONTENT))
def test_changed_artifact_sha_changes_the_hash(role: str) -> None:
    changed = _observe(_changed(**{role: CONTENT[role] + b" revised"}))

    assert changed.release_identity_hash != GOLDEN_SYNTHETIC_CONTENT_IDENTITY


def test_changed_role_changes_the_hash_and_fails_the_discovered_role_contract() -> None:
    renamed_pairs = (("concept_catalog_v2", "a" * 64), *FIXED_SHA_PAIRS[1:])
    assert _identity(renamed_pairs) != GOLDEN_FIXED_SHA_IDENTITY

    artifacts = [_artifact(role, payload) for role, payload in CONTENT.items()]
    artifacts[0] = _artifact("concept_catalog_v2", CONTENT["concept_catalog"])
    with pytest.raises(SourceContractError, match="was not observed"):
        release_identity_hash(_discovered(), artifacts)
    with pytest.raises(SourceContractError, match="role outside the discovered release"):
        release_identity_hash(
            _discovered(),
            [*artifacts[1:], _artifact("concept_catalog", b"x"), artifacts[0]],
        )


def test_scheme_source_family_and_revision_participate_in_identity() -> None:
    assert _identity(FIXED_SHA_PAIRS, scheme="other_source.artifact_set.v1") != (
        GOLDEN_FIXED_SHA_IDENTITY
    )
    assert _identity(FIXED_SHA_PAIRS, source_code="other_source") != GOLDEN_FIXED_SHA_IDENTITY
    assert _identity(FIXED_SHA_PAIRS, family="other_family") != GOLDEN_FIXED_SHA_IDENTITY
    assert _identity(FIXED_SHA_PAIRS, revision="r1") != GOLDEN_FIXED_SHA_IDENTITY


def test_identity_rejects_duplicate_roles_and_malformed_digests() -> None:
    with pytest.raises(SourceContractError, match="unique and sorted"):
        _identity((("concept_catalog", "a" * 64), ("concept_catalog", "b" * 64)))
    with pytest.raises(SourceContractError, match="lowercase hexadecimal SHA-256"):
        _identity((("concept_catalog", "A" * 64),))
    with pytest.raises(SourceContractError, match="at least one artifact role"):
        _identity(())


@pytest.mark.parametrize(
    "scheme", ["", " ", "noversion", "Upper.scheme.v1", "a..b", "a.b.", "a.b\n", "a." + "b" * 128]
)
def test_identity_scheme_must_be_safe_and_nonblank(scheme: str) -> None:
    with pytest.raises(SourceContractError, match="identity_scheme"):
        _identity(FIXED_SHA_PAIRS, scheme=scheme)
    with pytest.raises(SourceContractError, match="identity_scheme"):
        _discovered(scheme=scheme)


@pytest.mark.parametrize("revision", ["", "  "])
def test_identity_rejects_blank_revision(revision: str) -> None:
    with pytest.raises(SourceContractError, match="revision must be null or non-blank"):
        _identity(FIXED_SHA_PAIRS, revision=revision)


def test_revision_published_at_and_covered_period_remain_none() -> None:
    observed = _observe()

    assert observed.discovered.revision is None
    assert observed.discovered.published_at is None
    assert observed.discovered.covered_period_start is None
    assert observed.discovered.covered_period_end is None

    base = _discovered()
    for field_name, value in (
        ("revision", "2026-06"),
        ("published_at", OBSERVED_AT),
        ("covered_period_start", date(2000, 12, 31)),
        ("covered_period_end", date(2026, 7, 31)),
    ):
        with pytest.raises(SourceContractError, match="must not be inferred"):
            dataclasses.replace(base, **{field_name: value})


def test_validated_artifact_identity_matches_the_artifact_store_payload() -> None:
    for role, payload in CONTENT.items():
        artifact = _artifact(role, payload)
        stored = ArtifactPayload.from_bytes(payload)

        assert (artifact.sha256, artifact.byte_length) == (stored.sha256, stored.byte_length)


def test_validated_artifact_rejects_inconsistent_or_empty_bytes() -> None:
    artifact = _artifact("concept_catalog", CONTENT["concept_catalog"])

    with pytest.raises(SourceContractError, match="does not match its exact bytes"):
        dataclasses.replace(artifact, sha256="0" * 64)
    with pytest.raises(SourceContractError, match="does not match its exact bytes"):
        dataclasses.replace(artifact, byte_length=artifact.byte_length + 1)
    with pytest.raises(EmptyArtifactError):
        dataclasses.replace(artifact, content=b"", byte_length=0, sha256=sha256(b"").hexdigest())
    with pytest.raises(SourceContractError, match="frozen structure type"):
        dataclasses.replace(artifact, structure=_structure(SourceFormat.ZIP))


def test_observed_release_rejects_derived_field_tampering() -> None:
    observed = _observe()

    with pytest.raises(SourceContractError, match="release_identity_hash does not match"):
        dataclasses.replace(observed, release_identity_hash="0" * 64)
    with pytest.raises(SourceContractError, match="first_observed_at"):
        dataclasses.replace(observed, first_observed_at=OBSERVED_AT - timedelta(seconds=1))
    partial_metadata = dataclasses.replace(
        observed.metadata, artifacts=observed.metadata.artifacts[:2]
    )
    with pytest.raises(SourceContractError, match="metadata does not match"):
        dataclasses.replace(observed, metadata=partial_metadata)


def test_discovered_release_requires_sorted_unique_roles() -> None:
    artifacts = _discovered().artifacts

    with pytest.raises(SourceContractError, match="unique and sorted"):
        dataclasses.replace(_discovered(), artifacts=tuple(reversed(artifacts)))
    with pytest.raises(SourceContractError, match="unique and sorted"):
        dataclasses.replace(_discovered(), artifacts=(artifacts[0], artifacts[0]))
    with pytest.raises(SourceContractError, match="immutable tuple"):
        dataclasses.replace(_discovered(), artifacts=list(artifacts))


# Classification


def test_first_release_marks_every_role_new() -> None:
    observed = _observe()

    classification = classify_release(observed, _prior())

    assert classification.change == ReleaseChange.FIRST_RELEASE
    assert classification.release_identity_hash == observed.release_identity_hash
    assert classification.supersedes_release_identity_hash is None
    assert set(_results(classification).values()) == {ArtifactObservationResult.NEW}
    assert not any(item.content_changed for item in classification.artifacts)


def test_same_head_is_unchanged_and_every_role_reused() -> None:
    head = _cataloged(CONTENT)

    classification = classify_release(_observe(), _prior(head))

    assert classification.change == ReleaseChange.UNCHANGED
    assert classification.release_identity_hash == head.release_identity_hash
    assert classification.supersedes_release_identity_hash is None
    assert set(_results(classification).values()) == {ArtifactObservationResult.REUSED}


def test_one_changed_artifact_is_revised_and_others_reused() -> None:
    head = _cataloged(CONTENT)
    observed = _observe(_changed(concept_catalog=b"synthetic concept catalog v2"))

    classification = classify_release(observed, _prior(head))

    assert classification.change == ReleaseChange.REVISED
    assert classification.supersedes_release_identity_hash == head.release_identity_hash
    assert _results(classification) == {
        "concept_catalog": ArtifactObservationResult.REVISED,
        "historical_series_data": ArtifactObservationResult.REUSED,
        "institution_catalog": ArtifactObservationResult.REUSED,
    }
    assert [item.content_changed for item in classification.artifacts] == [True, False, False]


def test_multiple_changed_artifacts_are_each_revised() -> None:
    head = _cataloged(CONTENT)
    observed = _observe(
        _changed(
            historical_series_data=b"PK\x03\x04synthetic historical series v2",
            institution_catalog=b"synthetic institution catalog v2",
        )
    )

    classification = classify_release(observed, _prior(head))

    assert classification.change == ReleaseChange.REVISED
    assert _results(classification) == {
        "concept_catalog": ArtifactObservationResult.REUSED,
        "historical_series_data": ArtifactObservationResult.REVISED,
        "institution_catalog": ArtifactObservationResult.REVISED,
    }


def test_new_identity_supersedes_only_the_unique_head_of_a_chain() -> None:
    first = _cataloged(CONTENT)
    second = _cataloged(_changed(concept_catalog=b"concept v2"), first)
    third = _cataloged(_changed(concept_catalog=b"concept v3"), second)
    observed = _observe(_changed(concept_catalog=b"concept v3", institution_catalog=b"inst v2"))

    classification = classify_release(observed, _prior(second, third, first))

    assert classification.supersedes_release_identity_hash == third.release_identity_hash
    assert _results(classification) == {
        "concept_catalog": ArtifactObservationResult.REUSED,
        "historical_series_data": ArtifactObservationResult.REUSED,
        "institution_catalog": ArtifactObservationResult.REVISED,
    }
    assert classify_release(observed, _prior(second, third, first)) == classification


def test_several_heads_fail_closed() -> None:
    root = _cataloged(CONTENT)
    left = _cataloged(_changed(concept_catalog=b"left"), root)
    right = _cataloged(_changed(concept_catalog=b"right"), root)

    with pytest.raises(ReleaseLineageAmbiguousError, match="several heads"):
        classify_release(_observe(), _prior(root, left, right))
    with pytest.raises(ReleaseLineageAmbiguousError, match="several heads"):
        classify_release(_observe(), _prior(left, _cataloged(_changed(concept_catalog=b"x")), root))


def _cycle_pair() -> tuple[CatalogedRelease, CatalogedRelease]:
    first = _cataloged(_changed(concept_catalog=b"cycle one"))
    second = _cataloged(_changed(concept_catalog=b"cycle two"), first)
    return (
        dataclasses.replace(
            first, supersedes_release_identity_hash=second.release_identity_hash
        ),
        second,
    )


def test_lineage_cycles_fail_closed() -> None:
    first, second = _cycle_pair()
    with pytest.raises(ReleaseLineageAmbiguousError, match="no head"):
        classify_release(_observe(), _prior(first, second))

    head = _cataloged(_changed(concept_catalog=b"head"), first)
    with pytest.raises(ReleaseLineageAmbiguousError, match="cycle"):
        classify_release(_observe(), _prior(first, second, head))

    with pytest.raises(ReleaseLineageAmbiguousError, match="not one supersession chain"):
        classify_release(_observe(), _prior(_cataloged(CONTENT), first, second))


def test_superseded_identity_reappearing_fails_closed() -> None:
    release_a = _cataloged(CONTENT)
    release_b = _cataloged(_changed(concept_catalog=b"synthetic concept catalog v2"), release_a)

    with pytest.raises(ReleaseLineageAmbiguousError, match="previously superseded"):
        classify_release(_observe(CONTENT), _prior(release_a, release_b))


def test_source_mismatch_fails_closed() -> None:
    prior = PriorFamilyState(
        source_code="cnbv_bulletin",
        release_family_key=FAMILY,
        releases=(_cataloged(CONTENT, source_code="cnbv_bulletin"),),
    )

    with pytest.raises(ReleaseLineageAmbiguousError, match="different source"):
        classify_release(_observe(), prior)


def test_prior_identity_from_another_scheme_fails_closed() -> None:
    prior = _prior(_cataloged(CONTENT, scheme="other_source.artifact_set.v1"))

    with pytest.raises(ReleaseLineageAmbiguousError, match="under the identity scheme"):
        classify_release(_observe(), prior)


def test_family_mismatch_fails_closed() -> None:
    prior = PriorFamilyState(
        source_code=SOURCE_CODE, release_family_key="other_family", releases=()
    )

    with pytest.raises(ReleaseLineageAmbiguousError, match="different release family"):
        classify_release(_observe(), prior)


def test_role_set_mismatch_fails_closed() -> None:
    fewer_roles = {
        role: payload for role, payload in CONTENT.items() if role != "institution_catalog"
    }
    extra_roles = {**CONTENT, "notes_document": b"synthetic notes"}

    for head_content in (fewer_roles, extra_roles):
        with pytest.raises(ReleaseLineageAmbiguousError, match="roles differ"):
            classify_release(_observe(), _prior(_cataloged(head_content)))


def test_malformed_prior_state_fails_closed() -> None:
    head = _cataloged(CONTENT)
    dangling = _cataloged(_changed(concept_catalog=b"orphan"))
    dangling = dataclasses.replace(dangling, supersedes_release_identity_hash="f" * 64)

    with pytest.raises(ReleaseLineageAmbiguousError, match="outside the supplied family"):
        classify_release(_observe(), _prior(dangling))
    with pytest.raises(ReleaseLineageAmbiguousError, match="duplicate release identity"):
        _prior(head, head)
    with pytest.raises(ReleaseLineageAmbiguousError, match="does not match its artifact set"):
        classify_release(
            _observe(), _prior(dataclasses.replace(head, release_identity_hash="f" * 64))
        )
    with pytest.raises(ReleaseLineageAmbiguousError, match="immutable tuple"):
        PriorFamilyState(source_code=SOURCE_CODE, release_family_key=FAMILY, releases=[head])
    with pytest.raises(ReleaseLineageAmbiguousError, match="unique and sorted"):
        dataclasses.replace(
            head, artifact_sha256_by_role=tuple(reversed(head.artifact_sha256_by_role))
        )
    with pytest.raises(ReleaseLineageAmbiguousError, match="cannot supersede itself"):
        dataclasses.replace(head, supersedes_release_identity_hash=head.release_identity_hash)
    with pytest.raises(ReleaseLineageAmbiguousError, match=r"\(role, sha256\) tuples"):
        dataclasses.replace(head, artifact_sha256_by_role=(["concept_catalog", "a" * 64],))


def test_classification_invariants_match_the_audit_lifecycle() -> None:
    def artifact(result: ArtifactObservationResult, changed: bool) -> ArtifactClassification:
        return ArtifactClassification("concept_catalog", "a" * 64, result, changed)

    reused = artifact(ArtifactObservationResult.REUSED, False)
    revised = artifact(ArtifactObservationResult.REVISED, True)

    with pytest.raises(ReleaseLineageAmbiguousError, match="content_changed"):
        artifact(ArtifactObservationResult.REUSED, True)
    with pytest.raises(ReleaseLineageAmbiguousError, match="cannot be failed"):
        artifact(ArtifactObservationResult.FAILED, False)
    with pytest.raises(ReleaseLineageAmbiguousError, match="incompatible artifact result"):
        ReleaseClassification(ReleaseChange.FIRST_RELEASE, "b" * 64, None, (reused,))
    with pytest.raises(ReleaseLineageAmbiguousError, match="lowercase hexadecimal"):
        ReleaseClassification(ReleaseChange.REVISED, "b" * 64, None, (revised,))
    with pytest.raises(ReleaseLineageAmbiguousError, match="at least one artifact"):
        ReleaseClassification(ReleaseChange.REVISED, "b" * 64, "c" * 64, (reused,))
    with pytest.raises(ReleaseLineageAmbiguousError, match="cannot supersede a release"):
        ReleaseClassification(ReleaseChange.UNCHANGED, "b" * 64, "c" * 64, (reused,))


# Immutability


def _walk_values(value: object) -> Iterator[object]:
    yield value
    if dataclasses.is_dataclass(value) and not isinstance(value, type):
        for item in dataclasses.fields(value):
            yield from _walk_values(getattr(value, item.name))
    elif isinstance(value, tuple):
        for item in value:
            yield from _walk_values(item)


def test_models_retain_no_mutable_containers() -> None:
    observed = _observe()
    classification = classify_release(observed, _prior())
    prior = _prior(_cataloged(CONTENT))

    for root in (observed, classification, prior):
        for value in _walk_values(root):
            assert not isinstance(value, (dict, list, set, bytearray))


def test_frozen_models_cannot_be_mutated() -> None:
    observed = _observe()
    metadata = observed.metadata
    targets: tuple[tuple[object, str], ...] = (
        (metadata, "identity_scheme"),
        (metadata, "artifacts"),
        (metadata.artifacts[0], "byte_length"),
        (metadata.artifacts[0].structure, "header_sha256"),
        (metadata.artifacts[1].structure, "member_name"),
        (observed, "release_identity_hash"),
        (observed.discovered, "revision"),
        (observed.artifacts[0].http, "observed_at"),
    )

    for target, attribute in targets:
        with pytest.raises(dataclasses.FrozenInstanceError):
            setattr(target, attribute, "mutated")
    with pytest.raises((dataclasses.FrozenInstanceError, AttributeError, TypeError)):
        object.__setattr__(metadata, "extra", {})
    with pytest.raises(SourceContractError, match="immutable tuple"):
        dataclasses.replace(metadata, artifacts=list(metadata.artifacts))


def test_to_json_object_returns_an_independent_object_every_call() -> None:
    metadata = _observe().metadata
    first = metadata.to_json_object()
    second = metadata.to_json_object()

    assert first == second
    assert first is not second
    assert first["artifacts"] is not second["artifacts"]

    artifacts = first["artifacts"]
    assert isinstance(artifacts, list)
    artifacts[0]["structure"]["header_sha256"] = "mutated"
    artifacts.append({"artifact_role": "injected"})
    first["identity_scheme"] = "mutated"

    assert metadata.to_json_object() == second
    assert metadata.artifacts[0].structure.header_sha256 == "e" * 64


def test_metadata_json_representation_is_deterministic() -> None:
    expected = (
        '{"artifacts":['
        '{"artifact_format":"csv","artifact_role":"concept_catalog","byte_length":28,'
        '"structure":{"has_bom":false,"header_sha256":"' + "e" * 64 + '",'
        '"kind":"csv_text","line_terminator":"crlf"}},'
        '{"artifact_format":"zip","artifact_role":"historical_series_data","byte_length":34,'
        '"structure":{"header_sha256":"' + "d" * 64 + '","kind":"zip_member",'
        '"member_name":"sh_datos_40.csv","member_uncompressed_size":584795606}},'
        '{"artifact_format":"csv","artifact_role":"institution_catalog","byte_length":32,'
        '"structure":{"has_bom":false,"header_sha256":"' + "e" * 64 + '",'
        '"kind":"csv_text","line_terminator":"crlf"}}],'
        '"identity_scheme":"cnbv_portfolio.observed_artifact_set.v1",'
        '"snapshot_semantics":"exact_observed_artifact_set"}'
    )

    def canonical(metadata: ReleaseMetadata) -> str:
        return json.dumps(
            metadata.to_json_object(), sort_keys=True, separators=(",", ":"), ensure_ascii=True
        )

    assert canonical(_observe().metadata) == expected
    assert canonical(_observe(observed_at=OBSERVED_AT + timedelta(hours=1)).metadata) == expected
    assert canonical(
        ReleaseMetadata.from_artifacts(IDENTITY_SCHEME, list(reversed(_observe().artifacts)))
    ) == expected


def test_metadata_structure_must_match_the_artifact_format() -> None:
    with pytest.raises(SourceContractError, match="frozen structure type"):
        ArtifactMetadata("concept_catalog", SourceFormat.CSV, 1, _structure(SourceFormat.ZIP))
    with pytest.raises(SourceContractError, match="no frozen structural contract"):
        ArtifactMetadata("notes", SourceFormat.XLSX, 1, _structure(SourceFormat.ZIP))
    with pytest.raises(SourceContractError, match="crlf or lf"):
        CsvTextStructure(header_sha256="e" * 64, has_bom=False, line_terminator="cr")


# Error contract

EXPECTED_ERROR_CODES: dict[type[DiscoveryError], str] = {
    DiscoveryError: "discovery_failed",
    ContractError: "discovery_contract_invalid",
    SourceContractError: "source_contract_invalid",
    UnofficialArtifactUrlError: "artifact_url_unofficial",
    ReleaseLineageAmbiguousError: "release_lineage_ambiguous",
    ArtifactRetrievalError: "artifact_retrieval_failed",
    ArtifactTlsUntrustedError: "artifact_tls_untrusted",
    ArtifactTransportError: "artifact_transport_failed",
    ArtifactHttpStatusError: "artifact_http_status",
    ArtifactNotFoundHttpError: "artifact_not_found",
    ArtifactRedirectError: "artifact_redirect_invalid",
    ArtifactContentEncodingError: "artifact_content_encoding_unsupported",
    ArtifactTooLargeError: "artifact_too_large",
    ArtifactLengthMismatchError: "artifact_length_mismatch",
    ArtifactContentError: "artifact_content_invalid",
    EmptyArtifactError: "artifact_empty",
    HtmlArtifactError: "artifact_html_response",
    UnexpectedMediaTypeError: "artifact_media_type_unexpected",
    ArtifactSignatureError: "artifact_signature_invalid",
    SourceLayoutDriftError: "source_layout_drift",
}


def _all_error_classes() -> set[type[DiscoveryError]]:
    found: set[type[DiscoveryError]] = {DiscoveryError}
    pending = [DiscoveryError]
    while pending:
        for subclass in pending.pop().__subclasses__():
            if subclass.__module__ == discovery.__name__:
                found.add(subclass)
                pending.append(subclass)
    return found


def test_error_taxonomy_is_exactly_the_frozen_hierarchy() -> None:
    assert _all_error_classes() == set(EXPECTED_ERROR_CODES)
    assert {error: error.code for error in EXPECTED_ERROR_CODES} == EXPECTED_ERROR_CODES
    assert len(set(EXPECTED_ERROR_CODES.values())) == len(EXPECTED_ERROR_CODES)
    assert issubclass(ArtifactNotFoundHttpError, ArtifactHttpStatusError)

    contract = {SourceContractError, UnofficialArtifactUrlError, ReleaseLineageAmbiguousError}
    content = {
        EmptyArtifactError,
        HtmlArtifactError,
        UnexpectedMediaTypeError,
        ArtifactSignatureError,
        SourceLayoutDriftError,
    }
    branches = {DiscoveryError, ContractError, ArtifactRetrievalError, ArtifactContentError}
    for error in EXPECTED_ERROR_CODES:
        assert not issubclass(error, InvalidArtifactError)
        if error in contract:
            assert issubclass(error, ContractError)
            assert not issubclass(error, (ArtifactRetrievalError, ArtifactContentError))
        elif error in content:
            assert issubclass(error, ArtifactContentError)
            assert not issubclass(error, (ContractError, ArtifactRetrievalError))
        elif error not in branches:
            assert issubclass(error, ArtifactRetrievalError)
            assert not issubclass(error, (ContractError, ArtifactContentError))


@pytest.mark.parametrize("error", sorted(EXPECTED_ERROR_CODES, key=lambda item: item.code))
def test_every_error_code_and_default_summary_satisfy_audit_constraints(
    error: type[DiscoveryError],
) -> None:
    raised = error()

    assert AUDIT_ERROR_CODE.fullmatch(error.code)
    assert len(error.code) <= 64
    assert raised.safe_summary.strip()
    assert len(raised.safe_summary) <= 512
    assert not CONTROL_CHARACTERS.search(raised.safe_summary)
    assert str(raised) == raised.safe_summary


def test_safe_summary_is_bounded_and_strips_control_characters() -> None:
    noisy = SourceContractError("bad\x00value\r\ninjected\tline\x7f\x85\u2028end " + "x" * 2_000)

    assert len(noisy.safe_summary) <= 512
    assert noisy.safe_summary.startswith("bad value injected line end ")
    assert noisy.safe_summary.endswith("...")
    assert not CONTROL_CHARACTERS.search(noisy.safe_summary)
    assert SourceContractError("\x00\n\t ").safe_summary == SourceContractError.default_summary


def test_error_subclasses_must_declare_valid_codes() -> None:
    with pytest.raises(TypeError, match="audit-compatible error code"):
        type("MissingCode", (SourceContractError,), {})
    with pytest.raises(TypeError, match="audit-compatible error code"):
        type("BadCode", (SourceContractError,), {"code": "Bad-Code"})
    with pytest.raises(TypeError, match="audit-compatible error code"):
        type("LongCode", (SourceContractError,), {"code": "a" * 65})


def test_discovery_module_owns_no_source_specific_identity_values() -> None:
    text = Path(discovery.__file__).read_text(encoding="utf-8").casefold()

    for source_specific in ("cnbv", IDENTITY_SCHEME, FAMILY, "serie_historica", "banca"):
        assert source_specific not in text


def test_discovery_module_has_no_network_storage_database_or_source_imports() -> None:
    tree = ast.parse(Path(discovery.__file__).read_text(encoding="utf-8"))
    imported: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module is not None:
            imported.add(node.module)

    forbidden = ("httpx", "psycopg", "mx_bank_monitor.ingestion.", "mx_bank_monitor.persistence")
    assert not [name for name in imported if name.startswith(forbidden)]
    assert imported & {"mx_bank_monitor.config.models"}
