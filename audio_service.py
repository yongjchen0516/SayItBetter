"""語音處理模組：TTS（文字轉語音）與 STT（語音轉文字）。

- TTS：優先使用 edge-tts（免金鑰、台灣中文語音），失敗時退回 gTTS。
- STT：使用 streamlit-mic-recorder 的瀏覽器語音辨識（Web Speech API，
  請用 Chrome 或 Edge 開啟網頁，並允許麥克風權限）。
"""
import asyncio
import io
import re

import edge_tts
from gtts import gTTS

VOICES = {
    "女聲（曉臻）": "zh-TW-HsiaoChenNeural",
    "男聲（雲哲）": "zh-TW-YunJheNeural",
}

# 表情符號與特殊圖形，朗讀時直接略過
_EMOJI = re.compile(
    "[\U0001F000-\U0001FAFF\U00002600-\U000027BF\U0000FE0F\U0000200D]+", flags=re.UNICODE
)


class AudioServiceError(Exception):
    """語音處理失敗時丟出，供 UI 顯示友善訊息。"""


def _clean(text: str) -> str:
    return _EMOJI.sub("", text).strip()


async def _edge_tts(text: str, voice: str) -> bytes:
    buf = io.BytesIO()
    async for chunk in edge_tts.Communicate(text, voice).stream():
        if chunk["type"] == "audio":
            buf.write(chunk["data"])
    return buf.getvalue()


def text_to_speech(text: str, voice: str = VOICES["女聲（曉臻）"]) -> bytes:
    """回傳 mp3 位元組，可直接丟給 st.audio。"""
    text = _clean(text)
    if not text:
        raise AudioServiceError("沒有可朗讀的文字。")
    try:
        audio = asyncio.run(_edge_tts(text, voice))
        if audio:
            return audio
    except Exception:
        pass  # 退回 gTTS
    try:
        buf = io.BytesIO()
        gTTS(text=text, lang="zh-TW").write_to_fp(buf)
        return buf.getvalue()
    except Exception as e:
        raise AudioServiceError(f"語音生成失敗，請確認網路連線。({e})") from e


def speech_to_text(key: str, label: str = "🎙️ 語音輸入") -> str | None:
    """在畫面上顯示錄音按鈕；錄音結束後回傳辨識出的文字（只回傳一次），否則回傳 None。"""
    from streamlit_mic_recorder import speech_to_text as _stt

    return _stt(
        language="zh-TW",
        start_prompt=label,
        stop_prompt="⏹️ 停止錄音",
        just_once=True,
        use_container_width=False,
        key=key,
    )
