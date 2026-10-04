import ast
import hashlib
import ssl
from pathlib import Path

import certifi
import pytest

from mx_bank_monitor.ingestion import cnbv_portfolio
from mx_bank_monitor.ingestion.cnbv_portfolio import (
    IDENTITY_SCHEME,
    OFFICIAL_ARTIFACT_HOST,
    OFFICIAL_ARTIFACT_HOSTS,
    PINNED_INTERMEDIATE_DER_SHA256,
    RELEASE_FAMILY_KEY,
    authorize_cnbv_artifact_url,
    cnbv_ssl_context,
)
from mx_bank_monitor.ingestion.discovery import UnofficialArtifactUrlError, is_audit_error_code

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


def test_portfolio_module_has_no_adapter_or_parser_surface() -> None:
    tree = ast.parse(Path(cnbv_portfolio.__file__).read_text(encoding="utf-8"))
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            names.update(target.id for target in node.targets if isinstance(target, ast.Name))
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            names.add(node.target.id)

    forbidden = {
        "CnbvPortfolioAdapter",
        "discover",
        "validate",
        "observe",
        "REQUIRED_ROLES",
        "RETRIEVAL_ORDER",
    }
    assert names.isdisjoint(forbidden)


def test_portfolio_module_does_not_import_the_http_client() -> None:
    tree = ast.parse(Path(cnbv_portfolio.__file__).read_text(encoding="utf-8"))
    imported: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module is not None:
            imported.add(node.module)

    assert "httpx" not in imported
    assert "mx_bank_monitor.ingestion.http" not in imported
    assert "mx_bank_monitor.ingestion.discovery" in imported
