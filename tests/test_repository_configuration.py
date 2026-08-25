from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


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
