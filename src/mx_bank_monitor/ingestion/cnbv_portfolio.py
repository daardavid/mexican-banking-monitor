"""CNBV portfolio URL authority and pinned TLS trust.

This module holds source-specific transport policy only. The portfolio adapter,
discovery, validation, and artifact-package classification extend it later.
"""

from __future__ import annotations

import ssl
import unicodedata
from hashlib import sha256
from importlib.resources import files
from typing import Final
from urllib.parse import urlsplit

import certifi

from mx_bank_monitor.ingestion.discovery import UnofficialArtifactUrlError

IDENTITY_SCHEME: Final = "cnbv_portfolio.observed_artifact_set.v1"
RELEASE_FAMILY_KEY: Final = "serie_historica_banca_multiple_40"
OFFICIAL_ARTIFACT_HOST: Final = "portafolioinfdoctos.cnbv.gob.mx"
OFFICIAL_ARTIFACT_HOSTS: Final = frozenset({OFFICIAL_ARTIFACT_HOST})
PINNED_INTERMEDIATE_DER_SHA256: Final = (
    "b676ffa3179e8812093a1b5eafee876ae7a6aaf231078dad1bfb21cd2893764a"
)
_INTERMEDIATE_FILENAME: Final = "globalsign-rsa-ov-ssl-ca-2018.pem"
_HTTPS_PORT: Final = 443


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
