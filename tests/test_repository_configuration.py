import re
import shlex
import tomllib
from pathlib import Path

import yaml

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SUPABASE_CLI_VERSION = "2.115.0"
SUPABASE_SETUP_ACTION = (
    "supabase/setup-cli@3c2f5e2ae34c34e428e8e206e2c4d21fa2d20fbf"
)
CHECKOUT_ACTION = "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"


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


def test_refresh_workflow_is_manual_preflight_only() -> None:
    workflow_path = REPOSITORY_ROOT / ".github" / "workflows" / "refresh.yml"
    assert workflow_path.is_file()

    workflow_text = workflow_path.read_text(encoding="utf-8")
    workflow = yaml.safe_load(workflow_text)
    trigger = workflow.get("on", workflow.get(True))

    assert set(trigger) == {"workflow_dispatch"}
    assert "schedule" not in trigger
    assert "cron" not in workflow_text.lower()
    assert workflow["permissions"] == {"contents": "read"}

    refresh_job = workflow["jobs"]["refresh"]
    assert refresh_job["environment"] == "production"
    steps = refresh_job["steps"]
    assert steps[0]["uses"] == (
        "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd"
    )
    assert steps[1]["uses"] == (
        "astral-sh/setup-uv@c771a70e6277c0a99b617c7a806ffedaca235ff9"
    )
    assert steps[1]["with"]["version"] == "0.12.6"

    commands = [step["run"] for step in steps if "run" in step]
    assert commands == ["uv sync --locked", "uv run mbm doctor --database"]
    assert all(
        re.search(r"(?:^|\s)mbm\s+refresh(?:\s|$)", command) is None
        for command in commands
    )


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


def test_migration_smoke_is_present_and_transaction_safe() -> None:
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
        "evidence",
        "registry",
        "reported",
        "semantic",
        "metrics",
        "audit",
        "serving",
        "measurement_units",
        "reporting_scopes",
        "reporting_scope_versions",
        "gen_random_uuid()",
        "access_gate",
        "scope_versioning_gate",
        "scope_boundary_gate",
        "regulatory_bank_metrics_v1",
        "regulators",
        "sources",
        "source_definition_versions",
        "source_releases",
        "source_artifacts",
        "evidence_columns_gate",
        "evidence_constraints_gate",
        "evidence_relationship_gate",
        "evidence_access_state_gate",
        "legacy_table_gate",
    )
    for required_contract in required_catalog_contracts:
        assert required_contract in smoke_sql

    begin_statements = tuple(
        re.finditer(r"^\s*begin;\s*$", smoke_sql, flags=re.IGNORECASE | re.MULTILINE)
    )
    rollback_statements = tuple(
        re.finditer(r"^\s*rollback;\s*$", smoke_sql, flags=re.IGNORECASE | re.MULTILINE)
    )
    assert len(begin_statements) == 1
    assert len(rollback_statements) == 1

    forbidden_statement = re.compile(
        r"^\s*(?:create|alter|drop|truncate|grant|revoke|update|delete|commit)\b",
        flags=re.IGNORECASE | re.MULTILINE,
    )
    assert forbidden_statement.search(smoke_sql) is None

    insert_statements = tuple(
        re.finditer(r"^\s*insert\b", smoke_sql, flags=re.IGNORECASE | re.MULTILINE)
    )
    assert insert_statements
    assert begin_statements[0].start() < insert_statements[0].start()
    assert insert_statements[-1].end() < rollback_statements[0].start()


def test_production_migration_deploy_has_manual_main_only_serialized_contract() -> None:
    workflow = yaml.safe_load(
        (REPOSITORY_ROOT / ".github" / "workflows" / "deploy-database.yml").read_text(
            encoding="utf-8"
        )
    )
    trigger = workflow.get("on", workflow.get(True))

    assert trigger == {"workflow_dispatch": None}
    assert workflow["permissions"] == {"contents": "read"}
    assert workflow["concurrency"] == {
        "group": "production-database-migrations",
        "cancel-in-progress": False,
    }

    guard = workflow["jobs"]["main-guard"]
    guard_command = guard["steps"][0]["run"]
    assert '"$GITHUB_REF" != "refs/heads/main"' in guard_command
    assert "exit 1" in guard_command

    deploy = workflow["jobs"]["migrate"]
    assert deploy["needs"] == "main-guard"
    assert deploy["environment"] == "production"
    assert deploy["env"]["SUPABASE_ACCESS_TOKEN"] == (
        "${{ secrets.SUPABASE_ACCESS_TOKEN }}"
    )
    assert deploy["env"]["SUPABASE_DB_PASSWORD"] == (
        "${{ secrets.SUPABASE_DB_PASSWORD }}"
    )
    assert deploy["env"]["SUPABASE_PROJECT_ID"] == (
        "${{ secrets.SUPABASE_PROJECT_ID }}"
    )


def test_production_migration_deploy_pins_tools_and_orders_all_gates() -> None:
    workflow = yaml.safe_load(
        (REPOSITORY_ROOT / ".github" / "workflows" / "deploy-database.yml").read_text(
            encoding="utf-8"
        )
    )
    steps = workflow["jobs"]["migrate"]["steps"]
    named_steps = {step["name"]: step for step in steps if "name" in step}
    step_names = [step.get("name", "checkout") for step in steps]

    assert named_steps["Install Supabase CLI"]["uses"] == SUPABASE_SETUP_ACTION
    assert named_steps["Install Supabase CLI"]["with"]["version"] == SUPABASE_CLI_VERSION
    assert named_steps["Install Supabase CLI"]["with"]["version"] != "latest"

    ordered_gates = [
        "Validate local migration repository",
        "Link production project",
        "Inspect remote migration history",
        "Gate migration history drift",
        "Reject destructive pending migrations",
        "Preview pending migrations",
        "Verify dry-run plan",
        "Push pending migrations",
        "Inspect migration history after push",
        "Verify migration history after push",
        "Verify post-push dry-run is a no-op",
    ]
    assert [step_names.index(name) for name in ordered_gates] == sorted(
        step_names.index(name) for name in ordered_gates
    )

    assert named_steps["Link production project"]["run"] == (
        'supabase link --project-ref "$SUPABASE_PROJECT_ID"'
    )
    structured_steps = {
        "Inspect remote migration history": (
            "supabase migration list --linked --output-format json",
            "migration-history-before.json",
        ),
        "Preview pending migrations": (
            "supabase db push --linked --dry-run --skip-vault --output-format json",
            "migration-dry-run-before.json",
        ),
        "Inspect migration history after push": (
            "supabase migration list --linked --output-format json",
            "migration-history-after.json",
        ),
        "Verify post-push dry-run is a no-op": (
            "supabase db push --linked --dry-run --skip-vault --output-format json",
            "migration-dry-run-after.json",
        ),
    }
    for step_name, (command, output_name) in structured_steps.items():
        run = named_steps[step_name]["run"]
        assert command in run
        assert f'> "$RUNNER_TEMP/{output_name}"' in run
        assert "2>&1" not in run
        assert "tee " not in run

    assert "migration-history-before.json" in named_steps[
        "Gate migration history drift"
    ]["run"]
    assert "migration-dry-run-before.json" in named_steps["Verify dry-run plan"]["run"]
    push = named_steps["Push pending migrations"]
    assert push["if"] == "steps.history.outputs.has_pending == 'true'"
    assert push["run"] == "supabase db push --linked --skip-vault --yes"
    assert "--require-aligned" in named_steps["Verify migration history after push"]["run"]
    assert "migration-history-after.json" in named_steps[
        "Verify migration history after push"
    ]["run"]


def test_production_migration_db_push_commands_are_vault_free() -> None:
    workflow = yaml.safe_load(
        (REPOSITORY_ROOT / ".github" / "workflows" / "deploy-database.yml").read_text(
            encoding="utf-8"
        )
    )
    steps = workflow["jobs"]["migrate"]["steps"]
    commands = []

    for step in steps:
        for line in step.get("run", "").splitlines():
            command = line.strip().removesuffix("\\").rstrip()
            if command.startswith("supabase db push "):
                commands.append((step.get("name"), shlex.split(command)))

    expected_arguments = [
        (
            "Preview pending migrations",
            ["--linked", "--dry-run", "--skip-vault", "--output-format", "json"],
        ),
        (
            "Push pending migrations",
            ["--linked", "--skip-vault", "--yes"],
        ),
        (
            "Verify post-push dry-run is a no-op",
            ["--linked", "--dry-run", "--skip-vault", "--output-format", "json"],
        ),
    ]

    assert all(tokens[:3] == ["supabase", "db", "push"] for _, tokens in commands)
    actual_arguments = [(name, tokens[3:]) for name, tokens in commands]
    assert actual_arguments == expected_arguments
    arguments = [tokens for _, tokens in actual_arguments]
    assert all("--skip-vault" in tokens for tokens in arguments)
    assert sum("--dry-run" in tokens for tokens in arguments) == 2
    assert "--yes" in arguments[1]

    forbidden = ("--include-all", "--include-seed", "--include-roles", "repair", "reset")
    assert all(
        forbidden_token not in token.lower()
        for tokens in arguments
        for token in tokens
        for forbidden_token in forbidden
    )


def test_production_migration_deploy_never_bypasses_or_repairs_history() -> None:
    workflow = yaml.safe_load(
        (REPOSITORY_ROOT / ".github" / "workflows" / "deploy-database.yml").read_text(
            encoding="utf-8"
        )
    )
    serialized = repr(workflow).lower()

    for forbidden_contract in (
        "--include-all",
        "migration repair",
        "db reset --linked",
        "schema_migrations",
        "continue-on-error",
        "set -x",
        "printenv",
    ):
        assert forbidden_contract not in serialized


def test_artifact_storage_bucket_is_private_and_unrestricted() -> None:
    config = tomllib.loads(
        (REPOSITORY_ROOT / "supabase" / "config.toml").read_text(encoding="utf-8")
    )

    bucket = config["storage"]["buckets"]["regulatory-artifacts"]
    assert bucket == {"public": False}
    for premature_restriction in (
        "file_size_limit",
        "allowed_mime_types",
        "objects_path",
    ):
        assert premature_restriction not in bucket


def test_artifact_storage_provisioning_is_manual_main_only_and_serialized() -> None:
    storage_workflow = yaml.safe_load(
        (
            REPOSITORY_ROOT
            / ".github"
            / "workflows"
            / "provision-artifact-storage.yml"
        ).read_text(encoding="utf-8")
    )
    database_workflow = yaml.safe_load(
        (REPOSITORY_ROOT / ".github" / "workflows" / "deploy-database.yml").read_text(
            encoding="utf-8"
        )
    )
    trigger = storage_workflow.get("on", storage_workflow.get(True))

    assert trigger == {"workflow_dispatch": None}
    assert storage_workflow["permissions"] == {"contents": "read"}
    assert storage_workflow["concurrency"] == database_workflow["concurrency"] == {
        "group": "production-database-migrations",
        "cancel-in-progress": False,
    }

    guard = storage_workflow["jobs"]["main-guard"]
    guard_command = guard["steps"][0]["run"]
    assert '"$GITHUB_REF" != "refs/heads/main"' in guard_command
    assert "exit 1" in guard_command

    provision = storage_workflow["jobs"]["provision"]
    assert provision["needs"] == "main-guard"
    assert provision["environment"] == "production"
    assert provision["env"] == {
        "NO_COLOR": "1",
        "SUPABASE_ACCESS_TOKEN": "${{ secrets.SUPABASE_ACCESS_TOKEN }}",
        "SUPABASE_PROJECT_ID": "${{ secrets.SUPABASE_PROJECT_ID }}",
    }


def test_artifact_storage_provisioning_pins_tools_and_has_narrow_commands() -> None:
    workflow_path = (
        REPOSITORY_ROOT
        / ".github"
        / "workflows"
        / "provision-artifact-storage.yml"
    )
    workflow_text = workflow_path.read_text(encoding="utf-8")
    workflow = yaml.safe_load(workflow_text)
    steps = workflow["jobs"]["provision"]["steps"]
    named_steps = {step["name"]: step for step in steps if "name" in step}

    assert steps[0]["uses"] == CHECKOUT_ACTION
    assert steps[0]["with"] == {"persist-credentials": False}
    assert named_steps["Install Supabase CLI"]["uses"] == SUPABASE_SETUP_ACTION
    assert named_steps["Install Supabase CLI"]["with"] == {
        "version": SUPABASE_CLI_VERSION
    }
    assert named_steps["Link production project"]["run"] == (
        'supabase link --project-ref "$SUPABASE_PROJECT_ID"'
    )
    assert named_steps["Synchronize declared Storage buckets"]["run"] == (
        "supabase seed buckets --linked"
    )
    assert named_steps["Verify artifact bucket is reachable"]["run"] == (
        "supabase storage ls ss:///regulatory-artifacts --linked --experimental"
    )

    serialized = workflow_text.lower()
    for forbidden_contract in (
        "supabase storage cp",
        "supabase storage rm",
        "supabase db push",
        "migration repair",
        "db reset",
        "mbm_supabase_secret_key",
        "printenv",
        "set -x",
    ):
        assert forbidden_contract not in serialized


def test_database_deployment_does_not_provision_storage() -> None:
    database_workflow = (
        REPOSITORY_ROOT / ".github" / "workflows" / "deploy-database.yml"
    ).read_text(encoding="utf-8")

    assert "supabase seed buckets" not in database_workflow
    assert "supabase storage" not in database_workflow
