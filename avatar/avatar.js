// 3D 虛擬人物：預設為程式碼生成的卡通角色；若 models/ 內有 .vrm 或 .glb 則改用該模型。
// .glb 需含 ARKit 臉部控制點（jawOpen、mouthSmileLeft…）與 Mixamo 命名的骨架（Head、Spine1、LeftArm…）。
import * as THREE from 'three';

// ---------------------------------------------------------------- 性格外觀
const PERSONAS = {
  '強勢直率': { hair: 0x5b1e1e, skin: 0xe9b88e, shirt: 0x1f3557, browThick: 1.6, browBase: -0.14 },
  '敏感玻璃心': { hair: 0xc9a7e8, skin: 0xfad4b8, shirt: 0xf3b6cf, browThick: 0.8, browBase: 0.12 },
  '情緒勒索': { hair: 0x2d1b4e, skin: 0xf0c4a2, shirt: 0x6a2e6e, browThick: 1.1, browBase: 0.1 },
  '開門見山': { hair: 0x1e4d3a, skin: 0xe6b48a, shirt: 0x2f7d5b, browThick: 1.3, browBase: -0.05 },
  '一般友善': { hair: 0x6b4a2b, skin: 0xf6cba7, shirt: 0x2a8fa3, browThick: 1.0, browBase: 0.0 },
};
const DEFAULT_PERSONA = '一般友善';

// ---------------------------------------------------------------- 情緒 → 表情參數
// browAngle: 眉毛內側下壓為負（生氣）、上揚為正（難過）；curve: 嘴角上揚為正、下垂為負
const EMOTIONS = {
  neutral:   { browY: 0,     browAngle: 0,     eyeOpen: 1,    curve: 0,    mouthW: 1,    openBase: 0,   blush: 0 },
  happy:     { browY: 0.02,  browAngle: 0.06,  eyeOpen: 0.78, curve: 1,    mouthW: 1.2,  openBase: 0.1, blush: 0.55 },
  angry:     { browY: -0.03, browAngle: -0.5,  eyeOpen: 0.85, curve: -0.6,  mouthW: 0.95, openBase: 0,   blush: 0.15 },
  sad:       { browY: 0.02,  browAngle: 0.42,  eyeOpen: 0.8,  curve: -0.9,  mouthW: 0.8,  openBase: 0,   blush: 0 },
  annoyed:   { browY: -0.015, browAngle: -0.22, eyeOpen: 0.5,  curve: -0.3,  mouthW: 0.9,  openBase: 0,   blush: 0 },
  surprised: { browY: 0.08,  browAngle: 0.0,   eyeOpen: 1.25, curve: 0,    mouthW: 0.7,  openBase: 0.5, blush: 0 },
};

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

function mat(color, extra = {}) {
  return new THREE.MeshStandardMaterial({ color, roughness: 0.75, metalness: 0, ...extra });
}

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

    this.personaName = DEFAULT_PERSONA;
    this.target = { ...EMOTIONS.neutral };
    this.cur = { ...EMOTIONS.neutral };
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

    this._buildCharacter();
    this.setPersona(DEFAULT_PERSONA);
    this.setGender('female');
    this._loop = this._loop.bind(this);
    this.renderer.setAnimationLoop(this._loop);
  }

  // ---------------------------------------------------------------- 角色建模
  _buildCharacter() {
    const g = (this.root = new THREE.Group());
    this.scene.add(g);

    // 身體與脖子
    this.torso = new THREE.Mesh(new THREE.CapsuleGeometry(0.45, 0.55, 8, 20), (this.mShirt = mat(0x2a8fa3)));
    this.torso.scale.set(1.35, 1, 0.8);
    this.torso.position.y = -1.18;
    g.add(this.torso);
    this.neck = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.15, 0.3, 16), (this.mSkinNeck = mat(0xf6cba7)));
    this.neck.position.y = -0.52;
    g.add(this.neck);

    // 頭
    this.head = new THREE.Group();
    this.head.position.y = 0.05;
    g.add(this.head);
    const skull = new THREE.Mesh(new THREE.SphereGeometry(0.5, 40, 32), (this.mSkin = mat(0xf6cba7)));
    skull.scale.set(1, 1.05, 0.95);
    this.head.add(skull);

    // 耳朵
    for (const s of [-1, 1]) {
      const ear = new THREE.Mesh(new THREE.SphereGeometry(0.09, 16, 12), this.mSkin);
      ear.scale.set(0.5, 1, 0.7);
      ear.position.set(0.5 * s, -0.02, 0.0);
      this.head.add(ear);
    }

    // 頭髮（頂部半球，向後傾斜以露出額頭與眉眼）
    this.hair = new THREE.Mesh(
      new THREE.SphereGeometry(0.535, 40, 28, 0, Math.PI * 2, 0, Math.PI * 0.56),
      (this.mHair = mat(0x6b4a2b, { roughness: 0.9 }))
    );
    this.hair.scale.set(1.0, 1.06, 1.0);
    this.hair.rotation.x = -0.78;
    this.hair.position.set(0, 0.02, -0.04);
    this.head.add(this.hair);

    // 女生配件：後方長髮與兩側髮束（與頭髮同材質，跟著性格換色）、睫毛；以 setGender 切換
    this.femaleParts = new THREE.Group();
    const backHair = new THREE.Mesh(new THREE.SphereGeometry(0.5, 32, 24), this.mHair);
    backHair.scale.set(1.12, 1.45, 0.62);
    backHair.position.set(0, -0.3, -0.2);
    const sideGeo = new THREE.CapsuleGeometry(0.085, 0.5, 6, 12);
    for (const s of [-1, 1]) {
      const lock = new THREE.Mesh(sideGeo, this.mHair);
      lock.position.set(0.46 * s, -0.3, 0.06);
      lock.rotation.z = 0.08 * s;
      this.femaleParts.add(lock);
    }
    this.femaleParts.add(backHair);
    this.head.add(this.femaleParts);
    this.lashes = [];

    // 眼睛（以群組縮放 y 做眨眼與瞇眼）
    this.eyes = [];
    for (const s of [-1, 1]) {
      const eye = new THREE.Group();
      eye.position.set(0.18 * s, 0.03, 0.42);
      const white = new THREE.Mesh(new THREE.SphereGeometry(0.095, 20, 16), mat(0xffffff, { roughness: 0.4 }));
      white.scale.set(1, 1.05, 0.5);
      const pupil = new THREE.Mesh(new THREE.SphereGeometry(0.055, 16, 12), mat(0x1b1b24, { roughness: 0.3 }));
      pupil.position.set(0, 0, 0.035);
      pupil.scale.set(1, 1, 0.5);
      const glint = new THREE.Mesh(new THREE.SphereGeometry(0.016, 8, 8), mat(0xffffff, { roughness: 0.2 }));
      glint.position.set(0.02 * s, 0.02, 0.06);
      eye.add(white, pupil, glint);
      // 睫毛：放在眼睛群組上緣，眨眼時會跟著眼睛一起闔上
      const lash = new THREE.Mesh(new THREE.CapsuleGeometry(0.012, 0.15, 4, 8), mat(0x1b1b24));
      lash.rotation.z = Math.PI / 2 + 0.12 * s;  // 外側微微上揚
      lash.position.set(0.02 * s, 0.088, 0.03);
      eye.add(lash);
      this.lashes.push(lash);
      this.head.add(eye);
      this.eyes.push(eye);
    }

    // 眉毛
    this.brows = [];
    this.mBrow = mat(0x3a2a1c);
    for (const s of [-1, 1]) {
      const brow = new THREE.Mesh(new THREE.CapsuleGeometry(0.018, 0.12, 4, 8), this.mBrow);
      brow.rotation.z = Math.PI / 2;     // 橫放
      const holder = new THREE.Group();
      holder.position.set(0.18 * s, 0.17, 0.43);
      holder.add(brow);
      this.head.add(holder);
      this.brows.push({ holder, brow, side: s });
    }

    // 臉頰紅暈
    this.blushes = [];
    for (const s of [-1, 1]) {
      const m = new THREE.Mesh(
        new THREE.SphereGeometry(0.06, 12, 10),
        new THREE.MeshBasicMaterial({ color: 0xff7f8f, transparent: true, opacity: 0 })
      );
      m.scale.set(1.3, 0.8, 0.3);
      m.position.set(0.28 * s, -0.1, 0.4);
      this.head.add(m);
      this.blushes.push(m);
    }

    // 嘴巴：深色橢圓（張口）＋弧線（嘴角表情）
    this.mouthGroup = new THREE.Group();
    this.mouthGroup.position.set(0, -0.2, 0.44);
    this.mouthOpen = new THREE.Mesh(new THREE.SphereGeometry(0.075, 20, 14), mat(0x4a1418, { roughness: 0.5 }));
    this.mouthOpen.scale.set(1, 0.02, 0.35);
    this.lip = new THREE.Mesh(new THREE.TorusGeometry(0.1, 0.011, 6, 24, Math.PI), (this.mLip = mat(0x9a3f45)));
    this.lip.position.z = 0.012;
    this.mouthGroup.add(this.mouthOpen, this.lip);
    this.head.add(this.mouthGroup);

    // 鼻子
    const nose = new THREE.Mesh(new THREE.SphereGeometry(0.03, 12, 10), this.mSkin);
    nose.scale.set(1, 0.8, 0.8);
    nose.position.set(0, -0.06, 0.475);
    this.head.add(nose);
  }

  // ---------------------------------------------------------------- 公開 API
  setPersona(name) {
    const p = PERSONAS[name] || PERSONAS[DEFAULT_PERSONA];
    this.personaName = PERSONAS[name] ? name : DEFAULT_PERSONA;
    this.persona = p;
    this.mHair.color.setHex(p.hair);
    this.mSkin.color.setHex(p.skin);
    this.mSkinNeck.color.setHex(p.skin);
    this.mShirt.color.setHex(p.shirt);
    this.mBrow.color.setHex(new THREE.Color(p.hair).multiplyScalar(0.6).getHex());
    for (const b of this.brows) b.brow.scale.set(1, p.browThick, p.browThick);
  }

  /** 'female' | 'male'：切換內建卡通角色的女生配件（VRM 由 tryLoadVrm 依性別挑選）。 */
  setGender(g) {
    this.gender = g === 'male' ? 'male' : 'female';
    const female = this.gender === 'female';
    this.femaleParts.visible = female;
    for (const l of this.lashes) l.visible = female;
    this.mLip.color.setHex(female ? 0xd25a6e : 0x9a3f45);
  }

  setEmotion(name) {
    const e = EMOTIONS[name] ? name : 'neutral';
    this.emotionName = e;
    this.target = { ...EMOTIONS[e] };
    this.vrmEmotion = e;
  }

  setFixedMouth(v) { this.fixedMouth = v; }

  /** 依性別找模型（找到第一個就用；同名時 .vrm 優先於 .glb）：
   *  女生：female_<性格> → female → default；男生：male_<性格> → male。
   *  都沒有時顯示內建卡通角色。成功載入模型回傳 true。 */
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
      if (!url) { this._showProcedural(); return false; }
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
        if (!gltf.userData.vrm) { this._showProcedural(); return false; }
        this._useVrm(gltf.userData.vrm, vrmLib);
      } else if (!this._useGlb(gltf.scene)) {
        this._showProcedural();
        return false;
      }
      this.modelUrl = url;
      this._frameVrm();
      return true;
    } catch (err) {
      console.warn('模型載入失敗，改用內建角色：', err);
      if (seq === this._loadSeq) this._showProcedural();
      return false;
    }
  }

  _useVrm(vrm, vrmLib) {
    vrmLib.VRMUtils.rotateVRM0?.(vrm);
    this._removeModel();
    this.root.visible = false;
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

  /** 使用一般 .glb：找出有臉部控制點的網格與 Mixamo 命名的骨骼。沒有 jawOpen 視為不支援。 */
  _useGlb(scene) {
    const meshes = [];
    scene.traverse((o) => {
      if (o.isMesh && o.morphTargetDictionary) meshes.push(o);
      if (o.isMesh) o.frustumCulled = false;   // 蒙皮網格的包圍盒不準，避免拉近時整塊消失
    });
    if (!meshes.some((m) => 'jawOpen' in m.morphTargetDictionary)) {
      console.warn('這個 .glb 沒有 ARKit 臉部控制點（jawOpen），改用內建角色');
      return false;
    }
    const bone = (name) => scene.getObjectByName(name) || scene.getObjectByName('mixamorig' + name);
    this._removeModel();
    this.root.visible = false;
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

  /** 改回內建卡通角色，並把鏡頭還原成卡通角色的取景。 */
  _showProcedural() {
    this._removeModel();
    this.root.visible = true;
    this.camera.position.set(0, 0.2, 4.2);
    this.camera.lookAt(0, -0.1, 0);
    const c = this.renderer.domElement;
    this.resize(c.clientWidth, c.clientHeight);
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
    // 窄螢幕（直向手機）時把鏡頭拉遠，避免頭被裁切
    else this.camera.position.z = w / h < 0.9 ? 4.2 / Math.max(0.62, w / h) * 0.82 : 4.2;
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
    else this._updateProcedural(dt, blink);

    this.renderer.render(this.scene, this.camera);
  }

  _updateProcedural(dt, blink) {
    const k = 1 - Math.exp(-9 * dt);
    for (const key of Object.keys(this.target)) this.cur[key] += (this.target[key] - this.cur[key]) * k;
    const c = this.cur;
    const p = this.persona;

    // 眼睛
    const eyeScale = Math.max(0.05, c.eyeOpen * (1 - blink * 0.95));
    for (const e of this.eyes) e.scale.set(1, eyeScale, 1);

    // 眉毛
    for (const b of this.brows) {
      b.holder.position.y = 0.17 + c.browY;
      // 左眉(side=-1)內側在右：負角度=內側下壓；右眉鏡像
      b.holder.rotation.z = (c.browAngle + p.browBase) * (b.side === -1 ? 1 : -1);
    }

    // 臉頰
    for (const m of this.blushes) m.material.opacity = c.blush * 0.55;

    // 嘴巴：張口 = 情緒基礎張口 + 說話音量
    const open = clamp(c.openBase + this.mouth * 0.95, 0, 1);
    this.mouthOpen.scale.set(c.mouthW * (1 + open * 0.15), 0.02 + open * 1.0, 0.35);
    const curve = c.curve;
    this.lip.rotation.z = curve > 0 ? Math.PI : 0;
    this.lip.scale.set(c.mouthW, Math.max(0.02, Math.abs(curve) * 0.55) * (1 - open * 0.9), 1);
    this.lip.position.y = curve > 0 ? 0.0 : -0.0;
    this.lip.visible = open < 0.6;

    // 待機動作：呼吸、輕微晃頭；說話時微點頭
    this.torso.scale.y = 1 + Math.sin(this.t * 1.6) * 0.012;
    this.head.rotation.y = Math.sin(this.t * 0.55) * 0.06;
    this.head.rotation.z = Math.sin(this.t * 0.42) * 0.015;
    this.head.rotation.x = Math.sin(this.t * 0.8) * 0.02 + this.mouth * 0.05;
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
