"""HTTP artifact download.

``download`` preserves the original auto-following client. Authority-sensitive
retrieval uses ``retrieve``, which authorizes every request target itself.
"""

from __future__ import annotations

import re
import ssl
import time
import unicodedata
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import UTC, datetime
from hashlib import sha256
from pathlib import Path
from urllib.parse import urljoin

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

from mx_bank_monitor.ingestion.discovery import (
    ArtifactContentEncodingError,
    ArtifactHttpStatusError,
    ArtifactLengthMismatchError,
    ArtifactNotFoundHttpError,
    ArtifactRedirectError,
    ArtifactRetrievalError,
    ArtifactTlsUntrustedError,
    ArtifactTooLargeError,
    ArtifactTransportError,
    HttpObservation,
)

_MAX_ATTEMPTS = 3
_RETRY_BACKOFF_MIN_SECONDS = 1
_RETRY_BACKOFF_MAX_SECONDS = 8
_REDIRECT_STATUSES = frozenset({301, 302, 303, 307, 308})
_ETAG_MAX_LENGTH = 1024
_LAST_MODIFIED_MAX_LENGTH = 128
_MAX_CONTENT_LENGTH = 2**63 - 1
_CONTENT_LENGTH_DIGITS = re.compile(r"[0-9]+")

Authorizer = Callable[[str], object]
Clock = Callable[[], datetime]
Sleeper = Callable[[float], None]


def _retry_backoff_seconds(failed_attempt: int) -> float:
    """Pause after a failed attempt, matching download's exponential wait.

    ``wait_exponential(multiplier=1, min=1, max=8)`` waits 1s after the first
    attempt and 2s after the second, and never more than 8s.
    """
    delay = 2 ** (failed_attempt - 1)
    return float(min(max(delay, _RETRY_BACKOFF_MIN_SECONDS), _RETRY_BACKOFF_MAX_SECONDS))


@contextmanager
def _closing(response: httpx.Response) -> Iterator[httpx.Response]:
    """Release ``response`` exactly once on every exit path.

    A fully consumed ``iter_raw()`` closes the response after its last chunk.
    Every path that stops before that leaves the response open. This block
    closes only a response that is still open, so the stream is not left to
    garbage collection and is not closed twice.
    """
    try:
        yield response
    finally:
        if not response.is_closed:
            response.close()


def _utc_now() -> datetime:
    return datetime.now(UTC)


def _contains_control_character(value: str) -> bool:
    return any(
        unicodedata.category(character) == "Cc" or character in "\u2028\u2029"
        for character in value
    )


def _validate_max_bytes(value: int | None) -> None:
    if value is not None and (type(value) is not int or value < 0):
        raise ValueError("max_bytes must be a non-negative integer")


def _exception_chain(exc: BaseException) -> Iterator[BaseException]:
    pending = [exc]
    seen: set[int] = set()
    while pending:
        current = pending.pop()
        marker = id(current)
        if marker in seen:
            continue
        seen.add(marker)
        yield current
        if current.__cause__ is not None:
            pending.append(current.__cause__)
        if current.__context__ is not None:
            pending.append(current.__context__)
        nested = getattr(current, "exceptions", None)
        if isinstance(nested, tuple):
            pending.extend(item for item in nested if isinstance(item, BaseException))


def _has_cert_verification_error(exc: BaseException) -> bool:
    return any(isinstance(item, ssl.SSLCertVerificationError) for item in _exception_chain(exc))


def _redirect_protocol_summary(exc: BaseException) -> str | None:
    """Map httpx's pre-return Location rejection to the redirect contract.

    httpx validates a redirect Location before it returns the response. A
    control character therefore surfaces as RemoteProtocolError text rather
    than as a readable header. TLS failures are not classified this way.
    """
    message = str(exc).casefold()
    if "location header" not in message:
        return None
    if "non-printable" in message or "control" in message:
        return "The artifact redirect Location contains a control character."
    return "The artifact redirect Location is not a valid URL reference."


def _safe_observational_header(value: str | None, *, max_length: int | None) -> str | None:
    """Keep an audit-safe header, or return None instead of a truncated stand-in."""
    if value is None or _contains_control_character(value) or value.strip() == "":
        return None
    if max_length is not None and len(value) > max_length:
        return None
    return value


def _optional_content_length(headers: httpx.Headers) -> int | None:
    if "content-length" not in headers:
        return None
    raw = headers["content-length"].strip()
    if _CONTENT_LENGTH_DIGITS.fullmatch(raw) is None:
        return None
    value = int(raw)
    if value > _MAX_CONTENT_LENGTH:
        return None
    return value


def _optional_content_encoding(headers: httpx.Headers) -> str | None:
    if "content-encoding" not in headers:
        return None
    raw = headers["content-encoding"]
    if _contains_control_character(raw):
        return None
    trimmed = raw.strip()
    if trimmed == "":
        return None
    return trimmed


def _identity_encoding_accepted(headers: httpx.Headers) -> bool:
    if "content-encoding" not in headers:
        return True
    raw = headers["content-encoding"]
    if _contains_control_character(raw):
        return False
    return raw.strip().casefold() == "identity"


class InvalidArtifactError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class DownloadedArtifact:
    url: str
    content: bytes
    content_type: str
    observation: HttpObservation | None = None

    @property
    def checksum(self) -> str:
        return sha256(self.content).hexdigest()

    def assert_extension(self, suffix: str) -> None:
        normalized = suffix.lower()
        if normalized == ".xlsx" and not self.content.startswith(b"PK"):
            raise InvalidArtifactError("The response is not a valid XLSX/ZIP payload")
        if normalized == ".pdf" and not self.content.startswith(b"%PDF"):
            raise InvalidArtifactError("The response is not a valid PDF payload")
        if self.content.lstrip().lower().startswith((b"<!doctype html", b"<html")):
            raise InvalidArtifactError("The source returned HTML instead of a data artifact")

    def save(self, destination: Path) -> None:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(self.content)


class HttpArtifactClient:
    def __init__(
        self,
        timeout_seconds: float = 60.0,
        *,
        verify: ssl.SSLContext | bool = True,
        max_bytes: int | None = None,
        transport: httpx.BaseTransport | None = None,
        clock: Clock | None = None,
        sleeper: Sleeper | None = None,
    ) -> None:
        if verify is False:
            raise ValueError("TLS verification cannot be disabled")
        if not isinstance(verify, ssl.SSLContext) and verify is not True:
            raise ValueError("TLS verification must be enabled")
        _validate_max_bytes(max_bytes)
        self._max_bytes = max_bytes
        self._clock = clock or _utc_now
        self._sleep = sleeper or time.sleep
        self._client = httpx.Client(
            timeout=timeout_seconds,
            follow_redirects=True,
            headers={"User-Agent": "mx-bank-monitor/0.1 (+public-data-research)"},
            verify=verify,
            transport=transport,
        )

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=1, max=8))
    def download(self, url: str) -> DownloadedArtifact:
        """Download ``url``, following redirects automatically.

        This is the historical client behavior. CNBV retrieval must call
        ``retrieve`` so each target is authorized before it is contacted.
        """
        response = self._client.get(url)
        response.raise_for_status()
        return DownloadedArtifact(
            url=str(response.url),
            content=response.content,
            content_type=response.headers.get("content-type", ""),
        )

    def retrieve(
        self,
        url: str,
        *,
        authorize: Authorizer,
        max_redirects: int = 3,
        max_bytes: int | None = None,
    ) -> DownloadedArtifact:
        """Retrieve one artifact, authorizing every request URL before contacting it.

        Redirects are followed manually with ``follow_redirects=False``. A direct
        200 has an empty ``redirect_chain``. After redirects, the chain contains
        the absolute authorized target URLs in order, excluding the initial URL
        and including the final target URL. ``final_url`` is the URL that produced
        the terminal response.
        """
        if type(max_redirects) is not int or max_redirects < 0:
            raise ValueError("max_redirects must be a non-negative integer")
        limit = self._max_bytes if max_bytes is None else max_bytes
        _validate_max_bytes(limit)
        authorize(url)
        requested_url = url
        current = url
        chain: list[str] = []
        visited = {url}
        while True:
            outcome = self._exchange(
                current,
                requested_url=requested_url,
                redirect_chain=tuple(chain),
                visited=visited,
                authorize=authorize,
                max_redirects=max_redirects,
                max_bytes=limit,
            )
            if isinstance(outcome, DownloadedArtifact):
                return outcome
            visited.add(outcome)
            chain.append(outcome)
            current = outcome

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> HttpArtifactClient:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _send_once(self, url: str) -> httpx.Response:
        request = self._client.build_request(
            "GET",
            url,
            headers={"Accept-Encoding": "identity"},
        )
        return self._client.send(request, follow_redirects=False, stream=True)

    def _pause_before_retry(self, failed_attempt: int) -> None:
        self._sleep(_retry_backoff_seconds(failed_attempt))

    def _exchange(
        self,
        url: str,
        *,
        requested_url: str,
        redirect_chain: tuple[str, ...],
        visited: set[str],
        authorize: Authorizer,
        max_redirects: int,
        max_bytes: int | None,
    ) -> DownloadedArtifact | str:
        """Perform one authorized hop, including its retries.

        Every response obtained here is closed before this method returns,
        raises, or issues the next attempt. The return value is the artifact
        or the next absolute redirect target.
        """
        for attempt in range(1, _MAX_ATTEMPTS + 1):
            try:
                response = self._send_once(url)
            except httpx.DecodingError as exc:
                raise ArtifactContentEncodingError(requested_url=requested_url) from exc
            except httpx.RemoteProtocolError as exc:
                summary = _redirect_protocol_summary(exc)
                if summary is not None:
                    raise ArtifactRedirectError(
                        summary,
                        requested_url=requested_url,
                        final_url=url,
                    ) from exc
                if attempt == _MAX_ATTEMPTS:
                    raise ArtifactTransportError(requested_url=requested_url) from exc
                self._pause_before_retry(attempt)
                continue
            except httpx.TransportError as exc:
                if _has_cert_verification_error(exc):
                    raise ArtifactTlsUntrustedError(requested_url=requested_url) from exc
                if attempt == _MAX_ATTEMPTS:
                    raise ArtifactTransportError(requested_url=requested_url) from exc
                self._pause_before_retry(attempt)
                continue
            except httpx.RequestError as exc:
                raise ArtifactTransportError(requested_url=requested_url) from exc
            with _closing(response):
                status = response.status_code
                if status == 429 or 500 <= status <= 599:
                    if attempt == _MAX_ATTEMPTS:
                        raise _status_error(
                            status,
                            requested_url=requested_url,
                            final_url=url,
                            observation=self._observation(
                                response,
                                requested_url=requested_url,
                                final_url=url,
                                redirect_chain=redirect_chain,
                            ),
                        )
                elif status in _REDIRECT_STATUSES:
                    return self._redirect_target(
                        response,
                        current=url,
                        requested_url=requested_url,
                        redirect_chain=redirect_chain,
                        visited=visited,
                        authorize=authorize,
                        max_redirects=max_redirects,
                    )
                else:
                    return self._artifact_from_response(
                        response,
                        requested_url=requested_url,
                        final_url=url,
                        redirect_chain=redirect_chain,
                        max_bytes=max_bytes,
                    )
            self._pause_before_retry(attempt)
        raise AssertionError("retry loop exited without a response or a typed error")

    def _redirect_target(
        self,
        response: httpx.Response,
        *,
        current: str,
        requested_url: str,
        redirect_chain: tuple[str, ...],
        visited: set[str],
        authorize: Authorizer,
        max_redirects: int,
    ) -> str:
        observation = self._observation(
            response,
            requested_url=requested_url,
            final_url=current,
            redirect_chain=redirect_chain,
        )

        def reject(summary: str) -> ArtifactRedirectError:
            return ArtifactRedirectError(
                summary,
                requested_url=requested_url,
                final_url=current,
                observation=observation,
            )

        if "location" not in response.headers:
            raise reject("The artifact redirect is missing a Location header.")
        raw_location = response.headers["location"]
        if _contains_control_character(raw_location):
            raise reject("The artifact redirect Location contains a control character.")
        location = raw_location.strip()
        if location == "":
            raise reject("The artifact redirect Location is blank.")
        if any(character.isspace() for character in location):
            raise reject("The artifact redirect Location is not a valid URL reference.")
        target = urljoin(current, location)
        authorize(target)
        if target in visited:
            raise reject("The artifact redirect chain contains a loop.")
        if len(redirect_chain) >= max_redirects:
            raise reject("The artifact redirect chain exceeds the hop limit.")
        return target

    def _artifact_from_response(
        self,
        response: httpx.Response,
        *,
        requested_url: str,
        final_url: str,
        redirect_chain: tuple[str, ...],
        max_bytes: int | None,
    ) -> DownloadedArtifact:
        observation = self._observation(
            response,
            requested_url=requested_url,
            final_url=final_url,
            redirect_chain=redirect_chain,
        )
        if response.status_code != 200:
            raise _status_error(
                response.status_code,
                requested_url=requested_url,
                final_url=final_url,
                observation=observation,
            )
        if not _identity_encoding_accepted(response.headers):
            raise ArtifactContentEncodingError(
                requested_url=requested_url,
                final_url=final_url,
                observation=observation,
            )
        try:
            declared = _required_content_length(response.headers)
        except ArtifactLengthMismatchError:
            raise ArtifactLengthMismatchError(
                "The artifact Content-Length header is malformed.",
                requested_url=requested_url,
                final_url=final_url,
                observation=observation,
            ) from None
        if declared is not None and max_bytes is not None and declared > max_bytes:
            raise ArtifactTooLargeError(
                requested_url=requested_url,
                final_url=final_url,
                observation=observation,
            )
        content = self._read_body(
            response,
            max_bytes=max_bytes,
            requested_url=requested_url,
            final_url=final_url,
            redirect_chain=redirect_chain,
        )
        if declared is not None and len(content) != declared:
            raise ArtifactLengthMismatchError(
                requested_url=requested_url,
                final_url=final_url,
                observation=observation,
            )
        raw_type = response.headers.get("content-type", "")
        safe_type = _safe_observational_header(raw_type, max_length=None) if raw_type else None
        return DownloadedArtifact(
            url=final_url,
            content=content,
            content_type=safe_type or "",
            observation=observation,
        )

    def _read_body(
        self,
        response: httpx.Response,
        *,
        max_bytes: int | None,
        requested_url: str,
        final_url: str,
        redirect_chain: tuple[str, ...],
    ) -> bytes:
        chunks: list[bytes] = []
        received = 0
        try:
            for chunk in response.iter_raw():
                received += len(chunk)
                if max_bytes is not None and received > max_bytes:
                    raise ArtifactTooLargeError(
                        requested_url=requested_url,
                        final_url=final_url,
                        observation=self._observation(
                            response,
                            requested_url=requested_url,
                            final_url=final_url,
                            redirect_chain=redirect_chain,
                        ),
                    )
                chunks.append(chunk)
        except httpx.DecodingError as exc:
            raise ArtifactContentEncodingError(
                requested_url=requested_url,
                final_url=final_url,
            ) from exc
        return b"".join(chunks)

    def _observation(
        self,
        response: httpx.Response,
        *,
        requested_url: str,
        final_url: str,
        redirect_chain: tuple[str, ...],
    ) -> HttpObservation:
        headers = response.headers
        raw_type = headers.get("content-type")
        return HttpObservation(
            requested_url=requested_url,
            final_url=final_url,
            redirect_chain=redirect_chain,
            status_code=response.status_code,
            content_type=_safe_observational_header(raw_type, max_length=None),
            content_length=_optional_content_length(headers),
            content_encoding=_optional_content_encoding(headers),
            etag=_safe_observational_header(headers.get("etag"), max_length=_ETAG_MAX_LENGTH),
            last_modified=_safe_observational_header(
                headers.get("last-modified"),
                max_length=_LAST_MODIFIED_MAX_LENGTH,
            ),
            content_disposition=_safe_observational_header(
                headers.get("content-disposition"),
                max_length=None,
            ),
            observed_at=self._clock(),
        )


def _required_content_length(headers: httpx.Headers) -> int | None:
    if "content-length" not in headers:
        return None
    raw = headers["content-length"].strip()
    if _CONTENT_LENGTH_DIGITS.fullmatch(raw) is None:
        raise ArtifactLengthMismatchError("The artifact Content-Length header is malformed.")
    value = int(raw)
    if value > _MAX_CONTENT_LENGTH:
        raise ArtifactLengthMismatchError("The artifact Content-Length header is malformed.")
    return value


def _status_error(
    status: int,
    *,
    requested_url: str,
    final_url: str,
    observation: HttpObservation,
) -> ArtifactRetrievalError:
    if status == 404:
        return ArtifactNotFoundHttpError(
            requested_url=requested_url,
            final_url=final_url,
            observation=observation,
        )
    return ArtifactHttpStatusError(
        f"The artifact request returned HTTP {status}.",
        requested_url=requested_url,
        final_url=final_url,
        observation=observation,
    )
