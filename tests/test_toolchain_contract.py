import hashlib
import os
import platform
import subprocess
import tomllib
from pathlib import Path

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PYTHON_VERSION = "3.12.14"
UV_VERSION = "0.12.6"


def test_effective_toolchain_matches_project_contract() -> None:
    assert platform.python_implementation() == "CPython"
    assert platform.python_version() == PYTHON_VERSION

    uv_result = subprocess.run(
        ["uv", "--version"],
        check=True,
        capture_output=True,
        text=True,
    )
    assert uv_result.stdout.split()[1] == UV_VERSION


def test_project_pins_python_and_uv_exactly() -> None:
    python_version = (REPOSITORY_ROOT / ".python-version").read_text(encoding="utf-8").strip()
    uv_configuration = tomllib.loads(
        (REPOSITORY_ROOT / "uv.toml").read_text(encoding="utf-8")
    )

    assert python_version == PYTHON_VERSION
    assert uv_configuration["required-version"] == f"=={UV_VERSION}"


def test_linux_and_windows_ci_use_the_exact_toolchain() -> None:
    workflow = yaml.safe_load(
        (REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    )

    for job_name in ("quality", "powershell"):
        setup_steps = [
            step
            for step in workflow["jobs"][job_name]["steps"]
            if str(step.get("uses", "")).startswith("astral-sh/setup-uv@")
        ]
        assert len(setup_steps) == 1
        assert setup_steps[0]["with"]["version"] == UV_VERSION
        assert setup_steps[0]["with"]["python-version"] == PYTHON_VERSION


def test_bootstrap_and_checks_preserve_the_locked_environment() -> None:
    bootstrap = (REPOSITORY_ROOT / "scripts" / "bootstrap.ps1").read_text(encoding="utf-8")
    checks = (REPOSITORY_ROOT / "scripts" / "check.ps1").read_text(encoding="utf-8")
    update = (REPOSITORY_ROOT / "scripts" / "update.ps1").read_text(encoding="utf-8")
    laptop_workflow = (REPOSITORY_ROOT / "docs" / "two-laptop-workflow.md").read_text(
        encoding="utf-8"
    )

    assert f'@("python", "install", "{PYTHON_VERSION}")' in bootstrap
    assert '@("sync", "--locked", "--all-groups")' in bootstrap
    assert '@("sync", "--locked", "--all-groups")' in checks
    assert checks.count('"--no-sync"') == 4
    assert '@("sync", "--locked", "--all-groups")' in update
    assert update.count('"--no-sync"') == 2
    assert f"winget install --id astral-sh.uv -e --version {UV_VERSION}" in laptop_workflow


def test_stale_lock_is_rejected_without_rewriting_it(tmp_path: Path) -> None:
    (tmp_path / ".python-version").write_text(f"{PYTHON_VERSION}\n", encoding="utf-8")
    (tmp_path / "uv.toml").write_text(
        f'required-version = "=={UV_VERSION}"\n',
        encoding="utf-8",
    )
    project_path = tmp_path / "pyproject.toml"
    project_path.write_text(
        """[project]
name = "stale-lock-probe"
version = "0.1.0"
requires-python = ">=3.12,<3.13"
dependencies = []
""",
        encoding="utf-8",
    )
    environment = os.environ.copy()
    environment.pop("VIRTUAL_ENV", None)
    subprocess.run(
        ["uv", "lock", "--offline"],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        check=True,
    )

    lock_path = tmp_path / "uv.lock"
    lock_hash_before = hashlib.sha256(lock_path.read_bytes()).digest()
    project_path.write_text(
        project_path.read_text(encoding="utf-8").replace(
            'version = "0.1.0"',
            'version = "0.1.1"',
            1,
        ),
        encoding="utf-8",
    )
    result = subprocess.run(
        ["uv", "sync", "--locked", "--all-groups", "--offline"],
        cwd=tmp_path,
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "needs to be updated, but `--locked` was provided" in (
        result.stdout + result.stderr
    ).lower()
    assert hashlib.sha256(lock_path.read_bytes()).digest() == lock_hash_before
