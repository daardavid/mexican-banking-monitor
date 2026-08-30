from __future__ import annotations

import os
import re
import tempfile
import time
from contextlib import suppress
from dataclasses import dataclass
from enum import StrEnum
from hashlib import sha256
from pathlib import Path
from threading import Lock
from typing import Protocol
from urllib.parse import quote

import httpx

REGULATORY_ARTIFACTS_BUCKET = "regulatory-artifacts"
_SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
_CANONICAL_KEY_PATTERN = re.compile(r"^sha256/([0-9a-f]{2})/([0-9a-f]{64})$")
_DUPLICATE_CODES = frozenset(
    {"ResourceAlreadyExists", "KeyAlreadyExists", "already_exists"}
)
_AUTHORIZATION_CODES = frozenset({"AccessDenied", "InvalidJWT", "unauthorized"})
_TRANSIENT_STATUS_CODES = frozenset({408, 429, *range(500, 600)})


class InvalidArtifactPayloadError(ValueError):
    """The caller supplied bytes and identity metadata that disagree."""


class InvalidArtifactLocationError(ValueError):
    """A storage location is malformed or incompatible with its backend."""


class ArtifactStoreError(Exception):
    """Base class for artifact storage failures."""


class ArtifactNotFoundError(ArtifactStoreError):
    """The requested canonical artifact does not exist."""


class ArtifactIntegrityError(ArtifactStoreError):
    """Stored bytes do not satisfy their immutable content identity."""


class ArtifactCollisionError(ArtifactIntegrityError):
    """An existing canonical key contains different bytes."""


class ArtifactCorruptionError(ArtifactIntegrityError):
    """A stored artifact cannot be read back with its recorded identity."""


class ArtifactBackendError(ArtifactStoreError):
    """The storage backend could not complete an operation safely."""


class ArtifactAuthorizationError(ArtifactBackendError):
    """The storage backend rejected its server-side credentials."""


class ArtifactWriteOutcomeUnknownError(ArtifactBackendError):
    """A create-only upload could not be resolved through read-back."""


class _TransientBackendError(ArtifactBackendError):
    pass


class StorageBackend(StrEnum):
    LOCAL = "local"
    SUPABASE = "supabase"


class PutOutcome(StrEnum):
    STORED = "stored"
    REUSED = "reused"


def _validate_sha256(value: str, *, error_type: type[ValueError]) -> str:
    if not _SHA256_PATTERN.fullmatch(value):
        raise error_type("SHA-256 must be exactly 64 lowercase hexadecimal characters")
    return value


def canonical_artifact_key(artifact_sha256: str) -> str:
    validated = _validate_sha256(
        artifact_sha256,
        error_type=InvalidArtifactPayloadError,
    )
    return f"sha256/{validated[:2]}/{validated}"


def _sha256_from_key(storage_key: str) -> str:
    match = _CANONICAL_KEY_PATTERN.fullmatch(storage_key)
    if match is None or match.group(1) != match.group(2)[:2]:
        raise InvalidArtifactLocationError("Storage key is not a canonical artifact key")
    return match.group(2)


@dataclass(frozen=True, slots=True)
class ArtifactPayload:
    content: bytes
    sha256: str
    byte_length: int
    mime_type: str | None = None

    def __post_init__(self) -> None:
        if not isinstance(self.content, bytes):
            raise InvalidArtifactPayloadError("Artifact content must be bytes")
        if self.byte_length <= 0:
            raise InvalidArtifactPayloadError("Artifact byte length must be positive")
        _validate_sha256(self.sha256, error_type=InvalidArtifactPayloadError)
        if len(self.content) != self.byte_length:
            raise InvalidArtifactPayloadError("Artifact byte length does not match its content")
        if sha256(self.content).hexdigest() != self.sha256:
            raise InvalidArtifactPayloadError("Artifact SHA-256 does not match its content")
        if self.mime_type is not None:
            if not self.mime_type.strip():
                raise InvalidArtifactPayloadError("Artifact MIME type must not be blank")
            if any(ord(character) < 32 or ord(character) == 127 for character in self.mime_type):
                raise InvalidArtifactPayloadError(
                    "Artifact MIME type contains unsafe control characters"
                )

    @classmethod
    def from_bytes(
        cls,
        content: bytes,
        *,
        mime_type: str | None = None,
    ) -> ArtifactPayload:
        return cls(
            content=content,
            sha256=sha256(content).hexdigest(),
            byte_length=len(content),
            mime_type=mime_type,
        )


@dataclass(frozen=True, slots=True)
class StoredArtifactLocation:
    storage_backend: StorageBackend
    storage_bucket: str | None
    storage_key: str

    def __post_init__(self) -> None:
        _sha256_from_key(self.storage_key)
        if self.storage_backend is StorageBackend.LOCAL:
            if self.storage_bucket is not None:
                raise InvalidArtifactLocationError("Local artifact locations cannot name a bucket")
            return
        if self.storage_backend is StorageBackend.SUPABASE:
            if self.storage_bucket != REGULATORY_ARTIFACTS_BUCKET:
                raise InvalidArtifactLocationError(
                    "Supabase artifact location uses an unexpected bucket"
                )
            return
        raise InvalidArtifactLocationError("Unsupported artifact storage backend")


@dataclass(frozen=True, slots=True)
class StoredArtifact:
    location: StoredArtifactLocation
    sha256: str
    byte_length: int

    def __post_init__(self) -> None:
        _validate_sha256(self.sha256, error_type=InvalidArtifactLocationError)
        if self.byte_length <= 0:
            raise InvalidArtifactLocationError("Stored artifact byte length must be positive")
        if self.location.storage_key != canonical_artifact_key(self.sha256):
            raise InvalidArtifactLocationError(
                "Stored artifact identity does not match its canonical location"
            )


@dataclass(frozen=True, slots=True)
class PutArtifactResult:
    artifact: StoredArtifact
    outcome: PutOutcome


class ArtifactStore(Protocol):
    def put_if_absent(self, payload: ArtifactPayload, /) -> PutArtifactResult: ...

    def get(self, location: StoredArtifactLocation, /) -> bytes: ...

    def verify(self, artifact: StoredArtifact, /) -> None: ...


class LocalArtifactStore:
    def __init__(self, root: Path = Path("data/raw")) -> None:
        try:
            root.mkdir(parents=True, exist_ok=True)
            self._root = root.resolve(strict=True)
        except OSError:
            raise ArtifactBackendError("Local artifact root could not be prepared") from None
        self._directory_lock = Lock()

    def __repr__(self) -> str:
        return "LocalArtifactStore()"

    def put_if_absent(self, payload: ArtifactPayload, /) -> PutArtifactResult:
        self._validate_payload(payload)
        artifact = self._artifact_for(payload)
        target = self._target_path(artifact.location, prepare_parent=True)

        if target.exists():
            return self._reuse_existing(target, payload, artifact)

        temporary_path: Path | None = None
        published = False
        try:
            descriptor, temporary_name = tempfile.mkstemp(
                prefix=f".{payload.sha256}.",
                suffix=".tmp",
                dir=target.parent,
            )
            temporary_path = Path(temporary_name)
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(payload.content)
                handle.flush()
                os.fsync(handle.fileno())

            try:
                os.link(temporary_path, target)
                published = True
            except FileExistsError:
                return self._reuse_existing(target, payload, artifact)
            except OSError:
                raise ArtifactBackendError(
                    f"Local create-only publication failed for {artifact.location.storage_key}"
                ) from None

            self._assert_exact_payload(target, payload, collision=False)
            return PutArtifactResult(artifact=artifact, outcome=PutOutcome.STORED)
        except ArtifactStoreError:
            raise
        except OSError:
            if published:
                raise ArtifactWriteOutcomeUnknownError(
                    "Local artifact publication outcome is unknown for "
                    f"{artifact.location.storage_key}"
                ) from None
            raise ArtifactBackendError(
                f"Local artifact write failed for {artifact.location.storage_key}"
            ) from None
        finally:
            if temporary_path is not None:
                with suppress(OSError):
                    temporary_path.unlink(missing_ok=True)

    def get(self, location: StoredArtifactLocation, /) -> bytes:
        target = self._target_path(location)
        try:
            content = target.read_bytes()
        except FileNotFoundError:
            raise ArtifactNotFoundError(
                f"Local artifact not found: {location.storage_key}"
            ) from None
        except OSError:
            raise ArtifactBackendError(
                f"Local artifact read failed: {location.storage_key}"
            ) from None
        expected_sha256 = _sha256_from_key(location.storage_key)
        if sha256(content).hexdigest() != expected_sha256:
            raise ArtifactCorruptionError(
                f"Local artifact failed SHA-256 verification: {location.storage_key}"
            )
        return content

    def verify(self, artifact: StoredArtifact, /) -> None:
        self._validate_location(artifact.location)
        content = self.get(artifact.location)
        if len(content) != artifact.byte_length:
            raise ArtifactCorruptionError(
                f"Local artifact failed byte-length verification: {artifact.location.storage_key}"
            )

    @staticmethod
    def _validate_payload(payload: ArtifactPayload) -> None:
        ArtifactPayload(
            content=payload.content,
            sha256=payload.sha256,
            byte_length=payload.byte_length,
            mime_type=payload.mime_type,
        )

    def _validate_location(self, location: StoredArtifactLocation) -> None:
        if (
            location.storage_backend is not StorageBackend.LOCAL
            or location.storage_bucket is not None
        ):
            raise InvalidArtifactLocationError(
                "Location does not belong to the local artifact store"
            )
        _sha256_from_key(location.storage_key)

    def _target_path(
        self,
        location: StoredArtifactLocation,
        *,
        prepare_parent: bool = False,
    ) -> Path:
        self._validate_location(location)
        candidate = self._root.joinpath(*location.storage_key.split("/"))
        with self._directory_lock:
            if prepare_parent:
                try:
                    candidate.parent.mkdir(parents=True, exist_ok=True)
                except OSError:
                    raise ArtifactBackendError(
                        f"Local artifact directory could not be prepared: {location.storage_key}"
                    ) from None
            target = candidate.resolve(strict=False)
        if not target.is_relative_to(self._root):
            raise InvalidArtifactLocationError("Local artifact path escapes its configured root")
        return target

    @staticmethod
    def _artifact_for(payload: ArtifactPayload) -> StoredArtifact:
        return StoredArtifact(
            location=StoredArtifactLocation(
                storage_backend=StorageBackend.LOCAL,
                storage_bucket=None,
                storage_key=canonical_artifact_key(payload.sha256),
            ),
            sha256=payload.sha256,
            byte_length=payload.byte_length,
        )

    def _reuse_existing(
        self,
        target: Path,
        payload: ArtifactPayload,
        artifact: StoredArtifact,
    ) -> PutArtifactResult:
        self._assert_exact_payload(target, payload, collision=True)
        return PutArtifactResult(artifact=artifact, outcome=PutOutcome.REUSED)

    @staticmethod
    def _assert_exact_payload(
        target: Path,
        payload: ArtifactPayload,
        *,
        collision: bool,
    ) -> None:
        try:
            existing = target.read_bytes()
        except FileNotFoundError:
            raise ArtifactBackendError(
                "Local artifact changed during verification: "
                f"{canonical_artifact_key(payload.sha256)}"
            ) from None
        except OSError:
            raise ArtifactBackendError(
                f"Local artifact verification failed: {canonical_artifact_key(payload.sha256)}"
            ) from None
        if (
            len(existing) != payload.byte_length
            or sha256(existing).hexdigest() != payload.sha256
            or existing != payload.content
        ):
            error_type = ArtifactCollisionError if collision else ArtifactCorruptionError
            raise error_type(
                f"Local artifact content conflicts with {canonical_artifact_key(payload.sha256)}"
            )


class SupabaseArtifactStore:
    def __init__(
        self,
        *,
        supabase_url: str,
        secret_key: str,
        client: httpx.Client | None = None,
        read_attempts: int = 3,
        create_attempts: int = 2,
        retry_backoff_seconds: float = 0.1,
    ) -> None:
        if not supabase_url.strip():
            raise ValueError("Supabase URL must not be blank")
        if not secret_key:
            raise ValueError("Supabase secret key must not be blank")
        if read_attempts < 1 or create_attempts < 1:
            raise ValueError("Artifact retry attempts must be positive")
        if retry_backoff_seconds < 0:
            raise ValueError("Artifact retry backoff must not be negative")
        self._supabase_url = supabase_url.rstrip("/")
        self._secret_key = secret_key
        self._client = client or httpx.Client(timeout=60.0)
        self._owns_client = client is None
        self._read_attempts = read_attempts
        self._create_attempts = create_attempts
        self._retry_backoff_seconds = retry_backoff_seconds

    def __repr__(self) -> str:
        return f"SupabaseArtifactStore(bucket={REGULATORY_ARTIFACTS_BUCKET!r})"

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def __enter__(self) -> SupabaseArtifactStore:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def put_if_absent(self, payload: ArtifactPayload, /) -> PutArtifactResult:
        LocalArtifactStore._validate_payload(payload)
        artifact = self._artifact_for(payload)
        return self._create(payload, artifact, attempt=1)

    def get(self, location: StoredArtifactLocation, /) -> bytes:
        self._validate_location(location)
        content = self._read_with_retries(location)
        expected_sha256 = _sha256_from_key(location.storage_key)
        if sha256(content).hexdigest() != expected_sha256:
            raise ArtifactCorruptionError(
                f"Supabase artifact failed SHA-256 verification: {location.storage_key}"
            )
        return content

    def verify(self, artifact: StoredArtifact, /) -> None:
        self._validate_location(artifact.location)
        content = self.get(artifact.location)
        if len(content) != artifact.byte_length:
            raise ArtifactCorruptionError(
                "Supabase artifact failed byte-length verification: "
                f"{artifact.location.storage_key}"
            )

    def _create(
        self,
        payload: ArtifactPayload,
        artifact: StoredArtifact,
        *,
        attempt: int,
    ) -> PutArtifactResult:
        try:
            response = self._client.post(
                self._upload_url(artifact.location),
                headers={
                    "apikey": self._secret_key,
                    "Content-Type": payload.mime_type or "application/octet-stream",
                    "x-upsert": "false",
                },
                content=payload.content,
            )
        except (httpx.TimeoutException, httpx.TransportError):
            return self._resolve_ambiguous(payload, artifact, attempt=attempt)

        if response.is_success:
            try:
                self._assert_remote_payload(artifact.location, payload, collision=False)
            except ArtifactIntegrityError:
                raise
            except ArtifactStoreError:
                raise ArtifactWriteOutcomeUnknownError(
                    f"Supabase upload could not be verified: {artifact.location.storage_key}"
                ) from None
            return PutArtifactResult(artifact=artifact, outcome=PutOutcome.STORED)

        code = self._error_code(response)
        if code in _DUPLICATE_CODES:
            self._assert_remote_payload(artifact.location, payload, collision=True)
            return PutArtifactResult(artifact=artifact, outcome=PutOutcome.REUSED)
        if response.status_code in _TRANSIENT_STATUS_CODES:
            return self._resolve_ambiguous(payload, artifact, attempt=attempt)
        self._raise_response_error(response, operation="upload")
        raise AssertionError("unreachable")

    def _resolve_ambiguous(
        self,
        payload: ArtifactPayload,
        artifact: StoredArtifact,
        *,
        attempt: int,
    ) -> PutArtifactResult:
        try:
            self._assert_remote_payload(artifact.location, payload, collision=False)
        except ArtifactNotFoundError:
            if attempt < self._create_attempts:
                return self._create(payload, artifact, attempt=attempt + 1)
            raise ArtifactWriteOutcomeUnknownError(
                f"Supabase upload outcome is unresolved: {artifact.location.storage_key}"
            ) from None
        except ArtifactIntegrityError:
            raise
        except ArtifactStoreError:
            raise ArtifactWriteOutcomeUnknownError(
                f"Supabase upload outcome is unresolved: {artifact.location.storage_key}"
            ) from None
        return PutArtifactResult(artifact=artifact, outcome=PutOutcome.REUSED)

    def _read_with_retries(self, location: StoredArtifactLocation) -> bytes:
        last_transient = False
        for attempt in range(1, self._read_attempts + 1):
            try:
                return self._read_once(location)
            except _TransientBackendError:
                last_transient = True
                if attempt < self._read_attempts:
                    self._backoff(attempt)
        if last_transient:
            raise ArtifactBackendError(
                f"Supabase artifact read exhausted retries: {location.storage_key}"
            ) from None
        raise AssertionError("unreachable")

    def _read_once(self, location: StoredArtifactLocation) -> bytes:
        try:
            response = self._client.get(
                self._download_url(location),
                headers={"apikey": self._secret_key},
            )
        except (httpx.TimeoutException, httpx.TransportError):
            raise _TransientBackendError(
                f"Transient Supabase read failure: {location.storage_key}"
            ) from None
        if response.is_success:
            return response.content
        if response.status_code in _TRANSIENT_STATUS_CODES:
            raise _TransientBackendError(
                f"Transient Supabase read failure: {location.storage_key}"
            )
        self._raise_response_error(response, operation="read")
        raise AssertionError("unreachable")

    def _assert_remote_payload(
        self,
        location: StoredArtifactLocation,
        payload: ArtifactPayload,
        *,
        collision: bool,
    ) -> None:
        existing = self.get(location)
        if len(existing) != payload.byte_length or existing != payload.content:
            error_type = ArtifactCollisionError if collision else ArtifactCorruptionError
            raise error_type(
                f"Supabase artifact content conflicts with {location.storage_key}"
            )

    def _raise_response_error(self, response: httpx.Response, *, operation: str) -> None:
        code = self._error_code(response)
        safe_code = code or "unknown"
        if response.status_code in {401, 403} or code in _AUTHORIZATION_CODES:
            raise ArtifactAuthorizationError(
                f"Supabase artifact {operation} was unauthorized ({safe_code})"
            )
        if code == "NoSuchKey":
            raise ArtifactNotFoundError("Supabase artifact was not found")
        if code == "NoSuchBucket":
            raise ArtifactBackendError("Supabase artifact bucket does not exist")
        raise ArtifactBackendError(
            f"Supabase artifact {operation} failed with status "
            f"{response.status_code} ({safe_code})"
        )

    @staticmethod
    def _error_code(response: httpx.Response) -> str | None:
        try:
            body = response.json()
        except ValueError:
            return None
        if not isinstance(body, dict):
            return None
        for field in ("code", "error"):
            value = body.get(field)
            if isinstance(value, str) and value:
                return value
        return None

    def _validate_location(self, location: StoredArtifactLocation) -> None:
        if (
            location.storage_backend is not StorageBackend.SUPABASE
            or location.storage_bucket != REGULATORY_ARTIFACTS_BUCKET
        ):
            raise InvalidArtifactLocationError(
                "Location does not belong to the Supabase artifact store"
            )
        _sha256_from_key(location.storage_key)

    @staticmethod
    def _artifact_for(payload: ArtifactPayload) -> StoredArtifact:
        return StoredArtifact(
            location=StoredArtifactLocation(
                storage_backend=StorageBackend.SUPABASE,
                storage_bucket=REGULATORY_ARTIFACTS_BUCKET,
                storage_key=canonical_artifact_key(payload.sha256),
            ),
            sha256=payload.sha256,
            byte_length=payload.byte_length,
        )

    def _upload_url(self, location: StoredArtifactLocation) -> str:
        return f"{self._supabase_url}/storage/v1/object/{self._quoted_location(location)}"

    def _download_url(self, location: StoredArtifactLocation) -> str:
        return (
            f"{self._supabase_url}/storage/v1/object/authenticated/"
            f"{self._quoted_location(location)}"
        )

    @staticmethod
    def _quoted_location(location: StoredArtifactLocation) -> str:
        assert location.storage_bucket is not None
        segments = (location.storage_bucket, *location.storage_key.split("/"))
        return "/".join(quote(segment, safe="") for segment in segments)

    def _backoff(self, attempt: int) -> None:
        delay = self._retry_backoff_seconds * (2 ** (attempt - 1))
        if delay:
            time.sleep(delay)
