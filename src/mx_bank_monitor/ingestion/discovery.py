"""Source-independent release discovery identity, classification, and errors.

A release identity is an exact observed snapshot of a source's required artifact set. It does
not assert atomic regulator publication, an official revision label, simultaneous artifact
change, or publication eligibility. This module performs no network, storage, or database access.
"""

from __future__ import annotations

import json
import re
import unicodedata
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from datetime import date, datetime
from enum import StrEnum
from hashlib import sha256
from typing import ClassVar, Final, Literal

from mx_bank_monitor.config.models import SourceFormat

type SnapshotSemantics = Literal["exact_observed_artifact_set"]
type LineTerminator = Literal["crlf", "lf"]

EXACT_OBSERVED_ARTIFACT_SET: Final[SnapshotSemantics] = "exact_observed_artifact_set"
ERROR_CODE_MAX_LENGTH: Final = 64
SAFE_SUMMARY_MAX_LENGTH: Final = 512
IDENTITY_SCHEME_MAX_LENGTH: Final = 128

_IDENTIFIER_PATTERN = re.compile(r"[a-z][a-z0-9]*(?:_[a-z0-9]+)*")
_IDENTITY_SCHEME_PATTERN = re.compile(
    r"[a-z][a-z0-9]*(?:_[a-z0-9]+)*(?:\.[a-z0-9]+(?:_[a-z0-9]+)*)+"
)
_SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
_LINE_TERMINATORS: Final = frozenset({"crlf", "lf"})


def _is_control_character(character: str) -> bool:
    return unicodedata.category(character) == "Cc" or character in "\u2028\u2029"


def sanitize_summary(value: str) -> str:
    """Return a single-line summary that satisfies the audit error-summary constraints."""
    cleaned = "".join(" " if _is_control_character(item) else item for item in value)
    collapsed = " ".join(cleaned.split())
    if len(collapsed) > SAFE_SUMMARY_MAX_LENGTH:
        collapsed = collapsed[: SAFE_SUMMARY_MAX_LENGTH - 3].rstrip() + "..."
    return collapsed


def is_audit_error_code(value: str) -> bool:
    return (
        len(value) <= ERROR_CODE_MAX_LENGTH and _IDENTIFIER_PATTERN.fullmatch(value) is not None
    )


class DiscoveryError(Exception):
    code: ClassVar[str] = "discovery_failed"
    default_summary: ClassVar[str] = "Release discovery failed."

    def __init_subclass__(cls) -> None:
        super().__init_subclass__()
        code = cls.__dict__.get("code")
        if not isinstance(code, str) or not is_audit_error_code(code):
            raise TypeError(f"{cls.__name__} must define its own audit-compatible error code")

    def __init__(self, summary: str | None = None) -> None:
        cleaned = sanitize_summary(summary) if summary is not None else ""
        self.safe_summary = cleaned or sanitize_summary(self.default_summary)
        super().__init__(self.safe_summary)


class ContractError(DiscoveryError):
    code = "discovery_contract_invalid"
    default_summary = "The discovery contract was violated."


class SourceContractError(ContractError):
    code = "source_contract_invalid"
    default_summary = "The source definition or observation violates the source contract."


class UnofficialArtifactUrlError(ContractError):
    code = "artifact_url_unofficial"
    default_summary = "The artifact URL is outside the official source authority."


class ReleaseLineageAmbiguousError(ContractError):
    code = "release_lineage_ambiguous"
    default_summary = "The release lineage is ambiguous or inconsistent."


class ArtifactRetrievalError(DiscoveryError):
    """A retrieval failure that can carry safe HTTP context for a later audit row.

    ``requested_url`` is the caller-supplied URL. ``final_url`` is set only when a
    response was reached. ``observation`` is set only when response metadata exists.
    These fields are not database identifiers and are not release-identity inputs.
    """

    code = "artifact_retrieval_failed"
    default_summary = "The artifact could not be retrieved."

    def __init__(
        self,
        summary: str | None = None,
        *,
        requested_url: str | None = None,
        final_url: str | None = None,
        observation: HttpObservation | None = None,
    ) -> None:
        super().__init__(summary)
        self.requested_url = requested_url
        self.final_url = final_url
        self.observation = observation


class ArtifactTlsUntrustedError(ArtifactRetrievalError):
    code = "artifact_tls_untrusted"
    default_summary = "The artifact host TLS certificate could not be verified."


class ArtifactTransportError(ArtifactRetrievalError):
    code = "artifact_transport_failed"
    default_summary = "The artifact request failed at the transport level."


class ArtifactHttpStatusError(ArtifactRetrievalError):
    code = "artifact_http_status"
    default_summary = "The artifact request returned an unexpected HTTP status."


class ArtifactNotFoundHttpError(ArtifactHttpStatusError):
    code = "artifact_not_found"
    default_summary = "The artifact URL returned HTTP 404."


class ArtifactRedirectError(ArtifactRetrievalError):
    code = "artifact_redirect_invalid"
    default_summary = "The artifact request returned an invalid redirect."


class ArtifactContentEncodingError(ArtifactRetrievalError):
    code = "artifact_content_encoding_unsupported"
    default_summary = "The artifact response used an unsupported content encoding."


class ArtifactTooLargeError(ArtifactRetrievalError):
    code = "artifact_too_large"
    default_summary = "The artifact exceeds the configured byte limit."


class ArtifactLengthMismatchError(ArtifactRetrievalError):
    code = "artifact_length_mismatch"
    default_summary = "The received artifact length differs from Content-Length."


class ArtifactContentError(DiscoveryError):
    code = "artifact_content_invalid"
    default_summary = "The artifact content failed validation."


class EmptyArtifactError(ArtifactContentError):
    code = "artifact_empty"
    default_summary = "The artifact response contained no bytes."


class HtmlArtifactError(ArtifactContentError):
    code = "artifact_html_response"
    default_summary = "The artifact response contained HTML instead of a data artifact."


class UnexpectedMediaTypeError(ArtifactContentError):
    code = "artifact_media_type_unexpected"
    default_summary = "The artifact declared a media type incompatible with its format."


class ArtifactSignatureError(ArtifactContentError):
    code = "artifact_signature_invalid"
    default_summary = "The artifact bytes do not match the expected format signature."


class SourceLayoutDriftError(ArtifactContentError):
    code = "source_layout_drift"
    default_summary = "The artifact structure differs from the frozen source layout."


def _require(condition: bool, error: type[DiscoveryError], summary: str) -> None:
    if not condition:
        raise error(summary)


def _require_identifier(value: object, label: str, error: type[DiscoveryError]) -> None:
    _require(
        isinstance(value, str) and _IDENTIFIER_PATTERN.fullmatch(value) is not None,
        error,
        f"{label} must be a snake_case identifier",
    )


def _require_identity_scheme(value: object, error: type[DiscoveryError]) -> None:
    _require(
        isinstance(value, str)
        and len(value) <= IDENTITY_SCHEME_MAX_LENGTH
        and _IDENTITY_SCHEME_PATTERN.fullmatch(value) is not None,
        error,
        "identity_scheme must be dot-separated snake_case segments",
    )


def _require_sha256(value: object, label: str, error: type[DiscoveryError]) -> None:
    _require(
        isinstance(value, str) and _SHA256_PATTERN.fullmatch(value) is not None,
        error,
        f"{label} must be a lowercase hexadecimal SHA-256",
    )


def _require_tuple(value: object, label: str, error: type[DiscoveryError]) -> None:
    _require(type(value) is tuple, error, f"{label} must be an immutable tuple")


def _require_count(value: object, label: str, error: type[DiscoveryError]) -> None:
    _require(
        type(value) is int and value >= 0, error, f"{label} must be a non-negative integer"
    )


def _require_aware(value: object, label: str, error: type[DiscoveryError]) -> None:
    _require(
        isinstance(value, datetime) and value.utcoffset() is not None,
        error,
        f"{label} must be a timezone-aware datetime",
    )


def _require_sorted_unique_roles(
    roles: tuple[str, ...], label: str, error: type[DiscoveryError]
) -> None:
    _require(bool(roles), error, f"{label} must contain at least one artifact role")
    for role in roles:
        _require_identifier(role, f"{label} artifact role", error)
    _require(
        roles == tuple(sorted(set(roles))),
        error,
        f"{label} artifact roles must be unique and sorted by role",
    )


class ArtifactObservationResult(StrEnum):
    NEW = "new"
    REUSED = "reused"
    REVISED = "revised"
    FAILED = "failed"


class ReleaseChange(StrEnum):
    FIRST_RELEASE = "first_release"
    UNCHANGED = "unchanged"
    REVISED = "revised"


@dataclass(frozen=True, slots=True)
class HttpObservation:
    """Observational HTTP metadata. It never participates in release identity."""

    requested_url: str
    final_url: str
    redirect_chain: tuple[str, ...]
    status_code: int
    content_type: str | None
    content_length: int | None
    content_encoding: str | None
    etag: str | None
    last_modified: str | None
    content_disposition: str | None
    observed_at: datetime

    def __post_init__(self) -> None:
        _require_tuple(self.redirect_chain, "redirect_chain", SourceContractError)
        _require_aware(self.observed_at, "observed_at", SourceContractError)


@dataclass(frozen=True, slots=True)
class ZipMemberStructure:
    member_name: str
    member_uncompressed_size: int
    header_sha256: str

    def __post_init__(self) -> None:
        _require(
            isinstance(self.member_name, str) and bool(self.member_name),
            SourceContractError,
            "member_name must be non-empty text",
        )
        _require_count(
            self.member_uncompressed_size, "member_uncompressed_size", SourceContractError
        )
        _require_sha256(self.header_sha256, "header_sha256", SourceContractError)

    def to_json_object(self) -> dict[str, object]:
        return {
            "kind": "zip_member",
            "member_name": self.member_name,
            "member_uncompressed_size": self.member_uncompressed_size,
            "header_sha256": self.header_sha256,
        }


@dataclass(frozen=True, slots=True)
class CsvTextStructure:
    header_sha256: str
    has_bom: bool
    line_terminator: LineTerminator

    def __post_init__(self) -> None:
        _require_sha256(self.header_sha256, "header_sha256", SourceContractError)
        _require(type(self.has_bom) is bool, SourceContractError, "has_bom must be a boolean")
        _require(
            self.line_terminator in _LINE_TERMINATORS,
            SourceContractError,
            "line_terminator must be crlf or lf",
        )

    def to_json_object(self) -> dict[str, object]:
        return {
            "kind": "csv_text",
            "header_sha256": self.header_sha256,
            "has_bom": self.has_bom,
            "line_terminator": self.line_terminator,
        }


type ArtifactStructure = ZipMemberStructure | CsvTextStructure

_STRUCTURE_BY_FORMAT: Final[dict[SourceFormat, type[ZipMemberStructure | CsvTextStructure]]] = {
    SourceFormat.ZIP: ZipMemberStructure,
    SourceFormat.CSV: CsvTextStructure,
}


@dataclass(frozen=True, slots=True)
class ArtifactMetadata:
    artifact_role: str
    artifact_format: SourceFormat
    byte_length: int
    structure: ArtifactStructure

    def __post_init__(self) -> None:
        _require_identifier(self.artifact_role, "artifact_role", SourceContractError)
        _require(
            type(self.byte_length) is int and self.byte_length > 0,
            SourceContractError,
            "byte_length must be a positive integer",
        )
        _require_structure(self.artifact_format, self.structure)

    def to_json_object(self) -> dict[str, object]:
        return {
            "artifact_role": self.artifact_role,
            "artifact_format": self.artifact_format.value,
            "byte_length": self.byte_length,
            "structure": self.structure.to_json_object(),
        }


@dataclass(frozen=True, slots=True)
class ReleaseMetadata:
    identity_scheme: str
    snapshot_semantics: SnapshotSemantics
    artifacts: tuple[ArtifactMetadata, ...]

    def __post_init__(self) -> None:
        _require_identity_scheme(self.identity_scheme, SourceContractError)
        _require(
            self.snapshot_semantics == EXACT_OBSERVED_ARTIFACT_SET,
            SourceContractError,
            "snapshot_semantics must be exact_observed_artifact_set",
        )
        _require_tuple(self.artifacts, "metadata artifacts", SourceContractError)
        _require_sorted_unique_roles(
            tuple(item.artifact_role for item in self.artifacts),
            "metadata",
            SourceContractError,
        )

    @classmethod
    def from_artifacts(
        cls, identity_scheme: str, artifacts: Sequence[ValidatedArtifact]
    ) -> ReleaseMetadata:
        return cls(
            identity_scheme=identity_scheme,
            snapshot_semantics=EXACT_OBSERVED_ARTIFACT_SET,
            artifacts=tuple(
                ArtifactMetadata(
                    artifact_role=item.artifact_role,
                    artifact_format=item.artifact_format,
                    byte_length=item.byte_length,
                    structure=item.structure,
                )
                for item in sorted(artifacts, key=lambda item: item.artifact_role)
            ),
        )

    def to_json_object(self) -> dict[str, object]:
        """Build a new JSON-compatible object; callers never receive internal state."""
        return {
            "identity_scheme": self.identity_scheme,
            "snapshot_semantics": self.snapshot_semantics,
            "artifacts": [item.to_json_object() for item in self.artifacts],
        }


def _require_structure(artifact_format: object, structure: object) -> None:
    if not isinstance(artifact_format, SourceFormat):
        raise SourceContractError("artifact_format must be a supported source format")
    expected = _STRUCTURE_BY_FORMAT.get(artifact_format)
    _require(
        expected is not None,
        SourceContractError,
        f"artifact format {artifact_format} has no frozen structural contract",
    )
    _require(
        type(structure) is expected,
        SourceContractError,
        f"artifact format {artifact_format} requires its frozen structure type",
    )


@dataclass(frozen=True, slots=True)
class DiscoveredArtifact:
    artifact_role: str
    artifact_format: SourceFormat
    original_url: str

    def __post_init__(self) -> None:
        _require_identifier(self.artifact_role, "artifact_role", SourceContractError)
        _require(
            isinstance(self.artifact_format, SourceFormat),
            SourceContractError,
            "artifact_format must be a supported source format",
        )
        _require(
            isinstance(self.original_url, str) and bool(self.original_url),
            SourceContractError,
            "original_url must be non-empty text",
        )


@dataclass(frozen=True, slots=True)
class DiscoveredRelease:
    """Configured discovery candidate.

    revision, published_at, and the covered period stay None: they are never inferred.
    """

    source_code: str
    source_definition_version: int
    release_family_key: str
    identity_scheme: str
    artifacts: tuple[DiscoveredArtifact, ...]
    revision: str | None = None
    published_at: datetime | None = None
    covered_period_start: date | None = None
    covered_period_end: date | None = None

    def __post_init__(self) -> None:
        _require_identifier(self.source_code, "source_code", SourceContractError)
        _require(
            type(self.source_definition_version) is int and self.source_definition_version >= 1,
            SourceContractError,
            "source_definition_version must be a positive integer",
        )
        _require_identifier(self.release_family_key, "release_family_key", SourceContractError)
        _require_identity_scheme(self.identity_scheme, SourceContractError)
        _require_tuple(self.artifacts, "discovered artifacts", SourceContractError)
        _require_sorted_unique_roles(
            tuple(item.artifact_role for item in self.artifacts),
            "discovered release",
            SourceContractError,
        )
        for label, value in (
            ("revision", self.revision),
            ("published_at", self.published_at),
            ("covered_period_start", self.covered_period_start),
            ("covered_period_end", self.covered_period_end),
        ):
            _require(
                value is None,
                SourceContractError,
                f"{label} is not exposed by the source and must not be inferred",
            )


@dataclass(frozen=True, slots=True)
class ValidatedArtifact:
    artifact_role: str
    artifact_format: SourceFormat
    filename: str
    catalog_mime_type: str
    sha256: str
    byte_length: int
    content: bytes = field(repr=False)
    http: HttpObservation
    structure: ArtifactStructure

    def __post_init__(self) -> None:
        _require_identifier(self.artifact_role, "artifact_role", SourceContractError)
        _require_sha256(self.sha256, "sha256", SourceContractError)
        _require(
            type(self.content) is bytes, SourceContractError, "content must be immutable bytes"
        )
        _require(
            bool(self.content), EmptyArtifactError, f"artifact {self.artifact_role} is empty"
        )
        _require(
            self.byte_length == len(self.content)
            and sha256(self.content).hexdigest() == self.sha256,
            SourceContractError,
            f"artifact {self.artifact_role} identity does not match its exact bytes",
        )
        _require_structure(self.artifact_format, self.structure)


@dataclass(frozen=True, slots=True)
class ObservedRelease:
    discovered: DiscoveredRelease
    artifacts: tuple[ValidatedArtifact, ...]
    release_identity_hash: str
    first_observed_at: datetime
    metadata: ReleaseMetadata

    def __post_init__(self) -> None:
        _require_tuple(self.artifacts, "observed artifacts", SourceContractError)
        _require(
            tuple((item.artifact_role, item.artifact_format) for item in self.artifacts)
            == tuple(
                (item.artifact_role, item.artifact_format) for item in self.discovered.artifacts
            ),
            SourceContractError,
            "observed artifacts must match the discovered roles and formats in role order",
        )
        _require(
            self.release_identity_hash == release_identity_hash(self.discovered, self.artifacts),
            SourceContractError,
            "release_identity_hash does not match the observed artifact set",
        )
        _require(
            self.first_observed_at == min(item.http.observed_at for item in self.artifacts),
            SourceContractError,
            "first_observed_at must be the earliest artifact observation time",
        )
        _require(
            self.metadata
            == ReleaseMetadata.from_artifacts(self.discovered.identity_scheme, self.artifacts),
            SourceContractError,
            "release metadata does not match the observed artifacts",
        )

    @classmethod
    def from_validated_artifacts(
        cls, discovered: DiscoveredRelease, artifacts: Sequence[ValidatedArtifact]
    ) -> ObservedRelease:
        ordered = tuple(sorted(artifacts, key=lambda item: item.artifact_role))
        _require(bool(ordered), SourceContractError, "observed release has no artifacts")
        return cls(
            discovered=discovered,
            artifacts=ordered,
            release_identity_hash=release_identity_hash(discovered, ordered),
            first_observed_at=min(item.http.observed_at for item in ordered),
            metadata=ReleaseMetadata.from_artifacts(discovered.identity_scheme, ordered),
        )


@dataclass(frozen=True, slots=True)
class CatalogedRelease:
    release_identity_hash: str
    supersedes_release_identity_hash: str | None
    artifact_sha256_by_role: tuple[tuple[str, str], ...]

    def __post_init__(self) -> None:
        error = ReleaseLineageAmbiguousError
        _require_sha256(self.release_identity_hash, "release_identity_hash", error)
        if self.supersedes_release_identity_hash is not None:
            _require_sha256(
                self.supersedes_release_identity_hash, "supersedes_release_identity_hash", error
            )
            _require(
                self.supersedes_release_identity_hash != self.release_identity_hash,
                error,
                "a release cannot supersede itself",
            )
        _require_tuple(self.artifact_sha256_by_role, "artifact_sha256_by_role", error)
        for pair in self.artifact_sha256_by_role:
            _require(
                type(pair) is tuple and len(pair) == 2,
                error,
                "artifact_sha256_by_role entries must be (role, sha256) tuples",
            )
            _require_sha256(pair[1], "cataloged artifact sha256", error)
        _require_sorted_unique_roles(
            tuple(role for role, _ in self.artifact_sha256_by_role), "cataloged release", error
        )


@dataclass(frozen=True, slots=True)
class PriorFamilyState:
    """Complete caller-supplied catalog state for one source release family."""

    source_code: str
    release_family_key: str
    releases: tuple[CatalogedRelease, ...]

    def __post_init__(self) -> None:
        error = ReleaseLineageAmbiguousError
        _require_identifier(self.source_code, "prior source_code", error)
        _require_identifier(self.release_family_key, "prior release_family_key", error)
        _require_tuple(self.releases, "prior releases", error)
        _require(
            all(type(item) is CatalogedRelease for item in self.releases),
            error,
            "prior releases must be cataloged releases",
        )
        identities = tuple(item.release_identity_hash for item in self.releases)
        _require(
            len(identities) == len(set(identities)),
            error,
            "prior releases contain a duplicate release identity",
        )


@dataclass(frozen=True, slots=True)
class ArtifactClassification:
    artifact_role: str
    sha256: str
    result: ArtifactObservationResult
    content_changed: bool

    def __post_init__(self) -> None:
        error = ReleaseLineageAmbiguousError
        _require_identifier(self.artifact_role, "classified artifact_role", error)
        _require_sha256(self.sha256, "classified sha256", error)
        _require(
            self.result != ArtifactObservationResult.FAILED,
            error,
            "a classified release artifact cannot be failed",
        )
        _require(
            self.content_changed is (self.result == ArtifactObservationResult.REVISED),
            error,
            "content_changed must be true exactly for revised artifacts",
        )


_ALLOWED_RESULTS: Final = {
    ReleaseChange.FIRST_RELEASE: frozenset({ArtifactObservationResult.NEW}),
    ReleaseChange.UNCHANGED: frozenset({ArtifactObservationResult.REUSED}),
    ReleaseChange.REVISED: frozenset(
        {ArtifactObservationResult.REVISED, ArtifactObservationResult.REUSED}
    ),
}


@dataclass(frozen=True, slots=True)
class ReleaseClassification:
    change: ReleaseChange
    release_identity_hash: str
    supersedes_release_identity_hash: str | None
    artifacts: tuple[ArtifactClassification, ...]

    def __post_init__(self) -> None:
        error = ReleaseLineageAmbiguousError
        _require_sha256(self.release_identity_hash, "classified release_identity_hash", error)
        _require_tuple(self.artifacts, "classified artifacts", error)
        _require_sorted_unique_roles(
            tuple(item.artifact_role for item in self.artifacts), "classification", error
        )
        results = {item.result for item in self.artifacts}
        _require(
            results <= _ALLOWED_RESULTS[self.change],
            error,
            f"{self.change} classification contains an incompatible artifact result",
        )
        if self.change == ReleaseChange.REVISED:
            _require_sha256(
                self.supersedes_release_identity_hash, "supersedes_release_identity_hash", error
            )
            _require(
                self.supersedes_release_identity_hash != self.release_identity_hash,
                error,
                "a revised release cannot supersede itself",
            )
            _require(
                ArtifactObservationResult.REVISED in results,
                error,
                "a revised release must revise at least one artifact",
            )
        else:
            _require(
                self.supersedes_release_identity_hash is None,
                error,
                f"{self.change} classification cannot supersede a release",
            )


def artifact_set_identity_hash(
    *,
    identity_scheme: str,
    source_code: str,
    release_family_key: str,
    revision: str | None,
    artifact_sha256_by_role: Iterable[tuple[str, str]],
) -> str:
    """Hash the canonical role and SHA-256 artifact set under a caller-owned identity scheme."""
    pairs = tuple(sorted(artifact_sha256_by_role))
    _require_identity_scheme(identity_scheme, SourceContractError)
    _require_identifier(source_code, "source_code", SourceContractError)
    _require_identifier(release_family_key, "release_family_key", SourceContractError)
    _require(
        revision is None or (isinstance(revision, str) and bool(revision.strip())),
        SourceContractError,
        "revision must be null or non-blank text",
    )
    for _, digest in pairs:
        _require_sha256(digest, "artifact sha256", SourceContractError)
    _require_sorted_unique_roles(
        tuple(role for role, _ in pairs), "identity artifact set", SourceContractError
    )
    payload = {
        "identity_scheme": identity_scheme,
        "source_code": source_code,
        "release_family_key": release_family_key,
        "revision": revision,
        "artifacts": [{"role": role, "sha256": digest} for role, digest in pairs],
    }
    encoded = json.dumps(
        payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("utf-8")
    return sha256(encoded).hexdigest()


def release_identity_hash(
    discovered: DiscoveredRelease, artifacts: Sequence[ValidatedArtifact]
) -> str:
    observed = {item.artifact_role: item for item in artifacts}
    _require(
        len(observed) == len(artifacts),
        SourceContractError,
        "observed artifacts contain a duplicate role",
    )
    for expected in discovered.artifacts:
        artifact = observed.get(expected.artifact_role)
        _require(
            artifact is not None and artifact.artifact_format == expected.artifact_format,
            SourceContractError,
            f"required artifact role {expected.artifact_role} was not observed in its format",
        )
    _require(
        len(observed) == len(discovered.artifacts),
        SourceContractError,
        "observed artifacts contain a role outside the discovered release",
    )
    return artifact_set_identity_hash(
        identity_scheme=discovered.identity_scheme,
        source_code=discovered.source_code,
        release_family_key=discovered.release_family_key,
        revision=discovered.revision,
        artifact_sha256_by_role=((item.artifact_role, item.sha256) for item in artifacts),
    )


def _resolve_unique_head(
    releases: tuple[CatalogedRelease, ...],
) -> tuple[CatalogedRelease, frozenset[str]]:
    error = ReleaseLineageAmbiguousError
    by_identity = {item.release_identity_hash: item for item in releases}
    superseded: set[str] = set()
    for release in releases:
        predecessor = release.supersedes_release_identity_hash
        if predecessor is not None:
            _require(
                predecessor in by_identity,
                error,
                "a prior release supersedes an identity outside the supplied family state",
            )
            superseded.add(predecessor)
    heads = tuple(item for item in releases if item.release_identity_hash not in superseded)
    _require(bool(heads), error, "prior release lineage has no head")
    _require(len(heads) == 1, error, "prior release lineage has several heads")

    head = heads[0]
    visited: set[str] = set()
    current: CatalogedRelease | None = head
    while current is not None:
        _require(
            current.release_identity_hash not in visited,
            error,
            "prior release lineage contains a cycle",
        )
        visited.add(current.release_identity_hash)
        predecessor = current.supersedes_release_identity_hash
        current = by_identity[predecessor] if predecessor is not None else None
    _require(
        len(visited) == len(releases),
        error,
        "prior release lineage is not one supersession chain",
    )
    return head, frozenset(visited - {head.release_identity_hash})


def classify_release(observed: ObservedRelease, prior: PriorFamilyState) -> ReleaseClassification:
    """Classify an observed release against the complete prior state of its family.

    A new identity supersedes only the unique head. Any ambiguity fails closed.
    """
    error = ReleaseLineageAmbiguousError
    discovered = observed.discovered
    _require(
        prior.source_code == discovered.source_code,
        error,
        "prior release state belongs to a different source",
    )
    _require(
        prior.release_family_key == discovered.release_family_key,
        error,
        "prior release state belongs to a different release family",
    )
    for release in prior.releases:
        _require(
            release.release_identity_hash
            == artifact_set_identity_hash(
                identity_scheme=discovered.identity_scheme,
                source_code=prior.source_code,
                release_family_key=prior.release_family_key,
                revision=None,
                artifact_sha256_by_role=release.artifact_sha256_by_role,
            ),
            error,
            "a prior release identity does not match its artifact set under the identity scheme",
        )
    identity = observed.release_identity_hash
    pairs = tuple((item.artifact_role, item.sha256) for item in observed.artifacts)

    if not prior.releases:
        return ReleaseClassification(
            change=ReleaseChange.FIRST_RELEASE,
            release_identity_hash=identity,
            supersedes_release_identity_hash=None,
            artifacts=tuple(
                ArtifactClassification(role, digest, ArtifactObservationResult.NEW, False)
                for role, digest in pairs
            ),
        )

    head, superseded = _resolve_unique_head(prior.releases)
    head_sha_by_role = dict(head.artifact_sha256_by_role)
    _require(
        set(head_sha_by_role) == {role for role, _ in pairs},
        error,
        "observed artifact roles differ from the release head",
    )
    if identity == head.release_identity_hash:
        return ReleaseClassification(
            change=ReleaseChange.UNCHANGED,
            release_identity_hash=identity,
            supersedes_release_identity_hash=None,
            artifacts=tuple(
                ArtifactClassification(role, digest, ArtifactObservationResult.REUSED, False)
                for role, digest in pairs
            ),
        )
    _require(
        identity not in superseded,
        error,
        "a previously superseded release identity reappeared",
    )
    return ReleaseClassification(
        change=ReleaseChange.REVISED,
        release_identity_hash=identity,
        supersedes_release_identity_hash=head.release_identity_hash,
        artifacts=tuple(
            ArtifactClassification(
                role,
                digest,
                ArtifactObservationResult.REVISED
                if digest != head_sha_by_role[role]
                else ArtifactObservationResult.REUSED,
                digest != head_sha_by_role[role],
            )
            for role, digest in pairs
        ),
    )
