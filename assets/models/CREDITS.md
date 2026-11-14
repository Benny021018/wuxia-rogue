# 模型來源

| 用途 | 素材 | 作者 | 授權 |
|---|---|---|---|
| 主角模型與動作 | [Universal Animation Library 1、2](https://quaternius.com/packs/universalanimationlibrary.html)（`character/`） | Quaternius | CC0 1.0 |
| 敵人的頭、髮型、赤膊身體 | [Universal Base Characters](https://quaternius.itch.io/universal-base-characters)（Standard） | Quaternius | CC0 1.0 |
| 敵人的服裝（布衣、獵裝、兜帽） | [Modular Character Outfits - Fantasy](https://quaternius.itch.io/modular-character-outfits-fantasy)（Standard） | Quaternius | CC0 1.0 |
| 貨箱、板車、掩體、鐵匠鋪、商人攤 | [Fantasy Props MegaKit](https://quaternius.itch.io/fantasy-props-megakit)（Standard） | Quaternius | CC0 1.0 |
| 板車、石階 | [Medieval Village MegaKit](https://quaternius.itch.io/medieval-village-megakit)（Standard） | Quaternius | CC0 1.0 |
| 山賊弓手的拉弓動作（舊骨架片段轉移） | [KayKit Character Animations 1.1](https://kaylousberg.itch.io/kaykit-character-animations) | Kay Lousberg | CC0 1.0 |
| 黑羽鷹 | [Low poly pigeon](https://opengameart.org/content/low-poly-3d-pigeon-model-rigged-animated-untextured) | OpenGameArt | CC0 1.0 |

CC0 可商用、可修改，不需要標示作者；這份清單是給自己追溯來源用。

## 重建

素材包從 itch.io 下載 Standard 版後解壓到同一個資料夾（例如 `packs/`），需要 Blender 的 Python 模組（`python3.11 -m pip install bpy`）：

```
python3.11 tools/build_enemy_bodies.py packs/        # 敵人身體 → assets/models/enemy-bodies/（外觀在 data/enemy_looks.csv）
python3 tools/bake_enemy_motion.py <donors>           # 套上動作 → assets/models/enemy-motion/
python3.11 tools/build_props.py packs/                # 場景物件 → assets/models/greenwood/、npc/
```

`<donors>` 放 `H02_legacy.glb`（舊版山賊弓手，拉弓片段的來源，可從 git 歷史取出）；有 `bird.glb` 才會重做黑羽鷹。

寨門、拒馬、箭樓、擂台、迴廊、火盆、交椅、悟道碑還是原本的模型：素材包裡沒有風格合適的對應物件（只有歐式石屋與城牆）。
