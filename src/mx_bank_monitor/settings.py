from __future__ import annotations

from functools import lru_cache

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="MBM_",
        extra="ignore",
    )

    env: str = "development"
    log_level: str = "INFO"
    database_url: SecretStr | None = None
    supabase_url: str | None = None
    supabase_publishable_key: str | None = None
    supabase_secret_key: str | None = Field(default=None, repr=False)

    @property
    def database_configured(self) -> bool:
        return bool(self.database_url and self.database_url.get_secret_value())


@lru_cache
def get_settings() -> Settings:
    return Settings()
