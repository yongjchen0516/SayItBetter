// 3D 虛擬人物：從 models/ 載入真人 .glb（或 .vrm）模型，依情緒做表情、依聲音開合嘴巴。
// .glb 需含 ARKit 臉部控制點（jawOpen、mouthSmileLeft…），骨架為 Mixamo 或 3ds Max Biped（Rocketbox）命名。
import * as THREE from 'three';

const VRM_EXPRESSIONS = { happy: 'happy', angry: 'angry', sad: 'sad', surprised: 'surprised' };

// .glb（ARKit 控制點）的情緒表情；左右對稱的控制點只寫一次，L/R 會自動展開
const ARKIT_EMOTIONS = {
  neutral:   {},
  happy:     { mouthSmile: 0.55, cheekSquint: 0.35, eyeSquint: 0.2, browInnerUp: 0.1 },
  angry:     { browDown: 0.75, noseSneer: 0.3, eyeSquint: 0.3, mouthPress: 0.35, mouthFrown: 0.25 },
  sad:       { browInnerUp: 0.8, mouthFrown: 0.55, mouthShrugLower: 0.3, eyeSquint: 0.15 },
  annoyed:   { browDown: 0.4, eyeSquint: 0.35, mouthPress: 0.4, mouthFrown: 0.15, noseSneer: 0.1 },
  surprised: { browInnerUp: 0.7, browOuterUp: 0.75, eyeWide: 0.6, jawOpen: 0.08 },
};
const ARKIT_PAIRED = ['mouthSmile', 'mouthFrown', 'mouthPress', 'cheekSquint', 'eyeSquint', 'eyeWide',
  'browDown', 'browOuterUp', 'noseSneer'];
const expandArkit = (o) => Object.fromEntries(Object.entries(o).flatMap(([k, v]) =>
  ARKIT_PAIRED.includes(k) ? [[k + 'Left', v], [k + 'Right', v]] : [[k, v]]));
const ARKIT_TARGETS = Object.fromEntries(Object.entries(ARKIT_EMOTIONS).map(([k, v]) => [k, expandArkit(v)]));
// 每幀都要歸零再設定的控制點（情緒會用到的全部，加上嘴巴與眨眼）
const ARKIT_ANIMATED = [...new Set([
  ...Object.values(ARKIT_TARGETS).flatMap(Object.keys),
  'jawOpen', 'viseme_aa', 'eyeBlinkLeft', 'eyeBlinkRight',
  'mouthLowerDownLeft', 'mouthLowerDownRight', 'mouthUpperUpLeft', 'mouthUpperUpRight',
])];

const ARM_DOWN = 1.25;   // 手臂放下的角度（弧度）；若模型手臂往上翹，把正負號對調

const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

export class Avatar {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(30, 1, 0.1, 50);
    this.camera.position.set(0, 0.2, 4.2);
    this.camera.lookAt(0, -0.1, 0);

    this.scene.add(new THREE.HemisphereLight(0xffffff, 0xb8c4d6, 1.0));
    const key = new THREE.DirectionalLight(0xffffff, 1.3);
    key.position.set(1.5, 2.5, 3);
    this.scene.add(key);

    this.personaName = '一般友善';
    this.gender = 'female';
    this.mouth = 0;            // 0..1，說話時的嘴巴開合
    this.mouthSource = null;   // () => 0..1，由外部（音量）提供
    this.blinkT = 2 + Math.random() * 2;
    this.blinkPhase = -1;
    this.clock = new THREE.Clock();
    this.t = 0;
    this.vrm = null;
    this.glb = null;           // 載入的 .glb：{ scene, meshes, head, spine, headRest, spineRest }
    this.vrmEmotion = 'neutral';
    this.morphCur = {};        // .glb 控制點目前值（平滑過渡用）
    this.fixedMouth = null;    // 測試用：固定嘴型

    this._loop = this._loop.bind(this);
    this.renderer.setAnimationLoop(this._loop);
  }

  // ---------------------------------------------------------------- 公開 API
  setPersona(name) { this.personaName = name || this.personaName; }

  /** 'female' | 'male'：決定載入哪個模型（見 tryLoadVrm）。 */
  setGender(g) { this.gender = g === 'male' ? 'male' : 'female'; }

  setEmotion(name) {
    this.vrmEmotion = ARKIT_EMOTIONS[name] ? name : 'neutral';
  }

  setFixedMouth(v) { this.fixedMouth = v; }

  /** 依性別找模型（找到第一個就用；同名時 .vrm 優先於 .glb）：
   *  女生：female_<性格> → female → default；男生：male_<性格> → male。
   *  成功載入模型回傳 true；找不到或載入失敗回傳 false（畫面上不顯示角色）。 */
  async tryLoadVrm(personaName, gender = 'female', base = './models/') {
    const seq = (this._loadSeq = (this._loadSeq || 0) + 1);   // 只採用最後一次請求的結果
    const g = gender === 'male' ? 'male' : 'female';
    const names = [`${g}_${personaName}`, g];
    if (g === 'female') names.push('default');                 // default 是女生模型，男生不使用
    const candidates = names.flatMap((n) => [`${n}.vrm`, `${n}.glb`]);
    try {
      let url = null;
      for (const c of candidates) {
        const r = await fetch(base + encodeURIComponent(c), { method: 'HEAD' });
        if (r.ok) { url = base + encodeURIComponent(c); break; }
      }
      if (seq !== this._loadSeq) return false;
      if (!url) { this._removeModel(); return false; }
      if (this.modelUrl === url) return true;                  // 已經是這個模型

      const isVrm = url.endsWith('.vrm');
      const [{ GLTFLoader }, vrmLib] = await Promise.all([
        import('./vendor/examples/jsm/loaders/GLTFLoader.js'),
        isVrm ? import('./vendor/three-vrm.module.min.js') : null,
      ]);
      const loader = new GLTFLoader();
      if (isVrm) loader.register((parser) => new vrmLib.VRMLoaderPlugin(parser));
      const gltf = await loader.loadAsync(url);
      if (seq !== this._loadSeq) return false;                 // 載入期間又切換了
      if (isVrm) {
        if (!gltf.userData.vrm) { this._removeModel(); return false; }
        this._useVrm(gltf.userData.vrm, vrmLib);
      } else if (!this._useGlb(gltf.scene)) {
        this._removeModel();
        return false;
      }
      this.modelUrl = url;
      this._frameVrm();
      return true;
    } catch (err) {
      console.warn('模型載入失敗：', err);
      if (seq === this._loadSeq) this._removeModel();
      return false;
    }
  }

  _useVrm(vrm, vrmLib) {
    vrmLib.VRMUtils.rotateVRM0?.(vrm);
    this._removeModel();
    this.scene.add(vrm.scene);
    this.vrm = vrm;

    // 預設是 T 字形張開雙臂，把手臂放下成自然站姿
    const h = vrm.humanoid;
    const lArm = h?.getNormalizedBoneNode('leftUpperArm');
    const rArm = h?.getNormalizedBoneNode('rightUpperArm');
    if (lArm) lArm.rotation.z = ARM_DOWN;
    if (rArm) rArm.rotation.z = -ARM_DOWN;
    this.vrmHead = h?.getNormalizedBoneNode('head') || null;
    this.vrmSpine = h?.getNormalizedBoneNode('spine') || null;
    vrm.scene.updateMatrixWorld(true);

    // 鏡頭：以頭部骨骼為基準，取頭到胸口的半身構圖
    const p = new THREE.Vector3();
    (this.vrmHead || vrm.scene).getWorldPosition(p);
    this.vrmFrame = p.clone();
  }

  /** 使用一般 .glb：找出有臉部控制點的網格與骨骼（Mixamo 或 Biped 命名）。沒有 jawOpen 視為不支援。 */
  _useGlb(scene) {
    const meshes = [];
    scene.traverse((o) => {
      if (o.isMesh && o.morphTargetDictionary) meshes.push(o);
      if (o.isMesh) o.frustumCulled = false;   // 蒙皮網格的包圍盒不準，避免拉近時整塊消失
    });
    if (!meshes.some((m) => 'jawOpen' in m.morphTargetDictionary)) {
      console.warn('這個 .glb 沒有 ARKit 臉部控制點（jawOpen），無法使用');
      return false;
    }
    // 骨骼名稱：Mixamo（Head、LeftArm…，可有 mixamorig 前綴）或 3ds Max Biped（Rocketbox 的 Bip01 Head…；
    // three.js 會把名稱中的空白換成底線）
    const BIPED = { Head: 'Head', Spine: 'Spine', Spine1: 'Spine1', LeftArm: 'L UpperArm', LeftForeArm: 'L Forearm',
      RightArm: 'R UpperArm', RightForeArm: 'R Forearm' };
    const bone = (name) => [name, 'mixamorig' + name, 'mixamorig:' + name, `Bip01 ${BIPED[name]}`]
      .map((n) => scene.getObjectByName(n) || scene.getObjectByName(n.replace(/[\s:]/g, '_')))
      .find(Boolean);
    this._removeModel();
    this.scene.add(scene);
    scene.updateMatrixWorld(true);

    // 手臂從 T／A 字形放下：讓上臂指向斜下方（依骨骼實際方向計算，不受模型座標系影響）
    for (const [arm, fore, side] of [['LeftArm', 'LeftForeArm', 1], ['RightArm', 'RightForeArm', -1]]) {
      const a = bone(arm), f = bone(fore);
      if (a && f) pointBone(a, f, new THREE.Vector3(0.12 * side, -1, 0.02));
    }
    const head = bone('Head');
    const spine = bone('Spine1') || bone('Spine');
    this.glb = {
      scene, meshes, head, spine,
      headRest: head?.quaternion.clone(),
      spineRest: spine?.quaternion.clone(),
    };
    this.morphCur = {};
    scene.updateMatrixWorld(true);

    // 鏡頭基準：Mixamo 的 Head 骨骼在頭底部，與 VRM 的 head 位置相近
    const p = new THREE.Vector3();
    (head || scene).getWorldPosition(p);
    this.vrmFrame = p;
    return true;
  }

  _removeModel() {
    if (this.vrm) this.scene.remove(this.vrm.scene);
    if (this.glb) this.scene.remove(this.glb.scene);
    this.vrm = this.glb = null;
    this.modelUrl = null;
    this.vrmHead = this.vrmSpine = this.vrmFrame = null;
  }

  /** VRM 的取景：頭部骨骼在下巴附近，往上留出頭頂、往下帶到胸口。 */
  _frameVrm() {
    const p = this.vrmFrame;
    if (!p) return;
    const aspect = this.camera.aspect || 1;
    // 橫向（App 內的角色框）取頭到胸口；直向（單獨開頁面）取半身
    const dist = aspect < 0.9 ? 1.5 / Math.max(0.55, aspect) * 0.8 : 1.0;
    const look = aspect < 0.9 ? -0.02 : 0.0;
    this.camera.position.set(p.x, p.y + 0.04, p.z + dist);
    this.camera.lookAt(p.x, p.y + look, p.z);
  }

  resize(w, h) {
    if (!w || !h) return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    if (this.vrmFrame) this._frameVrm();
    this.camera.updateProjectionMatrix();
  }

  // ---------------------------------------------------------------- 每幀更新
  _loop() {
    const dt = Math.min(this.clock.getDelta(), 0.1);
    this.t += dt;

    let m = this.fixedMouth != null ? this.fixedMouth : (this.mouthSource ? this.mouthSource() : 0);
    this.mouth += (clamp(m, 0, 1) - this.mouth) * (1 - Math.exp(-25 * dt));

    // 眨眼
    this.blinkT -= dt;
    if (this.blinkT <= 0 && this.blinkPhase < 0) { this.blinkPhase = 0; }
    let blink = 0;
    if (this.blinkPhase >= 0) {
      this.blinkPhase += dt;
      blink = Math.sin(Math.min(this.blinkPhase / 0.16, 1) * Math.PI);
      if (this.blinkPhase >= 0.16) {
        this.blinkPhase = -1;
        this.blinkT = 2 + Math.random() * 3;
      }
    }

    if (this.vrm) this._updateVrm(dt, blink);
    else if (this.glb) this._updateGlb(dt, blink);

    this.renderer.render(this.scene, this.camera);
  }

  _updateVrm(dt, blink) {
    const em = this.vrm.expressionManager;
    if (em) {
      for (const n of ['happy', 'angry', 'sad', 'surprised', 'Surprised', 'relaxed']) em.setValue(n, 0);
      const mapped = VRM_EXPRESSIONS[this.vrmEmotion];
      // 「開心」「驚訝」這兩個表情本身是張嘴的；不說話時要閉嘴，所以依說話程度混合
      const talk = clamp(this.mouth * 4, 0, 1);
      if (this.vrmEmotion === 'happy') {
        em.setValue('happy', 0.8 * talk);
        em.setValue('relaxed', 0.7 * (1 - talk));       // 閉嘴的微笑
      } else if (this.vrmEmotion === 'surprised') {
        // VRoid 匯出的模型把「驚訝」存成大寫的自訂表情；沒有的話就略過
        em.setValue('Surprised', 0.8 * talk);
        em.setValue('surprised', 0.8 * talk);
        em.setValue('sad', 0.25 * (1 - talk));          // 閉嘴時以微微皺眉代替
      } else if (mapped) em.setValue(mapped, 0.8);
      else if (this.vrmEmotion === 'annoyed') em.setValue('angry', 0.35);
      em.setValue('aa', clamp(this.mouth, 0, 1));
      em.setValue('blink', blink);
    }
    // 待機動作：呼吸與輕微晃頭；說話時微點頭
    if (this.vrmSpine) this.vrmSpine.rotation.x = Math.sin(this.t * 1.6) * 0.012;
    if (this.vrmHead) {
      this.vrmHead.rotation.y = Math.sin(this.t * 0.55) * 0.07;
      this.vrmHead.rotation.z = Math.sin(this.t * 0.42) * 0.02;
      this.vrmHead.rotation.x = Math.sin(this.t * 0.8) * 0.02 + this.mouth * 0.06;
    }
    this.vrm.update(dt);
  }

  _updateGlb(dt, blink) {
    const { meshes, head, spine, headRest, spineRest } = this.glb;
    const target = ARKIT_TARGETS[this.vrmEmotion] || ARKIT_TARGETS.neutral;
    const k = 1 - Math.exp(-9 * dt);
    const talk = clamp(this.mouth, 0, 1);
    const values = {};
    for (const n of ARKIT_ANIMATED) {
      const cur = this.morphCur[n] || 0;
      values[n] = this.morphCur[n] = cur + ((target[n] || 0) - cur) * k;
    }
    // 說話：下顎張開、上下唇分開，加一點「啊」的嘴型（只用 viseme 的話舌頭會露太多）；
    // 說話時收一點笑容，嘴型才不會被拉扁
    values.jawOpen = clamp(values.jawOpen + talk * 0.4, 0, 1);
    values.viseme_aa = clamp(talk * 0.2, 0, 1);
    for (const s of ['Left', 'Right']) {
      values['mouthLowerDown' + s] = clamp(talk * 0.4, 0, 1);
      values['mouthUpperUp' + s] = clamp(talk * 0.2, 0, 1);
      values['mouthSmile' + s] *= 1 - talk * 0.5;
      values['mouthPress' + s] *= 1 - talk;
      values['eyeBlink' + s] = clamp(blink + (values['eyeBlink' + s] || 0), 0, 1);
    }
    for (const m of meshes) {
      const dict = m.morphTargetDictionary, inf = m.morphTargetInfluences;
      for (const n in values) {
        const i = dict[n];
        if (i !== undefined) inf[i] = values[n];
      }
    }
    // 待機動作：呼吸與輕微晃頭；說話時微點頭（疊加在骨骼原本的姿勢上）
    if (spine) spine.quaternion.copy(spineRest).multiply(_q.setFromEuler(_e.set(Math.sin(this.t * 1.6) * 0.012, 0, 0)));
    if (head) {
      _e.set(Math.sin(this.t * 0.8) * 0.02 + this.mouth * 0.05, Math.sin(this.t * 0.55) * 0.07, Math.sin(this.t * 0.42) * 0.02);
      head.quaternion.copy(headRest).multiply(_q.setFromEuler(_e));
    }
  }
}

const _q = new THREE.Quaternion();
const _e = new THREE.Euler();

/** 旋轉骨骼 bone，讓它指向子骨骼 child 的方向變成世界座標的 dir。 */
function pointBone(bone, child, dir) {
  const a = bone.getWorldPosition(new THREE.Vector3());
  const b = child.getWorldPosition(new THREE.Vector3());
  const turn = new THREE.Quaternion().setFromUnitVectors(b.sub(a).normalize(), dir.clone().normalize());
  const world = bone.getWorldQuaternion(new THREE.Quaternion()).premultiply(turn);
  const parent = bone.parent.getWorldQuaternion(new THREE.Quaternion());
  bone.quaternion.copy(parent.invert().multiply(world));
  bone.updateMatrixWorld(true);
}
