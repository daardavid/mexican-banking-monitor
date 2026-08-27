import re
from pathlib import Path

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SUPABASE_CLI_VERSION = "2.115.0"
SUPABASE_SETUP_ACTION = (
    "supabase/setup-cli@3c2f5e2ae34c34e428e8e206e2c4d21fa2d20fbf"
)


def test_environment_example_uses_modern_supabase_keys() -> None:
    environment_example = (REPOSITORY_ROOT / ".env.example").read_text(encoding="utf-8")

    assert "MBM_SUPABASE_PUBLISHABLE_KEY=replace-me" in environment_example
    assert "MBM_SUPABASE_SECRET_KEY=replace-me" in environment_example
    assert "MBM_SUPABASE_SERVICE_ROLE_KEY" not in environment_example


def test_refresh_workflow_uses_modern_supabase_secret() -> None:
    refresh_workflow = (
        REPOSITORY_ROOT / ".github" / "workflows" / "refresh.yml"
    ).read_text(encoding="utf-8")

    expected = "MBM_SUPABASE_SECRET_KEY: ${{ secrets.MBM_SUPABASE_SECRET_KEY }}"
    assert expected in refresh_workflow
    assert "MBM_SUPABASE_SERVICE_ROLE_KEY" not in refresh_workflow


def test_migration_validation_is_local_only_and_secret_free() -> None:
    workflow = yaml.safe_load(
        (REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    )
    job = workflow["jobs"]["migration-validation"]

    assert workflow["permissions"] == {"contents": "read"}
    assert job["runs-on"] == "ubuntu-latest"
    assert "environment" not in job
    assert "env" not in job

    serialized_job = repr(job).lower()
    forbidden_remote_contracts = (
        "secrets.",
        "supabase_access_token",
        "supabase_db_password",
        "supabase_project_id",
        "mbm_database_url",
        "supabase link",
        "supabase db push",
        "--linked",
        "--db-url",
    )
    for forbidden_contract in forbidden_remote_contracts:
        assert forbidden_contract not in serialized_job


def test_migration_validation_pins_cli_and_fails_fast() -> None:
    workflow = yaml.safe_load(
        (REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    )
    steps = workflow["jobs"]["migration-validation"]["steps"]
    named_steps = {step["name"]: step for step in steps if "name" in step}

    setup_step = named_steps["Install Supabase CLI"]
    assert setup_step["uses"] == SUPABASE_SETUP_ACTION
    assert setup_step["with"]["version"] == SUPABASE_CLI_VERSION
    assert setup_step["with"]["version"] != "latest"

    assert named_steps["Start local database"]["run"] == "supabase db start"
    reset_step = named_steps["Rebuild database from migrations"]
    assert reset_step["run"] == "supabase db reset --local --no-seed"
    assert reset_step.get("continue-on-error") is not True
    assert named_steps["Lint migrated database"]["run"] == (
        "supabase db lint --local --level error --fail-on error"
    )

    smoke_step = named_steps["Smoke-test migrated schema"]
    assert smoke_step["run"].endswith("--file=supabase/tests/migration_smoke.sql")
    assert "--host=127.0.0.1" in smoke_step["run"]

    cleanup_step = named_steps["Stop local database"]
    assert cleanup_step["if"] == "${{ always() }}"
    assert cleanup_step["run"] == (
        "supabase stop --no-backup --project-id mexican-banking-monitor"
    )


def test_migration_smoke_is_present_and_read_only() -> None:
    smoke_sql = (
        REPOSITORY_ROOT / "supabase" / "tests" / "migration_smoke.sql"
    ).read_text(encoding="utf-8")

    required_catalog_contracts = (
        "core",
        "institutions",
        "current_financial_facts",
        "ops",
        "pipeline_runs",
        "analytics",
        "metric_definitions",
        "public",
        "bank_metrics",
        "relrowsecurity",
        "Public metrics are readable",
    )
    for required_contract in required_catalog_contracts:
        assert required_contract in smoke_sql

    write_statement = re.compile(
        r"^\s*(?:insert|update|delete|create|alter|drop|truncate|grant|revoke)\b",
        flags=re.IGNORECASE | re.MULTILINE,
    )
    assert write_statement.search(smoke_sql) is None
