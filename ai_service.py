"""Azure OpenAI 串接與 Prompt 工程。

環境變數：
  AZURE_OPENAI_ENDPOINT     (必填) 例如 https://xxx.openai.azure.com/
  AZURE_OPENAI_API_KEY      (必填)
  AZURE_OPENAI_DEPLOYMENT   (選填) 部署名稱，預設 gpt-4o-mini
  AZURE_OPENAI_API_VERSION  (選填) 預設 2024-10-21
"""
import json
import os
from urllib.parse import urlparse

from openai import AzureOpenAI, OpenAI

DEPLOYMENT = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4o-mini")
API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION", "2024-10-21")

SCENARIOS = [
    "委婉拒絕別人邀約",
    "和朋友發生矛盾想要道歉",
    "向別人提出請求求助",
    "應付長輩盤問",
    "婉拒推銷／借錢",
    "理性協商",
    "化解冷場尷尬",
]
STYLES = ["溫和委婉版", "直接簡潔版", "幽默圓場版"]
CHANNELS = ["面對面口頭", "LINE訊息", "正式Email"]
PERSONAS = ["強勢直率", "敏感玻璃心", "情緒勒索", "開門見山", "一般友善"]

_CHANNEL_HINTS = {
    "面對面口頭": "口語、自然，可有語氣詞，一口氣說得完，不使用條列或標題。",
    "LINE訊息": "即時通訊風格，簡短分句、可適度使用 1~2 個表情符號，不要太正式。",
    "正式Email": "完整格式：稱呼、開場、正文、結語、署名（署名用「你的名字」代替），用語正式有禮。",
}

_client: AzureOpenAI | OpenAI | None = None


class AIServiceError(Exception):
    """對外統一的錯誤型別，供 UI 顯示友善訊息。"""


def _get_client() -> AzureOpenAI | OpenAI:
    global _client
    if _client is None:
        endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
        api_key = os.getenv("AZURE_OPENAI_API_KEY")
        if not endpoint or not api_key:
            raise AIServiceError(
                "尚未設定環境變數 AZURE_OPENAI_ENDPOINT 與 AZURE_OPENAI_API_KEY。"
            )
        host = urlparse(endpoint).netloc
        if host.endswith((".services.ai.azure.com", ".cognitiveservices.azure.com")):
            # Foundry 資源（含 /api/projects/... 專案網址）：改用 v1 路徑，只取網域部分
            _client = OpenAI(base_url=f"https://{host}/openai/v1/", api_key=api_key)
        else:
            _client = AzureOpenAI(azure_endpoint=endpoint, api_key=api_key, api_version=API_VERSION)
    return _client


def _chat_json(system: str, messages: list[dict], temperature: float = 0.8) -> dict:
    """呼叫模型並強制回傳 JSON，解析為 dict。"""
    try:
        resp = _get_client().chat.completions.create(
            model=DEPLOYMENT,
            messages=[{"role": "system", "content": system}, *messages],
            temperature=temperature,
            response_format={"type": "json_object"},
        )
        return json.loads(resp.choices[0].message.content)
    except AIServiceError:
        raise
    except json.JSONDecodeError as e:
        raise AIServiceError(f"AI 回傳格式無法解析，請重試。({e})") from e
    except Exception as e:  # 網路、驗證、額度等
        raise AIServiceError(f"呼叫 Azure OpenAI 失敗：{e}") from e


# ---------------------------------------------------------------- 話術生成
_SCRIPT_SYSTEM = """你是一位擅長人際溝通的台灣溝通教練。使用者會給你一個溝通情境、溝通管道與其內心真實想法，
請用繁體中文（台灣用語）產生三種不同風格的話術，並做換位思考分析。

溝通管道：{channel}
管道格式要求：{channel_hint}
三種話術都必須符合此管道的表達方式。

三種風格：
1. 溫和委婉版：顧及對方感受，語氣柔軟
2. 直接簡潔版：不繞彎，立場清晰，但仍保持禮貌
3. 幽默圓場版：適合熟人，輕鬆化解氣氛，不可嘲諷或冒犯對方

另外請提供：
- perspective：換位思考，站在對方角度，分析對方聽完你說的話後內心最可能的真實感受（2~4 句）
- pitfalls：這類情境最容易踩到的 1~2 個溝通地雷，每個包含 mine（地雷是什麼）與 why（為何會惹毛或傷到對方）
- tip：一個簡短的溝通小技巧（1~2 句）

話術必須忠實反映使用者的真實想法，不可編造使用者未提及的事實。
只輸出 JSON，格式如下：
{{
  "scripts": [
    {{"style": "溫和委婉版", "text": "..."}},
    {{"style": "直接簡潔版", "text": "..."}},
    {{"style": "幽默圓場版", "text": "..."}}
  ],
  "perspective": "...",
  "pitfalls": [{{"mine": "...", "why": "..."}}],
  "tip": "..."
}}"""


def generate_scripts(scenario: str, thoughts: str, channel: str = CHANNELS[0]) -> dict:
    system = _SCRIPT_SYSTEM.format(
        channel=channel, channel_hint=_CHANNEL_HINTS.get(channel, "")
    )
    data = _chat_json(
        system,
        [{"role": "user", "content": f"【情境】{scenario}\n【我的內心真實想法】{thoughts}"}],
    )
    scripts = data.get("scripts")
    pitfalls = data.get("pitfalls")
    if (
        not isinstance(scripts, list) or len(scripts) < 3
        or not isinstance(pitfalls, list) or not pitfalls
        or not data.get("perspective") or not data.get("tip")
    ):
        raise AIServiceError("AI 回傳內容缺少必要欄位，請重試。")
    return {
        "scripts": [
            {"style": str(s.get("style", STYLES[i])), "text": str(s.get("text", "")).strip()}
            for i, s in enumerate(scripts[:3])
        ],
        "perspective": str(data["perspective"]).strip(),
        "pitfalls": [
            {"mine": str(p.get("mine", "")).strip(), "why": str(p.get("why", "")).strip()}
            for p in pitfalls[:2]
            if isinstance(p, dict)
        ],
        "tip": str(data["tip"]).strip(),
    }


# ---------------------------------------------------------------- 對話模擬
_ROLE_SYSTEM = """你正在進行「人際溝通演練」。請扮演情境中的「對方」，使用者則是在練習應對的人。
情境：{scenario}
使用者的背景/想法：{thoughts}
你扮演的對方性格/態度：{persona}{gender_line}

規則：
- 全程貫徹上述性格來說話與回應，用繁體中文（台灣口語），一次只說一到三句話，符合真人說話習慣。
- 保持角色，不要洩漏你是 AI，也不要替使用者說話。
- 根據使用者的回覆自然地推進對話（可以追問、堅持、讓步或轉移話題）；使用者若處理得好，你的態度可逐步軟化，處理不好則維持或加強壓力。"""

_TURN_SYSTEM = _ROLE_SYSTEM + """

此外你同時是溝通教練。每次使用者回覆後，請輸出 JSON：
{{
  "strengths": "使用者這句話的優點",
  "improvements": "可以改善的地方",
  "better_reply": "更佳的參考回覆（可直接說出口，並考慮對方的性格）",
  "next_line": "你扮演的對方接下來說的話"
}}"""


EMOTIONS = ["neutral", "happy", "angry", "sad", "annoyed", "surprised"]

_EMOTION_RULE = (
    '"emotion" 必須是下列其中之一（代表你說這句話時的情緒，供虛擬人物表情使用）：'
    + "、".join(EMOTIONS)
)

_REPLY_SYSTEM = _ROLE_SYSTEM + """

請只輸出 JSON：
{{
  "next_line": "你扮演的對方接下來說的話",
  "emotion": "情緒"
}}
""" + _EMOTION_RULE

_COACH_SYSTEM = """你是一位溝通教練。使用者正在練習以下情境，對方的性格是「{persona}」。{gender_line}
情境：{scenario}
使用者的背景/想法：{thoughts}

下面是目前的對話，最後一則是使用者剛說的話。請只針對「使用者最後一句話」給出點評，並輸出 JSON：
{{
  "strengths": "使用者這句話的優點",
  "improvements": "可以改善的地方",
  "better_reply": "更佳的參考回覆（可直接說出口，並考慮對方的性格）"
}}
使用繁體中文（台灣用語）。"""


GENDERS = {"female": "女性", "male": "男性"}


def _fmt(template: str, scenario: str, thoughts: str, persona: str, gender: str = "") -> str:
    """填入演練提示詞；gender 為空時不寫入性別（維持舊行為）。"""
    label = GENDERS.get(gender)
    return template.format(
        scenario=scenario,
        thoughts=thoughts or "（未提供）",
        persona=persona,
        gender_line=f"\n你扮演的對方性別：{label}（自稱與語氣請符合）" if label else "",
    )


def _opening_line(scenario: str, thoughts: str, persona: str, gender: str = "") -> dict:
    system = _fmt(_ROLE_SYSTEM, scenario, thoughts, persona, gender)
    data = _chat_json(
        system
        + '\n\n請只輸出 JSON：{"next_line": "你作為對方說的第一句話", "emotion": "情緒"}\n'
        + _EMOTION_RULE,
        [{"role": "user", "content": "請開始，說出對方的第一句話。"}],
    )
    line = str(data.get("next_line", "")).strip()
    if not line:
        raise AIServiceError("AI 未產生開場台詞，請重試。")
    return {"next_line": line, "emotion": _clean_emotion(data.get("emotion"))}


def _clean_emotion(value) -> str:
    value = str(value or "").strip().lower()
    return value if value in EMOTIONS else "neutral"


def start_simulation(
    scenario: str, thoughts: str, persona: str = PERSONAS[-1], gender: str = ""
) -> str:
    """AI 依性格扮演對方，說出第一句台詞。"""
    return _opening_line(scenario, thoughts, persona, gender)["next_line"]


def start_simulation_with_emotion(
    scenario: str, thoughts: str, persona: str = PERSONAS[-1], gender: str = ""
) -> dict:
    """同 start_simulation，另外回傳情緒：{'next_line', 'emotion'}。"""
    return _opening_line(scenario, thoughts, persona, gender)


def simulation_reply(
    scenario: str, thoughts: str, persona: str, history: list[dict], user_reply: str,
    gender: str = "",
) -> dict:
    """只產生對方的下一句與情緒（較快，供語音通話先開口）。"""
    system = _fmt(_REPLY_SYSTEM, scenario, thoughts, persona, gender)
    messages = [{"role": m["role"], "content": m["content"]} for m in history]
    messages.append({"role": "user", "content": user_reply})
    data = _chat_json(system, messages)
    line = str(data.get("next_line", "")).strip()
    if not line:
        raise AIServiceError("AI 未產生回應，請重試。")
    return {"next_line": line, "emotion": _clean_emotion(data.get("emotion"))}


def simulation_coach(
    scenario: str, thoughts: str, persona: str, history: list[dict], user_reply: str,
    gender: str = "",
) -> dict:
    """只產生對使用者最後一句話的點評（可與 simulation_reply 平行呼叫）。"""
    system = _fmt(_COACH_SYSTEM, scenario, thoughts, persona, gender)
    transcript = "\n".join(
        f"{'對方' if m['role'] == 'assistant' else '使用者'}：{m['content']}" for m in history
    )
    transcript += f"\n使用者：{user_reply}"
    data = _chat_json(system, [{"role": "user", "content": transcript}], temperature=0.5)
    keys = ("strengths", "improvements", "better_reply")
    if not all(data.get(k) for k in keys):
        raise AIServiceError("AI 回傳內容缺少必要欄位，請重試。")
    return {k: str(data[k]).strip() for k in keys}


def simulation_turn(
    scenario: str, thoughts: str, persona: str, history: list[dict], user_reply: str,
    gender: str = "",
) -> dict:
    """history: [{'role': 'assistant'|'user', 'content': str}, ...]（不含本次 user_reply）。"""
    system = _fmt(_TURN_SYSTEM, scenario, thoughts, persona, gender)
    messages = [
        {"role": m["role"], "content": m["content"]} for m in history
    ] + [{"role": "user", "content": user_reply}]
    data = _chat_json(system, messages)
    keys = ("strengths", "improvements", "better_reply", "next_line")
    if not all(data.get(k) for k in keys):
        raise AIServiceError("AI 回傳內容缺少必要欄位，請重試。")
    return {k: str(data[k]).strip() for k in keys}
