"""語音處理模組：TTS（文字轉語音）與 STT（語音轉文字）。

- TTS：依序嘗試
  1. Azure AI Speech（官方服務，需環境變數 AZURE_SPEECH_KEY、AZURE_SPEECH_REGION；與 edge-tts 同一套台灣中文聲音）
  2. edge-tts（免金鑰，但微軟可能隨時擋掉連線）
  3. gTTS（只有一種女聲，選男聲也會是女聲）
- STT：使用 streamlit-mic-recorder 的瀏覽器語音辨識（Web Speech API，
  請用 Chrome 或 Edge 開啟網頁，並允許麥克風權限）。
"""
import asyncio
import io
import logging
import os
import re
from xml.sax.saxutils import escape

import edge_tts
import httpx
from gtts import gTTS

log = logging.getLogger(__name__)

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


def _azure_tts(text: str, voice: str) -> bytes | None:
    """Azure AI Speech REST API；沒有設定金鑰時回傳 None。"""
    key, region = os.getenv("AZURE_SPEECH_KEY"), os.getenv("AZURE_SPEECH_REGION")
    if not (key and region):
        return None
    ssml = (
        "<speak version='1.0' xml:lang='zh-TW'>"
        f"<voice name='{voice}'>{escape(text)}</voice></speak>"
    )
    r = httpx.post(
        f"https://{region.strip()}.tts.speech.microsoft.com/cognitiveservices/v1",
        headers={
            "Ocp-Apim-Subscription-Key": key.strip(),
            "Content-Type": "application/ssml+xml",
            "X-Microsoft-OutputFormat": "audio-24khz-48kbitrate-mono-mp3",
            "User-Agent": "SayItBetter",
        },
        content=ssml.encode("utf-8"),
        timeout=20,
    )
    r.raise_for_status()
    return r.content


_azure_status: str | None = None


def azure_status() -> str:
    """Azure 語音的狀態（給 /api/meta 診斷用，不含金鑰）：未設定／正常／失敗原因。第一次呼叫時試念一個字並記住結果。"""
    global _azure_status
    if _azure_status is None:
        try:
            _azure_status = "正常" if _azure_tts("好", VOICES["男聲（雲哲）"]) else "未設定"
        except httpx.HTTPStatusError as e:
            _azure_status = f"失敗：HTTP {e.response.status_code}"
        except Exception as e:
            _azure_status = f"失敗：{type(e).__name__}"
    return _azure_status


def synthesize(text: str, voice: str = VOICES["女聲（曉臻）"]) -> tuple[bytes, bool]:
    """回傳 (mp3 位元組, 是否為指定的聲音)。退回 gTTS 時聲音固定是女聲，第二個值為 False。"""
    text = _clean(text)
    if not text:
        raise AudioServiceError("沒有可朗讀的文字。")
    try:
        audio = _azure_tts(text, voice)
        if audio:
            return audio, True
    except Exception as e:
        log.warning("Azure 語音失敗，改用 edge-tts：%s", e)
    try:
        audio = asyncio.run(_edge_tts(text, voice))
        if audio:
            return audio, True
    except Exception as e:
        log.warning("edge-tts 失敗，改用 gTTS（只有女聲）：%s", e)
    try:
        buf = io.BytesIO()
        gTTS(text=text, lang="zh-TW").write_to_fp(buf)
        return buf.getvalue(), False
    except Exception as e:
        raise AudioServiceError(f"語音生成失敗，請確認網路連線。({e})") from e


def text_to_speech(text: str, voice: str = VOICES["女聲（曉臻）"]) -> bytes:
    """回傳 mp3 位元組，可直接丟給 st.audio。"""
    return synthesize(text, voice)[0]


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
