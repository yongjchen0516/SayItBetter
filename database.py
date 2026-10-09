"""資料庫：話術範本庫 CRUD。

- 預設使用 SQLite（本機的 templates.db）。
- 設定了 PostgreSQL 連線字串時改用 PostgreSQL（雲端部署用，例如 Neon）：
  環境變數 DATABASE_URL，或 `.streamlit/secrets.toml` 的 [database] url。

每筆範本都屬於一位使用者（user_id = Google 帳號的 sub，未啟用登入時為 "local"），
所有查詢、修改、刪除都只作用在該使用者自己的資料上。
"""
import os
import sqlite3
import tomllib
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

DB_PATH = Path(__file__).with_name("templates.db")
_SECRETS = Path(__file__).parent / ".streamlit" / "secrets.toml"
_TAIPEI = timezone(timedelta(hours=8))   # 雲端主機時區是 UTC，建立時間一律記台灣時間


def _database_url() -> str:
    url = os.getenv("DATABASE_URL", "")
    if not url:
        try:
            with open(_SECRETS, "rb") as f:
                url = tomllib.load(f).get("database", {}).get("url", "")
        except (FileNotFoundError, tomllib.TOMLDecodeError):
            url = ""
    return url.strip()


DATABASE_URL = _database_url()
USE_POSTGRES = DATABASE_URL.startswith(("postgres://", "postgresql://"))


def backend_name() -> str:
    return "PostgreSQL" if USE_POSTGRES else "SQLite"


@contextmanager
def _conn():
    if USE_POSTGRES:
        import psycopg
        from psycopg.rows import dict_row

        conn = psycopg.connect(DATABASE_URL, row_factory=dict_row, connect_timeout=15)
    else:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _sql(query: str) -> str:
    """SQL 一律用 ? 當參數佔位符，PostgreSQL 時換成 %s。"""
    return query.replace("?", "%s") if USE_POSTGRES else query


def _exec(c, query: str, params: tuple = ()):
    return c.execute(_sql(query), params)


def init_db() -> None:
    with _conn() as c:
        if USE_POSTGRES:
            c.execute(
                """
                CREATE TABLE IF NOT EXISTS templates (
                    id BIGSERIAL PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    scenario TEXT NOT NULL,
                    style TEXT NOT NULL,
                    content TEXT NOT NULL,
                    note TEXT DEFAULT '',
                    channel TEXT DEFAULT '',
                    created_at TEXT NOT NULL
                )
                """
            )
        else:
            c.execute(
                """
                CREATE TABLE IF NOT EXISTS templates (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    scenario TEXT NOT NULL,
                    style TEXT NOT NULL,
                    content TEXT NOT NULL,
                    note TEXT DEFAULT '',
                    created_at TEXT NOT NULL
                )
                """
            )
            # 舊版資料庫缺少的欄位自動補上
            cols = [r["name"] for r in c.execute("PRAGMA table_info(templates)")]
            if "channel" not in cols:
                c.execute("ALTER TABLE templates ADD COLUMN channel TEXT DEFAULT ''")
            if "user_id" not in cols:
                # 加入登入功能前的舊資料 user_id 為空字串，不屬於任何人，登入後看不到
                c.execute("ALTER TABLE templates ADD COLUMN user_id TEXT NOT NULL DEFAULT ''")
        c.execute("CREATE INDEX IF NOT EXISTS idx_templates_user ON templates(user_id, id)")


def _require_user(user_id: str) -> None:
    if not user_id:
        raise ValueError("user_id 不可為空")


def add_template(
    user_id: str, scenario: str, style: str, content: str, note: str = "", channel: str = ""
) -> int:
    _require_user(user_id)
    params = (user_id, scenario, style, content, note, channel,
              datetime.now(_TAIPEI).strftime("%Y-%m-%d %H:%M"))
    insert = ("INSERT INTO templates (user_id, scenario, style, content, note, channel, created_at)"
              " VALUES (?,?,?,?,?,?,?)")
    with _conn() as c:
        if USE_POSTGRES:
            return _exec(c, insert + " RETURNING id", params).fetchone()["id"]
        return _exec(c, insert, params).lastrowid


def list_templates(user_id: str, scenario: str | None = None) -> list[dict]:
    _require_user(user_id)
    with _conn() as c:
        if scenario:
            rows = _exec(
                c, "SELECT * FROM templates WHERE user_id = ? AND scenario = ? ORDER BY id DESC",
                (user_id, scenario),
            ).fetchall()
        else:
            rows = _exec(
                c, "SELECT * FROM templates WHERE user_id = ? ORDER BY id DESC", (user_id,)
            ).fetchall()
    return [dict(r) for r in rows]


def get_template(user_id: str, template_id: int) -> dict | None:
    _require_user(user_id)
    with _conn() as c:
        row = _exec(
            c, "SELECT * FROM templates WHERE id = ? AND user_id = ?", (template_id, user_id)
        ).fetchone()
    return dict(row) if row else None


def export_templates(user_id: str) -> list[dict]:
    """匯出該使用者的全部範本（不含 id 與 user_id），供備份用。"""
    return [
        {k: r[k] for k in ("scenario", "style", "content", "note", "channel", "created_at")}
        for r in reversed(list_templates(user_id))
    ]


def import_templates(user_id: str, rows: list[dict]) -> int:
    """匯入範本到該使用者，略過與自己現有範本 scenario+style+content 完全相同者，回傳實際新增筆數。"""
    existing = {(r["scenario"], r["style"], r["content"]) for r in list_templates(user_id)}
    added = 0
    for r in rows:
        scenario = str(r.get("scenario", "")).strip()
        style = str(r.get("style", "")).strip()
        content = str(r.get("content", "")).strip()
        if not scenario or not content or (scenario, style, content) in existing:
            continue
        add_template(user_id, scenario, style, content,
                     str(r.get("note", "")), str(r.get("channel", "")))
        existing.add((scenario, style, content))
        added += 1
    return added


def list_scenarios(user_id: str) -> list[str]:
    _require_user(user_id)
    with _conn() as c:
        rows = _exec(
            c, "SELECT DISTINCT scenario FROM templates WHERE user_id = ? ORDER BY scenario",
            (user_id,),
        ).fetchall()
    return [r["scenario"] for r in rows]


def update_template(
    user_id: str, template_id: int, scenario: str, style: str, content: str, note: str,
    channel: str = "",
) -> bool:
    """回傳是否有更新到（不是自己的範本時為 False）。"""
    _require_user(user_id)
    with _conn() as c:
        cur = _exec(
            c,
            "UPDATE templates SET scenario=?, style=?, content=?, note=?, channel=?"
            " WHERE id=? AND user_id=?",
            (scenario, style, content, note, channel, template_id, user_id),
        )
        return cur.rowcount > 0


def delete_template(user_id: str, template_id: int) -> bool:
    """回傳是否有刪除到（不是自己的範本時為 False）。"""
    _require_user(user_id)
    with _conn() as c:
        cur = _exec(
            c, "DELETE FROM templates WHERE id = ? AND user_id = ?", (template_id, user_id)
        )
        return cur.rowcount > 0
