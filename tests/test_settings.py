from mx_bank_monitor.settings import Settings

SECRET_MARKER = "THIS_PASSWORD_MUST_NEVER_APPEAR"


def test_supabase_keys_use_modern_environment_names(monkeypatch) -> None:
    monkeypatch.setenv("MBM_SUPABASE_PUBLISHABLE_KEY", "example-publishable-key")
    monkeypatch.setenv("MBM_SUPABASE_SECRET_KEY", "example-secret-key")

    settings = Settings(_env_file=None)

    assert settings.supabase_publishable_key == "example-publishable-key"
    assert settings.supabase_secret_key == "example-secret-key"


def test_supabase_secret_key_is_redacted_from_repr() -> None:
    settings = Settings(_env_file=None, supabase_secret_key=SECRET_MARKER)

    assert SECRET_MARKER not in repr(settings)


def test_database_url_is_redacted_from_repr() -> None:
    database_url = f"postgresql://monitor:{SECRET_MARKER}@db.invalid:6543/postgres"
    settings = Settings(_env_file=None, database_url=database_url)

    assert SECRET_MARKER not in repr(settings)
    assert database_url not in repr(settings)


def test_database_configuration_requires_a_nonempty_url() -> None:
    assert Settings(_env_file=None).database_configured is False
    assert Settings(_env_file=None, database_url="").database_configured is False
