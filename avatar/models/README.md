# 3D 角色模型

演練前可選「女生／男生」。程式會在這個資料夾依序找模型，找到第一個就用（同名時 `.vrm` 優先於 `.glb`）：

| 性別 | 尋找順序 |
|---|---|
| 女生 | `female_<性格>` → `female` → `default` → 內建卡通女生 |
| 男生 | `male_<性格>` → `male` → 內建卡通男生 |

- `<性格>` 為：強勢直率、敏感玻璃心、情緒勒索、開門見山、一般友善。例如 `male_強勢直率.glb`。
- `default` 視為**女生**模型，選男生時不會使用它。
- 放好後在瀏覽器按 Ctrl+F5 重新整理即可，不需重啟後端。
- 單獨測試：開 `/avatar/index.html?gender=female&model&emotion=happy&mouth=0.5`。

## 目前內建的模型
| 檔案 | 來源 | 授權 |
|---|---|---|
| `female.glb` | [TalkingHead](https://github.com/met4citizen/TalkingHead) 的 `avatars/mpfb.glb`（以 Blender + MPFB 製作），用 `tools/shrink_glb.py` 縮小：37 MB → 8 MB | CC0（公眾領域，可公開、可商用） |

## 支援的格式
- **寫實 `.glb`**：需含 **ARKit 臉部控制點**（至少 `jawOpen`，另有 `mouthSmileLeft`、`browDownLeft`、`eyeBlinkLeft`…會用來做表情與眨眼），
  骨架為 **Mixamo 命名**（`Head`、`Spine1`、`LeftArm`、`LeftForeArm`…，可有 `mixamorig` 前綴）。沒有 `jawOpen` 的 .glb 會改用內建角色。
- **動漫風 `.vrm`**：需含表情（happy / angry / sad / surprised）、`aa` 嘴型與 `blink`，VRoid 匯出的模型預設都有。
  `.vrm` 預設不上傳 GitHub（見 `.gitignore`），因為 VRoid Hub 的模型授權多半禁止再散布。

## 去哪取得
- **可公開使用**：Microsoft Rocketbox（MIT，115 個寫實人物，需用 Blender 轉成 GLB，TalkingHead 有轉換腳本）、
  MakeHuman / MPFB（CC0，自己在 Blender 捏人）。
- **限個人／非商業使用**：Avaturn（照片產生寫實人物；條款規定所有權屬 Avaturn、僅供個人使用、需標示來源），
  網站給別人用之前請先取得書面同意。
- **請先確認授權允許你的用途**（個人／商用、能否修改、是否要標示作者）。

## 建議規格（手機瀏覽器才順暢）
- 檔案約 10 MB 以下，貼圖 1024 像素左右，面數幾萬以內。
- 太大的 .glb 可用 `python tools/shrink_glb.py 原檔.glb 輸出.glb` 縮小（需要 Pillow）。
