// 把角色、語音層與外層（Flutter）用 postMessage 接起來。
import { Avatar } from './avatar.js';
import { VoiceIO } from './voice.js';

const params = new URLSearchParams(location.search);
const canvas = document.getElementById('c');
const hint = document.getElementById('hint');
const status = document.getElementById('status');
const embedded = window.parent !== window;

const post = (msg) => { if (embedded) window.parent.postMessage(msg, location.origin); };

// 把頁面內的錯誤回報給外層，方便除錯
window.addEventListener('error', (e) => post({ type: 'jsError', message: String(e.message) }));
window.addEventListener('unhandledrejection', (e) => post({ type: 'jsError', message: String(e.reason) }));

const avatar = new Avatar(canvas);
window.__avatar = avatar;   // 除錯用

const voice = new VoiceIO({
  onTranscript: (text, final) => post({ type: 'transcript', text, final }),
  onListening: (on) => post({ type: 'listening', on }),
  onError: (code, message) => post({ type: 'sttError', code, message }),
});
avatar.mouthSource = () => voice.getLevel();

// ---------------------------------------------------------------- 尺寸
const fit = () => avatar.resize(window.innerWidth, window.innerHeight);
new ResizeObserver(fit).observe(document.body);
fit();

// ---------------------------------------------------------------- 模型
let loadId = 0;
async function loadModel(persona, gender) {
  const id = ++loadId;
  avatar.setPersona(persona);
  avatar.setGender(gender);
  if (!avatar.glb && !avatar.vrm) { status.textContent = '角色載入中…'; status.hidden = false; }
  const ok = await avatar.tryLoadVrm(avatar.personaName, avatar.gender);
  if (id !== loadId) return;   // 載入期間又切換了，以最後一次為準
  status.textContent = '角色載入失敗';
  status.hidden = ok;
  post({ type: 'vrm', loaded: ok });
}

// ---------------------------------------------------------------- 外層指令
async function speak(url, emotion) {
  if (emotion) avatar.setEmotion(emotion);
  post({ type: 'speakStart' });
  try {
    await voice.speak(url);
    post({ type: 'speakEnd' });
  } catch (err) {
    post({ type: 'speakError', message: String(err?.message || err) });
  }
}

window.addEventListener('message', (ev) => {
  if (ev.origin !== location.origin) return;
  const m = ev.data || {};
  switch (m.type) {
    case 'setPersona': loadModel(m.persona, m.gender); break;
    case 'setEmotion': avatar.setEmotion(m.emotion); break;
    case 'unlock': voice.unlock(); break;
    case 'speak': voice.unlock(); speak(m.url, m.emotion); break;
    case 'stopSpeaking': voice.stopSpeaking(); break;
    case 'startListening': voice.startListening(); break;
    case 'stopListening': voice.stopListening(); break;
  }
});

// 單獨開啟頁面時，點一下畫面即可解除自動播放限制
canvas.addEventListener('pointerdown', () => { voice.unlock(); hint.style.display = 'none'; });

// ---------------------------------------------------------------- 測試用：以網址參數固定外觀
// 例：/avatar/index.html?gender=male&emotion=angry&mouth=0.6
if (params.has('emotion')) avatar.setEmotion(params.get('emotion'));
if (params.has('mouth')) avatar.setFixedMouth(parseFloat(params.get('mouth')) || 0);
// 單獨開啟頁面時直接載入模型；嵌在 App 裡則等外層告知性別（setPersona）再載入，避免多下載一個模型
if (!embedded) loadModel(params.get('persona') || '一般友善', params.get('gender') || 'female');
if (embedded) hint.style.display = 'none';

post({ type: 'ready', sttSupported: voice.sttSupported });
