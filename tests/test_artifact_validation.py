import pytest

from mx_bank_monitor.ingestion.http import DownloadedArtifact, InvalidArtifactError


def test_rejects_html_disguised_as_xlsx() -> None:
    artifact = DownloadedArtifact(
        url="https://example.test/file.xlsx",
        content=b"<!doctype html><title>Sign in</title>",
        content_type="text/html",
    )
    with pytest.raises(InvalidArtifactError):
        artifact.assert_extension(".xlsx")


def test_accepts_xlsx_zip_signature() -> None:
    artifact = DownloadedArtifact(
        url="https://example.test/file.xlsx",
        content=b"PK\x03\x04payload",
        content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )
    artifact.assert_extension(".xlsx")
