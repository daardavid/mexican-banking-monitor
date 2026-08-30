from __future__ import annotations

import os
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from pathlib import Path

import httpx
import pytest

from mx_bank_monitor.ingestion.artifacts import (
    REGULATORY_ARTIFACTS_BUCKET,
    ArtifactAuthorizationError,
    ArtifactBackendError,
    ArtifactCollisionError,
    ArtifactCorruptionError,
    ArtifactNotFoundError,
    ArtifactPayload,
    ArtifactWriteOutcomeUnknownError,
    InvalidArtifactLocationError,
    InvalidArtifactPayloadError,
    LocalArtifactStore,
    PutOutcome,
    StorageBackend,
    StoredArtifact,
    StoredArtifactLocation,
    SupabaseArtifactStore,
    canonical_artifact_key,
)

CONTENT = b"immutable-regulatory-artifact"
MIME_TYPE = "application/pdf"
SECRET_MARKER = "sb_secret_THIS_MUST_NEVER_APPEAR"
SUPABASE_URL = "https://project.example.test"


def payload(content: bytes = CONTENT, *, mime_type: str | None = MIME_TYPE) -> ArtifactPayload:
    return ArtifactPayload.from_bytes(content, mime_type=mime_type)


def local_location(artifact_sha256: str) -> StoredArtifactLocation:
    return StoredArtifactLocation(
        storage_backend=StorageBackend.LOCAL,
        storage_bucket=None,
        storage_key=canonical_artifact_key(artifact_sha256),
    )


def supabase_location(artifact_sha256: str) -> StoredArtifactLocation:
    return StoredArtifactLocation(
        storage_backend=StorageBackend.SUPABASE,
        storage_bucket=REGULATORY_ARTIFACTS_BUCKET,
        storage_key=canonical_artifact_key(artifact_sha256),
    )


def response(
    status_code: int,
    *,
    request: httpx.Request,
    content: bytes | None = None,
    json: object | None = None,
) -> httpx.Response:
    if json is not None:
        return httpx.Response(status_code, request=request, json=json)
    return httpx.Response(status_code, request=request, content=content or b"")


def supabase_store(
    handler: httpx.MockTransport,
    *,
    read_attempts: int = 3,
    create_attempts: int = 2,
) -> SupabaseArtifactStore:
    return SupabaseArtifactStore(
        supabase_url=SUPABASE_URL,
        secret_key=SECRET_MARKER,
        client=httpx.Client(transport=handler),
        read_attempts=read_attempts,
        create_attempts=create_attempts,
        retry_backoff_seconds=0,
    )


def test_canonical_key_is_deterministic_lowercase_and_sharded() -> None:
    digest = sha256(CONTENT).hexdigest()

    assert canonical_artifact_key(digest) == f"sha256/{digest[:2]}/{digest}"
    assert canonical_artifact_key(digest) == canonical_artifact_key(digest)
    assert "." not in canonical_artifact_key(digest)


@pytest.mark.parametrize(
    "invalid_hash",
    ["a" * 63, "a" * 65, "G" * 64, "A" * 64, "../" + "a" * 61],
)
def test_canonical_key_rejects_invalid_or_uppercase_hashes(invalid_hash: str) -> None:
    with pytest.raises(InvalidArtifactPayloadError):
        canonical_artifact_key(invalid_hash)


def test_canonical_key_has_no_editorial_identity_inputs() -> None:
    digest = sha256(CONTENT).hexdigest()
    key = canonical_artifact_key(digest)

    for forbidden in ("cnbv", "release", "2026", "artifact.pdf", "https"):
        assert forbidden not in key


def test_payload_from_bytes_calculates_identity() -> None:
    artifact_payload = payload()

    assert artifact_payload.content == CONTENT
    assert artifact_payload.sha256 == sha256(CONTENT).hexdigest()
    assert artifact_payload.byte_length == len(CONTENT)
    assert artifact_payload.mime_type == MIME_TYPE


def test_payload_rejects_incorrect_expected_sha() -> None:
    with pytest.raises(InvalidArtifactPayloadError, match="SHA-256 does not match"):
        ArtifactPayload(
            content=CONTENT,
            sha256="0" * 64,
            byte_length=len(CONTENT),
            mime_type=MIME_TYPE,
        )


def test_payload_rejects_incorrect_expected_length() -> None:
    with pytest.raises(InvalidArtifactPayloadError, match="byte length does not match"):
        ArtifactPayload(
            content=CONTENT,
            sha256=sha256(CONTENT).hexdigest(),
            byte_length=len(CONTENT) + 1,
            mime_type=MIME_TYPE,
        )


def test_payload_rejects_empty_content() -> None:
    with pytest.raises(InvalidArtifactPayloadError, match="must be positive"):
        ArtifactPayload.from_bytes(b"")


@pytest.mark.parametrize("mime_type", ["", "   ", "application/pdf\r\nX-Unsafe: yes"])
def test_payload_rejects_unsafe_optional_mime(mime_type: str) -> None:
    with pytest.raises(InvalidArtifactPayloadError):
        ArtifactPayload.from_bytes(CONTENT, mime_type=mime_type)


def test_payload_accepts_absent_or_safe_mime() -> None:
    assert payload(mime_type=None).mime_type is None
    assert payload(mime_type="application/pdf; charset=binary").mime_type is not None


def test_location_validates_backend_bucket_compatibility() -> None:
    digest = sha256(CONTENT).hexdigest()

    with pytest.raises(InvalidArtifactLocationError):
        StoredArtifactLocation(
            storage_backend=StorageBackend.LOCAL,
            storage_bucket=REGULATORY_ARTIFACTS_BUCKET,
            storage_key=canonical_artifact_key(digest),
        )
    with pytest.raises(InvalidArtifactLocationError):
        StoredArtifactLocation(
            storage_backend=StorageBackend.SUPABASE,
            storage_bucket="unexpected",
            storage_key=canonical_artifact_key(digest),
        )


def test_local_store_put_get_verify_and_reuse(tmp_path: Path) -> None:
    store = LocalArtifactStore(tmp_path / "raw")
    artifact_payload = payload()

    first = store.put_if_absent(artifact_payload)
    second = store.put_if_absent(artifact_payload)

    assert first.outcome is PutOutcome.STORED
    assert second.outcome is PutOutcome.REUSED
    assert first.artifact == second.artifact
    assert first.artifact.location.storage_backend is StorageBackend.LOCAL
    assert first.artifact.location.storage_bucket is None
    assert first.artifact.location.storage_key == canonical_artifact_key(artifact_payload.sha256)
    assert not Path(first.artifact.location.storage_key).is_absolute()
    assert "\\" not in first.artifact.location.storage_key
    assert store.get(first.artifact.location) == CONTENT
    assert store.verify(first.artifact) is None

    target = tmp_path / "raw" / Path(*first.artifact.location.storage_key.split("/"))
    assert target.read_bytes() == CONTENT
    assert target.parent.is_dir()


def test_local_store_detects_tampered_existing_object_without_overwrite(tmp_path: Path) -> None:
    store = LocalArtifactStore(tmp_path / "raw")
    artifact_payload = payload()
    location = local_location(artifact_payload.sha256)
    target = tmp_path / "raw" / Path(*location.storage_key.split("/"))
    target.parent.mkdir(parents=True)
    target.write_bytes(b"corrupt")

    with pytest.raises(ArtifactCollisionError):
        store.put_if_absent(artifact_payload)

    assert target.read_bytes() == b"corrupt"


def test_local_store_get_detects_corruption(tmp_path: Path) -> None:
    store = LocalArtifactStore(tmp_path / "raw")
    artifact_payload = payload()
    result = store.put_if_absent(artifact_payload)
    target = tmp_path / "raw" / Path(*result.artifact.location.storage_key.split("/"))
    target.write_bytes(b"tampered")

    with pytest.raises(ArtifactCorruptionError):
        store.get(result.artifact.location)


def test_local_store_verify_detects_wrong_expected_length(tmp_path: Path) -> None:
    store = LocalArtifactStore(tmp_path / "raw")
    result = store.put_if_absent(payload())
    wrong_length = StoredArtifact(
        location=result.artifact.location,
        sha256=result.artifact.sha256,
        byte_length=result.artifact.byte_length + 1,
    )

    with pytest.raises(ArtifactCorruptionError, match="byte-length"):
        store.verify(wrong_length)


def test_local_store_reports_missing_object(tmp_path: Path) -> None:
    store = LocalArtifactStore(tmp_path / "raw")

    with pytest.raises(ArtifactNotFoundError):
        store.get(local_location(sha256(CONTENT).hexdigest()))


def test_local_store_rejects_supabase_location(tmp_path: Path) -> None:
    store = LocalArtifactStore(tmp_path / "raw")

    with pytest.raises(InvalidArtifactLocationError):
        store.get(supabase_location(sha256(CONTENT).hexdigest()))


def test_local_concurrent_identical_writers_converge(tmp_path: Path) -> None:
    store = LocalArtifactStore(tmp_path / "raw")
    artifact_payload = payload()

    with ThreadPoolExecutor(max_workers=8) as executor:
        results = tuple(executor.map(store.put_if_absent, [artifact_payload] * 16))

    assert sum(result.outcome is PutOutcome.STORED for result in results) == 1
    assert sum(result.outcome is PutOutcome.REUSED for result in results) == 15
    assert {result.artifact for result in results} == {results[0].artifact}
    assert store.get(results[0].artifact.location) == CONTENT


def test_local_store_fails_closed_when_hard_links_are_unsupported(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    store = LocalArtifactStore(tmp_path / "raw")

    def unsupported_link(_source: os.PathLike[str], _target: os.PathLike[str]) -> None:
        raise OSError("unsupported")

    monkeypatch.setattr(os, "link", unsupported_link)

    with pytest.raises(ArtifactBackendError, match="create-only publication failed"):
        store.put_if_absent(payload())

    assert not tuple((tmp_path / "raw").rglob("*.tmp"))
    location = local_location(sha256(CONTENT).hexdigest())
    canonical_target = tmp_path / "raw" / Path(*location.storage_key.split("/"))
    assert not canonical_target.exists()


def test_supabase_new_upload_uses_exact_create_only_request_and_verifies() -> None:
    requests: list[httpx.Request] = []
    artifact_payload = payload()

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.method == "POST":
            return response(200, request=request, json={"Key": "stored"})
        return response(200, request=request, content=CONTENT)

    store = supabase_store(httpx.MockTransport(handler))
    result = store.put_if_absent(artifact_payload)

    assert result.outcome is PutOutcome.STORED
    assert result.artifact.location == supabase_location(artifact_payload.sha256)
    assert [request.method for request in requests] == ["POST", "GET"]
    expected_path = (
        "/storage/v1/object/regulatory-artifacts/"
        f"sha256/{artifact_payload.sha256[:2]}/{artifact_payload.sha256}"
    )
    assert requests[0].url.path == expected_path
    assert "%2F" not in str(requests[0].url)
    assert requests[0].headers["x-upsert"] == "false"
    assert requests[0].headers["content-type"] == MIME_TYPE
    assert requests[0].headers["apikey"] == SECRET_MARKER
    assert "authorization" not in requests[0].headers
    assert requests[0].content == CONTENT
    assert requests[1].url.path.startswith(
        "/storage/v1/object/authenticated/regulatory-artifacts/sha256/"
    )
    assert "authorization" not in requests[1].headers


def test_supabase_upload_defaults_to_binary_content_type() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.method == "POST":
            return response(200, request=request, json={})
        return response(200, request=request, content=CONTENT)

    store = supabase_store(httpx.MockTransport(handler))
    store.put_if_absent(payload(mime_type=None))

    assert requests[0].headers["content-type"] == "application/octet-stream"


@pytest.mark.parametrize(
    ("status_code", "error_body"),
    [
        (409, {"code": "ResourceAlreadyExists", "message": "exists"}),
        (409, {"code": "KeyAlreadyExists", "message": "exists"}),
        (400, {"error": "already_exists", "message": "exists"}),
    ],
)
def test_supabase_explicit_duplicate_reuses_exact_existing_object(
    status_code: int,
    error_body: dict[str, str],
) -> None:
    methods: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        methods.append(request.method)
        if request.method == "POST":
            return response(status_code, request=request, json=error_body)
        return response(200, request=request, content=CONTENT)

    result = supabase_store(httpx.MockTransport(handler)).put_if_absent(payload())

    assert result.outcome is PutOutcome.REUSED
    assert methods == ["POST", "GET"]


def test_supabase_duplicate_detects_corrupt_existing_object() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.method == "POST":
            return response(409, request=request, json={"code": "KeyAlreadyExists"})
        return response(200, request=request, content=b"corrupt")

    with pytest.raises(ArtifactCorruptionError):
        supabase_store(httpx.MockTransport(handler)).put_if_absent(payload())


def test_supabase_timeout_then_exact_read_returns_reused_without_post_retry() -> None:
    methods: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        methods.append(request.method)
        if request.method == "POST":
            raise httpx.ReadTimeout("ambiguous", request=request)
        return response(200, request=request, content=CONTENT)

    result = supabase_store(httpx.MockTransport(handler)).put_if_absent(payload())

    assert result.outcome is PutOutcome.REUSED
    assert methods == ["POST", "GET"]


def test_supabase_timeout_then_missing_retries_only_create_only_post() -> None:
    requests: list[httpx.Request] = []
    post_count = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal post_count
        requests.append(request)
        if request.method == "POST":
            post_count += 1
            if post_count == 1:
                raise httpx.ReadTimeout("ambiguous", request=request)
            return response(200, request=request, json={})
        if post_count == 1:
            return response(404, request=request, json={"code": "NoSuchKey"})
        return response(200, request=request, content=CONTENT)

    result = supabase_store(httpx.MockTransport(handler)).put_if_absent(payload())

    assert result.outcome is PutOutcome.STORED
    assert [request.method for request in requests] == ["POST", "GET", "POST", "GET"]
    assert [request.headers["x-upsert"] for request in requests if request.method == "POST"] == [
        "false",
        "false",
    ]


def test_supabase_unresolved_timeout_fails_closed() -> None:
    methods: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        methods.append(request.method)
        if request.method == "POST":
            raise httpx.ReadTimeout("ambiguous", request=request)
        return response(503, request=request, json={"code": "InternalError"})

    with pytest.raises(ArtifactWriteOutcomeUnknownError):
        supabase_store(httpx.MockTransport(handler), read_attempts=2).put_if_absent(payload())

    assert methods == ["POST", "GET", "GET"]


@pytest.mark.parametrize("status_code", [408, 500, 501, 599])
def test_supabase_ambiguous_server_response_is_resolved_by_read(status_code: int) -> None:
    methods: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        methods.append(request.method)
        if request.method == "POST":
            return response(status_code, request=request, json={"code": "InternalError"})
        return response(200, request=request, content=CONTENT)

    result = supabase_store(httpx.MockTransport(handler)).put_if_absent(payload())

    assert result.outcome is PutOutcome.REUSED
    assert methods == ["POST", "GET"]


def test_supabase_get_retries_throttling() -> None:
    get_count = 0
    artifact_payload = payload()

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal get_count
        get_count += 1
        if get_count == 1:
            return response(429, request=request, json={"code": "SlowDown"})
        return response(200, request=request, content=CONTENT)

    store = supabase_store(httpx.MockTransport(handler))

    assert store.get(supabase_location(artifact_payload.sha256)) == CONTENT
    assert get_count == 2


def test_supabase_get_and_verify_detect_corruption_and_wrong_length() -> None:
    artifact_payload = payload()

    def corrupt_handler(request: httpx.Request) -> httpx.Response:
        return response(200, request=request, content=b"corrupt")

    store = supabase_store(httpx.MockTransport(corrupt_handler))
    with pytest.raises(ArtifactCorruptionError):
        store.get(supabase_location(artifact_payload.sha256))

    def exact_handler(request: httpx.Request) -> httpx.Response:
        return response(200, request=request, content=CONTENT)

    exact_store = supabase_store(httpx.MockTransport(exact_handler))
    wrong_length = StoredArtifact(
        location=supabase_location(artifact_payload.sha256),
        sha256=artifact_payload.sha256,
        byte_length=artifact_payload.byte_length + 1,
    )
    with pytest.raises(ArtifactCorruptionError, match="byte-length"):
        exact_store.verify(wrong_length)


def test_supabase_distinguishes_missing_object_and_bucket() -> None:
    artifact_payload = payload()

    def missing_key(request: httpx.Request) -> httpx.Response:
        return response(404, request=request, json={"code": "NoSuchKey"})

    with pytest.raises(ArtifactNotFoundError):
        supabase_store(httpx.MockTransport(missing_key)).get(
            supabase_location(artifact_payload.sha256)
        )

    def missing_bucket(request: httpx.Request) -> httpx.Response:
        return response(404, request=request, json={"code": "NoSuchBucket"})

    with pytest.raises(ArtifactBackendError, match="bucket does not exist"):
        supabase_store(httpx.MockTransport(missing_bucket)).get(
            supabase_location(artifact_payload.sha256)
        )


@pytest.mark.parametrize("status_code", [401, 403])
def test_supabase_authorization_errors_are_sanitized(status_code: int) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return response(status_code, request=request, json={"code": "AccessDenied"})

    store = supabase_store(httpx.MockTransport(handler))
    with pytest.raises(ArtifactAuthorizationError) as raised:
        store.get(supabase_location(sha256(CONTENT).hexdigest()))

    assert SECRET_MARKER not in repr(store)
    assert SECRET_MARKER not in str(raised.value)
    assert SECRET_MARKER not in repr(raised.value)
    assert SUPABASE_URL not in str(raised.value)


def test_supabase_unknown_or_malformed_response_fails_closed() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return response(400, request=request, content=b"not-json")

    with pytest.raises(ArtifactBackendError, match=r"status 400 \(unknown\)"):
        supabase_store(httpx.MockTransport(handler)).get(
            supabase_location(sha256(CONTENT).hexdigest())
        )


def test_supabase_does_not_treat_arbitrary_conflict_as_duplicate() -> None:
    methods: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        methods.append(request.method)
        return response(409, request=request, json={"code": "ResourceLocked"})

    with pytest.raises(ArtifactBackendError, match="ResourceLocked"):
        supabase_store(httpx.MockTransport(handler)).put_if_absent(payload())

    assert methods == ["POST"]


def test_supabase_store_rejects_local_location() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise AssertionError("backend must not be contacted")

    store = supabase_store(httpx.MockTransport(handler))

    with pytest.raises(InvalidArtifactLocationError):
        store.get(local_location(sha256(CONTENT).hexdigest()))
