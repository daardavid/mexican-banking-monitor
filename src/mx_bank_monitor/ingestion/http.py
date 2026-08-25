from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path

import httpx
from tenacity import retry, stop_after_attempt, wait_exponential


class InvalidArtifactError(ValueError):
    pass


@dataclass(frozen=True, slots=True)
class DownloadedArtifact:
    url: str
    content: bytes
    content_type: str

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
    def __init__(self, timeout_seconds: float = 60.0) -> None:
        self._client = httpx.Client(
            timeout=timeout_seconds,
            follow_redirects=True,
            headers={"User-Agent": "mx-bank-monitor/0.1 (+public-data-research)"},
        )

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=1, max=8))
    def download(self, url: str) -> DownloadedArtifact:
        response = self._client.get(url)
        response.raise_for_status()
        return DownloadedArtifact(
            url=str(response.url),
            content=response.content,
            content_type=response.headers.get("content-type", ""),
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> HttpArtifactClient:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
