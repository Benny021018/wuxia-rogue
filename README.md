# 天魔劫：武俠 Roguelike（灰盒原型）

韓漫武俠風格的 3D 第一人稱地圖探索 Roguelike。十年前天魔神教血洗中原，如今天魔復活；主角一路闖過綠林山寨、暗月樓、屍門鬼谷，殺上天魔神教總壇。4 張地圖 × 5 個區域，進入區域即「鎖陣」，殺光敵人「破陣」，在悟道碑轉動「天機輪」免費參悟三選一（中線決定門派、三個悟觸發頓悟，機率全部窮舉驗證並在遊戲中公示）；殺敵吸納真氣，衝擊奇經八脈的 61 個穴位；每全通一條經脈就突破一個境界（三流到自然境，共九境）。

## 天機輪：機率模型與驗證

悟道碑的「天機輪」是一個 3 軸小型轉輪，轉出的結果決定這次三選一的候選（門派、稀有度、免費參悟）。我把它當成一個老虎機數學題來做：先寫規格，再算精確理論，最後拿遊戲本身的程式碼去對照。

| 項目 | 內容 |
|---|---|
| 規則 | 3 軸 × 3 列、中線判定。前兩軸同門＝門派感應；三軸同門（八卦百搭）＝門派共鳴，三張候選都出該門派且升一階；三個八卦＝八卦歸一，必出一張絕世；畫面任意 3 個「悟」＝頓悟，送 3 次免費參悟、可再觸發 |
| 回報口徑 | 「天機回報」＝一次參悟次數拿到的候選稀有度預算總和（凡品 1／良品 2.2／神兵 5／絕世 12），含免費參悟；起始狀態，不含幸運與保底 |
| 精確理論 | 窮舉 8,000 種停輪組合：頓悟 p = 27/1000，期望總轉數 1/(1−3p) = 1.0881，**天機回報 6.5105**，σ = 3.61（分支過程推導） |
| 回報拆分 | 基本 86.4%、門派共鳴 5.4%、八卦歸一 0.1%、頓悟 8.1% |
| 蒙地卡羅 | 50 萬次、5 個種子：6.5121，95% CI [6.5021, 6.5221]，z = +0.31 |
| 對照遊戲實作 | 609 組黃金盤面逐一比對 GDScript 判定（100% 一致）；遊戲內機率公示自己窮舉，等於模型精確值；遊戲亂數實轉 2 萬次；`roll_choices()` 用固定種子實抽候選，平均預算對理論的 z 值在 −0.90 到 +1.23 之間 |
| 抓到的錯 | 第一版模型把門派共鳴的三張候選當成獨立升階，但遊戲是從同一門派的武學池不重複抽，抽完會往下退。少林、唐門只有 1 門神兵，影響最大。修正後門派共鳴的貢獻少了 12%，總回報少了 0.8%；舊模型對遊戲實抽的 z 值是 −6.96 到 −16.39 |

- 完整報告：[`docs/shrine-math/report.md`](docs/shrine-math/report.md)；所有數字：[`results.json`](docs/shrine-math/results.json)
- 模型程式：[`tools/shrine_math/wheel.py`](tools/shrine_math/wheel.py)（只用標準函式庫，約 3 秒跑完）
- 遊戲實作：[`scripts/game.gd`](scripts/game.gd) 的 `wheel_*` 與 `roll_choices()`；對照測試在 [`tests/smoke_test.gd`](tests/smoke_test.gd) 的 `_check_wheel()`
- 參數全部在 `data/wheel_*.csv`，輪帶由 `tools/shrine_math/make_reels.py` 用固定種子產生（保證每軸畫面最多一個悟）
- 推到 main 或開 PR 時，GitHub Actions 會先跑數學模型、再跑冒煙測試（`.github/workflows/smoke-test.yml`）

```
python3 tools/shrine_math/wheel.py      # 理論＋模擬＋黃金樣本＋報告
godot --headless --path . --import && godot --headless --fixed-fps 60 --path . res://tests/Smoke.tscn
```

## 開啟方式

1. 安裝 **Godot 4.3 以上**（標準版即可，不需要 .NET）。
2. Godot 專案管理器 →「匯入」→ 選這個資料夾裡的 `project.godot`。
3. 第一次開啟會匯入資源，完成後按 F5 執行。

## 快速執行（Windows）

- `run_game.bat`：直接開始遊戲
- `run_tests.bat`：無頭模式跑自動冒煙測試，結果寫在 `tests/smoke.log`，最後一行應為 `SMOKE_DONE errors=0`
- `res://tests/UICapture.tscn`：依序打開各畫面截圖到 `user://ui_capture/`，對照設計稿用（需要有畫面，不能 `--headless`）

兩個批次檔預設使用 `..\Godot\` 裡的 Godot 4.7.1。若 Godot 放在別處，請設定環境變數 `GODOT`（console 版）和 `GODOT_GUI`。

## 操作

| 按鍵 | 功能 |
|---|---|
| WASD／滑鼠 | 移動／視角 |
| 空白鍵 | 跳躍（可跳上 1 公尺高台） |
| Shift | 衝刺（0.2 秒無敵） |
| 左鍵 | 用手上的武器出招；弓：按住拉弓、放開射出 |
| 右鍵 | 弓：瞄準（視角放大） |
| Q／滑鼠滾輪 | 切換主武器、副武器（同時只用一把） |
| 1／2 | 直接拿主武器／副武器 |
| E | 在悟道碑參悟、找鐵匠／商人、撿武器 |
| K | 奇經八脈・衝穴（A／D 換經脈、空白鍵衝擊） |
| Tab | 武學與門派面板 |
| Esc | 暫停 |

## 專案結構

```
project.godot
scenes/Main.tscn          只有一個節點，其餘全部由程式產生
scripts/
  data.gd                 （自動載入 Data）讀取 data/ 的所有 CSV 與 zones.json
  game.gd                 （自動載入 Game）一局的狀態：真氣與穴位、銀兩、武器、武學、門派、屬性彙總、參悟抽獎
  main.gd                 畫面流程：選單 → 角色 → 遊戲 → 結算
  world.gd                依 zones.json 搭灰盒地圖；鎖陣、分波出怪、破陣、悟道碑、換圖
  player.gd               第一人稱移動、主副武器切換、受傷流程、所有武學／門派／境界的戰鬥效果
  enemy.gd                20 種敵人的 AI 與首領技能
  projectile.gd           投射物（距離判定，不用物理）
  hazard.gd               毒池、毒霧、火、斷崖等持續傷害區
  fx.gd                   材質、浮動傷害數字、預警圈
  ui/                     HUD、參悟三選一、主選單／角色選擇／暫停／面板／結算
    ui_kit.gd             （UIKit）配色、字型、主題與元件工廠
    comic_*.gd            條漫風元件：旁白／系統框、斜切按鈕、斜尾條、朱印、集中線與刀光
assets/fonts/             隨遊戲附帶的 Noto Serif／Sans TC 裁切字型（OFL，見 OFL.txt）
assets/models/npc/        休息區的鐵匠鋪與商人攤（Blender 以 tools/build_rest_stops.py 搭建並匯出）
docs/ui-drafts/           介面 SVG 設計稿（tools/build_ui_drafts.py 產生）
data/                     與數值平衡腳本共用的 CSV（.import 設為 keep，不會被當成翻譯檔）
```

## 修改數值

所有數值都在 `data/` 的 CSV 裡，改完直接重新執行遊戲即可：

- 敵人血量、傷害、獎勵：`enemies.csv`、`combat_config.csv`
- 每區的怪物組成、數量、波數：`stages.csv`、`stage_report.csv`
- 武器、武學、門派傳承：`weapons.csv`、`martial_arts.csv`、`sect_bonds.csv`
- 抽獎機率、保底、價格：`rarity.csv`、`gacha_config.csv`
- 武器詞條、掉落機率、鐵匠與商人價格：`weapon_affixes.csv`、`shop_config.csv`
- 地圖配置（與設計畫布同一份）：`zones.json`

改完數值建議回到數值專案跑一次 `calibrate_all.sh`，重新校準經濟與各區強度。

武器、詞條、掉落、鐵匠與商人的整局模擬在 `tools/balance/sim.py`（只用 Python 標準函式庫）：

```
python3 tools/balance/sim.py --runs 1000                       # 新舊規則逐區比較、銀兩去向、掉落數
python3 tools/balance/sim.py --set drop_chance_minion=0.02      # 試算單一參數，不改 CSV
```

舊規則取自改版前的 commit（`--old-rev`，預設 440139b），新規則取自目前的 `data/`；以 `stage_report.csv` 的目標秒數為錨點換算清場時間。

## 實作範圍

**已實作**
- 3 名角色的被動與 9 個境界效果
- [17 把武器的模型與第一人稱出招預覽](docs/weapon-art.md)
- 17 把武器：近戰扇形、中距離直線、遠程投射物，以及淬煉 +15%／級
- 主武器／副武器：同時只用一把，切換有短暫收出時間（`combat_config.csv` 的 `weapon_swap_s`）
- 所有兵器同一品質（有效 DPS 統一為 100，差別只在打法）；起手兵器（`weapons.csv` 的 `starter`）沒有詞條；打怪隨機掉落帶詞條的兵器（`weapon_affixes.csv`），只有手上那把的詞條生效，走過去按 E 撿起
- 每張地圖第 4 區破陣後出現鐵匠（強化淬煉、重鑄詞條）與商人（隨機上架武學）；機率與價格在 `shop_config.csv`、`rarity.csv` 的 `martial_price`、`stages.csv` 的 `rest_stop`
- [條漫風介面](docs/ui-drafts/README.md)：參考韓式武俠條漫的旁白框、系統框、狀聲詞與集中線
- 38 門武學的 Lv1–5 數值成長
- 大部分小成／圓滿特效
- 5 個門派共 15 階門派傳承
- 20 種敵人的專屬機制與 4 個首領
- 抽獎：幸運、軟保底與硬保底、已擁有加權、門派加權
- 真氣衝穴與境界突破、20 個區域的鎖陣流程、換圖、死亡與通關結算

**目前只有文字、尚未實作效果**
- 武器的器靈覺醒（+5）
- 部分小成／圓滿特效：金鐘罩・圓滿、鐵布衫、旋風掌、望氣術・圓滿、頓悟心法以外的部分、連環腿・小成、踏雪無痕・圓滿、雷霆劍訣與移花接木的突破、腐骨掌的突破、萬劍歸宗的突破、金剛伏魔掌的突破
- 影刃落地刀氣的減速

**簡化之處**
- 地面追擊依房間障礙與體型尋路，近戰遇隊友擋路會從側面接近；飛行、跳撲與衝刺沿用各自的移動規則。弓手、毒鏢手及毒瓶手會移動到有射線的位置，地形也能攔截已發射的敵方投射物。
- 斷崖以高傷害區域代替墜落

## 測試狀態

已在 Godot 4.7.1（Windows）上驗證：
- 冒煙測試：三名角色各自跑完 4 張地圖、20 個區域，並測過全部 17 把武器、38 門武學圓滿、參悟、受傷流程與所有介面畫面，結果為 0 錯誤。
- 實機遊玩：主選單、角色選擇、進區鎖陣、射擊擊殺、修為累積、死亡結算皆正常。

## 協作

AI 協作規則寫在 `AGENTS.md`（Codex 會自動讀取；Claude 經由 `CLAUDE.md` 讀取）。GitHub Actions 會在每次 push 或 PR 時自動跑冒煙測試（`.github/workflows/smoke-test.yml`）。

## 天機輪機率模型

悟道碑的參悟改成三軸「天機輪」，數學規格、窮舉理論值、蒙地卡羅驗證與 Python／GDScript 黃金測試見 `docs/shrine-math/report.md`，重跑：
```
python3 tools/shrine_math/wheel.py      # 窮舉 8000 種停輪＋50 萬次模擬，輸出 results.json、report.md、tests/wheel_golden.json
python3 tools/shrine_math/make_reels.py # 依 wheel_config.csv 的種子重排輪帶
```
冒煙測試會比對 609 組黃金停輪，並以遊戲 RNG 轉 2 萬次做 z 檢定。
