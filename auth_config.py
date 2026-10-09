"""Google 登入設定：Streamlit 與 FastAPI 共用同一份 `.streamlit/secrets.toml`。

環境變數 GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / AUTH_COOKIE_SECRET 若有設定則優先使用。
兩者都沒有設定時，視為「未啟用登入」，系統以本機單人模式運作（user_id = "local"）。
"""
import os
import secrets
import tomllib
from dataclasses import dataclass
from pathlib import Path

SECRETS_PATH = Path(__file__).parent / ".streamlit" / "secrets.toml"
LOCAL_USER_ID = "local"
GOOGLE_METADATA_URL = "https://accounts.google.com/.well-known/openid-configuration"


@dataclass(frozen=True)
class AuthConfig:
    client_id: str
    client_secret: str
    cookie_secret: str

    @property
    def enabled(self) -> bool:
        return bool(self.client_id and self.client_secret)


def _read_secrets() -> dict:
    try:
        with open(SECRETS_PATH, "rb") as f:
            return tomllib.load(f)
    except FileNotFoundError:
        return {}


def load() -> AuthConfig:
    auth = _read_secrets().get("auth", {})
    google = auth.get("google", {})
    return AuthConfig(
        client_id=os.getenv("GOOGLE_CLIENT_ID") or google.get("client_id", ""),
        client_secret=os.getenv("GOOGLE_CLIENT_SECRET") or google.get("client_secret", ""),
        # 沒有設定時臨時產生：功能正常，但後端重啟後大家都要重新登入
        cookie_secret=os.getenv("AUTH_COOKIE_SECRET") or auth.get("cookie_secret") or secrets.token_urlsafe(32),
    )
