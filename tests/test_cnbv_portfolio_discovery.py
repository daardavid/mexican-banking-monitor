import ast
import hashlib
import inspect
import io
import re
import socket
import ssl
import zipfile
from collections.abc import Callable
from datetime import UTC, datetime, timedelta, timezone
from hashlib import sha256
from pathlib import Path

import certifi
import httpx
import pytest
from pydantic import ValidationError

from mx_bank_monitor.config.loader import load_config_bundle
from mx_bank_monitor.config.models import DefinitionLifecycle, SourceDefinition
from mx_bank_monitor.ingestion import cnbv_portfolio
from mx_bank_monitor.ingestion.cnbv_portfolio import (
    CATALOG_MAX_BYTES,
    HISTORICAL_SERIES_MAX_BYTES,
    IDENTITY_SCHEME,
    OFFICIAL_ARTIFACT_HOST,
    OFFICIAL_ARTIFACT_HOSTS,
    PINNED_INTERMEDIATE_DER_SHA256,
    RELEASE_FAMILY_KEY,
    ZIP_MEMBER_MAX_UNCOMPRESSED_BYTES,
    ArtifactFailure,
    CnbvPortfolioAdapter,
    ObservationOutcome,
    authorize_cnbv_artifact_url,
    cnbv_ssl_context,
    logical_header_sha256,
)
from mx_bank_monitor.ingestion.discovery import (
    ArtifactSignatureError,
    CsvTextStructure,
    DiscoveredArtifact,
    EmptyArtifactError,
    HtmlArtifactError,
    HttpObservation,
    ObservedRelease,
    ReleaseMetadata,
    SourceContractError,
    SourceLayoutDriftError,
    UnexpectedMediaTypeError,
    UnofficialArtifactUrlError,
    ZipMemberStructure,
    artifact_set_identity_hash,
    is_audit_error_code,
)
from mx_bank_monitor.ingestion.http import DownloadedArtifact, HttpArtifactClient

HOST = OFFICIAL_ARTIFACT_HOST
SECRET = "SuperSecretValue"
USERNAME = "leak-user"
FROZEN_DER_SHA256 = "b676ffa3179e8812093a1b5eafee876ae7a6aaf231078dad1bfb21cd2893764a"
OFFICIAL_PATH = (
    "https://portafolioinfdoctos.cnbv.gob.mx/Documentacion/minfo/"
    "CSV/series_historicas/BM/sh_datos_csv_40.zip"
)


def test_source_constants_match_the_frozen_identity_names() -> None:
    assert IDENTITY_SCHEME == "cnbv_portfolio.observed_artifact_set.v1"
    assert RELEASE_FAMILY_KEY == "serie_historica_banca_multiple_40"
    assert frozenset({HOST}) == OFFICIAL_ARTIFACT_HOSTS


@pytest.mark.parametrize(
    "url",
    [
        f"https://{HOST}/historical.zip",
        f"https://{HOST}:443/historical.zip",
        f"https://{HOST}/",
        "https://PortafolioInfDoctos.CNBV.gob.mx/historical.zip",
        OFFICIAL_PATH,
    ],
)
def test_authorize_accepts_official_https_artifact_urls(url: str) -> None:
    assert authorize_cnbv_artifact_url(url) == url


@pytest.mark.parametrize(
    ("url", "summary_part"),
    [
        (f"http://{HOST}/historical.zip", "scheme is not https"),
        (f"https://{USERNAME}:{SECRET}@{HOST}/historical.zip", "user information"),
        (f"https://{HOST}:8443/historical.zip", "port is not 443"),
        (f"https://{HOST}/historical.zip?x=1", "includes a query"),
        (f"https://{HOST}/historical.zip#section", "includes a fragment"),
        (f"https://{HOST}./historical.zip", "trailing dot"),
        ("https://evil.example/historical.zip", "evil.example"),
        ("https://portafolioinfo.cnbv.gob.mx/historical.zip", "portafolioinfo.cnbv.gob.mx"),
        ("/historical.zip", "scheme is not https"),
        ("", "outside the official source authority"),
    ],
)
def test_authorize_rejects_unofficial_urls(url: str, summary_part: str) -> None:
    with pytest.raises(UnofficialArtifactUrlError) as raised:
        authorize_cnbv_artifact_url(url)

    error = raised.value
    assert error.code == "artifact_url_unofficial"
    assert is_audit_error_code(error.code)
    assert summary_part in error.safe_summary
    assert len(error.safe_summary) <= 512
    assert SECRET not in error.safe_summary
    assert USERNAME not in error.safe_summary
    assert SECRET not in str(error)
    assert USERNAME not in str(error)


def test_userinfo_rejection_does_not_echo_credentials() -> None:
    url = f"https://{USERNAME}:{SECRET}@{HOST}/historical.zip"

    with pytest.raises(UnofficialArtifactUrlError) as raised:
        authorize_cnbv_artifact_url(url)

    rendered = f"{raised.value!s} {raised.value!r} {raised.value.safe_summary}"
    assert SECRET not in rendered
    assert USERNAME not in rendered


def test_packaged_intermediate_matches_the_frozen_der_fingerprint() -> None:
    pem = (
        Path(cnbv_portfolio.__file__).parent.joinpath(
            "trust", "globalsign-rsa-ov-ssl-ca-2018.pem"
        )
    ).read_text(encoding="ascii")
    der = ssl.PEM_cert_to_DER_cert(pem)

    assert hashlib.sha256(der).hexdigest() == FROZEN_DER_SHA256
    assert PINNED_INTERMEDIATE_DER_SHA256 == FROZEN_DER_SHA256


def test_cnbv_ssl_context_uses_certifi_plus_the_pinned_intermediate() -> None:
    pem = (
        Path(cnbv_portfolio.__file__).parent.joinpath(
            "trust", "globalsign-rsa-ov-ssl-ca-2018.pem"
        )
    ).read_text(encoding="ascii")
    der = ssl.PEM_cert_to_DER_cert(pem)
    context = cnbv_ssl_context()
    base = ssl.create_default_context(cafile=certifi.where())
    pinned = set(context.get_ca_certs(binary_form=True))
    trusted = set(base.get_ca_certs(binary_form=True))

    assert isinstance(context, ssl.SSLContext)
    assert context.verify_mode == ssl.CERT_REQUIRED
    assert context.check_hostname is True
    assert der in pinned
    assert trusted <= pinned
    assert len(pinned) == len(trusted) + (0 if der in trusted else 1)


def test_portfolio_module_exposes_the_adapter_and_not_a_fact_parser() -> None:
    tree = ast.parse(Path(cnbv_portfolio.__file__).read_text(encoding="utf-8"))
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            names.update(target.id for target in node.targets if isinstance(target, ast.Name))
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            names.add(node.target.id)

    assert {"CnbvPortfolioAdapter", "REQUIRED_ROLES", "RETRIEVAL_ORDER"} <= names
    forbidden = {
        "parse_facts",
        "parse_period",
        "extract_institutions",
        "extract_concepts",
        "reported_fact",
        "covered_period",
        "ArtifactStore",
    }
    assert names.isdisjoint(forbidden)
    assert not any(
        isinstance(node, ast.Attribute) and node.attr == "lifecycle" for node in ast.walk(tree)
    )


def test_portfolio_module_imports_http_only_for_retrieval() -> None:
    tree = ast.parse(Path(cnbv_portfolio.__file__).read_text(encoding="utf-8"))
    imported: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module is not None:
            imported.add(node.module)

    assert "httpx" not in imported
    assert "mx_bank_monitor.ingestion.http" in imported
    assert "mx_bank_monitor.ingestion.discovery" in imported
    assert "mx_bank_monitor.ingestion.artifacts" not in imported
    assert "mx_bank_monitor.persistence" not in imported
    assert "mx_bank_monitor.cli" not in imported


CONCEPT_URL = (
    "https://portafolioinfdoctos.cnbv.gob.mx/Documentacion/minfo/"
    "CSV/series_historicas/BM/cat_conceptos_40.csv"
)
INSTITUTION_URL = (
    "https://portafolioinfdoctos.cnbv.gob.mx/Documentacion/minfo/"
    "CSV/series_historicas/BM/cat_instituciones_40.csv"
)
SERIES_URL = (
    "https://portafolioinfdoctos.cnbv.gob.mx/Documentacion/minfo/"
    "CSV/series_historicas/BM/sh_datos_csv_40.zip"
)
LANDING_URL = "https://portafolioinfo.cnbv.gob.mx/Paginas/Inicio.aspx"
SERIES_HEADER = '"sector","idconcepto","entidad","periodo","saldo","valor"'
CONCEPT_HEADER = '"sector","idtema","idconcepto","descripcion","nivel","indicador","orden"'
INSTITUTION_HEADER = '"sector","entidad","nombre_entidad","grupo","nombre_grupo","orden"'
MEMBER_NAME = "sh_datos_40.csv"
OBSERVED_AT = datetime(2026, 10, 3, 12, 0, tzinfo=UTC)
SECRET = "SuperSecretValue"
_CONTROL_CHARACTERS = re.compile(r"[\x00-\x1f\x7f-\x9f\u2028\u2029]")


def _endpoint_rows() -> list[dict[str, str]]:
    return [
        {"kind": "landing_page", "url": LANDING_URL},
        {
            "kind": "artifact",
            "artifact_role": "historical_series_data",
            "artifact_format": "zip",
            "url": SERIES_URL,
        },
        {
            "kind": "artifact",
            "artifact_role": "concept_catalog",
            "artifact_format": "csv",
            "url": CONCEPT_URL,
        },
        {
            "kind": "artifact",
            "artifact_role": "institution_catalog",
            "artifact_format": "csv",
            "url": INSTITUTION_URL,
        },
    ]


def _source_payload(**overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "code": "cnbv_portfolio",
        "definition_version": 1,
        "label": "CNBV Portfolio Information",
        "regulator_code": "cnbv",
        "country": "MX",
        "sector": "banca_multiple",
        "adapter_key": "cnbv_portfolio",
        "methodological_role": "primary",
        "formats": ["csv", "zip"],
        "endpoints": _endpoint_rows(),
        "reporting_scope_codes": ["individual_legal_entity"],
        "lifecycle": "draft",
    }
    payload.update(overrides)
    return payload


def _source(**overrides: object) -> SourceDefinition:
    return SourceDefinition.model_validate(_source_payload(**overrides))


def _adapter(**overrides: object) -> CnbvPortfolioAdapter:
    return CnbvPortfolioAdapter(_source(**overrides))


def _repository_source() -> SourceDefinition:
    bundle = load_config_bundle(Path(__file__).resolve().parents[1] / "config")
    return next(item for item in bundle.sources.sources if item.code == "cnbv_portfolio")


def _catalog(
    header: str,
    row: str = '"40","row"',
    *,
    terminator: str = "\n",
    bom: bool = False,
) -> bytes:
    raw = f"{header}{terminator}{row}{terminator}".encode()
    if bom:
        return b"\xef\xbb\xbf" + raw
    return raw


def _series_member(terminator: bytes = b"\n") -> bytes:
    return (
        SERIES_HEADER.encode()
        + terminator
        + b'"40","1","010001","202601","0","1"'
        + terminator
    )


def _zip_bytes(members: list[tuple[str, bytes]], *, stored: bool = False) -> bytes:
    buffer = io.BytesIO()
    compression = zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
    with zipfile.ZipFile(buffer, "w", compression=compression) as archive:
        for name, payload in members:
            archive.writestr(name, payload)
    return buffer.getvalue()


def _valid_zip(terminator: bytes = b"\n") -> bytes:
    return _zip_bytes([(MEMBER_NAME, _series_member(terminator))])


def _patch_encryption(payload: bytes) -> bytes:
    raw = bytearray(payload)
    for marker, offset in ((b"PK\x03\x04", 6), (b"PK\x01\x02", 8)):
        index = raw.find(marker)
        raw[index + offset] |= 0x01
    return bytes(raw)


def _patch_uncompressed_size(payload: bytes, size: int) -> bytes:
    raw = bytearray(payload)
    index = raw.rfind(b"PK\x01\x02")
    raw[index + 24 : index + 28] = size.to_bytes(4, "little")
    return bytes(raw)


def _body_for(role: str, *, concept_row: str = '"40","concept"') -> bytes:
    if role == "historical_series_data":
        return _valid_zip()
    if role == "institution_catalog":
        return _catalog(INSTITUTION_HEADER, row='"40","1","Banco","g","Grupo","1"')
    return _catalog(CONCEPT_HEADER, row=concept_row)


def _downloaded(
    artifact: DiscoveredArtifact,
    content: bytes,
    *,
    content_type: str = "application/octet-stream",
    disposition: str | None = None,
    final_url: str | None = None,
    observed_at: datetime = OBSERVED_AT,
) -> DownloadedArtifact:
    final = artifact.original_url if final_url is None else final_url
    chain = () if final == artifact.original_url else (final,)
    observation = HttpObservation(
        requested_url=artifact.original_url,
        final_url=final,
        redirect_chain=chain,
        status_code=200,
        content_type=content_type or None,
        content_length=len(content),
        content_encoding=None,
        etag=None,
        last_modified=None,
        content_disposition=disposition,
        observed_at=observed_at,
    )
    return DownloadedArtifact(
        url=final,
        content=content,
        content_type=content_type,
        observation=observation,
    )


def _artifact(adapter: CnbvPortfolioAdapter, role: str) -> DiscoveredArtifact:
    return next(item for item in adapter.discover().artifacts if item.artifact_role == role)


def _assert_safe_summary(summary: str) -> None:
    assert summary
    assert len(summary) <= 512
    assert _CONTROL_CHARACTERS.search(summary) is None
    assert SECRET not in summary


class RecordingClient(HttpArtifactClient):
    def __init__(self, transport: httpx.BaseTransport, clock: Callable[[], datetime]) -> None:
        super().__init__(transport=transport, clock=clock, sleeper=lambda _delay: None)
        self.calls: list[tuple[str, object, int | None]] = []
        self.download_calls = 0

    def retrieve(
        self,
        url: str,
        *,
        authorize: Callable[[str], object],
        max_redirects: int = 3,
        max_bytes: int | None = None,
    ) -> DownloadedArtifact:
        self.calls.append((url, authorize, max_bytes))
        return super().retrieve(
            url,
            authorize=authorize,
            max_redirects=max_redirects,
            max_bytes=max_bytes,
        )

    def download(self, url: str) -> DownloadedArtifact:
        self.download_calls += 1
        raise AssertionError("legacy download")


def _transport(
    routes: dict[str, tuple[int, dict[str, str], bytes]],
) -> httpx.MockTransport:
    def handler(request: httpx.Request) -> httpx.Response:
        status, headers, body = routes[str(request.url)]
        return httpx.Response(
            status,
            headers=headers,
            stream=httpx.ByteStream(body),
            request=request,
        )

    return httpx.MockTransport(handler)


def _clock(moments: list[datetime]) -> Callable[[], datetime]:
    pending = iter(moments)

    def current() -> datetime:
        return next(pending)

    return current


def _routes(
    adapter: CnbvPortfolioAdapter,
    *,
    concept_row: str = '"40","concept"',
    concept_status: int = 200,
    institution_status: int = 200,
    series_status: int = 200,
    series_body: bytes | None = None,
    concept_type: str = "text/csv",
    institution_type: str = "application/octet-stream",
    series_type: str = "application/zip",
    concept_disposition: str | None = None,
) -> dict[str, tuple[int, dict[str, str], bytes]]:
    routes: dict[str, tuple[int, dict[str, str], bytes]] = {}
    concept_body = _body_for("concept_catalog", concept_row=concept_row)
    institution_body = _body_for("institution_catalog")
    historical_body = series_body or _body_for("historical_series_data")
    specs = (
        ("concept_catalog", concept_status, concept_type, concept_body, concept_disposition),
        ("institution_catalog", institution_status, institution_type, institution_body, None),
        ("historical_series_data", series_status, series_type, historical_body, None),
    )
    for role, status, media, body, disposition in specs:
        headers = {"content-type": media, "content-length": str(len(body))}
        if disposition is not None:
            headers["content-disposition"] = disposition
        routes[_artifact(adapter, role).original_url] = (status, headers, body)
    return routes


def test_d1_repository_config_constructs_the_adapter() -> None:
    adapter = CnbvPortfolioAdapter(_repository_source())
    release = adapter.discover()

    assert release.source_code == "cnbv_portfolio"
    assert release.source_definition_version == 1
    assert release.identity_scheme == IDENTITY_SCHEME
    assert release.release_family_key == RELEASE_FAMILY_KEY
    assert [item.original_url for item in release.artifacts] == [
        CONCEPT_URL,
        SERIES_URL,
        INSTITUTION_URL,
    ]


def test_d2_wrong_source_code_is_rejected() -> None:
    with pytest.raises(SourceContractError) as raised:
        _adapter(code="other_source")

    assert raised.value.code == "source_contract_invalid"


def test_d3_wrong_adapter_key_is_rejected() -> None:
    with pytest.raises(SourceContractError) as raised:
        _adapter(adapter_key="cnbv_bulletin")

    assert raised.value.code == "source_contract_invalid"


def test_d4_missing_required_role_is_rejected() -> None:
    endpoints = [
        row for row in _endpoint_rows() if row.get("artifact_role") != "institution_catalog"
    ]

    with pytest.raises(SourceContractError) as raised:
        _adapter(endpoints=endpoints)

    assert "missing" in raised.value.safe_summary


def test_d5_extra_role_is_rejected() -> None:
    endpoints = _endpoint_rows()
    endpoints.append(
        {
            "kind": "artifact",
            "artifact_role": "notes",
            "artifact_format": "csv",
            "url": f"https://{HOST}/notes.csv",
        }
    )

    with pytest.raises(SourceContractError) as raised:
        _adapter(endpoints=endpoints)

    assert "outside the frozen contract" in raised.value.safe_summary


def test_d6_duplicate_role_is_rejected_by_config() -> None:
    endpoints = _endpoint_rows()
    endpoints.append(
        {
            "kind": "artifact",
            "artifact_role": "concept_catalog",
            "artifact_format": "csv",
            "url": f"https://{HOST}/other_concepts.csv",
        }
    )

    with pytest.raises(ValidationError) as raised:
        _source(endpoints=endpoints)

    assert "duplicate artifact role" in str(raised.value)


def test_duplicate_artifact_url_is_rejected_by_config() -> None:
    endpoints = _endpoint_rows()
    for row in endpoints:
        if row.get("artifact_role") == "institution_catalog":
            row["url"] = CONCEPT_URL

    with pytest.raises(ValidationError) as raised:
        _source(endpoints=endpoints)

    assert "duplicate source endpoint" in str(raised.value)


def test_d7_wrong_role_format_is_rejected() -> None:
    endpoints = _endpoint_rows()
    for row in endpoints:
        if row.get("artifact_role") == "concept_catalog":
            row["artifact_format"] = "zip"

    with pytest.raises(SourceContractError) as raised:
        _adapter(endpoints=endpoints)

    assert "wrong format" in raised.value.safe_summary


def test_d8_unauthorized_artifact_url_is_rejected_before_network(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fail(*_args: object, **_kwargs: object) -> None:
        raise AssertionError("network")

    monkeypatch.setattr(socket, "create_connection", fail)
    endpoints = _endpoint_rows()
    for row in endpoints:
        if row.get("artifact_role") == "concept_catalog":
            row["url"] = "https://evil.example/cat.csv"

    with pytest.raises(UnofficialArtifactUrlError) as raised:
        _adapter(endpoints=endpoints)

    assert raised.value.code == "artifact_url_unofficial"


def test_source_formats_must_be_exactly_csv_and_zip() -> None:
    with pytest.raises(SourceContractError):
        _adapter(formats=["csv", "zip", "pdf"])


def test_l1_every_lifecycle_discovers_the_same_release() -> None:
    baseline = _adapter().discover()

    for lifecycle in DefinitionLifecycle:
        discovered = _adapter(lifecycle=lifecycle.value).discover()
        assert discovered == baseline

    assert "production_eligible" not in dir(CnbvPortfolioAdapter)
    parameters = inspect.signature(CnbvPortfolioAdapter.discover).parameters
    assert list(parameters) == ["self"]
    assert "period" not in inspect.signature(CnbvPortfolioAdapter.observe).parameters


def test_clock_does_not_change_discovery() -> None:
    source = _source()
    with_clock = CnbvPortfolioAdapter(source, clock=lambda: OBSERVED_AT)
    without_clock = CnbvPortfolioAdapter(source)

    assert with_clock.discover() == without_clock.discover()


def test_discover_is_deterministic_and_does_not_use_the_network(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def fail(*_args: object, **_kwargs: object) -> None:
        raise AssertionError("network")

    monkeypatch.setattr(socket, "create_connection", fail)
    adapter = _adapter(endpoints=[row for row in _endpoint_rows() if row["kind"] == "artifact"])
    release = adapter.discover()

    assert release.revision is None
    assert release.published_at is None
    assert release.covered_period_start is None
    assert release.covered_period_end is None
    assert release.identity_scheme == IDENTITY_SCHEME
    assert release.release_family_key == RELEASE_FAMILY_KEY
    assert [item.artifact_role for item in release.artifacts] == [
        "concept_catalog",
        "historical_series_data",
        "institution_catalog",
    ]
    assert [item.artifact_format.value for item in release.artifacts] == ["csv", "zip", "csv"]
    assert adapter.discover() == release


@pytest.mark.parametrize(
    "media",
    [
        "application/zip",
        "application/x-zip-compressed",
        "application/x-zip",
        "application/octet-stream",
        " Application/ZIP ; charset=binary ",
    ],
)
def test_allowed_zip_media_types_are_normalized(media: str) -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "historical_series_data")
    validated = adapter.validate(artifact, _downloaded(artifact, _valid_zip(), content_type=media))

    assert validated.catalog_mime_type == media.strip().lower().split(";", 1)[0].strip()


@pytest.mark.parametrize(
    "media",
    [
        "text/csv",
        "text/plain",
        "application/csv",
        "application/vnd.ms-excel",
        "application/octet-stream",
        " Text/CSV ; charset=UTF-8 ",
    ],
)
def test_allowed_csv_media_types_are_normalized(media: str) -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "concept_catalog")
    validated = adapter.validate(
        artifact, _downloaded(artifact, _catalog(CONCEPT_HEADER), content_type=media)
    )

    assert validated.catalog_mime_type == media.strip().lower().split(";", 1)[0].strip()


@pytest.mark.parametrize("media", ["text/html", "application/pdf", "application/json", "text/csv"])
def test_zip_rejects_incompatible_media_types(media: str) -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "historical_series_data")

    with pytest.raises(UnexpectedMediaTypeError) as raised:
        adapter.validate(artifact, _downloaded(artifact, _valid_zip(), content_type=media))

    assert raised.value.code == "artifact_media_type_unexpected"


@pytest.mark.parametrize(
    "media",
    ["application/zip", "application/pdf", "text/html", "application/json", ""],
)
def test_catalog_rejects_incompatible_media_types(media: str) -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "institution_catalog")

    with pytest.raises(UnexpectedMediaTypeError) as raised:
        adapter.validate(
            artifact,
            _downloaded(artifact, _catalog(INSTITUTION_HEADER), content_type=media),
        )

    assert raised.value.code == "artifact_media_type_unexpected"


def test_valid_bytes_with_forbidden_media_are_rejected() -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "concept_catalog")

    with pytest.raises(UnexpectedMediaTypeError):
        adapter.validate(
            artifact,
            _downloaded(artifact, _catalog(CONCEPT_HEADER), content_type="application/pdf"),
        )


def test_allowed_media_does_not_accept_invalid_bytes() -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "historical_series_data")

    with pytest.raises(ArtifactSignatureError) as raised:
        adapter.validate(artifact, _downloaded(artifact, b"hello", content_type="application/zip"))

    assert raised.value.code == "artifact_signature_invalid"


@pytest.mark.parametrize(
    "content",
    [b" \r\n<html>secret</html>", b"\xef\xbb\xbf\n<!DOCTYPE html>", b"\t<HTML>"],
)
def test_html_payloads_are_rejected_before_format_parsing(content: bytes) -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "concept_catalog")

    with pytest.raises(HtmlArtifactError) as raised:
        adapter.validate(
            artifact,
            _downloaded(artifact, content, content_type="application/octet-stream"),
        )

    assert raised.value.code == "artifact_html_response"
    assert "<" not in raised.value.safe_summary
    assert SECRET not in raised.value.safe_summary


def test_empty_artifact_is_rejected() -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "concept_catalog")

    with pytest.raises(EmptyArtifactError) as raised:
        adapter.validate(artifact, _downloaded(artifact, b""))

    assert raised.value.code == "artifact_empty"


@pytest.mark.parametrize("terminator", [b"\n", b"\r\n"])
def test_valid_zip_accepts_the_frozen_header(terminator: bytes) -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "historical_series_data")
    validated = adapter.validate(artifact, _downloaded(artifact, _valid_zip(terminator)))
    structure = validated.structure
    digest = sha256(SERIES_HEADER.encode()).hexdigest()

    assert isinstance(structure, ZipMemberStructure)
    assert structure.member_name == MEMBER_NAME
    assert structure.member_uncompressed_size > 0
    assert structure.header_sha256 == digest
    assert logical_header_sha256(SERIES_HEADER) == digest
    assert validated.sha256 == sha256(validated.content).hexdigest()
    assert validated.byte_length == len(validated.content)
    assert validated.filename == "sh_datos_csv_40.zip"


@pytest.mark.parametrize(
    ("members", "summary_part"),
    [
        (
            [("[Content_Types].xml", b"<Types></Types>"), ("xl/workbook.xml", b"<workbook/>")],
            "exactly one",
        ),
        ([("[Content_Types].xml", b"<Types></Types>")], "sh_datos_40.csv"),
        ([(MEMBER_NAME, _series_member()), ("notes.txt", b"note")], "exactly one"),
        ([("../sh_datos_40.csv", _series_member())], "unsafe"),
        ([("/sh_datos_40.csv", _series_member())], "unsafe"),
        ([(MEMBER_NAME + "/", b"")], "directory"),
        ([(MEMBER_NAME, b"")], "empty"),
        ([(MEMBER_NAME, b'"sector","nope"\n"40"\n')], "header"),
        ([(MEMBER_NAME, SERIES_HEADER.encode())], "line terminator"),
    ],
)
def test_zip_layout_drift_is_rejected(
    members: list[tuple[str, bytes]], summary_part: str
) -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "historical_series_data")

    with pytest.raises(SourceLayoutDriftError) as raised:
        adapter.validate(
            artifact,
            _downloaded(artifact, _zip_bytes(members), content_type="application/zip"),
        )

    assert raised.value.code == "source_layout_drift"
    assert summary_part in raised.value.safe_summary


def test_encrypted_zip_member_is_rejected() -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "historical_series_data")
    payload = _patch_encryption(_valid_zip(b"\n"))

    with pytest.raises(SourceLayoutDriftError) as raised:
        adapter.validate(artifact, _downloaded(artifact, payload, content_type="application/zip"))

    assert "encrypted" in raised.value.safe_summary


def test_zip_member_over_one_gib_is_rejected_without_a_large_fixture() -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "historical_series_data")
    payload = _patch_uncompressed_size(
        _zip_bytes([(MEMBER_NAME, _series_member())], stored=True),
        ZIP_MEMBER_MAX_UNCOMPRESSED_BYTES + 1,
    )

    with pytest.raises(SourceLayoutDriftError) as raised:
        adapter.validate(artifact, _downloaded(artifact, payload, content_type="application/zip"))

    assert "uncompressed size" in raised.value.safe_summary
    assert len(payload) < 1024 * 1024


@pytest.mark.parametrize("payload", [b"PK\x03\x04not-a-zip", b"this is not a zip"])
def test_corrupt_zip_is_a_signature_failure(payload: bytes) -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "historical_series_data")

    with pytest.raises(ArtifactSignatureError) as raised:
        adapter.validate(artifact, _downloaded(artifact, payload, content_type="application/zip"))

    assert raised.value.code == "artifact_signature_invalid"


@pytest.mark.parametrize("terminator", ["\n", "\r\n"])
def test_valid_catalogs_record_header_structure(terminator: str) -> None:
    adapter = _adapter()
    expected = {
        "concept_catalog": CONCEPT_HEADER,
        "institution_catalog": INSTITUTION_HEADER,
    }
    for role, header in expected.items():
        artifact = _artifact(adapter, role)
        validated = adapter.validate(
            artifact,
            _downloaded(artifact, _catalog(header, terminator=terminator)),
        )
        structure = validated.structure

        assert isinstance(structure, CsvTextStructure)
        assert structure.has_bom is False
        assert structure.line_terminator == ("lf" if terminator == "\n" else "crlf")
        assert structure.header_sha256 == sha256(header.encode()).hexdigest()


def test_catalog_bom_is_recorded_and_excluded_from_the_header_digest() -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "concept_catalog")
    validated = adapter.validate(
        artifact,
        _downloaded(artifact, _catalog(CONCEPT_HEADER, bom=True)),
    )
    structure = validated.structure

    assert isinstance(structure, CsvTextStructure)
    assert structure.has_bom is True
    assert structure.header_sha256 == sha256(CONCEPT_HEADER.encode()).hexdigest()


@pytest.mark.parametrize(
    ("content", "summary_part"),
    [
        (CONCEPT_HEADER.encode() + b"\n\xff\n", "UTF-8"),
        (CONCEPT_HEADER.encode() + b"\nrow\x00\n", "NUL"),
        (
            b'"sector","idtema","nope","descripcion","nivel","indicador","orden"\n"40"\n',
            "header",
        ),
        (CONCEPT_HEADER.encode() + b"\n", "data row"),
        (CONCEPT_HEADER.encode(), "line terminator"),
        (CONCEPT_HEADER.encode() + b"\r" + b'"40"\r', "line terminator"),
    ],
)
def test_catalog_structural_failures(content: bytes, summary_part: str) -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "concept_catalog")

    with pytest.raises(SourceLayoutDriftError) as raised:
        adapter.validate(artifact, _downloaded(artifact, content))

    assert raised.value.code == "source_layout_drift"
    assert summary_part in raised.value.safe_summary


def test_filename_uses_a_safe_content_disposition_or_the_url_basename() -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "concept_catalog")
    content = _catalog(CONCEPT_HEADER)

    from_header = adapter.validate(
        artifact,
        _downloaded(artifact, content, disposition='attachment; filename="conceptos.csv"'),
    )
    from_star = adapter.validate(
        artifact,
        _downloaded(
            artifact,
            content,
            disposition="attachment; filename*=UTF-8''conceptos.csv",
        ),
    )
    from_blank = adapter.validate(
        artifact,
        _downloaded(artifact, content, disposition='attachment; filename=""'),
    )
    from_traversal = adapter.validate(
        artifact,
        _downloaded(
            artifact,
            content,
            disposition='attachment; filename="../../cat_conceptos_40.csv"',
        ),
    )
    from_control = adapter.validate(
        artifact,
        _downloaded(artifact, content, disposition="attachment;\nfilename=evil.csv"),
    )

    assert from_header.filename == "conceptos.csv"
    assert from_star.filename == "conceptos.csv"
    assert from_blank.filename == "cat_conceptos_40.csv"
    assert from_traversal.filename == "cat_conceptos_40.csv"
    assert "/" not in from_traversal.filename
    assert from_control.filename == "cat_conceptos_40.csv"
    assert "evil" not in from_control.filename
    assert "\n" not in from_control.filename


def test_blank_url_basename_is_rejected() -> None:
    adapter = _adapter()
    artifact = _artifact(adapter, "concept_catalog")

    with pytest.raises(SourceLayoutDriftError) as raised:
        adapter.validate(
            artifact,
            _downloaded(
                artifact,
                _catalog(CONCEPT_HEADER),
                final_url=f"https://{HOST}/",
                disposition='attachment; filename=""',
            ),
        )

    assert raised.value.code == "source_layout_drift"
    assert "filename" in raised.value.safe_summary


def test_successful_observation_uses_retrieval_order_and_frozen_identity() -> None:
    adapter = _adapter()
    moments = [
        datetime(2026, 10, 3, 12, 0, tzinfo=UTC),
        datetime(2026, 10, 3, 11, 30, tzinfo=UTC),
        datetime(2026, 10, 3, 12, 5, tzinfo=UTC),
    ]
    client = RecordingClient(_transport(_routes(adapter)), _clock(moments))
    outcome = adapter.observe(client)
    release = outcome.release

    assert isinstance(outcome, ObservationOutcome)
    assert client.download_calls == 0
    assert outcome.failure is None
    assert release is not None
    assert [url.rsplit("/", 1)[-1] for url, _authorize, _limit in client.calls] == [
        "cat_conceptos_40.csv",
        "cat_instituciones_40.csv",
        "sh_datos_csv_40.zip",
    ]
    assert [limit for _url, _authorize, limit in client.calls] == [
        CATALOG_MAX_BYTES,
        CATALOG_MAX_BYTES,
        HISTORICAL_SERIES_MAX_BYTES,
    ]
    assert [authorize for _url, authorize, _limit in client.calls] == [
        authorize_cnbv_artifact_url,
        authorize_cnbv_artifact_url,
        authorize_cnbv_artifact_url,
    ]
    assert CATALOG_MAX_BYTES == 8 * 1024 * 1024
    assert HISTORICAL_SERIES_MAX_BYTES == 128 * 1024 * 1024
    assert release.first_observed_at == min(moments)
    pairs = tuple((item.artifact_role, item.sha256) for item in release.artifacts)
    assert release.release_identity_hash == artifact_set_identity_hash(
        identity_scheme=IDENTITY_SCHEME,
        source_code="cnbv_portfolio",
        release_family_key=RELEASE_FAMILY_KEY,
        revision=None,
        artifact_sha256_by_role=pairs,
    )
    assert release.metadata == ReleaseMetadata.from_artifacts(IDENTITY_SCHEME, release.artifacts)
    assert release.metadata.snapshot_semantics == "exact_observed_artifact_set"
    assert [item.artifact_role for item in release.metadata.artifacts] == [
        "concept_catalog",
        "historical_series_data",
        "institution_catalog",
    ]


def test_metadata_and_filename_changes_do_not_change_identity() -> None:
    adapter = _adapter()
    discovered = adapter.discover()

    def package(media: str, filename: str, moment: datetime) -> ObservedRelease:
        validated = []
        for artifact in discovered.artifacts:
            disposition = None
            if artifact.artifact_role == "concept_catalog":
                disposition = f'attachment; filename="{filename}"'
            content_type = media if artifact.artifact_format.value == "csv" else "application/zip"
            validated.append(
                adapter.validate(
                    artifact,
                    _downloaded(
                        artifact,
                        _body_for(artifact.artifact_role),
                        content_type=content_type,
                        disposition=disposition,
                        observed_at=moment,
                    ),
                )
            )
        return ObservedRelease.from_validated_artifacts(discovered, validated)

    left = package("text/csv", "left.csv", datetime(2026, 10, 1, tzinfo=UTC))
    right = package("application/octet-stream", "right.csv", datetime(2026, 10, 2, tzinfo=UTC))
    changed = _body_for("concept_catalog", concept_row='"40","changed-row"')
    changed_artifacts = []
    for artifact in discovered.artifacts:
        if artifact.artifact_role == "concept_catalog":
            content = changed
        else:
            content = _body_for(artifact.artifact_role)
        changed_artifacts.append(adapter.validate(artifact, _downloaded(artifact, content)))
    revised = ObservedRelease.from_validated_artifacts(discovered, changed_artifacts)

    assert left.release_identity_hash == right.release_identity_hash
    assert {item.filename for item in left.artifacts} != {item.filename for item in right.artifacts}
    assert left.metadata.artifacts[0].structure.header_sha256 == revised.metadata.artifacts[
        0
    ].structure.header_sha256
    assert left.release_identity_hash != revised.release_identity_hash
    assert revised.artifacts[0].sha256 != left.artifacts[0].sha256
    assert "header_sha256" in str(left.metadata.to_json_object())
    assert left.release_identity_hash == artifact_set_identity_hash(
        identity_scheme=IDENTITY_SCHEME,
        source_code="cnbv_portfolio",
        release_family_key=RELEASE_FAMILY_KEY,
        revision=None,
        artifact_sha256_by_role=((item.artifact_role, item.sha256) for item in left.artifacts),
    )


def test_first_retrieval_failure_does_not_request_later_artifacts() -> None:
    adapter = _adapter()
    concept = _artifact(adapter, "concept_catalog")
    routes = {
        concept.original_url: (
            404,
            {"content-type": "text/html"},
            f"<html>{SECRET}</html>".encode(),
        )
    }
    client = RecordingClient(_transport(routes), _clock([OBSERVED_AT]))
    outcome = adapter.observe(client)
    failure = outcome.failure

    assert outcome.release is None
    assert failure is not None
    assert failure.artifact_role == "concept_catalog"
    assert failure.error_code == "artifact_not_found"
    assert failure.observation is not None
    assert failure.observation.status_code == 404
    assert len(client.calls) == 1
    _assert_safe_summary(failure.error_summary)
    assert SECRET not in repr(failure)


def test_second_artifact_failure_does_not_request_the_zip() -> None:
    adapter = _adapter()
    routes = _routes(adapter)
    institution = _artifact(adapter, "institution_catalog")
    routes[institution.original_url] = (
        404,
        {"content-type": "text/plain"},
        b"missing",
    )
    del routes[_artifact(adapter, "historical_series_data").original_url]
    client = RecordingClient(
        _transport(routes),
        _clock([OBSERVED_AT, datetime(2026, 10, 3, 12, 1, tzinfo=UTC)]),
    )
    outcome = adapter.observe(client)

    assert outcome.release is None
    assert outcome.failure is not None
    assert outcome.failure.artifact_role == "institution_catalog"
    assert outcome.failure.error_code == "artifact_not_found"
    assert [url.rsplit("/", 1)[-1] for url, _authorize, _limit in client.calls] == [
        "cat_conceptos_40.csv",
        "cat_instituciones_40.csv",
    ]


def test_zip_validation_failure_does_not_produce_a_partial_release() -> None:
    adapter = _adapter()
    routes = _routes(adapter, series_body=b"not-a-zip", series_type="application/zip")
    client = RecordingClient(
        _transport(routes),
        _clock(
            [
                OBSERVED_AT,
                datetime(2026, 10, 3, 12, 1, tzinfo=UTC),
                datetime(2026, 10, 3, 12, 2, tzinfo=UTC),
            ]
        ),
    )
    outcome = adapter.observe(client)

    assert outcome.release is None
    assert outcome.failure is not None
    assert outcome.failure.artifact_role == "historical_series_data"
    assert outcome.failure.error_code == "artifact_signature_invalid"
    assert outcome.failure.observation is not None
    assert outcome.failure.observation.status_code == 200
    assert len(client.calls) == 3
    _assert_safe_summary(outcome.failure.error_summary)


def test_catalog_validation_failure_maps_to_artifact_failure() -> None:
    adapter = _adapter()
    concept = _artifact(adapter, "concept_catalog")
    routes = {
        concept.original_url: (
            200,
            {"content-type": "text/csv", "content-length": "4"},
            b"nope",
        )
    }
    client = RecordingClient(_transport(routes), _clock([OBSERVED_AT]))
    outcome = adapter.observe(client)

    assert outcome.release is None
    assert outcome.failure is not None
    assert outcome.failure.error_code == "source_layout_drift"
    assert outcome.failure.observation is not None
    assert "nope" not in outcome.failure.error_summary
    assert len(client.calls) == 1


ADAPTER_AT = datetime(2026, 1, 2, 3, 4, tzinfo=UTC)
HTTP_AT = datetime(2026, 8, 27, 21, 5, tzinfo=UTC)


def _counting_clock(moment: datetime, calls: list[datetime]) -> Callable[[], datetime]:
    def current() -> datetime:
        calls.append(moment)
        return moment

    return current


def _assert_absent_http_fields(failure: ArtifactFailure) -> None:
    assert failure.observation is None
    assert failure.http_status_code is None
    assert failure.http_etag is None
    assert failure.http_last_modified is None
    assert failure.http_content_length is None


def _no_response_client(
    kind: str,
) -> tuple[CnbvPortfolioAdapter, RecordingClient, list[str], list[datetime], list[datetime]]:
    adapter_calls: list[datetime] = []
    client_calls: list[datetime] = []
    adapter = CnbvPortfolioAdapter(_source(), clock=_counting_clock(ADAPTER_AT, adapter_calls))
    concept_url = _artifact(adapter, "concept_catalog").original_url
    requested: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requested.append(str(request.url))
        if str(request.url) != concept_url:
            raise AssertionError(str(request.url))
        if kind == "transport":
            raise httpx.ConnectError(f"connection refused {SECRET}", request=request)
        if kind == "tls":
            try:
                raise ssl.SSLCertVerificationError(1, "certificate verify failed")
            except ssl.SSLCertVerificationError as cause:
                raise httpx.ConnectError("connection failed", request=request) from cause
        if kind == "redirect":
            return httpx.Response(
                302,
                headers={"Location": f"https://{HOST}/next.zip\nbad"},
                stream=httpx.ByteStream(b"unread"),
                request=request,
            )
        raise AssertionError(kind)

    client = RecordingClient(
        httpx.MockTransport(handler),
        _counting_clock(HTTP_AT, client_calls),
    )
    return adapter, client, requested, adapter_calls, client_calls


def test_nf1_transport_failure_uses_the_adapter_clock() -> None:
    adapter, client, requested, adapter_calls, client_calls = _no_response_client("transport")
    outcome = adapter.observe(client)
    failure = outcome.failure
    concept_url = _artifact(adapter, "concept_catalog").original_url

    assert outcome.release is None
    assert failure is not None
    assert failure.artifact_role == "concept_catalog"
    assert failure.observed_url == concept_url
    assert failure.final_url is None
    assert failure.observed_at == ADAPTER_AT
    assert failure.error_code == "artifact_transport_failed"
    _assert_absent_http_fields(failure)
    _assert_safe_summary(failure.error_summary)
    assert SECRET not in repr(failure)
    assert adapter_calls == [ADAPTER_AT]
    assert client_calls == []
    assert client.calls[0][0] == concept_url
    assert requested == [concept_url, concept_url, concept_url]
    assert client.download_calls == 0


def test_nf2_tls_failure_uses_the_adapter_clock() -> None:
    adapter, client, requested, adapter_calls, client_calls = _no_response_client("tls")
    outcome = adapter.observe(client)
    failure = outcome.failure

    assert outcome.release is None
    assert failure is not None
    assert failure.artifact_role == "concept_catalog"
    assert failure.observed_url == _artifact(adapter, "concept_catalog").original_url
    assert failure.final_url is None
    assert failure.observed_at == ADAPTER_AT
    assert failure.error_code == "artifact_tls_untrusted"
    _assert_absent_http_fields(failure)
    _assert_safe_summary(failure.error_summary)
    assert failure.error_summary == "The artifact host TLS certificate could not be verified."
    assert "verify failed" not in failure.error_summary
    assert adapter_calls == [ADAPTER_AT]
    assert client_calls == []
    assert requested == [failure.observed_url]
    assert len(client.calls) == 1


def test_nf3_redirect_without_observation_uses_the_adapter_clock() -> None:
    adapter, client, requested, adapter_calls, client_calls = _no_response_client("redirect")
    outcome = adapter.observe(client)
    failure = outcome.failure
    concept_url = _artifact(adapter, "concept_catalog").original_url

    assert outcome.release is None
    assert failure is not None
    assert failure.artifact_role == "concept_catalog"
    assert failure.observed_url == concept_url
    assert failure.final_url == concept_url
    assert failure.observed_at == ADAPTER_AT
    assert failure.observed_at != HTTP_AT
    assert failure.error_code == "artifact_redirect_invalid"
    _assert_absent_http_fields(failure)
    _assert_safe_summary(failure.error_summary)
    assert "next.zip" not in failure.error_summary
    assert adapter_calls == [ADAPTER_AT]
    assert client_calls == []
    assert requested == [concept_url]
    assert len(client.calls) == 1


def test_nf4_http_error_uses_the_observation_timestamp() -> None:
    adapter_calls: list[datetime] = []
    http_calls: list[datetime] = []
    adapter = CnbvPortfolioAdapter(_source(), clock=_counting_clock(ADAPTER_AT, adapter_calls))
    concept = _artifact(adapter, "concept_catalog")
    body = b"<html>no"
    routes = {
        concept.original_url: (
            404,
            {
                "content-type": "text/html",
                "etag": '"abc"',
                "last-modified": "Thu, 27 Aug 2026 21:05:00 GMT",
                "content-length": str(len(body)),
            },
            body,
        )
    }
    client = RecordingClient(_transport(routes), _counting_clock(HTTP_AT, http_calls))
    outcome = adapter.observe(client)
    failure = outcome.failure

    assert outcome.release is None
    assert failure is not None
    assert failure.observation is not None
    assert failure.observed_at == HTTP_AT
    assert failure.observed_at == failure.observation.observed_at
    assert failure.observed_at != ADAPTER_AT
    assert failure.error_code == "artifact_not_found"
    assert failure.http_status_code == 404
    assert failure.http_etag == '"abc"'
    assert failure.http_last_modified == "Thu, 27 Aug 2026 21:05:00 GMT"
    assert failure.http_content_length == len(body)
    assert failure.observed_url == concept.original_url
    assert adapter_calls == []
    assert http_calls == [HTTP_AT]
    assert len(client.calls) == 1


def test_nf5_validation_failure_uses_the_observation_timestamp() -> None:
    adapter_calls: list[datetime] = []
    http_calls: list[datetime] = []
    adapter = CnbvPortfolioAdapter(_source(), clock=_counting_clock(ADAPTER_AT, adapter_calls))
    concept = _artifact(adapter, "concept_catalog")
    body = b"nope"
    routes = {
        concept.original_url: (
            200,
            {"content-type": "text/csv", "content-length": str(len(body))},
            body,
        )
    }
    client = RecordingClient(_transport(routes), _counting_clock(HTTP_AT, http_calls))
    outcome = adapter.observe(client)
    failure = outcome.failure

    assert outcome.release is None
    assert failure is not None
    assert failure.observation is not None
    assert failure.error_code == "source_layout_drift"
    assert failure.observed_at == HTTP_AT
    assert failure.observed_at == failure.observation.observed_at
    assert failure.observed_at != ADAPTER_AT
    assert failure.http_status_code == 200
    assert failure.http_etag is None
    assert failure.http_last_modified is None
    assert failure.http_content_length == len(body)
    assert "nope" not in failure.error_summary
    assert adapter_calls == []
    assert http_calls == [HTTP_AT]


@pytest.mark.parametrize(
    ("moment", "summary_part"),
    [
        (datetime(2026, 1, 2, 3, 4), "timezone-aware"),
        (datetime(2026, 1, 2, 3, 4, tzinfo=timezone(timedelta(hours=-6))), "UTC"),
    ],
)
def test_fallback_clock_must_be_aware_utc(moment: datetime, summary_part: str) -> None:
    adapter = CnbvPortfolioAdapter(_source(), clock=lambda: moment)
    concept_url = _artifact(adapter, "concept_catalog").original_url
    requested: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requested.append(str(request.url))
        raise httpx.ConnectError("connection refused", request=request)

    client = RecordingClient(httpx.MockTransport(handler), lambda: HTTP_AT)

    with pytest.raises(SourceContractError) as raised:
        adapter.observe(client)

    assert summary_part in raised.value.safe_summary
    assert requested == [concept_url, concept_url, concept_url]
