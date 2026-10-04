"""CNBV portfolio transport policy and structural artifact adapter.

The adapter discovers the configured artifact set, retrieves it through
``HttpArtifactClient.retrieve``, and validates ZIP and CSV structure. It does
not parse financial facts, map institutions or concepts, derive a covered
period, persist observations, or classify releases.
"""

from __future__ import annotations

import io
import re
import ssl
import unicodedata
import zipfile
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from datetime import datetime, timedelta
from hashlib import sha256
from importlib.resources import files
from typing import Final
from urllib.parse import unquote, urlsplit
from zipfile import ZipFile

import certifi

from mx_bank_monitor.config.models import EndpointKind, SourceDefinition, SourceFormat
from mx_bank_monitor.ingestion.discovery import (
    ArtifactRetrievalError,
    ArtifactSignatureError,
    CsvTextStructure,
    DiscoveredArtifact,
    DiscoveredRelease,
    DiscoveryError,
    EmptyArtifactError,
    HtmlArtifactError,
    HttpObservation,
    LineTerminator,
    ObservedRelease,
    SourceContractError,
    SourceLayoutDriftError,
    UnexpectedMediaTypeError,
    UnofficialArtifactUrlError,
    ValidatedArtifact,
    ZipMemberStructure,
    is_audit_error_code,
    sanitize_summary,
)
from mx_bank_monitor.ingestion.http import DownloadedArtifact, HttpArtifactClient

IDENTITY_SCHEME: Final = "cnbv_portfolio.observed_artifact_set.v1"
RELEASE_FAMILY_KEY: Final = "serie_historica_banca_multiple_40"
OFFICIAL_ARTIFACT_HOST: Final = "portafolioinfdoctos.cnbv.gob.mx"
OFFICIAL_ARTIFACT_HOSTS: Final = frozenset({OFFICIAL_ARTIFACT_HOST})
PINNED_INTERMEDIATE_DER_SHA256: Final = (
    "b676ffa3179e8812093a1b5eafee876ae7a6aaf231078dad1bfb21cd2893764a"
)
_INTERMEDIATE_FILENAME: Final = "globalsign-rsa-ov-ssl-ca-2018.pem"
_HTTPS_PORT: Final = 443
_UTF8_BOM: Final = b"\xef\xbb\xbf"
_ASCII_WHITESPACE: Final = b" \t\r\n\f\v"
_HEADER_PROBE_BYTES: Final = 512
HISTORICAL_SERIES_MAX_BYTES: Final = 128 * 1024 * 1024
CATALOG_MAX_BYTES: Final = 8 * 1024 * 1024
ZIP_MEMBER_MAX_UNCOMPRESSED_BYTES: Final = 1024 * 1024 * 1024
HISTORICAL_MEMBER_NAME: Final = "sh_datos_40.csv"
HISTORICAL_SERIES_HEADER: Final = '"sector","idconcepto","entidad","periodo","saldo","valor"'
CONCEPT_CATALOG_HEADER: Final = (
    '"sector","idtema","idconcepto","descripcion","nivel","indicador","orden"'
)
INSTITUTION_CATALOG_HEADER: Final = (
    '"sector","entidad","nombre_entidad","grupo","nombre_grupo","orden"'
)
REQUIRED_ROLES: Final[tuple[tuple[str, SourceFormat], ...]] = (
    ("concept_catalog", SourceFormat.CSV),
    ("historical_series_data", SourceFormat.ZIP),
    ("institution_catalog", SourceFormat.CSV),
)
RETRIEVAL_ORDER: Final[tuple[str, ...]] = (
    "concept_catalog",
    "institution_catalog",
    "historical_series_data",
)
_REQUIRED_FORMAT_BY_ROLE: Final = dict(REQUIRED_ROLES)
_MAX_BYTES_BY_ROLE: Final = {
    "concept_catalog": CATALOG_MAX_BYTES,
    "institution_catalog": CATALOG_MAX_BYTES,
    "historical_series_data": HISTORICAL_SERIES_MAX_BYTES,
}
_CATALOG_HEADER_BY_ROLE: Final = {
    "concept_catalog": CONCEPT_CATALOG_HEADER,
    "institution_catalog": INSTITUTION_CATALOG_HEADER,
}
_ZIP_MEDIA_TYPES: Final = frozenset(
    {
        "application/zip",
        "application/x-zip-compressed",
        "application/x-zip",
        "application/octet-stream",
    }
)
_CSV_MEDIA_TYPES: Final = frozenset(
    {
        "text/csv",
        "text/plain",
        "application/csv",
        "application/vnd.ms-excel",
        "application/octet-stream",
    }
)
_FILENAME_STAR_RE: Final = re.compile(
    r"filename\*\s*=\s*([^\s']*)''([^;]*)",
    re.IGNORECASE,
)
_FILENAME_QUOTED_RE: Final = re.compile(
    r'filename\s*=\s*"((?:[^"\\]|\\.)*)"',
    re.IGNORECASE,
)
_FILENAME_TOKEN_RE: Final = re.compile(
    r"filename\s*=\s*([^;\s]+)",
    re.IGNORECASE,
)

Clock = Callable[[], datetime]


def _contains_control_character(value: str) -> bool:
    return any(
        unicodedata.category(character) == "Cc" or character in "\u2028\u2029"
        for character in value
    )


def _unofficial(summary: str) -> UnofficialArtifactUrlError:
    return UnofficialArtifactUrlError(summary)


def authorize_cnbv_artifact_url(url: str) -> str:
    """Return ``url`` when it is an official HTTPS CNBV artifact URL.

    A rejection is an ``artifact_url_unofficial`` contract error. Callers must
    not send a request to a URL this function rejects.
    """
    if not isinstance(url, str) or url == "" or _contains_control_character(url):
        raise _unofficial("The artifact URL is outside the official source authority.")
    parts = urlsplit(url)
    if parts.scheme != "https":
        raise _unofficial("The artifact URL scheme is not https.")
    if parts.username is not None or parts.password is not None or "@" in parts.netloc:
        raise _unofficial("The artifact URL includes user information.")
    hostname = parts.hostname
    if hostname is not None and hostname.endswith("."):
        raise _unofficial("The artifact URL hostname has a trailing dot.")
    if (
        hostname is None
        or _contains_control_character(hostname)
        or hostname not in OFFICIAL_ARTIFACT_HOSTS
    ):
        reported_host = hostname if isinstance(hostname, str) else None
        if (
            reported_host is not None
            and not _contains_control_character(reported_host)
            and len(reported_host) <= 253
        ):
            raise _unofficial(
                f"The artifact URL host {reported_host} is not the official CNBV artifact host."
            )
        raise _unofficial("The artifact URL host is not the official CNBV artifact host.")
    try:
        port = parts.port
    except ValueError:
        raise _unofficial("The artifact URL port is not 443.") from None
    if port not in (None, _HTTPS_PORT):
        raise _unofficial("The artifact URL port is not 443.")
    if parts.query:
        raise _unofficial("The artifact URL includes a query.")
    if parts.fragment:
        raise _unofficial("The artifact URL includes a fragment.")
    return url


def _pinned_intermediate_pem() -> str:
    pem = (
        files("mx_bank_monitor.ingestion")
        .joinpath("trust", _INTERMEDIATE_FILENAME)
        .read_text(encoding="ascii")
    )
    digest = sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest()
    if digest != PINNED_INTERMEDIATE_DER_SHA256:
        raise RuntimeError(
            "The pinned GlobalSign intermediate does not match the reviewed fingerprint."
        )
    return pem


def cnbv_ssl_context() -> ssl.SSLContext:
    """Return certifi trust plus the reviewed GlobalSign RSA OV SSL CA 2018 intermediate.

    Verification stays required. This context never disables TLS checks.
    """
    context = ssl.create_default_context(cafile=certifi.where())
    context.load_verify_locations(cadata=_pinned_intermediate_pem())
    if context.verify_mode != ssl.CERT_REQUIRED or not context.check_hostname:
        raise RuntimeError("TLS verification must not be disabled.")
    return context


def logical_header_sha256(header: str) -> str:
    """Return the SHA-256 of one exact logical CSV header.

    The digest is the lowercase hexadecimal SHA-256 of ``header`` encoded as
    strict UTF-8. The header must already exclude a leading UTF-8 BOM and the
    line terminator. CRLF and LF observations of the same header therefore
    share one digest. No other byte is stripped or rewritten.
    """
    if not isinstance(header, str) or "\n" in header or "\r" in header or "\ufeff" in header:
        raise SourceContractError("a logical header must exclude the BOM and line terminator")
    if "\x00" in header:
        raise SourceContractError("a logical header must not contain a NUL")
    return sha256(header.encode("utf-8")).hexdigest()


def _artifact_url_key(url: str) -> tuple[str, int, str]:
    """Identity of an artifact URL under the CNBV authority comparison.

    Host case and the default HTTPS port are not distinct. The path remains
    exact. ``authorize_cnbv_artifact_url`` has already rejected a query,
    fragment, userinfo, and any non-443 port.
    """
    parts = urlsplit(url)
    hostname = parts.hostname or ""
    port = _HTTPS_PORT if parts.port is None else parts.port
    return (hostname, port, parts.path)


def _require_portfolio_source(source: SourceDefinition) -> tuple[int, dict[str, str]]:
    if type(source) is not SourceDefinition:
        raise SourceContractError("source must be a source definition")
    if source.code != "cnbv_portfolio":
        raise SourceContractError("source.code must be cnbv_portfolio")
    if source.adapter_key != "cnbv_portfolio":
        raise SourceContractError("source.adapter_key must be cnbv_portfolio")
    if set(source.formats) != {SourceFormat.CSV, SourceFormat.ZIP}:
        raise SourceContractError("source formats must be exactly csv and zip")

    urls: dict[str, str] = {}
    keys: list[tuple[str, int, str]] = []
    for endpoint in source.endpoints:
        if endpoint.kind != EndpointKind.ARTIFACT:
            continue
        role = endpoint.artifact_role
        artifact_format = endpoint.artifact_format
        if not isinstance(role, str) or artifact_format is None:
            raise SourceContractError("an artifact endpoint is missing its role or format")
        if role in urls:
            raise SourceContractError("artifact roles must be unique")
        expected = _REQUIRED_FORMAT_BY_ROLE.get(role)
        if expected is None:
            raise SourceContractError(
                "the source declares an artifact role outside the frozen contract"
            )
        if artifact_format != expected:
            raise SourceContractError(f"artifact role {role} has the wrong format")
        url = str(endpoint.url)
        authorize_cnbv_artifact_url(url)
        urls[role] = url
        keys.append(_artifact_url_key(url))

    found = set(urls)
    expected_roles = set(_REQUIRED_FORMAT_BY_ROLE)
    if found != expected_roles:
        if found - expected_roles:
            raise SourceContractError(
                "the source declares an artifact role outside the frozen contract"
            )
        raise SourceContractError("the source is missing a required artifact role")
    if len(keys) != len(set(keys)):
        raise SourceContractError("artifact endpoint URLs must be unique")
    return source.definition_version, urls


def _normalize_media_type(value: str | None) -> str:
    if value is None or _contains_control_character(value):
        raise UnexpectedMediaTypeError()
    media = value.strip().lower().split(";", 1)[0].strip()
    if media == "" or "/" not in media or any(character.isspace() for character in media):
        raise UnexpectedMediaTypeError()
    return media


def _reject_html(content: bytes) -> None:
    body = content[len(_UTF8_BOM) :] if content.startswith(_UTF8_BOM) else content
    meaningful = body.lstrip(_ASCII_WHITESPACE)
    if meaningful.startswith(b"<"):
        raise HtmlArtifactError()


def _split_first_line(payload: bytes) -> tuple[bytes, LineTerminator, bytes]:
    line_feed = payload.find(b"\n")
    carriage_return = payload.find(b"\r")
    if carriage_return >= 0 and (line_feed < 0 or carriage_return < line_feed):
        if line_feed == carriage_return + 1:
            return payload[:carriage_return], "crlf", payload[line_feed + 1 :]
        raise SourceLayoutDriftError("The artifact header has no recognizable line terminator.")
    if line_feed < 0:
        raise SourceLayoutDriftError("The artifact header has no recognizable line terminator.")
    return payload[:line_feed], "lf", payload[line_feed + 1 :]


def _logical_header(payload: bytes, expected: str) -> tuple[str, LineTerminator]:
    header_bytes, terminator, _rest = _split_first_line(payload)
    try:
        header = header_bytes.decode("utf-8")
    except UnicodeError:
        raise SourceLayoutDriftError("The artifact header is not strict UTF-8.") from None
    if header != expected:
        raise SourceLayoutDriftError("The artifact header does not match the frozen source layout.")
    return header, terminator


def _unsafe_zip_member_path(name: str) -> bool:
    if name == "" or _contains_control_character(name) or name.startswith(("/", "\\")):
        return True
    if ":" in name or "/" in name or "\\" in name:
        return True
    return name in {".", ".."}


def _validate_zip(content: bytes) -> ZipMemberStructure:
    try:
        archive: ZipFile = ZipFile(io.BytesIO(content))
    except (zipfile.BadZipFile, zipfile.LargeZipFile):
        raise ArtifactSignatureError("The artifact is not a valid ZIP archive.") from None
    with archive:
        members = archive.infolist()
        if len(members) != 1:
            raise SourceLayoutDriftError("The ZIP archive does not contain exactly one member.")
        info = members[0]
        name = info.filename
        if info.flag_bits & 0x1:
            raise SourceLayoutDriftError("The ZIP member is encrypted.")
        if info.is_dir():
            raise SourceLayoutDriftError("The ZIP member is a directory.")
        if _unsafe_zip_member_path(name):
            raise SourceLayoutDriftError("The ZIP member path is unsafe.")
        if name != HISTORICAL_MEMBER_NAME:
            raise SourceLayoutDriftError("The ZIP member is not sh_datos_40.csv.")
        if type(info.file_size) is not int or info.file_size <= 0:
            raise SourceLayoutDriftError("The ZIP member is empty.")
        if info.file_size > ZIP_MEMBER_MAX_UNCOMPRESSED_BYTES:
            raise SourceLayoutDriftError("The ZIP member exceeds the uncompressed size limit.")
        try:
            with archive.open(info, "r") as member:
                prefix = member.read(_HEADER_PROBE_BYTES)
        except zipfile.BadZipFile:
            raise ArtifactSignatureError("The artifact is not a valid ZIP archive.") from None
        except (RuntimeError, NotImplementedError, ValueError):
            raise SourceLayoutDriftError("The ZIP member could not be inspected.") from None
    header, _terminator = _logical_header(prefix, HISTORICAL_SERIES_HEADER)
    return ZipMemberStructure(
        member_name=name,
        member_uncompressed_size=info.file_size,
        header_sha256=logical_header_sha256(header),
    )


def _validate_catalog(content: bytes, expected_header: str) -> CsvTextStructure:
    if b"\x00" in content:
        raise SourceLayoutDriftError("The catalog contains a NUL byte.")
    try:
        content.decode("utf-8")
    except UnicodeError:
        raise SourceLayoutDriftError("The catalog is not strict UTF-8.") from None
    has_bom = content.startswith(_UTF8_BOM)
    body = content[len(_UTF8_BOM) :] if has_bom else content
    header_bytes, terminator, rest = _split_first_line(body)
    try:
        header = header_bytes.decode("utf-8")
    except UnicodeError:
        raise SourceLayoutDriftError("The catalog header is not strict UTF-8.") from None
    if header != expected_header:
        raise SourceLayoutDriftError(
            "The catalog header does not match the frozen source layout."
        )
    if not any(byte not in b"\r\n" for byte in rest):
        raise SourceLayoutDriftError("The catalog has no data row.")
    return CsvTextStructure(
        header_sha256=logical_header_sha256(header),
        has_bom=has_bom,
        line_terminator=terminator,
    )


def _safe_basename(candidate: str) -> str | None:
    if candidate == "" or _contains_control_character(candidate):
        return None
    base = candidate.replace("\\", "/").split("/")[-1].strip()
    if base in {"", ".", ".."} or _contains_control_character(base):
        return None
    if "/" in base or "\\" in base or ":" in base:
        return None
    return base


def _disposition_filename(header: str) -> str | None:
    if _contains_control_character(header):
        return None
    starred = _FILENAME_STAR_RE.search(header)
    if starred is not None:
        charset = starred.group(1).strip().lower()
        if charset not in {"", "utf-8", "ascii"}:
            return None
        try:
            decoded = unquote(starred.group(2).strip(), encoding="utf-8", errors="strict")
        except UnicodeError:
            return None
        return _safe_basename(decoded)
    quoted = _FILENAME_QUOTED_RE.search(header)
    if quoted is not None:
        raw = quoted.group(1).replace(r"\\", "\\").replace(r"\"", '"')
        return _safe_basename(raw)
    token = _FILENAME_TOKEN_RE.search(header)
    if token is not None:
        return _safe_basename(token.group(1).strip().strip('"'))
    return None


def _filename_from_url(url: str) -> str | None:
    try:
        decoded = unquote(urlsplit(url).path, encoding="utf-8", errors="strict")
    except UnicodeError:
        return None
    return _safe_basename(decoded)


def _artifact_filename(observation: HttpObservation) -> str:
    if observation.content_disposition:
        from_header = _disposition_filename(observation.content_disposition)
        if from_header is not None:
            return from_header
    from_url = _filename_from_url(observation.final_url)
    if from_url is None:
        raise SourceLayoutDriftError("The artifact filename is not a safe basename.")
    return from_url


def _public_url(value: str | None) -> str | None:
    if not isinstance(value, str) or value == "" or _contains_control_character(value):
        return None
    parts = urlsplit(value)
    if parts.username is not None or parts.password is not None or "@" in parts.netloc:
        return None
    return value


@dataclass(frozen=True, slots=True)
class ArtifactFailure:
    """Audit-safe failure for one artifact. It never carries a response body."""

    artifact_role: str
    observed_url: str
    error_code: str
    error_summary: str
    observed_at: datetime
    final_url: str | None = None
    http_status_code: int | None = None
    http_etag: str | None = None
    http_last_modified: str | None = None
    http_content_length: int | None = None
    observation: HttpObservation | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.artifact_role, str) or self.artifact_role == "":
            raise SourceContractError("artifact_role must be non-empty text")
        if _public_url(self.observed_url) != self.observed_url:
            raise SourceContractError("observed_url is not a public artifact URL")
        if not is_audit_error_code(self.error_code):
            raise SourceContractError("error_code is not audit compatible")
        if (
            not isinstance(self.error_summary, str)
            or self.error_summary == ""
            or self.error_summary != sanitize_summary(self.error_summary)
        ):
            raise SourceContractError("error_summary is not audit compatible")
        if (
            not isinstance(self.observed_at, datetime)
            or self.observed_at.utcoffset() is None
        ):
            raise SourceContractError("observed_at must be a timezone-aware datetime")
        if self.final_url is not None and _public_url(self.final_url) != self.final_url:
            raise SourceContractError("final_url is not a public artifact URL")
        if self.http_status_code is not None and type(self.http_status_code) is not int:
            raise SourceContractError("http_status_code must be an integer when present")
        if self.http_content_length is not None and (
            type(self.http_content_length) is not int or self.http_content_length < 0
        ):
            raise SourceContractError("http_content_length must be a non-negative integer")
        for label, value in (
            ("http_etag", self.http_etag),
            ("http_last_modified", self.http_last_modified),
        ):
            if value is not None and not isinstance(value, str):
                raise SourceContractError(f"{label} must be text when present")


@dataclass(frozen=True, slots=True)
class ObservationOutcome:
    """One complete observation, or the first artifact failure. Never both."""

    release: ObservedRelease | None
    failure: ArtifactFailure | None

    def __post_init__(self) -> None:
        if (self.release is None) == (self.failure is None):
            raise SourceContractError(
                "an observation outcome must contain a release or a failure"
            )
        if self.release is not None and type(self.release) is not ObservedRelease:
            raise SourceContractError("observation release must be an observed release")
        if self.failure is not None and type(self.failure) is not ArtifactFailure:
            raise SourceContractError("observation failure must be an artifact failure")


def _fallback_observed_at(clock: Clock | None) -> datetime:
    """Return one UTC timestamp when retrieval failed before any HTTP observation.

    The clock is called only on this path, so a stateful clock is not consumed
    while an ``HttpObservation`` already supplies the time.
    """
    if not callable(clock):
        raise SourceContractError(
            "a failure before an HTTP observation requires the adapter clock"
        )
    moment = clock()
    offset = moment.utcoffset() if isinstance(moment, datetime) else None
    if not isinstance(moment, datetime) or offset is None:
        raise SourceContractError("the adapter clock must return a timezone-aware datetime")
    if offset != timedelta(0):
        raise SourceContractError("the adapter clock must return UTC")
    return moment


def _failure_for(
    artifact: DiscoveredArtifact,
    exc: DiscoveryError,
    downloaded: DownloadedArtifact | None,
    clock: Clock | None,
) -> ArtifactFailure:
    final: str | None = None
    observation: HttpObservation | None = None
    if isinstance(exc, ArtifactRetrievalError):
        final = _public_url(exc.final_url)
        observation = exc.observation
    elif downloaded is not None and type(downloaded.observation) is HttpObservation:
        observation = downloaded.observation
    if observation is not None:
        observed_at = observation.observed_at
        if final is None:
            final = _public_url(observation.final_url)
        http_status_code: int | None = observation.status_code
        http_etag = observation.etag
        http_last_modified = observation.last_modified
        http_content_length = observation.content_length
    else:
        observed_at = _fallback_observed_at(clock)
        http_status_code = None
        http_etag = None
        http_last_modified = None
        http_content_length = None
    return ArtifactFailure(
        artifact_role=artifact.artifact_role,
        observed_url=artifact.original_url,
        error_code=type(exc).code,
        error_summary=exc.safe_summary,
        observed_at=observed_at,
        final_url=final,
        http_status_code=http_status_code,
        http_etag=http_etag,
        http_last_modified=http_last_modified,
        http_content_length=http_content_length,
        observation=observation,
    )


class CnbvPortfolioAdapter:
    """Discover, retrieve, and structurally validate the CNBV portfolio package.

    Construction checks the source contract shape only. It does not read source
    lifecycle and does not decide production eligibility. A response-backed
    failure uses ``HttpObservation.observed_at``. When retrieval fails before
    any observation exists, ``clock`` supplies that timestamp. The clock is not
    called during construction.
    """

    def __init__(self, source: SourceDefinition, *, clock: Clock | None = None) -> None:
        if clock is not None and not callable(clock):
            raise SourceContractError("clock must be callable")
        definition_version, urls = _require_portfolio_source(source)
        self._clock = clock
        self._definition_version = definition_version
        self._urls_by_role: Mapping[str, str] = urls

    def discover(self) -> DiscoveredRelease:
        """Build one discovered release from configuration, without network access."""
        return DiscoveredRelease(
            source_code="cnbv_portfolio",
            source_definition_version=self._definition_version,
            release_family_key=RELEASE_FAMILY_KEY,
            identity_scheme=IDENTITY_SCHEME,
            artifacts=tuple(
                DiscoveredArtifact(
                    artifact_role=role,
                    artifact_format=artifact_format,
                    original_url=self._urls_by_role[role],
                )
                for role, artifact_format in REQUIRED_ROLES
            ),
        )

    def retrieve(
        self, artifact: DiscoveredArtifact, client: HttpArtifactClient
    ) -> DownloadedArtifact:
        """Retrieve one configured artifact through the authority-sensitive client."""
        if type(artifact) is not DiscoveredArtifact:
            raise SourceContractError("artifact must be a discovered artifact")
        expected = _REQUIRED_FORMAT_BY_ROLE.get(artifact.artifact_role)
        if expected is None or artifact.artifact_format != expected:
            raise SourceContractError("artifact role and format are outside the frozen contract")
        if self._urls_by_role.get(artifact.artifact_role) != artifact.original_url:
            raise SourceContractError("artifact URL is not the configured source endpoint")
        authorize_cnbv_artifact_url(artifact.original_url)
        if not isinstance(client, HttpArtifactClient):
            raise SourceContractError("client must be an HTTP artifact client")
        return client.retrieve(
            artifact.original_url,
            authorize=authorize_cnbv_artifact_url,
            max_bytes=_MAX_BYTES_BY_ROLE[artifact.artifact_role],
        )

    def validate(
        self, artifact: DiscoveredArtifact, downloaded: DownloadedArtifact
    ) -> ValidatedArtifact:
        """Validate exact bytes against the frozen structural contract for ``artifact``."""
        if type(artifact) is not DiscoveredArtifact:
            raise SourceContractError("artifact must be a discovered artifact")
        if type(downloaded) is not DownloadedArtifact:
            raise SourceContractError("downloaded artifact is required")
        observation = downloaded.observation
        if type(observation) is not HttpObservation:
            raise SourceContractError("downloaded observation is required")
        expected = _REQUIRED_FORMAT_BY_ROLE.get(artifact.artifact_role)
        if expected is None or artifact.artifact_format != expected:
            raise SourceContractError("artifact role and format are outside the frozen contract")
        content = downloaded.content
        if type(content) is not bytes:
            raise SourceContractError("downloaded content must be bytes")
        if content == b"":
            raise EmptyArtifactError()
        if observation.requested_url != artifact.original_url:
            raise SourceContractError("the download does not match the discovered artifact URL")
        if downloaded.url != observation.final_url:
            raise SourceContractError("the download URL does not match its observation")
        authorize_cnbv_artifact_url(observation.requested_url)
        authorize_cnbv_artifact_url(observation.final_url)
        _reject_html(content)
        media_type = _normalize_media_type(
            observation.content_type
            if observation.content_type is not None
            else downloaded.content_type
        )
        allowed = (
            _ZIP_MEDIA_TYPES
            if artifact.artifact_format == SourceFormat.ZIP
            else _CSV_MEDIA_TYPES
        )
        if media_type not in allowed:
            raise UnexpectedMediaTypeError()
        if artifact.artifact_format == SourceFormat.ZIP:
            structure: ZipMemberStructure | CsvTextStructure = _validate_zip(content)
        else:
            structure = _validate_catalog(content, _CATALOG_HEADER_BY_ROLE[artifact.artifact_role])
        return ValidatedArtifact(
            artifact_role=artifact.artifact_role,
            artifact_format=artifact.artifact_format,
            filename=_artifact_filename(observation),
            catalog_mime_type=media_type,
            sha256=sha256(content).hexdigest(),
            byte_length=len(content),
            content=content,
            http=observation,
            structure=structure,
        )

    def observe(self, client: HttpArtifactClient) -> ObservationOutcome:
        """Retrieve the package in catalog-then-archive order and fail on the first error."""
        discovered = self.discover()
        by_role = {item.artifact_role: item for item in discovered.artifacts}
        validated: list[ValidatedArtifact] = []
        for role in RETRIEVAL_ORDER:
            artifact = by_role[role]
            downloaded: DownloadedArtifact | None = None
            try:
                downloaded = self.retrieve(artifact, client)
                validated.append(self.validate(artifact, downloaded))
            except DiscoveryError as exc:
                return ObservationOutcome(
                    release=None,
                    failure=_failure_for(artifact, exc, downloaded, self._clock),
                )
        return ObservationOutcome(
            release=ObservedRelease.from_validated_artifacts(discovered, validated),
            failure=None,
        )
