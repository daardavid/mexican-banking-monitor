from mx_bank_monitor.settings import Settings


def test_supabase_keys_use_modern_environment_names(monkeypatch) -> None:
    monkeypatch.setenv("MBM_SUPABASE_PUBLISHABLE_KEY", "example-publishable-key")
    monkeypatch.setenv("MBM_SUPABASE_SECRET_KEY", "example-secret-key")

    settings = Settings(_env_file=None)

    assert settings.supabase_publishable_key == "example-publishable-key"
    assert settings.supabase_secret_key == "example-secret-key"


def test_supabase_secret_key_is_redacted_from_repr() -> None:
    settings = Settings(_env_file=None, supabase_secret_key="example-secret-key")

    assert "example-secret-key" not in repr(settings)
