// 語音層：瀏覽器語音辨識（STT）＋ 語音播放與音量分析（驅動口型）。

const SR = window.SpeechRecognition || window.webkitSpeechRecognition;

const ERROR_TEXT = {
  'not-allowed': '麥克風權限被拒絕，請在瀏覽器網址列左側允許使用麥克風。',
  'service-not-allowed': '此瀏覽器不允許語音辨識服務。',
  'audio-capture': '找不到麥克風，請確認裝置已連接。',
  'network': '語音辨識需要連網，請檢查網路連線。',
  'language-not-supported': '瀏覽器不支援中文語音辨識。',
};

export class VoiceIO {
  /**
   * @param {{onTranscript:(text:string, final:boolean)=>void,
   *          onListening:(on:boolean)=>void,
   *          onError:(code:string, message:string)=>void}} cb
   */
  constructor(cb) {
    this.cb = cb;
    this.want = false;       // 使用者希望持續聆聽
    this.rec = null;
    this.restartCount = 0;
    this.ctx = null;
    this.analyser = null;
    this.buf = null;
    this.audio = null;
    this.analysisOk = false;
    this.speaking = false;
    this.level = 0;
  }

  get sttSupported() { return !!SR; }

  // ---------------------------------------------------------------- 音訊
  _ensureCtx() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
    this.analyser = this.ctx.createAnalyser();
    this.analyser.fftSize = 1024;
    this.analyser.connect(this.ctx.destination);
    this.buf = new Uint8Array(this.analyser.fftSize);
  }

  /** 需在使用者點擊後呼叫一次，解除瀏覽器的自動播放限制。 */
  unlock() {
    this._ensureCtx();
    this.ctx?.resume?.().catch(() => {});
  }

  /** 播放網址上的語音；播放結束時 resolve，失敗時 reject。 */
  async speak(url) {
    this.stopSpeaking();
    this._ensureCtx();
    try { await this.ctx?.resume?.(); } catch { /* 忽略 */ }

    const audio = new Audio();
    audio.preload = 'auto';
    audio.src = url;
    this.audio = audio;

    // 只有 AudioContext 處於 running 才經由它播放並分析音量，否則直接播放並以模擬嘴型代替
    this.analysisOk = false;
    let node = null;
    if (this.ctx && this.ctx.state === 'running') {
      try {
        node = this.ctx.createMediaElementSource(audio);
        node.connect(this.analyser);
        this.analysisOk = true;
      } catch { node = null; }
    }

    this.speaking = true;
    return new Promise((resolve, reject) => {
      const done = (err) => {
        if (this.audio !== audio) { resolve(); return; }   // 已被 stopSpeaking 取代
        this.speaking = false;
        this.audio = null;
        try { node?.disconnect(); } catch { /* 忽略 */ }
        err ? reject(err) : resolve();
      };
      audio.onended = () => done();
      audio.onerror = () => done(new Error('語音載入失敗，請稍後再試。'));
      audio.play().catch((e) => done(e));
    });
  }

  stopSpeaking() {
    const a = this.audio;
    this.audio = null;
    this.speaking = false;
    if (a) { try { a.pause(); a.removeAttribute('src'); a.load(); } catch { /* 忽略 */ } }
  }

  /** 目前說話音量 0..1（平滑後）。 */
  getLevel() {
    let target = 0;
    if (this.speaking) {
      if (this.analysisOk && this.analyser) {
        this.analyser.getByteTimeDomainData(this.buf);
        let sum = 0;
        for (let i = 0; i < this.buf.length; i++) {
          const v = (this.buf[i] - 128) / 128;
          sum += v * v;
        }
        const rms = Math.sqrt(sum / this.buf.length);
        target = Math.min(1, Math.max(0, (rms - 0.012) * 7));
      } else {
        // 無法分析音量時，以隨機節奏模擬說話
        target = 0.25 + 0.4 * Math.abs(Math.sin(performance.now() * 0.012)) * (0.6 + Math.random() * 0.4);
      }
    }
    this.level += (target - this.level) * 0.5;
    return this.level;
  }

  // ---------------------------------------------------------------- 語音辨識
  startListening() {
    if (!SR) {
      this.cb.onError('unsupported', '這個瀏覽器不支援語音辨識，請改用電腦版 Chrome 或 Edge，或直接打字。');
      return;
    }
    if (this.want) return;
    this.want = true;
    this.restartCount = 0;
    this._start();
  }

  stopListening() {
    this.want = false;
    if (this.rec) { try { this.rec.abort(); } catch { /* 忽略 */ } }
  }

  _start() {
    const rec = new SR();
    this.rec = rec;
    rec.lang = 'zh-TW';
    rec.continuous = false;
    rec.interimResults = true;
    rec.maxAlternatives = 1;

    rec.onstart = () => this.cb.onListening(true);

    rec.onresult = (e) => {
      let interim = '';
      let fin = '';
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const t = e.results[i][0].transcript;
        if (e.results[i].isFinal) fin += t; else interim += t;
      }
      this.restartCount = 0;
      if (fin.trim()) {
        this.want = false;                       // 一句話辨識完成，交給上層處理
        this.cb.onTranscript(fin.trim(), true);
      } else if (interim) {
        this.cb.onTranscript(interim.trim(), false);
      }
    };

    rec.onerror = (e) => {
      if (e.error === 'no-speech' || e.error === 'aborted') return;   // 靜音逾時：由 onend 重啟
      this.want = false;
      this.cb.onError(e.error, ERROR_TEXT[e.error] || `語音辨識發生錯誤（${e.error}）。`);
    };

    rec.onend = () => {
      if (this.rec === rec) this.rec = null;
      if (this.want) {
        // 靜音逾時等情況自動重新開始；連續太多次沒有結果就放棄，避免無限迴圈
        if (++this.restartCount > 15) {
          this.want = false;
          this.cb.onListening(false);
          this.cb.onError('no-speech', '一直沒有聽到聲音，請確認麥克風後再按一次。');
          return;
        }
        setTimeout(() => { if (this.want) this._start(); }, 150);
      } else {
        this.cb.onListening(false);
      }
    };

    try { rec.start(); } catch (err) {
      this.want = false;
      this.cb.onError('start-failed', '無法啟動語音辨識，請稍後再試。');
    }
  }
}
