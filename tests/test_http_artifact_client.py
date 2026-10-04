from __future__ import annotations

import hashlib
import re
import ssl
from collections.abc import Callable, Iterator
from datetime import UTC, datetime
from pathlib import Path

import httpx
import pytest

from mx_bank_monitor.ingestion import http as http_module
from mx_bank_monitor.ingestion.cnbv_portfolio import authorize_cnbv_artifact_url
from mx_bank_monitor.ingestion.discovery import (
    ArtifactContentEncodingError,
    ArtifactContentError,
    ArtifactHttpStatusError,
    ArtifactLengthMismatchError,
    ArtifactNotFoundHttpError,
    ArtifactRedirectError,
    ArtifactRetrievalError,
    ArtifactTlsUntrustedError,
    ArtifactTooLargeError,
    ArtifactTransportError,
    is_audit_error_code,
)
from mx_bank_monitor.ingestion.http import (
    DownloadedArtifact,
    HttpArtifactClient,
    InvalidArtifactError,
)

HOST = "portafolioinfdoctos.cnbv.gob.mx"
ORIGIN = f"https://{HOST}/historical.zip"
OBSERVED_AT = datetime(2026, 8, 27, 21, 5, tzinfo=UTC)
SECRET = "SuperSecretValue"
USERNAME = "leak-user"
CONTROL_CHARACTERS = re.compile("[\x00-\x1f\x7f-\x9f\u2028\u2029]")
USER_AGENT = "mx-bank-monitor/0.1 (+public-data-research)"

Step = tuple[int, dict[str, str], tuple[bytes, ...]] | str


class FlagStream(httpx.SyncByteStream):
    def __init__(
        self,
        chunks: tuple[bytes, ...],
        *,
        events: list[tuple[str, str]] | None = None,
        label: str = "",
    ) -> None:
        self._chunks = chunks
        self._events = events
        self._label = label
        self.pulled = 0
        self.closes = 0

    def __iter__(self) -> Iterator[bytes]:
        for chunk in self._chunks:
            self.pulled += 1
            self._record("read")
            yield chunk

    def close(self) -> None:
        self.closes += 1
        self._record("close")

    def _record(self, kind: str) -> None:
        if self._events is not None:
            self._events.append((kind, self._label))


def _fail(kind: str, request: httpx.Request) -> None:
    if kind == "transport":
        raise httpx.ConnectError(f"connection refused {SECRET}", request=request)
    if kind == "tls":
        try:
            raise ssl.SSLCertVerificationError(1, "certificate verify failed")
        except ssl.SSLCertVerificationError as cause:
            raise httpx.ConnectError("connection failed", request=request) from cause
    if kind == "tls-context":
        error = httpx.ConnectError("connection failed", request=request)
        error.__context__ = ssl.SSLCertVerificationError(1, "certificate verify failed")
        raise error
    if kind == "spoof":
        raise httpx.ConnectError(
            "ssl.SSLCertVerificationError: certificate verify failed",
            request=request,
        )
    raise AssertionError(kind)


def _no_sleep(_delay: float) -> None:
    return None


def _session(
    steps: list[Step],
    *,
    max_bytes: int | None = None,
    sleeper: Callable[[float], None] | None = None,
    events: list[tuple[str, str]] | None = None,
) -> tuple[HttpArtifactClient, list[httpx.Request], list[FlagStream]]:
    requests: list[httpx.Request] = []
    streams: list[FlagStream] = []
    pending = list(steps)
    accepted: list[str] = []

    def authorize(url: str) -> str:
        authorized = authorize_cnbv_artifact_url(url)
        accepted.append(authorized)
        return authorized

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        label = str(len(requests))
        if events is not None:
            events.append(("request", label))
        assert any(httpx.URL(url) == request.url for url in accepted)
        if not pending:
            raise AssertionError(f"unexpected request for {request.url}")
        step = pending.pop(0)
        if isinstance(step, str):
            _fail(step, request)
        status, headers, chunks = step
        stream = FlagStream(chunks, events=events, label=label)
        streams.append(stream)
        return httpx.Response(status, headers=headers, stream=stream, request=request)

    client = HttpArtifactClient(
        transport=httpx.MockTransport(handler),
        clock=lambda: OBSERVED_AT,
        max_bytes=max_bytes,
        sleeper=sleeper or _no_sleep,
    )
    client.authorize = authorize  # type: ignore[attr-defined]
    return client, requests, streams


def _authorize(client: HttpArtifactClient):
    return client.authorize  # type: ignore[attr-defined]


def _ok(
    payload: bytes = b"abc",
    status: int = 200,
    headers: dict[str, str] | None = None,
) -> Step:
    return (status, {} if headers is None else headers, (payload,))


def _redirect(location: str, status: int = 302, payload: bytes = b"unread") -> Step:
    return (status, {"Location": location}, (payload,))


def _urls(requests: list[httpx.Request]) -> list[str]:
    return [str(request.url) for request in requests]


def _assert_identity_requests(requests: list[httpx.Request]) -> None:
    assert requests
    for request in requests:
        assert request.method == "GET"
        assert request.headers["accept-encoding"] == "identity"
        assert request.headers["user-agent"] == USER_AGENT


def _assert_unread(streams: list[FlagStream]) -> None:
    assert streams
    assert all(stream.pulled == 0 for stream in streams)
    assert all(stream.closes == 1 for stream in streams)


def _assert_closed_once(streams: list[FlagStream]) -> None:
    assert streams
    assert all(stream.closes == 1 for stream in streams)


def _assert_safe_retrieval(error: ArtifactRetrievalError) -> None:
    assert not isinstance(error, ArtifactContentError)
    assert not isinstance(error, InvalidArtifactError)
    assert is_audit_error_code(error.code)
    assert len(error.code) <= 64
    assert error.safe_summary.strip()
    assert len(error.safe_summary) <= 512
    assert CONTROL_CHARACTERS.search(error.safe_summary) is None
    assert str(error) == error.safe_summary
    assert SECRET not in error.safe_summary


def test_direct_200_preserves_exact_bytes_and_empty_redirect_chain() -> None:
    payload = b"\xff\xfePK\x03\x04exact"
    client, requests, streams = _session(
        [
            _ok(
                payload,
                headers={
                    "Content-Type": "application/zip",
                    "Content-Length": str(len(payload)),
                },
            )
        ]
    )

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    assert _urls(requests) == [ORIGIN]
    _assert_identity_requests(requests)
    assert streams[0].pulled == 1
    assert streams[0].closes == 1
    assert artifact.content == payload
    assert artifact.checksum == hashlib.sha256(payload).hexdigest()
    assert artifact.url == ORIGIN
    assert artifact.content_type == "application/zip"
    assert artifact.observation is not None
    assert artifact.observation.requested_url == ORIGIN
    assert artifact.observation.final_url == ORIGIN
    assert artifact.observation.redirect_chain == ()
    assert artifact.observation.status_code == 200
    assert artifact.observation.content_length == len(payload)
    assert artifact.observation.content_encoding is None
    assert artifact.observation.observed_at == OBSERVED_AT


@pytest.mark.parametrize("status", [301, 302, 307, 308])
def test_manual_redirect_follows_only_an_authorized_target(status: int) -> None:
    target = f"https://{HOST}/next.zip"
    client, requests, streams = _session([_redirect(target, status=status), _ok(b"payload")])

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    assert _urls(requests) == [ORIGIN, target]
    _assert_identity_requests(requests)
    assert streams[0].pulled == 0
    assert streams[0].closes == 1
    assert streams[1].pulled == 1
    assert streams[1].closes == 1
    assert artifact.content == b"payload"
    assert artifact.url == target
    assert artifact.observation is not None
    assert artifact.observation.requested_url == ORIGIN
    assert artifact.observation.final_url == target
    assert artifact.observation.redirect_chain == (target,)
    assert artifact.observation.status_code == 200


def test_relative_location_is_resolved_before_authorization() -> None:
    origin = f"https://{HOST}/dir/old.zip"
    target = f"https://{HOST}/dir/next.zip"
    client, requests, _streams = _session([_redirect("next.zip"), _ok(b"next")])

    with client:
        artifact = client.retrieve(origin, authorize=_authorize(client))

    assert _urls(requests) == [origin, target]
    assert artifact.observation is not None
    assert artifact.observation.redirect_chain == (target,)
    assert artifact.observation.final_url == target
    assert artifact.content == b"next"


def test_303_redirect_is_followed_as_get() -> None:
    target = f"https://{HOST}/after-303.zip"
    client, requests, streams = _session([_redirect(target, status=303), _ok(b"done")])

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    assert [request.method for request in requests] == ["GET", "GET"]
    assert _urls(requests) == [ORIGIN, target]
    assert streams[0].pulled == 0
    assert streams[0].closes == 1
    assert artifact.content == b"done"
    assert artifact.observation is not None
    assert artifact.observation.redirect_chain == (target,)


def test_redirect_chain_excludes_the_origin_and_includes_each_target() -> None:
    origin = f"https://{HOST}/origin.zip"
    middle = f"https://{HOST}/middle.zip"
    final = f"https://{HOST}/final.zip"
    client, requests, streams = _session(
        [_redirect(middle, status=302), _redirect(final, status=307), _ok(b"zip-bytes")]
    )

    with client:
        artifact = client.retrieve(origin, authorize=_authorize(client))

    assert _urls(requests) == [origin, middle, final]
    assert streams[0].pulled == 0
    assert streams[1].pulled == 0
    _assert_closed_once(streams)
    assert artifact.observation is not None
    assert artifact.observation.requested_url == origin
    assert artifact.observation.final_url == final
    assert artifact.observation.redirect_chain == (middle, final)


@pytest.mark.parametrize(
    "location",
    [
        "https://evil.example/historical.zip",
        f"http://{HOST}/historical.zip",
        "https://portafolioinfo.cnbv.gob.mx/historical.zip",
        f"https://{USERNAME}:{SECRET}@{HOST}/historical.zip",
        f"https://{HOST}:8443/historical.zip",
        f"https://{HOST}/historical.zip?x=1",
        f"https://{HOST}/historical.zip#section",
        f"https://{HOST}./historical.zip",
    ],
)
def test_unauthorized_redirect_is_rejected_before_the_target_is_contacted(location: str) -> None:
    client, requests, streams = _session([_redirect(location), _ok(b"should-not-be-read")])

    with client, pytest.raises(Exception) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    error = raised.value
    assert type(error) is not ArtifactContentError
    assert getattr(error, "code", None) == "artifact_url_unofficial"
    assert len(requests) == 1
    assert _urls(requests) == [ORIGIN]
    _assert_unread(streams)
    assert SECRET not in error.safe_summary
    assert USERNAME not in error.safe_summary
    assert SECRET not in str(error)
    assert USERNAME not in str(error)
    assert SECRET not in repr(error)


@pytest.mark.parametrize(
    "url",
    [
        "https://evil.example/historical.zip",
        f"http://{HOST}/historical.zip",
        f"https://{USERNAME}:{SECRET}@{HOST}/historical.zip",
        f"https://{HOST}:8443/historical.zip",
    ],
)
def test_invalid_initial_url_fails_before_the_first_request(url: str) -> None:
    client, requests, streams = _session([_ok(b"should-not-be-read")])

    with client, pytest.raises(Exception) as raised:
        client.retrieve(url, authorize=_authorize(client))

    assert getattr(raised.value, "code", None) == "artifact_url_unofficial"
    assert requests == []
    assert streams == []
    assert SECRET not in raised.value.safe_summary
    assert USERNAME not in raised.value.safe_summary


def test_redirect_error_summary_never_contains_userinfo() -> None:
    location = f"https://{USERNAME}:{SECRET}@{HOST}/next.zip"
    client, requests, _streams = _session([_redirect(location)])

    with client, pytest.raises(Exception) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    rendered = f"{raised.value.safe_summary} {raised.value!s} {raised.value!r}"
    assert len(requests) == 1
    assert SECRET not in rendered
    assert USERNAME not in rendered


@pytest.mark.parametrize(
    ("headers", "summary_part"),
    [
        ({}, "missing a Location header"),
        ({"Location": ""}, "Location is blank"),
        ({"Location": "   "}, "Location is blank"),
        ({"Location": f"https://{HOST}/next.zip\nbad"}, "control character"),
    ],
)
def test_invalid_redirect_location_is_not_followed(
    headers: dict[str, str], summary_part: str
) -> None:
    client, requests, streams = _session([(302, headers, (b"unread",))])

    with client, pytest.raises(ArtifactRedirectError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    error = raised.value
    _assert_safe_retrieval(error)
    assert error.code == "artifact_redirect_invalid"
    assert summary_part in error.safe_summary
    assert len(requests) == 1
    _assert_unread(streams)
    assert error.requested_url == ORIGIN
    assert error.final_url == ORIGIN
    if summary_part == "control character":
        assert error.observation is None
    else:
        assert error.observation is not None
        assert error.observation.status_code == 302


def test_redirect_loop_is_rejected_without_repeating_the_request() -> None:
    origin = f"https://{HOST}/a.zip"
    other = f"https://{HOST}/b.zip"
    client, requests, streams = _session([_redirect(other), _redirect(origin), _ok()])

    with client, pytest.raises(ArtifactRedirectError) as raised:
        client.retrieve(origin, authorize=_authorize(client))

    assert raised.value.code == "artifact_redirect_invalid"
    assert "loop" in raised.value.safe_summary
    assert _urls(requests) == [origin, other]
    _assert_unread(streams)


def test_too_many_redirects_stops_before_the_next_target() -> None:
    urls = [f"https://{HOST}/h{index}.zip" for index in range(5)]
    steps: list[Step] = [_redirect(urls[index + 1]) for index in range(4)]
    steps.append(_ok(b"too-far"))
    client, requests, streams = _session(steps)

    with client, pytest.raises(ArtifactRedirectError) as raised:
        client.retrieve(urls[0], authorize=_authorize(client))

    assert raised.value.code == "artifact_redirect_invalid"
    assert "hop limit" in raised.value.safe_summary
    assert _urls(requests) == urls[:4]
    _assert_unread(streams)
    assert raised.value.final_url == urls[3]
    assert raised.value.observation is not None
    assert raised.value.observation.redirect_chain == tuple(urls[1:4])


def test_absent_content_encoding_is_accepted_and_length_is_enforced() -> None:
    client, requests, _streams = _session(
        [_ok(b"abcd", headers={"Content-Type": "text/csv", "Content-Length": "4"})]
    )

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    _assert_identity_requests(requests)
    assert artifact.observation is not None
    assert artifact.observation.content_encoding is None
    assert artifact.observation.content_length == 4
    assert artifact.observation.content_type == "text/csv"


@pytest.mark.parametrize("encoding", ["identity", " Identity ", "IDENTITY"])
def test_identity_content_encoding_is_accepted(encoding: str) -> None:
    client, _requests, streams = _session(
        [_ok(b"abcd", headers={"Content-Encoding": encoding, "Content-Length": "4"})]
    )

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    assert streams[0].pulled == 1
    assert artifact.content == b"abcd"
    assert artifact.observation is not None
    assert artifact.observation.content_encoding == encoding.strip()
    assert artifact.observation.content_encoding.casefold() == "identity"


@pytest.mark.parametrize("encoding", ["gzip", "br", "deflate", "gzip, identity", "", "   "])
def test_non_identity_content_encoding_fails_before_the_body_is_read(encoding: str) -> None:
    client, requests, streams = _session(
        [_ok(b"compressed-body", headers={"Content-Encoding": encoding, "Content-Length": "16"})]
    )

    with client, pytest.raises(ArtifactContentEncodingError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    _assert_safe_retrieval(raised.value)
    assert raised.value.code == "artifact_content_encoding_unsupported"
    assert len(requests) == 1
    _assert_unread(streams)
    assert "compressed-body" not in raised.value.safe_summary


def test_content_length_mismatch_fails_after_the_identity_body_is_read() -> None:
    client, requests, streams = _session(
        [_ok(b"ab", headers={"Content-Encoding": "identity", "Content-Length": "4"})]
    )

    with client, pytest.raises(ArtifactLengthMismatchError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    _assert_safe_retrieval(raised.value)
    assert raised.value.code == "artifact_length_mismatch"
    assert len(requests) == 1
    assert streams[0].pulled == 1
    assert raised.value.observation is not None
    assert raised.value.observation.content_length == 4


@pytest.mark.parametrize("status", [201, 204, 206])
def test_non_200_success_status_is_rejected(status: int) -> None:
    client, requests, streams = _session([_ok(b"partial", status=status)])

    with client, pytest.raises(ArtifactHttpStatusError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    _assert_safe_retrieval(raised.value)
    assert raised.value.code == "artifact_http_status"
    assert str(status) in raised.value.safe_summary
    assert len(requests) == 1
    _assert_unread(streams)


@pytest.mark.parametrize("status", [300, 304])
def test_other_redirect_statuses_are_not_followed(status: int) -> None:
    client, requests, streams = _session(
        [(status, {"Location": f"https://{HOST}/other.zip"}, (b"unread",))]
    )

    with client, pytest.raises(ArtifactHttpStatusError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 1
    _assert_unread(streams)
    assert raised.value.code == "artifact_http_status"


def test_404_is_not_retried_and_keeps_http_observation() -> None:
    client, requests, streams = _session([_ok(b"missing", status=404)])

    with client, pytest.raises(ArtifactNotFoundHttpError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    error = raised.value
    _assert_safe_retrieval(error)
    assert error.code == "artifact_not_found"
    assert len(requests) == 1
    _assert_unread(streams)
    assert error.requested_url == ORIGIN
    assert error.final_url == ORIGIN
    assert error.observation is not None
    assert error.observation.status_code == 404
    assert error.observation.redirect_chain == ()
    assert error.observation.observed_at == OBSERVED_AT
    assert "missing" not in error.safe_summary


def test_other_4xx_is_not_retried() -> None:
    client, requests, streams = _session([_ok(b"denied", status=403)])

    with client, pytest.raises(ArtifactHttpStatusError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert not isinstance(raised.value, ArtifactNotFoundHttpError)
    assert len(requests) == 1
    _assert_unread(streams)


@pytest.mark.parametrize("status", [429, 500, 503])
def test_retryable_statuses_are_attempted_three_times(status: int) -> None:
    client, requests, streams = _session([_ok(SECRET.encode(), status=status) for _ in range(3)])

    with client, pytest.raises(ArtifactHttpStatusError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    _assert_safe_retrieval(raised.value)
    assert len(requests) == 3
    _assert_unread(streams)
    assert SECRET not in raised.value.safe_summary


def test_retryable_status_can_succeed_on_a_later_attempt() -> None:
    client, requests, streams = _session([_ok(b"busy", status=500), _ok(b"ready")])

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 2
    assert streams[0].pulled == 0
    assert artifact.content == b"ready"


def test_transport_errors_are_retried_and_do_not_echo_the_cause() -> None:
    client, requests, _streams = _session(["transport", "transport", "transport"])

    with client, pytest.raises(ArtifactTransportError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    _assert_safe_retrieval(raised.value)
    assert raised.value.code == "artifact_transport_failed"
    assert len(requests) == 3
    assert raised.value.requested_url == ORIGIN
    assert raised.value.final_url is None
    assert raised.value.observation is None
    assert SECRET not in str(raised.value)


def test_tls_verification_failure_is_not_retried() -> None:
    client, requests, _streams = _session(["tls", "transport"])

    with client, pytest.raises(ArtifactTlsUntrustedError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    _assert_safe_retrieval(raised.value)
    assert raised.value.code == "artifact_tls_untrusted"
    assert len(requests) == 1
    assert isinstance(raised.value.__cause__, httpx.ConnectError)
    assert isinstance(raised.value.__cause__.__cause__, ssl.SSLCertVerificationError)


def test_tls_verification_failure_in_exception_context_is_not_retried() -> None:
    client, requests, _streams = _session(["tls-context"])

    with client, pytest.raises(ArtifactTlsUntrustedError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 1
    assert raised.value.code == "artifact_tls_untrusted"
    assert isinstance(raised.value.__cause__, httpx.ConnectError)
    context = raised.value.__cause__.__context__
    assert isinstance(context, ssl.SSLCertVerificationError)


def test_tls_message_text_without_the_exception_type_is_retried_as_transport() -> None:
    client, requests, _streams = _session(["spoof", "spoof", "spoof"])

    with client, pytest.raises(ArtifactTransportError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 3
    assert raised.value.code == "artifact_transport_failed"
    assert not isinstance(raised.value, ArtifactTlsUntrustedError)


def test_content_length_above_the_cap_is_rejected_before_the_body_is_read() -> None:
    client, requests, streams = _session(
        [_ok(b"0123456789", headers={"Content-Length": "10"})],
        max_bytes=4,
    )

    with client, pytest.raises(ArtifactTooLargeError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    _assert_safe_retrieval(raised.value)
    assert raised.value.code == "artifact_too_large"
    assert len(requests) == 1
    _assert_unread(streams)


def test_stream_is_aborted_when_received_bytes_exceed_the_cap() -> None:
    client, _requests, streams = _session(
        [(200, {}, (b"aa", b"bb", b"cc", b"dd"))],
        max_bytes=4,
    )

    with client, pytest.raises(ArtifactTooLargeError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert streams[0].pulled == 3
    assert streams[0].closes == 1


def test_caller_max_bytes_overrides_the_client_limit() -> None:
    client, _requests, streams = _session(
        [_ok(b"123456", headers={"Content-Length": "6"})],
        max_bytes=100,
    )

    with client, pytest.raises(ArtifactTooLargeError):
        client.retrieve(ORIGIN, authorize=_authorize(client), max_bytes=4)

    _assert_unread(streams)


@pytest.mark.parametrize("header", ["nope", "-1", "1.5", "0x10"])
def test_malformed_content_length_fails_closed_before_the_body_is_read(header: str) -> None:
    client, requests, streams = _session([_ok(b"abcd", headers={"Content-Length": header})])

    with client, pytest.raises(ArtifactLengthMismatchError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))

    _assert_safe_retrieval(raised.value)
    assert len(requests) == 1
    _assert_unread(streams)


def test_absent_content_length_has_no_mismatch_check() -> None:
    client, _requests, _streams = _session([_ok(b"abc")])

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    assert artifact.content == b"abc"
    assert artifact.observation is not None
    assert artifact.observation.content_length is None


def test_observation_keeps_audit_safe_headers_and_drops_unsafe_ones() -> None:
    safe_modified = "Thu, 27 Aug 2026 21:05:00 GMT"
    client, _requests, _streams = _session(
        [
            _redirect(f"https://{HOST}/final.zip"),
            _ok(
                b"data",
                headers={
                    "Content-Type": "application/zip",
                    "Content-Length": "4",
                    "Content-Encoding": "identity",
                    "ETag": '"765443abfe36dd1:0"',
                    "Last-Modified": safe_modified,
                    "Content-Disposition": 'attachment; filename="historical.zip"',
                },
            ),
        ]
    )

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    observation = artifact.observation
    assert observation is not None
    assert observation.etag == '"765443abfe36dd1:0"'
    assert observation.last_modified == safe_modified
    assert observation.content_disposition == 'attachment; filename="historical.zip"'
    assert observation.content_type == "application/zip"
    assert observation.content_encoding == "identity"
    assert observation.content_length == 4
    assert observation.requested_url == ORIGIN
    assert observation.final_url == f"https://{HOST}/final.zip"
    assert observation.redirect_chain == (observation.final_url,)
    assert observation.observed_at == OBSERVED_AT


def test_unsafe_observational_headers_become_absent_instead_of_truncated() -> None:
    long_etag = "e" * 1025
    max_etag = "e" * 1024
    long_modified = "m" * 129
    max_modified = "m" * 128
    client, _requests, _streams = _session(
        [
            _ok(
                b"abcd",
                headers={
                    "Content-Length": "4",
                    "ETag": long_etag,
                    "Last-Modified": long_modified,
                    "Content-Disposition": "attachment;\nfilename=a.zip",
                },
            )
        ]
    )
    bounded, _requests, _streams = _session(
        [
            _ok(
                b"abcd",
                headers={
                    "Content-Length": "4",
                    "ETag": max_etag,
                    "Last-Modified": max_modified,
                    "Content-Type": "text/plain\nbad",
                },
            )
        ]
    )

    with client:
        dropped = client.retrieve(ORIGIN, authorize=_authorize(client))
    with bounded:
        kept = bounded.retrieve(f"https://{HOST}/other.zip", authorize=_authorize(bounded))

    assert dropped.observation is not None
    assert dropped.observation.etag is None
    assert dropped.observation.last_modified is None
    assert dropped.observation.content_disposition is None
    assert kept.observation is not None
    assert kept.observation.etag == max_etag
    assert kept.observation.last_modified == max_modified
    assert kept.observation.content_type is None
    assert kept.content_type == ""


def test_legacy_download_still_follows_redirects_without_an_observation() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path == "/start":
            return httpx.Response(
                302,
                headers={"Location": "https://example.test/final"},
                request=request,
            )
        return httpx.Response(
            200,
            content=b"PK\x03\x04legacy",
            headers={"Content-Type": "application/zip"},
            request=request,
        )

    with HttpArtifactClient(transport=httpx.MockTransport(handler)) as client:
        artifact = client.download("https://example.test/start")

    assert _urls(requests) == ["https://example.test/start", "https://example.test/final"]
    assert artifact.content == b"PK\x03\x04legacy"
    assert artifact.content_type == "application/zip"
    assert artifact.url == "https://example.test/final"
    assert artifact.observation is None
    assert artifact.checksum == hashlib.sha256(artifact.content).hexdigest()


def test_downloaded_artifact_three_argument_form_remains_compatible(tmp_path: Path) -> None:
    artifact = DownloadedArtifact(
        url="https://example.test/file.xlsx",
        content=b"PK\x03\x04payload",
        content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )

    assert artifact.observation is None
    artifact.assert_extension(".xlsx")
    destination = tmp_path / "nested" / "file.xlsx"
    artifact.save(destination)
    assert destination.read_bytes() == artifact.content


def test_tls_verification_cannot_be_disabled() -> None:
    with pytest.raises(ValueError, match="cannot be disabled"):
        HttpArtifactClient(verify=False)


def test_production_sources_do_not_disable_tls() -> None:
    root = Path(http_module.__file__).resolve().parents[1]
    for path in root.rglob("*.py"):
        text = path.read_text(encoding="utf-8")
        assert "verify=False" not in text
        assert "verify = False" not in text
        assert "CERT_NONE" not in text


def test_http_module_depends_on_discovery_and_not_the_portfolio_module() -> None:
    import ast

    tree = ast.parse(Path(http_module.__file__).read_text(encoding="utf-8"))
    imported: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module is not None:
            imported.add(node.module)

    assert "mx_bank_monitor.ingestion.discovery" in imported
    assert "mx_bank_monitor.ingestion.cnbv_portfolio" not in imported


def test_rsp1_redirect_response_closes_before_the_next_request() -> None:
    target = f"https://{HOST}/next.zip"
    events: list[tuple[str, str]] = []
    waits: list[float] = []
    client, requests, streams = _session(
        [_redirect(target), _ok(b"payload")],
        sleeper=waits.append,
        events=events,
    )

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    assert _urls(requests) == [ORIGIN, target]
    assert artifact.content == b"payload"
    assert waits == []
    assert events == [
        ("request", "1"),
        ("close", "1"),
        ("request", "2"),
        ("read", "2"),
        ("close", "2"),
    ]
    assert streams[0].pulled == 0
    _assert_closed_once(streams)


@pytest.mark.parametrize("status", [429, 503], ids=["rsp2", "rsp3"])
def test_rsp_retryable_status_closes_before_the_next_attempt(status: int) -> None:
    events: list[tuple[str, str]] = []
    client, requests, streams = _session(
        [_ok(b"busy", status=status) for _ in range(3)],
        events=events,
    )

    with client, pytest.raises(ArtifactHttpStatusError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 3
    assert events == [
        ("request", "1"),
        ("close", "1"),
        ("request", "2"),
        ("close", "2"),
        ("request", "3"),
        ("close", "3"),
    ]
    assert all(stream.pulled == 0 for stream in streams)
    _assert_closed_once(streams)


def test_rsp4_unsupported_content_encoding_closes_without_reading_the_body() -> None:
    events: list[tuple[str, str]] = []
    waits: list[float] = []
    client, requests, streams = _session(
        [_ok(b"compressed-body", headers={"Content-Encoding": "gzip"})],
        sleeper=waits.append,
        events=events,
    )

    with client, pytest.raises(ArtifactContentEncodingError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 1
    assert waits == []
    assert events == [("request", "1"), ("close", "1")]
    assert streams[0].pulled == 0
    _assert_closed_once(streams)


def test_rsp5_content_length_above_the_cap_closes_without_reading_the_body() -> None:
    events: list[tuple[str, str]] = []
    waits: list[float] = []
    client, requests, streams = _session(
        [_ok(b"0123456789", headers={"Content-Length": "10"})],
        max_bytes=4,
        sleeper=waits.append,
        events=events,
    )

    with client, pytest.raises(ArtifactTooLargeError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 1
    assert waits == []
    assert events == [("request", "1"), ("close", "1")]
    assert streams[0].pulled == 0
    _assert_closed_once(streams)


def test_rsp6_stream_crossing_the_cap_closes() -> None:
    events: list[tuple[str, str]] = []
    waits: list[float] = []
    client, _requests, streams = _session(
        [(200, {}, (b"aa", b"bb", b"cc", b"dd"))],
        max_bytes=4,
        sleeper=waits.append,
        events=events,
    )

    with client, pytest.raises(ArtifactTooLargeError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert waits == []
    assert events == [
        ("request", "1"),
        ("read", "1"),
        ("read", "1"),
        ("read", "1"),
        ("close", "1"),
    ]
    assert streams[0].pulled == 3
    _assert_closed_once(streams)


def test_rsp7_not_found_closes() -> None:
    events: list[tuple[str, str]] = []
    waits: list[float] = []
    client, requests, streams = _session(
        [_ok(b"missing", status=404)],
        sleeper=waits.append,
        events=events,
    )

    with client, pytest.raises(ArtifactNotFoundHttpError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 1
    assert waits == []
    assert events == [("request", "1"), ("close", "1")]
    assert streams[0].pulled == 0
    _assert_closed_once(streams)


@pytest.mark.parametrize("status", [204, 206])
def test_rsp8_non_200_success_status_closes(status: int) -> None:
    events: list[tuple[str, str]] = []
    waits: list[float] = []
    client, requests, streams = _session(
        [_ok(b"partial", status=status)],
        sleeper=waits.append,
        events=events,
    )

    with client, pytest.raises(ArtifactHttpStatusError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 1
    assert waits == []
    assert events == [("request", "1"), ("close", "1")]
    assert streams[0].pulled == 0
    _assert_closed_once(streams)


def test_rsp9_content_length_mismatch_closes() -> None:
    events: list[tuple[str, str]] = []
    waits: list[float] = []
    client, requests, streams = _session(
        [_ok(b"ab", headers={"Content-Length": "4"})],
        sleeper=waits.append,
        events=events,
    )

    with client, pytest.raises(ArtifactLengthMismatchError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 1
    assert waits == []
    assert events == [("request", "1"), ("read", "1"), ("close", "1")]
    assert streams[0].pulled == 1
    _assert_closed_once(streams)


def test_rsp10_successful_200_closes_after_the_exact_bytes_are_read() -> None:
    payload = b"abcd"
    events: list[tuple[str, str]] = []
    client, requests, streams = _session(
        [(200, {"Content-Length": "4"}, (b"ab", b"cd"))],
        events=events,
    )

    with client:
        artifact = client.retrieve(ORIGIN, authorize=_authorize(client))

    assert _urls(requests) == [ORIGIN]
    assert artifact.content == payload
    assert artifact.checksum == hashlib.sha256(payload).hexdigest()
    assert events == [
        ("request", "1"),
        ("read", "1"),
        ("read", "1"),
        ("close", "1"),
    ]
    assert streams[0].pulled == 2
    _assert_closed_once(streams)


def test_retry_backoff_matches_the_download_exponential_wait() -> None:
    from tenacity import wait_exponential

    wait = wait_exponential(multiplier=1, min=1, max=8)

    class _Attempt:
        def __init__(self, attempt_number: int) -> None:
            self.attempt_number = attempt_number

    assert http_module._retry_backoff_seconds(1) == float(wait(_Attempt(1))) == 1.0
    assert http_module._retry_backoff_seconds(2) == float(wait(_Attempt(2))) == 2.0
    assert http_module._retry_backoff_seconds(5) == float(wait(_Attempt(5))) == 8.0


@pytest.mark.parametrize("status", [429, 503], ids=["b1", "b2"])
def test_b1_b2_retryable_status_waits_between_three_attempts(status: int) -> None:
    events: list[tuple[str, str]] = []
    waits: list[float] = []

    def sleeper(delay: float) -> None:
        waits.append(delay)
        events.append(("wait", f"{delay:.1f}"))

    client, requests, streams = _session(
        [_ok(b"busy", status=status) for _ in range(3)],
        sleeper=sleeper,
        events=events,
    )

    with client, pytest.raises(ArtifactHttpStatusError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 3
    assert waits == [1.0, 2.0]
    assert events == [
        ("request", "1"),
        ("close", "1"),
        ("wait", "1.0"),
        ("request", "2"),
        ("close", "2"),
        ("wait", "2.0"),
        ("request", "3"),
        ("close", "3"),
    ]
    assert all(stream.pulled == 0 for stream in streams)
    _assert_closed_once(streams)


def test_b3_transport_failure_waits_between_three_attempts() -> None:
    events: list[tuple[str, str]] = []
    waits: list[float] = []

    def sleeper(delay: float) -> None:
        waits.append(delay)
        events.append(("wait", f"{delay:.1f}"))

    client, requests, streams = _session(
        ["transport", "transport", "transport"],
        sleeper=sleeper,
        events=events,
    )

    with client, pytest.raises(ArtifactTransportError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 3
    assert streams == []
    assert waits == [1.0, 2.0]
    assert events == [
        ("request", "1"),
        ("wait", "1.0"),
        ("request", "2"),
        ("wait", "2.0"),
        ("request", "3"),
    ]


def test_b4_not_found_makes_one_attempt_and_does_not_wait() -> None:
    waits: list[float] = []
    client, requests, streams = _session(
        [_ok(b"missing", status=404), _ok(b"should-not-run")],
        sleeper=waits.append,
    )

    with client, pytest.raises(ArtifactNotFoundHttpError):
        client.retrieve(ORIGIN, authorize=_authorize(client))

    assert len(requests) == 1
    assert waits == []
    _assert_unread(streams)


def test_b5_tls_verification_failure_makes_one_attempt_and_does_not_wait() -> None:
    for steps in (["tls", "transport"], ["tls-context", "transport"]):
        waits: list[float] = []
        client, requests, streams = _session(steps, sleeper=waits.append)

        with client, pytest.raises(ArtifactTlsUntrustedError):
            client.retrieve(ORIGIN, authorize=_authorize(client))

        assert len(requests) == 1
        assert waits == []
        assert streams == []


def test_b6_authority_and_redirect_errors_do_not_wait() -> None:
    waits: list[float] = []
    client, requests, streams = _session([_ok(b"unread")], sleeper=waits.append)
    with client, pytest.raises(Exception) as raised:
        client.retrieve("https://evil.example/historical.zip", authorize=_authorize(client))
    assert getattr(raised.value, "code", None) == "artifact_url_unofficial"
    assert requests == []
    assert streams == []
    assert waits == []

    waits.clear()
    client, requests, streams = _session(
        [_redirect("https://evil.example/historical.zip"), _ok(b"unread")],
        sleeper=waits.append,
    )
    with client, pytest.raises(Exception) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))
    assert getattr(raised.value, "code", None) == "artifact_url_unofficial"
    assert len(requests) == 1
    assert waits == []
    _assert_unread(streams)

    waits.clear()
    origin = f"https://{HOST}/a.zip"
    other = f"https://{HOST}/b.zip"
    client, requests, streams = _session(
        [_redirect(other), _redirect(origin)],
        sleeper=waits.append,
    )
    with client, pytest.raises(ArtifactRedirectError):
        client.retrieve(origin, authorize=_authorize(client))
    assert len(requests) == 2
    assert waits == []
    _assert_unread(streams)

    waits.clear()
    client, requests, streams = _session([(302, {}, (b"unread",))], sleeper=waits.append)
    with client, pytest.raises(ArtifactRedirectError):
        client.retrieve(ORIGIN, authorize=_authorize(client))
    assert len(requests) == 1
    assert waits == []
    _assert_unread(streams)

    waits.clear()
    client, requests, streams = _session(
        [(302, {"Location": f"https://{HOST}/next.zip\nbad"}, (b"unread",))],
        sleeper=waits.append,
    )
    with client, pytest.raises(ArtifactRedirectError) as raised:
        client.retrieve(ORIGIN, authorize=_authorize(client))
    assert raised.value.observation is None
    assert len(requests) == 1
    assert waits == []
    _assert_unread(streams)
