"""FastAPI 後端：把 ai_service / audio_service / database 包成 HTTP API，
並（若已建置）一併提供 Flutter Web 靜態檔。

啟動：uvicorn api:app --host 0.0.0.0 --port 8000
設定：
  AZURE_OPENAI_*      同 ai_service.py
  Google 登入         `.streamlit/secrets.toml` 的 [auth]（見 auth_config.py）；未設定時為本機單人模式
  APP_PASSWORD        選填，設定後所有 API 都要另外帶密碼
"""
import hmac
import html
import os
from pathlib import Path

from authlib.integrations.starlette_client import OAuth, OAuthError
from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from starlette.middleware.sessions import SessionMiddleware

import ai_service
import audio_service
import auth_config
import database

WEB_DIR = Path(__file__).parent / "mobile" / "build" / "web"
AVATAR_DIR = Path(__file__).parent / "avatar"
MAX_TTS_CHARS = 1000
LOCAL_HOSTS = {"localhost", "127.0.0.1"}

AUTH = auth_config.load()

app = FastAPI(title="Say It Better API")
app.add_middleware(
    SessionMiddleware,
    secret_key=AUTH.cookie_secret,
    session_cookie="comm_session",
    max_age=14 * 24 * 3600,
    same_site="lax",
    # 雲端（HTTPS）部署時設環境變數 COOKIE_SECURE=1，cookie 只走加密連線；本機 http://localhost 維持關閉
    https_only=os.getenv("COOKIE_SECURE") == "1",
)
database.init_db()

oauth = OAuth()
if AUTH.enabled:
    oauth.register(
        "google",
        client_id=AUTH.client_id,
        client_secret=AUTH.client_secret,
        server_metadata_url=auth_config.GOOGLE_METADATA_URL,
        client_kwargs={"scope": "openid email profile"},
    )


# ---------------------------------------------------------------- 錯誤與驗證
@app.exception_handler(ai_service.AIServiceError)
@app.exception_handler(audio_service.AudioServiceError)
async def _service_error(_: Request, exc: Exception):
    return JSONResponse(status_code=502, content={"detail": str(exc)})


def _password_ok(given: str | None) -> bool:
    expected = os.getenv("APP_PASSWORD")
    return not expected or hmac.compare_digest((given or "").encode(), expected.encode())


def require_password(x_app_password: str | None = Header(default=None)) -> None:
    if not _password_ok(x_app_password):
        raise HTTPException(status_code=401, detail="密碼錯誤或尚未輸入密碼。")


LOCAL_USER = {"sub": auth_config.LOCAL_USER_ID, "email": "", "name": "本機使用者", "picture": ""}


def current_user(request: Request) -> dict:
    """目前登入的使用者；未啟用 Google 登入時一律是本機使用者。"""
    if not AUTH.enabled:
        return LOCAL_USER
    user = request.session.get("user")
    if not user or not user.get("sub"):
        # 用標頭與密碼錯誤（同為 401）區分，前端據此顯示登入畫面
        raise HTTPException(status_code=401, detail="請先登入。", headers={"X-Login-Required": "1"})
    return user


api = APIRouter(prefix="/api", dependencies=[Depends(require_password)])
# 需要登入的端點
user_api = APIRouter(prefix="/api", dependencies=[Depends(require_password), Depends(current_user)])


# ---------------------------------------------------------------- 請求模型
class ScriptsReq(BaseModel):
    scenario: str = Field(min_length=1)
    thoughts: str = Field(min_length=1)
    channel: str = ai_service.CHANNELS[0]


class SimStartReq(BaseModel):
    scenario: str = Field(min_length=1)
    thoughts: str = ""
    persona: str = ai_service.PERSONAS[-1]
    gender: str = Field(default="", pattern="^(|female|male)$")  # 對方性別，空字串＝不指定


class ChatMsg(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    content: str


class SimTurnReq(SimStartReq):
    history: list[ChatMsg] = []
    reply: str = Field(min_length=1)


class TemplateIn(BaseModel):
    scenario: str = Field(min_length=1)
    style: str = ""
    content: str = Field(min_length=1)
    note: str = ""
    channel: str = ""


class ImportReq(BaseModel):
    templates: list[dict]


# ---------------------------------------------------------------- Google 登入
auth_router = APIRouter(prefix="/api/auth")


def _message_page(title: str, body: str, status: int = 400) -> HTMLResponse:
    return HTMLResponse(
        f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title>
<body style="font-family:system-ui,'Noto Sans TC',sans-serif;max-width:560px;margin:48px auto;padding:0 16px;line-height:1.7">
<h2>{html.escape(title)}</h2><p>{body}</p><p><a href="/">回到首頁</a></p></body>""",
        status_code=status,
    )


@auth_router.get("/me")
def auth_me(request: Request):
    """前端啟動時呼叫：是否啟用登入、目前是誰（未登入時 user 為 null）。"""
    if not AUTH.enabled:
        return {"enabled": False, "user": LOCAL_USER}
    user = request.session.get("user")
    return {"enabled": True, "user": user or None}


@auth_router.get("/login")
async def auth_login(request: Request):
    if not AUTH.enabled:
        return RedirectResponse("/")
    host = request.url.hostname or ""
    if request.url.scheme == "http" and host not in LOCAL_HOSTS:
        return _message_page(
            "這個網址無法使用 Google 登入",
            "Google 只允許在 <b>localhost</b> 或 <b>HTTPS</b> 網址登入。"
            "請在電腦上改用 <b>http://localhost:8000</b> 開啟；手機要登入需要先部署成 HTTPS 網址。",
        )
    if host == "127.0.0.1":
        # Google 後台登記的是 localhost，且 cookie 依網域區分，統一用 localhost
        return RedirectResponse(str(request.url.replace(hostname="localhost")))
    redirect_uri = str(request.url_for("auth_callback"))
    return await oauth.google.authorize_redirect(request, redirect_uri, prompt="select_account")


@auth_router.get("/callback", name="auth_callback")
async def auth_callback(request: Request):
    if not AUTH.enabled:
        return RedirectResponse("/")
    try:
        token = await oauth.google.authorize_access_token(request)
    except OAuthError as e:
        return _message_page("登入沒有完成", f"Google 回傳：{html.escape(e.description or e.error or '未知錯誤')}。請回首頁再試一次。")
    info = token.get("userinfo") or {}
    if not info.get("sub") or not info.get("email_verified", False):
        return _message_page("登入沒有完成", "無法確認這個 Google 帳號的 Email，請改用其他帳號。")
    request.session["user"] = {
        "sub": info["sub"],
        "email": info.get("email", ""),
        "name": info.get("name", ""),
        "picture": info.get("picture", ""),
    }
    return RedirectResponse("/")


@auth_router.post("/logout", status_code=204)
def auth_logout(request: Request):
    request.session.clear()
    return Response(status_code=204)


# ---------------------------------------------------------------- 一般與 AI
@api.get("/meta")
def meta():
    """不需登入；同時用來檢查密碼是否正確。"""
    return {
        "scenarios": ai_service.SCENARIOS,
        "channels": ai_service.CHANNELS,
        "personas": ai_service.PERSONAS,
        "voices": list(audio_service.VOICES),
        "azure_speech": audio_service.azure_status(),   # 診斷用：男聲需要 Azure 語音
    }


@user_api.post("/scripts")
def scripts(req: ScriptsReq):
    return ai_service.generate_scripts(req.scenario.strip(), req.thoughts.strip(), req.channel)


@user_api.post("/sim/start")
def sim_start(req: SimStartReq):
    r = ai_service.start_simulation_with_emotion(
        req.scenario.strip(), req.thoughts.strip(), req.persona, req.gender
    )
    return {"line": r["next_line"], "emotion": r["emotion"]}


@user_api.post("/sim/reply")
def sim_reply(req: SimTurnReq):
    """只回對方的下一句與情緒（語音通話用，速度較快）。"""
    history = [m.model_dump() for m in req.history]
    return ai_service.simulation_reply(
        req.scenario.strip(), req.thoughts.strip(), req.persona, history, req.reply.strip(),
        req.gender,
    )


@user_api.post("/sim/coach")
def sim_coach(req: SimTurnReq):
    """只回對使用者最後一句話的點評，可與 /sim/reply 平行呼叫。"""
    history = [m.model_dump() for m in req.history]
    return ai_service.simulation_coach(
        req.scenario.strip(), req.thoughts.strip(), req.persona, history, req.reply.strip(),
        req.gender,
    )


@user_api.post("/sim/turn")
def sim_turn(req: SimTurnReq):
    history = [m.model_dump() for m in req.history]
    return ai_service.simulation_turn(
        req.scenario.strip(), req.thoughts.strip(), req.persona, history, req.reply.strip(),
        req.gender,
    )


# ---------------------------------------------------------------- 範本庫（只會讀寫目前使用者自己的資料）
@user_api.get("/templates")
def templates_list(scenario: str | None = None, user: dict = Depends(current_user)):
    return database.list_templates(user["sub"], scenario or None)


@user_api.get("/templates/scenarios")
def templates_scenarios(user: dict = Depends(current_user)):
    return database.list_scenarios(user["sub"])


@user_api.get("/templates/export")
def templates_export(user: dict = Depends(current_user)):
    return database.export_templates(user["sub"])


@user_api.post("/templates/import")
def templates_import(req: ImportReq, user: dict = Depends(current_user)):
    return {"added": database.import_templates(user["sub"], req.templates)}


@user_api.post("/templates", status_code=201)
def templates_create(t: TemplateIn, user: dict = Depends(current_user)):
    new_id = database.add_template(
        user["sub"], t.scenario.strip(), t.style.strip(), t.content.strip(), t.note, t.channel
    )
    return database.get_template(user["sub"], new_id)


@user_api.put("/templates/{template_id}")
def templates_update(template_id: int, t: TemplateIn, user: dict = Depends(current_user)):
    ok = database.update_template(
        user["sub"], template_id, t.scenario.strip(), t.style.strip(), t.content.strip(),
        t.note.strip(), t.channel.strip(),
    )
    if not ok:
        raise HTTPException(status_code=404, detail="找不到這筆範本。")
    return database.get_template(user["sub"], template_id)


@user_api.delete("/templates/{template_id}", status_code=204)
def templates_delete(template_id: int, user: dict = Depends(current_user)):
    if not database.delete_template(user["sub"], template_id):
        raise HTTPException(status_code=404, detail="找不到這筆範本。")
    return Response(status_code=204)


app.include_router(auth_router)
app.include_router(api)
app.include_router(user_api)


# ---------------------------------------------------------------- 語音（播放器直接用網址，無法帶標頭，密碼改用 token；登入靠 cookie）
@app.get("/api/tts")
def tts(
    text: str = Query(min_length=1, max_length=MAX_TTS_CHARS),
    voice: str = Query(default=next(iter(audio_service.VOICES))),
    token: str | None = None,
    _user: dict = Depends(current_user),
):
    if not _password_ok(token):
        raise HTTPException(status_code=401, detail="密碼錯誤或尚未輸入密碼。")
    if voice not in audio_service.VOICES:
        raise HTTPException(status_code=400, detail="未知的聲音選項。")
    audio = audio_service.text_to_speech(text, audio_service.VOICES[voice])
    return Response(content=audio, media_type="audio/mpeg", headers={"Cache-Control": "private, max-age=3600"})


# ---------------------------------------------------------------- 3D 虛擬人物網頁層（需在 "/" 之前掛載）
if AVATAR_DIR.is_dir():
    app.mount("/avatar", StaticFiles(directory=AVATAR_DIR, html=True), name="avatar")


# ---------------------------------------------------------------- Flutter Web 靜態檔（需放在最後）
if WEB_DIR.is_dir():
    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
