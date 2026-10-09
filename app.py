"""生活人際溝通輔助系統 — Streamlit 主程式。"""
import streamlit as st

import ai_service
import audio_service
import auth_config
import database

st.set_page_config(page_title="生活人際溝通輔助系統", page_icon="💬", layout="wide")
database.init_db()


def _login_enabled() -> bool:
    # Streamlit 的 st.login 只讀 .streamlit/secrets.toml 的 [auth]，所以以它為準（環境變數只對 FastAPI 有效）
    try:
        google = st.secrets["auth"]["google"]
        return bool(google.get("client_id") and google.get("client_secret"))
    except (KeyError, FileNotFoundError):
        return False


LOGIN_ENABLED = _login_enabled()


# ---------------------------------------------------------------- Google 登入
def require_user() -> str:
    """回傳目前使用者的 ID（Google 帳號的 sub）；未登入時顯示登入畫面並停止執行。
    未設定 Google 登入時為本機單人模式。"""
    if not LOGIN_ENABLED:
        return auth_config.LOCAL_USER_ID
    if not st.user.get("is_logged_in"):
        st.title("💬 生活人際溝通輔助系統")
        st.write("說出口之前，先練習一次。請先登入，你的話術範本只有你自己看得到。")
        if st.button("使用 Google 登入", type="primary"):
            st.login("google")
        st.caption("請在電腦上用 http://localhost:8501 開啟；Google 不允許在區網 IP 的 http 網址登入。")
        st.stop()
    return st.user.sub


USER_ID = require_user()

PRESET_SCENARIOS = ai_service.SCENARIOS
CUSTOM = "✏️ 自訂場景…"


# ---------------------------------------------------------------- 共用元件
def scenario_picker(key: str) -> str:
    choice = st.selectbox("溝通情境", PRESET_SCENARIOS + [CUSTOM], key=f"{key}_choice")
    if choice == CUSTOM:
        return st.text_input("請描述你的自訂場景", key=f"{key}_custom").strip()
    return choice


def run_ai(fn, *args):
    """執行 AI 呼叫並統一處理錯誤，失敗回傳 None。"""
    try:
        with st.spinner("AI 思考中…"):
            return fn(*args)
    except ai_service.AIServiceError as e:
        st.error(str(e))
        return None


@st.cache_data(show_spinner=False, max_entries=64)
def cached_tts(text: str, voice: str) -> bytes:
    return audio_service.text_to_speech(text, voice)


def play_button(text: str, key: str) -> None:
    """「🔊 播放語音」按鈕：點擊後生成語音並在按鈕下方顯示播放器。"""
    ss = st.session_state
    clicked = st.button("🔊 播放語音", key=f"tts_{key}", use_container_width=True)
    if clicked:
        voice = audio_service.VOICES[ss.get("voice_name", next(iter(audio_service.VOICES)))]
        try:
            with st.spinner("生成語音中…"):
                ss[f"audio_{key}"] = cached_tts(text, voice)
        except audio_service.AudioServiceError as e:
            st.error(str(e))
    data = ss.get(f"audio_{key}")
    if data:
        st.audio(data, format="audio/mp3", autoplay=clicked)


def clear_audio(prefix: str) -> None:
    for k in [k for k in st.session_state if k.startswith(f"audio_{prefix}")]:
        del st.session_state[k]


# ---------------------------------------------------------------- 頁面一：話術生成
def page_generate():
    st.header("💬 話術生成")
    scenario = scenario_picker("gen")
    channel = st.radio("溝通管道", ai_service.CHANNELS, horizontal=True, key="gen_channel")
    spoken = audio_service.speech_to_text("gen_stt")
    if spoken:  # 語音辨識結果附加到想法欄（必須在 text_area 建立前寫入）
        st.session_state.gen_thoughts = f"{st.session_state.get('gen_thoughts', '')} {spoken}".strip()
    st.caption("可直接打字，或按上方麥克風用語音說出內心想法（建議使用 Chrome／Edge）。")
    thoughts = st.text_area(
        "內心真實想法", height=140, key="gen_thoughts",
        placeholder="例如：同事一直約我週末聚餐，但我只想在家休息，又不想傷感情……",
    )

    if st.button("✨ 生成話術", type="primary"):
        if not scenario or not thoughts.strip():
            st.warning("請先選擇／輸入情境，並寫下你的內心想法。")
        else:
            result = run_ai(ai_service.generate_scripts, scenario, thoughts.strip(), channel)
            if result:
                clear_audio("gen_")
                st.session_state.gen_result = {"scenario": scenario, "channel": channel, **result}

    result = st.session_state.get("gen_result")
    if not result:
        return

    st.divider()
    st.subheader(f"情境：{result['scenario']}（{result['channel']}）")
    cols = st.columns(3)
    for i, (col, s) in enumerate(zip(cols, result["scripts"])):
        with col, st.container(border=True):
            st.markdown(f"#### {s['style']}")
            st.code(s["text"], language=None, wrap_lines=True)  # 右上角內建一鍵複製
            play_button(s["text"], f"gen_{i}")
            if st.button("💾 儲存至範本庫", key=f"save_{i}", use_container_width=True):
                database.add_template(
                    USER_ID, result["scenario"], s["style"], s["text"], channel=result["channel"]
                )
                st.toast("已儲存至範本庫！", icon="✅")

    left, right = st.columns(2)
    with left, st.container(border=True):
        st.markdown("#### 🔄 換位思考")
        st.write(result["perspective"])
    with right, st.container(border=True):
        st.markdown("#### 💣 溝通地雷")
        for p in result["pitfalls"]:
            st.markdown(f"- **{p['mine']}**：{p['why']}")
    st.info(f"💡 **溝通小技巧**：{result['tip']}")


# ---------------------------------------------------------------- 頁面二：對話模擬演練
def page_simulation():
    st.header("🎭 對話模擬演練")
    ss = st.session_state
    ss.setdefault("sim_active", False)
    ss.setdefault("sim_log", [])  # [{'role': 'assistant'|'user', 'content':..., 'feedback':...}]

    if not ss.sim_active:
        scenario = scenario_picker("sim")
        persona = st.selectbox("對方的性格／態度", ai_service.PERSONAS, key="sim_persona_choice")
        thoughts = st.text_area(
            "你的背景／想法（選填，讓 AI 更貼近你的處境）", height=100, key="sim_thoughts"
        )
        if st.button("▶️ 開始演練", type="primary"):
            if not scenario:
                st.warning("請先選擇或輸入場景。")
                return
            line = run_ai(ai_service.start_simulation, scenario, thoughts.strip(), persona)
            if line:
                ss.sim_active = True
                ss.sim_scenario = scenario
                ss.sim_persona = persona
                ss.sim_thoughts_used = thoughts.strip()
                ss.sim_log = [{"role": "assistant", "content": line}]
                clear_audio("sim_")
                st.rerun()
        return

    top = st.columns([4, 1])
    top[0].caption(f"演練場景：**{ss.sim_scenario}**｜對方性格：**{ss.sim_persona}**（AI 扮演對方）")
    if top[1].button("⏹️ 結束演練", use_container_width=True):
        ss.sim_active = False
        ss.sim_log = []
        clear_audio("sim_")
        st.rerun()

    for idx, msg in enumerate(ss.sim_log):
        with st.chat_message("assistant" if msg["role"] == "assistant" else "user"):
            st.write(msg["content"])
            if msg["role"] == "assistant":
                play_button(msg["content"], f"sim_{idx}")
            fb = msg.get("feedback")
            if fb:
                with st.expander("📝 教練點評", expanded=True):
                    st.markdown(f"**👍 優點**：{fb['strengths']}")
                    st.markdown(f"**🔧 可改善**：{fb['improvements']}")
                    st.markdown("**✨ 更佳參考回覆**")
                    st.code(fb["better_reply"], language=None, wrap_lines=True)
                    play_button(fb["better_reply"], f"sim_better_{idx}")

    spoken = audio_service.speech_to_text("sim_stt", "🎙️ 語音回覆")
    typed = st.chat_input("輸入你的回覆…")
    reply = typed or spoken  # 語音辨識完成後會直接當作回覆送出
    if reply:
        history = [{"role": m["role"], "content": m["content"]} for m in ss.sim_log]
        result = run_ai(
            ai_service.simulation_turn,
            ss.sim_scenario, ss.sim_thoughts_used, ss.sim_persona, history, reply,
        )
        if result:
            ss.sim_log.append({"role": "user", "content": reply, "feedback": result})
            ss.sim_log.append({"role": "assistant", "content": result["next_line"]})
            st.rerun()


# ---------------------------------------------------------------- 頁面三：範本庫
def page_library():
    st.header("📚 我的話術範本庫")
    scenarios = database.list_scenarios(USER_ID)
    selected = st.selectbox("依場景篩選", ["全部"] + scenarios)
    rows = database.list_templates(USER_ID, None if selected == "全部" else selected)

    if not rows:
        st.info("目前沒有範本。到「話術生成」頁面儲存你喜歡的話術吧！")
        return
    st.caption(f"共 {len(rows)} 筆")

    for r in rows:
        with st.container(border=True):
            meta = " ・ ".join(x for x in (r["scenario"], r["channel"], r["style"]) if x)
            st.markdown(f"**{meta}** ・ <small>{r['created_at']}</small>", unsafe_allow_html=True)
            st.code(r["content"], language=None, wrap_lines=True)
            if r["note"]:
                st.caption(f"備註：{r['note']}")

            c1, c2, _ = st.columns([1, 1, 6])
            editing = st.session_state.get("editing_id") == r["id"]
            if c1.button("✏️ 編輯", key=f"edit_{r['id']}"):
                st.session_state.editing_id = None if editing else r["id"]
                st.rerun()
            if c2.button("🗑️ 刪除", key=f"del_{r['id']}"):
                database.delete_template(USER_ID, r["id"])
                st.session_state.pop("editing_id", None)
                st.toast("已刪除", icon="🗑️")
                st.rerun()

            if editing:
                with st.form(f"form_{r['id']}"):
                    scen = st.text_input("場景", r["scenario"])
                    style = st.text_input("風格", r["style"])
                    channel = st.text_input("溝通管道", r["channel"] or "")
                    content = st.text_area("話術內容", r["content"], height=120)
                    note = st.text_input("備註", r["note"] or "")
                    if st.form_submit_button("儲存修改", type="primary"):
                        if not scen.strip() or not content.strip():
                            st.warning("場景與話術內容不可為空。")
                        else:
                            database.update_template(
                                USER_ID, r["id"], scen.strip(), style.strip(), content.strip(),
                                note.strip(), channel.strip(),
                            )
                            st.session_state.editing_id = None
                            st.toast("已更新", icon="✅")
                            st.rerun()


# ---------------------------------------------------------------- 導覽
PAGES = {
    "💬 話術生成": page_generate,
    "🎭 對話模擬演練": page_simulation,
    "📚 話術範本庫": page_library,
}

with st.sidebar:
    st.title("生活人際溝通輔助系統")
    page = st.radio("功能", list(PAGES), label_visibility="collapsed")
    st.caption("說出口之前，先練習一次。")
    st.selectbox("🔊 朗讀聲音", list(audio_service.VOICES), key="voice_name")
    st.divider()
    if LOGIN_ENABLED:
        st.caption(f"已登入：{st.user.get('email', '')}")
        if st.button("登出", use_container_width=True):
            st.logout()
    else:
        st.caption("本機單人模式（尚未設定 Google 登入）")
PAGES[page]()
