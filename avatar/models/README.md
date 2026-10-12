# 3D 角色模型

演練前可選「女生／男生」。程式會在這個資料夾依序找模型，找到第一個就用（同名時 `.vrm` 優先於 `.glb`）：

| 性別 | 尋找順序 |
|---|---|
| 女生 | `female_<性格>` → `female` → `default` |
| 男生 | `male_<性格>` → `male` |

- `<性格>` 為：強勢直率、敏感玻璃心、情緒勒索、開門見山、一般友善。例如 `male_強勢直率.glb`。
- `default` 視為**女生**模型，選男生時不會使用它。
- 都找不到或載入失敗時，畫面顯示「角色載入失敗」（不再有卡通角色），對話與語音照常可用。
- 放好後在瀏覽器按 Ctrl+F5 重新整理即可，不需重啟後端。
- 單獨測試：開 `/avatar/index.html?gender=male&emotion=happy&mouth=0.5`。

## 目前內建的模型
| 檔案 | 來源 | 授權 |
|---|---|---|
| `female.glb` | [Microsoft Rocketbox](https://github.com/microsoft/Microsoft-Rocketbox) 的 `Adults/Female_Adult_15`（`_facial` 版） | MIT（可公開、可商用） |
| `male.glb` | Microsoft Rocketbox 的 `Adults/Male_Adult_02`（`_facial` 版） | MIT（可公開、可商用） |

轉檔方式（需要 Blender，以 Male_Adult_02 為例）：
```powershell
blender -b --python tools/rocketbox_to_glb.py -- Male_Adult_02/Export/Male_Adult_02_facial.fbx Male_Adult_02/Textures male_raw.glb
python tools/shrink_glb.py male_raw.glb avatar/models/male.glb    # 約 30 MB → 3 MB
```
換其他 Rocketbox 人物也是同樣兩行。Rocketbox 的授權全文在 `ROCKETBOX_LICENSE.md`（MIT 要求散布時附上）。

之前用過的 TalkingHead `mpfb.glb`（CC0）也相容，可用 `shrink_glb.py` 縮小後放進來。

## 支援的格式
- **寫實 `.glb`**：需含 **ARKit 臉部控制點**（至少 `jawOpen`，另有 `mouthSmileLeft`、`browDownLeft`、`eyeBlinkLeft`…會用來做表情與眨眼），
  骨架為 **Mixamo 命名**（`Head`、`Spine1`、`LeftArm`、`LeftForeArm`…，可有 `mixamorig` 前綴）
  或 **3ds Max Biped 命名**（Rocketbox 的 `Bip01 Head`、`Bip01 L UpperArm`…）。沒有 `jawOpen` 的 .glb 無法使用。
- **動漫風 `.vrm`**：需含表情（happy / angry / sad / surprised）、`aa` 嘴型與 `blink`，VRoid 匯出的模型預設都有。
  `.vrm` 預設不上傳 GitHub（見 `.gitignore`），因為 VRoid Hub 的模型授權多半禁止再散布。

## 去哪取得
- **可公開使用**：Microsoft Rocketbox（MIT，115 個寫實人物，用上面的 `tools/rocketbox_to_glb.py` 轉檔）、
  MakeHuman / MPFB（CC0，自己在 Blender 捏人）。
- **限個人／非商業使用**：Avaturn（照片產生寫實人物；條款規定所有權屬 Avaturn、僅供個人使用、需標示來源），
  網站給別人用之前請先取得書面同意。
- **請先確認授權允許你的用途**（個人／商用、能否修改、是否要標示作者）。

## 建議規格（手機瀏覽器才順暢）
- 檔案約 10 MB 以下，貼圖 1024 像素左右，面數幾萬以內。
- 太大的 .glb 可用 `python tools/shrink_glb.py 原檔.glb 輸出.glb` 縮小（需要 Pillow）。
