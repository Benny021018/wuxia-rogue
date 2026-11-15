# 怪物動作

遊戲依敵人 ID 載入 `assets/models/enemy-motion/<ID>.glb`。20 隻敵人共使用 113 個片段；相同來源用於不同敵人時分開計數。動作清單、每段的秒數、節奏與來源名稱見 [enemy_motion.csv](../data/enemy_motion.csv)。`beat` 為目標時間比例，`source_beat` 為此刻對應的來源時間比例。來源相同的動作可分別微調。

## 來源與修改

- Quaternius 的 Universal Animation Library 1、2 Standard 提供人形骨架與動作，專案已有這兩份來源 GLB。行屍使用屍步與抓擊，煉屍門徒使用施法，血刀客使用揮砍與突進。依每種敵人的行為取樣並重定時。授權為 CC0。[UAL 1](https://quaternius.com/packs/universalanimationlibrary.html) · [UAL 2](https://quaternius.com/packs/universalanimationlibrary2.html)
- Kay Lousberg 的 KayKit Character Animations Free 1.1 提供山賊弓手的待機、拉弓與放箭。烘焙時將拉弓與放箭合併為 Shoot，弦離手的片段時間為 1.15 秒；遊戲依山賊弓手的實際瞄準與收勢時間驅動這段動畫。授權為 CC0。[作者頁](https://kaylousberg.com/game-assets/character-animations) · [下載檔鏡像](https://github.com/MightyBubble/Ludots-Assets/blob/main/animations/KayKit-Character-Animations-Free-1.1.zip)
- 黑羽鷹以 OpenGameArt 的 CC0 鴿型骨架製作。拍翼用於盤旋；俯衝加快拍翼並調整動作節奏；死亡收足，飛行路徑由遊戲 AI 控制。這是一隻以鴿型代演的黑色飛禽。[作者發布頁](https://opengameart.org/content/low-poly-3d-pigeon-model-rigged-animated-untextured) · [Blender 原檔](https://opengameart.org/sites/default/files/genuinely-my-pigeon-extended-furthur.blend)

## 在動作臺修改

選擇中文怪物名稱，在「角色自带」選動作。Idle／Walk 為待機與移動，Slash／Shoot 為近戰與遠攻，Hit／Death 為受擊與死亡；其餘依怪物包含 Dash、Charge、Dive、Leap、Summon、Burst 或 Realm。動作臺的「匹配动作」會提出其他怪物相容的動作，這些不屬於所選怪物的遊戲片段。

十九隻人形敵人的外觀由 `tools/build_enemy_bodies.py` 以 Quaternius 的 Universal Base Characters 與 Modular Character Outfits - Fantasy（CC0）組成：服裝（布衣、獵裝、兜帽）、頭、髮型與上色設定在 `data/enemy_looks.csv`。這兩包跟 Universal Animation Library 同一套 65 骨骨架，動作直接套用；只轉移骨頭旋轉（`root`、`pelvis` 以外不轉移位移），保留各身體自己的骨長。黑羽鷹沿用鴿型模型。遊戲另行處理命中、擊退、浮空、範圍預警、粒子與手持兵器。片段的模型預覽只播放骨架。審閱工作區保留獨立副本；採用候選後，更新對應 ID 的遊戲 GLB，再跑冒煙測試。直接重跑烘焙會重建遊戲 GLB，已有手修版本時應先保存。

## 重建

先以 `python3.11 tools/build_enemy_bodies.py <素材資料夾>` 產生 `assets/models/enemy-bodies/`（見 `assets/models/CREDITS.md`），再以 Python、NumPy、SciPy 執行 `python tools/bake_enemy_motion.py <來源目錄>`。山賊弓手的待機與拉弓標成 `legacy:` 片段，從來源目錄的 `H02_legacy.glb`（舊版十六骨弓手，可從 git 歷史取出）轉移到新骨架。來源目錄中可另外放入以下檔案。

- `ranged.glb` 取自 KayKit 套件的 `Animations/gltf/Rig_Medium/Rig_Medium_CombatRanged.glb`。下載 ZIP 的 SHA-256 為 `65882f31f905ad2e953819648a59287cdeab8f623908d5ef701971d3758be20f`。
- `bird.glb` 以 Blender 從上列鴿型原檔匯出，只選取 pigeon-armature 與 pigeon-model，以 NLA Tracks 各自匯出 flap-wings-animation、idle-animation、legs-up-animation 三個同名片段。原始 .blend 的 SHA-256 為 `a02f6b2a327dba85edb4a2b31904351e59bbd367519a3b703cd9a934495a8643`。

