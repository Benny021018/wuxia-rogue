# 介面 SVG 初稿

以韓式武俠條漫（《奈米魔神》）的視覺語彙為基準重做介面。只取語彙，不沿用該作角色與標題字；人物仍用本作立繪。

已定稿並實作進遊戲（`scripts/ui/`）。之後改介面先改稿、再改程式，並用 `res://tests/UICapture.tscn` 截圖對照。

| 稿 | 對應程式 |
|---|---|
| 00-style.svg 風格稿 | `scripts/ui/ui_kit.gd`（配色、按鈕、條） |
| 01-main-menu.svg 主選單 | `screens.gd` `show_main` |
| 02-character-select.svg 角色選擇 | `screens.gd` `show_select` |
| 03-hud.svg 戰鬥 HUD | `hud.gd` |
| 04-shrine.svg 悟道碑・參悟 | `gacha_ui.gd` |
| 05-martial-panel.svg 武學與門派 | `screens.gd` `show_inventory` |
| 06-pause.svg 暫停 | `screens.gd` `show_pause` |
| 07-result.svg 結算 | `screens.gd` `show_end` |
| 08-start-weapon.svg 選起手兵器 | `screens.gd` `show_weapon_pick` |
| 09-drop-compare.svg 掉落兵器比較 | `hud.gd` `show_drop_compare` |
| 10-smith.svg 鐵匠 | `shop_ui.gd` `open_smith` |
| 11-merchant.svg 商人 | `shop_ui.gd` `open_merchant` |
| 12-meridian.svg 奇經八脈・衝穴（A 案：正背面人形） | 待定稿（K 鍵） |
| 12b-meridian-scroll.svg 奇經八脈・衝穴（B 案：古卷打坐圖） | 待定稿 |
| 12c-meridian-pose.svg 奇經八脈・衝穴（定案：一脈一式剪影＋穴位星圖） | `meridian_ui.gd`、`meridian_chart.gd` |
| 12d-meridian-poses.svg 八脈八式一覽 | C 案的招式表 |
| 13-bow-aim.svg 弓・拉弓與瞄準 | `hud.gd` 紅圈準星 |
| 14-tianji-wheel.svg 悟道碑・天機輪（三軸石輪＋機率公示） | `gacha_ui.gd`、`wheel_reel.gd` |

## 語彙

- **配色**：墨黑底、血紅／橘紅（生命、敵方、標題）、電光青（系統、真氣、穴位、突破）、骨白（文字、框線）。冷黃只用在銀兩。
- **旁白框**：實心墨黑加內縮白線，用於區域名、劇情、結算句，襯線字。
- **系統框**：白底粗黑邊、四角缺角加青色外括弧，用於數值、提示、說明，黑體。戰鬥中改用暗版。
- **狀聲詞標題**：極粗襯線加乾筆毛邊與黑描邊，可傾斜；「鎖陣」配鋸齒吶喊泡泡。
- **分格**：斜切面板、刀光斜劈畫面、集中線、血點、火星。
- **稀有度**：色相沿用 `data/rarity.csv`，明度改配黑底（建議值見風格稿）。

黃色便條是稿面註記，不是介面。

## 重新產生

```
python3 tools/build_ui_drafts.py            # 全部
python3 tools/build_ui_drafts.py s03_hud    # 單張
```

卡片文字直接讀 `data/*.csv`；立繪與背景從 `assets/` 內嵌。字體依序用 Noto Serif／Sans CJK TC，沒有時退回新細明體與微軟正黑體，所以各機器上字形略有差異。遊戲內改用隨附的裁切字型（`assets/fonts/`，`tools/subset_fonts.py` 產生），各機器字形一致。
