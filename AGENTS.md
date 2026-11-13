# AGENTS.md — 給 AI 協作者（Codex、Claude 等）的專案規則

這是 Godot 4（GDScript）的 3D 第一人稱武俠 Roguelike 灰盒原型。動手前先讀完這份檔案和 README.md。

## 架構
- `scenes/Main.tscn` 只有一個節點；場景、介面全部由程式產生。不要新增手寫的 .tscn，除非有充分理由。
- 自動載入：`Data`（scripts/data.gd，讀 CSV）、`Game`（scripts/game.gd，一局的狀態與抽獎）、`Settings`（設定與音量匯流排）、`Music`（配樂）、`Sfx`（音效）、`Feel`（頓幀與震屏）。
- 音效與配樂都由程式產生：`tools/sfx/make_sfx.py`、`tools/music/`；播放設定在 `data/sfx.csv`、`data/music.csv`。新增遊戲事件時用 `Sfx.play(id, 位置)`，id 要先加進 sfx.csv 與 make_sfx.py。打擊感數值在 `data/feel_config.csv`。
- 戰鬥正在改成第三人稱（設計見 `docs/combat-design.md`）：六種狀態的邏輯在 `scripts/combat_state.gd`（玩家與敵人共用），招式與每一下的硬直／浮空／破霸體／擊倒在 `data/moves.csv`、`data/move_hits.csv`，改完跑 `tools/combat_doc.py` 更新文件。
- `world.gd` 依 `data/zones.json` 搭地圖；`player.gd` 負責所有戰鬥效果；`enemy.gd` 依 enemy_id 實作怪物機制。
- 武器分主武器（`Game.weapons[0]`）與副武器（`[1]`），同時只用 `Game.active_weapon` 那一把。
- 介面一律用 `UIKit` 與 `scripts/ui/comic_*.gd` 元件，版面依 `docs/ui-drafts/` 的 SVG 稿；`UIKit.at()` 直接吃 1600×900 稿面座標。CanvasLayer 會截斷主題繼承，新介面根節點要設 `theme = UIKit.theme()`。改介面後可跑 `res://tests/UICapture.tscn` 截圖對照。新增介面文字後重跑 `tools/subset_fonts.py`，否則缺字會退回系統字型。

## 規則
1. **數值一律放在 `data/*.csv`**，不要寫死在程式裡。新增欄位時同步更新讀取它的程式。
2. CSV 的 `.import` 檔必須保持 `importer="keep"`，否則 Godot 會把 CSV 當成翻譯檔匯入。
3. 數值平衡由另一個數值專案（balance_check.py、enemy_check.py、calibrate_all.sh）校準。改了敵人、武學、武器、經濟相關數值，要在 PR 說明裡註明「需要重新校準」。
4. GDScript 型別慣例：
   - 從 Dictionary 或無型別變數取值時，不要用 `:=` 推斷型別，改用 `var x: float = ...` 或無型別 `var x = ...`。
   - 指向其他節點的變數若會呼叫自訂方法，宣告成無型別（`var world`），不要宣告成 `Node`。
   - Control 全螢幕用 `set_anchors_and_offsets_preset()`，不要用 `set_anchors_preset()`。
   - 介面文字一律繁體中文，用語參考 `data/terminology.csv`（真氣、衝穴、參悟、鎖陣、破陣…）。
5. 每次修改後執行冒煙測試，必須輸出 `SMOKE_DONE errors=0`：
   ```
   godot --headless --path . --import
   godot --headless --fixed-fps 60 --path . res://tests/Smoke.tscn
   ```
   Windows 可直接執行 `run_tests.bat`。新增系統時，請在 `tests/smoke_test.gd` 加上對應的檢查。

## Git 流程
- 不要直接推 `main`。每項工作開一個分支（例如 `feature/weapon-awaken`、`fix/boss-hp`），用 PR 合併。
- Commit 訊息用繁體中文，第一行簡述做了什麼。
- 不要提交 `.godot/`、`tests/*.log`、匯出檔（見 .gitignore）。
