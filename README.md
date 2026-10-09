# Say It Better

生活人際溝通輔助系統：說出口之前，先練習一次。

Streamlit + Azure OpenAI + SQLite，支援語音輸入（STT）與語音試聽（TTS）。

## 檔案結構
- `app.py`：Streamlit 介面（話術生成／對話模擬演練／範本庫），含語音輸入與播放元件
- `ai_service.py`：Azure OpenAI 串接與 Prompt
- `audio_service.py`：TTS（edge-tts，失敗退回 gTTS）與 STT（瀏覽器語音辨識）
- `database.py`：SQLite 初始化與 CRUD（資料存於 `templates.db`，首次執行自動建立）

## 執行（Windows PowerShell）
```powershell
pip install -r requirements.txt

$env:AZURE_OPENAI_ENDPOINT = "https://<你的資源>.openai.azure.com/"   # 或 Foundry 專案端點
$env:AZURE_OPENAI_API_KEY  = "你的金鑰"          # 直接貼金鑰，不要加 < >
$env:AZURE_OPENAI_DEPLOYMENT = "gpt-4.1"         # 你在 Azure 建立的「部署名稱」

streamlit run app.py
```
瀏覽器會自動開啟 http://localhost:8501 ，之後全部在網頁上操作。

## Google 帳號登入（每個人的範本庫互相隔離）
設定後，電腦版與手機版都要先用 Google 登入，每個人只看得到自己的範本。**沒設定時是本機單人模式**，照常可用。

1. 到 Google Cloud Console（console.cloud.google.com）建立或選一個專案。
2. 「API 和服務 → OAuth 同意畫面」：使用者類型選「外部」，填應用程式名稱與你的 Email；
   發布狀態維持「測試」，並在「測試使用者」加入要登入的 Gmail（測試模式下只有名單上的帳號能登入）。
3. 「API 和服務 → 憑證 → 建立憑證 → OAuth 用戶端 ID」：類型選「網頁應用程式」，
   「已授權的重新導向 URI」加入這兩個：
   - `http://localhost:8000/api/auth/callback`（手機版／FastAPI）
   - `http://localhost:8501/oauth2callback`（電腦版／Streamlit）
4. 把 `.streamlit/secrets.toml.example` 複製成 `.streamlit/secrets.toml`，填入用戶端 ID、用戶端密鑰，
   並把 `cookie_secret` 換成隨機長字串：
   ```powershell
   python -c "import secrets; print(secrets.token_urlsafe(32))"
   ```
5. 重新啟動後端與 Streamlit。用 **http://localhost:8000**（不是 127.0.0.1、也不是區網 IP）開啟就會看到登入畫面。

注意：
- `secrets.toml` 內含密鑰，不要分享或上傳（已列在 `.gitignore`）。
- Google 只允許 `localhost` 或 HTTPS 網址登入，所以**手機在區網（http://192.168.x.x）無法登入**，要等部署成 HTTPS。
- 加入登入功能前的舊範本不屬於任何帳號，登入後看不到（資料仍在 `templates.db`，沒有刪除）。

## 手機版（Flutter Web + FastAPI）
`api.py` 把後端包成 API，同時提供 `mobile/build/web` 的 Flutter 網頁，手機用瀏覽器開即可。

```powershell
# 1. 啟動（與上面相同的三個環境變數，另可加 APP_PASSWORD 設定存取密碼）
python -m uvicorn api:app --host 0.0.0.0 --port 8000

# 2. 第一次需以「系統管理員」身分開 PowerShell，放行防火牆
New-NetFirewallRule -DisplayName "Comm Assistant 8000" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Private

# 3. 查電腦的區網 IP（例如 192.168.100.2）
ipconfig
```
iPhone 與電腦連同一個 Wi-Fi，Safari 開 `http://電腦IP:8000`，按分享鍵 →「加入主畫面」。

重新編譯前端（改過 `mobile/lib` 之後）：
```powershell
cd mobile
flutter build web --release
```
注意：區網是 `http://`，iPhone Safari 會擋麥克風，🎙️ 按鈕會自動隱藏，請改用鍵盤上的聽寫鍵；🔊 播放不受影響。

### 3D 虛擬人物與語音通話（對話演練）
在「演練」頁保持「語音通話（虛擬人物）」開啟，按「開始演練」：
- 對方會以 3D 卡通角色出現並開口說話，嘴巴隨聲音開合，表情依 AI 判斷的情緒變化，外觀依性格換配色。
- **電腦 Chrome**（開 `http://localhost:8000`，首次允許麥克風）：說完一句話會自動送出，對方回應後自動回到聆聽，形成連續通話。
  對方說話時想打斷，按麥克風鈕即可（不做自動打斷，避免喇叭聲音被誤當成你在說話）。
- 對方的回應和教練點評是分開取得的：對方先開口，點評稍後出現在你的那句話下方。
- 也可以隨時打字回覆。**iPhone（區網 http）** 無法使用麥克風與語音辨識，會自動隱藏麥克風，但仍看得到角色、聽得到對方說話。
- 開始前可選對方是「女生／男生」：角色外觀、對方的聲音（女聲曉臻／男聲雲哲）與說話口吻都會跟著改變。
- 女生、男生都是寫實 3D 人物（`avatar/models/female.glb`、`male.glb`，來自 Microsoft Rocketbox，MIT 授權）。
- 想換成自己的角色：把寫實 `.glb`（需含 ARKit 臉部控制點）或動漫風 `.vrm` 放進 `avatar/models/`
  （女生 `female.*`，男生 `male.*`，也可依性格命名如 `male_強勢直率.glb`），格式、授權與取得方式見該資料夾的 README。
- 瀏覽器內建的語音辨識需要連網。

## 部署：上傳 GitHub ＋ Render 雲端

雲端只跑 FastAPI 後端（`api.py`），它同時提供手機版網頁與 3D 角色頁面；Streamlit 電腦版不部署。
部署設定都已寫在 `render.yaml`（Render Blueprint）與 `requirements-server.txt`。

### 1. 上傳到 GitHub
1. 到 https://github.com/new 建立新的儲存庫（例如 `SayItBetter`）。**不要**勾選「Add a README / .gitignore / license」，保持空的。
   Public 或 Private 都可以，Render 都能讀取。
2. 在專案資料夾執行（把網址換成你的儲存庫）：
   ```powershell
   git remote add origin https://github.com/<你的帳號>/SayItBetter.git
   git push -u origin main
   ```
   第一次 push 會跳出 GitHub 登入視窗，用瀏覽器授權即可。
3. 上傳前確認沒有密鑰被加入：`git status` 不應出現 `.streamlit/secrets.toml` 或 `templates.db`（已列在 `.gitignore`）。
   `.vrm` 角色模型預設也不上傳（授權多半禁止再散布）；`.glb` 會上傳，請確認授權允許公開。

之後改了程式，只要：
```powershell
git add .
git commit -m "說明這次改了什麼"
git push
```
Render 偵測到 push 會自動重新部署。改過 `mobile/lib` 的話，記得先 `flutter build web --release` 再 commit，因為雲端直接使用 `mobile/build/web`。

### 2. 準備雲端資料庫（PostgreSQL）
Render 免費方案的硬碟在每次重新部署或休眠後會清空，SQLite 的 `templates.db` 會不見，所以範本庫要放在外部 PostgreSQL。
建議用 Neon（免費、不會過期）：
1. 到 https://neon.tech 註冊並建立專案，區域選 **Asia Pacific (Singapore)**（與 Render 同區，速度較快）。
2. 在 Dashboard →「Connection string」複製連線字串，格式像
   `postgresql://user:password@ep-xxx.ap-southeast-1.aws.neon.tech/neondb?sslmode=require`。
3. 資料表會在後端第一次啟動時自動建立，不需手動操作。

### 3. 在 Render 建立服務
1. 到 https://render.com 用 GitHub 帳號登入。
2. 「New → Blueprint」，選剛才的 GitHub 儲存庫，Render 會讀取 `render.yaml`。
3. 依提示填入密鑰（標示 `sync: false` 的變數）：

   | 變數 | 內容 |
   |---|---|
   | `AZURE_OPENAI_ENDPOINT` | Azure OpenAI 端點，同本機設定 |
   | `AZURE_OPENAI_API_KEY` | Azure OpenAI 金鑰 |
   | `GOOGLE_CLIENT_ID` | Google OAuth 用戶端 ID（不啟用登入可留空，但雲端所有人會共用同一個範本庫） |
   | `GOOGLE_CLIENT_SECRET` | Google OAuth 用戶端密鑰 |
   | `DATABASE_URL` | 上一步複製的 Neon 連線字串 |

   `AZURE_OPENAI_DEPLOYMENT` 預設 `gpt-4.1`，部署名稱不同的話到服務的「Environment」修改；
   `AUTH_COOKIE_SECRET` 由 Render 自動產生，`COOKIE_SECURE=1` 已設定好。
   想加存取密碼，可在「Environment」另外加 `APP_PASSWORD`。
4. 按「Apply」，等建置完成（約 3–5 分鐘），網址為 `https://say-it-better.onrender.com`
   （名稱被用走時 Render 會加後綴，以服務頁面上顯示的為準）。

### 4. 把雲端網址加到 Google 登入
回到 Google Cloud Console →「憑證」→ 你的 OAuth 用戶端，在「已授權的重新導向 URI」**新增**：
```
https://<你的 Render 網址>/api/auth/callback
```
（保留原本 localhost 的兩個，本機開發仍可用。）OAuth 同意畫面若仍是「測試」狀態，要登入的帳號必須在「測試使用者」名單內。

### 5. 使用
- 手機或電腦瀏覽器開 `https://<你的 Render 網址>`，用 Google 登入即可。因為是 HTTPS，**iPhone Safari 也能使用麥克風**。
- iPhone：Safari 分享鍵 →「加入主畫面」，就像 App 一樣開啟。

### 注意事項
- **休眠**：免費方案閒置 15 分鐘會休眠，下次開啟要等 30–60 秒喚醒，屬正常現象。
- **建置失敗**：到 Render 服務頁的「Logs」看錯誤訊息，常見是環境變數填錯或 `DATABASE_URL` 少了 `?sslmode=require`。
- **健康檢查**：Render 以 `/api/meta` 檢查服務是否正常，可直接開這個網址確認後端有在運作（有回傳 JSON 即正常）。

## 語音功能注意事項
- **語音輸入（🎙️）**：使用瀏覽器內建的語音辨識，請用 **Chrome 或 Edge** 開啟，並允許麥克風權限。
- **語音試聽（🔊）**：edge-tts 與 gTTS 都需要連網。可在側邊欄切換女聲／男聲。
- 部署名稱必須是 Azure 中的**部署名稱**，不一定等於模型名稱。
- API 版本預設 `2024-10-21`，可用 `AZURE_OPENAI_API_VERSION` 覆寫；Foundry（`services.ai.azure.com`）端點會自動改走 v1 路徑。
