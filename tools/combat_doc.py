"""由 data/moves.csv、move_hits.csv、combat_state_config.csv 產生 docs/combat-design.md。

    python3 tools/combat_doc.py
"""
import csv
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
rd = lambda n: list(csv.DictReader((ROOT / "data" / f"{n}.csv").open(encoding="utf-8")))
moves, hits, cfg = rd("moves"), rd("move_hits"), {r["key"]: r for r in rd("combat_state_config")}
chars = {r["char_id"]: r for r in rd("characters")}
KEYS = {"attack": "左鍵", "skill1": "右鍵", "skill2": "Q", "skill3": "E", "skill4": "R", "skill5": "1", "skill6": "2", "skill7": "3", "ult": "V"}
WEAPON = {"nangong": "太刀", "han": "巨劍", "tang": "竹弓"}
STYLE = {"nangong": "快、連段長、擅長把敵人挑空追打；靠無敵招閃避，破霸體手段少（拔刀・一閃、大招）。",
         "han": "慢、每一下都重、出招大多帶霸體可以硬換；破霸體手段最多（衝撞、擒殺、大招）。",
         "tang": "遠程、靠陷阱與毒霧控場、近身用燕返脫離；破霸體靠穿雲箭與大招。"}
SELF = {"": "", "armor": "霸體", "invincible": "無敵"}
f = lambda v: ("%g" % float(v))
L = ["# 第三人稱戰鬥設計：狀態、招式表（tools/combat_doc.py 產生）", "",
     "數值都在 `data/moves.csv`、`data/move_hits.csv`、`data/combat_state_config.csv`，改完重跑這支工具。狀態邏輯在 `scripts/combat_state.gd`，玩家與敵人共用。", "",
     "## 1. 六種狀態", "",
     "| 狀態 | 能否操控 | 被打到會怎樣 | 怎麼結束 |", "|---|---|---|---|",
     "| 正常 | 可以 | 依招式進入受擊、浮空或倒地 | — |",
     "| 受擊 | 不行 | 重新計算硬直；浮空招照樣打浮空 | 硬直時間到 → 正常 |",
     f"| 倒地 | 不行 | **浮空**（至少彈起 {f(cfg['down_hit_launch_h_m']['value'])} 公尺） | {f(cfg['hit_down_time_s']['value'])} 秒內沒被打 → 起身無敵 {f(cfg['getup_invincible_s']['value'])} 秒 → 正常 |",
     "| 霸體 | 可以 | 照樣受傷並有頓幀，但不進入受擊；**破霸體**的招式會打斷 | 霸體時間到，或被破除 |",
     "| 無敵 | 可以 | 打不到、不受傷 | 無敵時間到 |",
     f"| 浮空 | 不行 | 再往上彈（每多一下高度 ×{f(cfg['juggle_decay']['value'])}） | 碰到地板 → 起身無敵 {f(cfg['getup_invincible_s']['value'])} 秒 → 正常 |", "",
     "每一下攻擊帶五個屬性：**硬直時間**、**是否浮空**、**浮空高度**、**是否破霸體**、**是否擊倒**。前四個是需求指定的；「擊倒」是我加的，因為浮空落地會直接起身，需要有招式能讓站著的目標進入倒地。", "",
     "補充規則：", "",
     f"- 浮空中被不帶浮空的招式打到，會小彈 {f(cfg['air_hit_pop_h_m']['value'])} 公尺；彈起高度衰減到 {f(cfg['juggle_min_h_m']['value'])} 公尺以下就不再托得住，避免無限連。",
     f"- 精英與首領常駐霸體；被破除後有 {f(cfg['armor_break_s']['value'])} 秒空窗，這段時間可以打出硬直、浮空、倒地。精英硬直 ×{f(cfg['hitstun_elite_mult']['value'])}、首領 ×{f(cfg['hitstun_boss_mult']['value'])}。",
     f"- 大招靠怒氣：命中 +{f(cfg['rage_per_hit']['value'])}、受擊 +{f(cfg['rage_per_hurt']['value'])}，集滿 {f(cfg['rage_max']['value'])} 可放。技能只受冷卻限制，開局全部可用。",
     "- 敵人的攻擊同樣帶這五個屬性，玩家也會被打出硬直、浮空、倒地。", "",
     "## 2. 操作", "",
     "| 按鍵 | 功能 |", "|---|---|", "| WASD／滑鼠 | 移動／轉動鏡頭（第三人稱，鏡頭在角色後上方） |", "| 左鍵 | 普攻（連按接下一段；唐七按住拉弓） |",
     "| 右鍵、Q、E、R、1、2、3 | 技能一～七 |", "| V | 大招 |", "| Shift | 閃避（短暫無敵） |", "| 空白鍵 | 跳 |", "| F | 互動（參悟、鐵匠、商人；原本的 E 讓給技能） |", "| K | 經脈 |", "",
     "裝備改動：拿掉選兵器、武器掉落、主副武器切換與天機輪的武器候選；南宮逸固定太刀、韓天狼固定巨劍、唐七固定竹弓。鐵匠改為強化角色的固定兵器。", "",
     "## 3. 招式表", "", "傷害是基礎攻擊力的百分比（初版數值，接進遊戲後需要重新校準）。", ""]
by = {}
for h in hits:
    by.setdefault(h["move_id"], []).append(h)
for cid in ("nangong", "han", "tang"):
    L += [f"### {chars[cid]['name_zh']}（{WEAPON[cid]}）", "", STYLE[cid], "",
          "| 按鍵 | 招式 | 冷卻 | 自身狀態 | 段數×傷害 | 硬直 | 浮空 | 破霸體 | 擊倒 | 說明 |", "|---|---|---|---|---|---|---|---|---|---|"]
    for m in [m for m in moves if m["char_id"] == cid]:
        hs = by.get(m["move_id"], [])
        dm = "—"
        if hs:
            ds = [f(h["dmg_pct"]) for h in hs]
            dm = f"{len(ds)}×{ds[0]}%" if len(set(ds)) == 1 else "＋".join(sorted(set(f"{ds.count(d)}×{d}%" for d in ds), key=lambda s_: -int(s_.split('×')[0])))
        stun = "—" if not hs else "～".join(sorted({f(h["hitstun_s"]) for h in hs}, key=float)) + " 秒"
        la = [h for h in hs if h["launch"] == "1"]
        launch = "—" if not la else "～".join(sorted({f(h["launch_h_m"]) for h in la}, key=float)) + " m"
        br = "✓" if any(h["break_armor"] == "1" for h in hs) else ""
        kd = "✓" if any(h["knockdown"] == "1" for h in hs) else ""
        ss = SELF[m["self_state"]]
        if ss:
            ss += f" {f(m['self_from_s'])}–{f(m['self_to_s'])} 秒"
        cd = "—" if float(m["cooldown_s"]) == 0 else f(m["cooldown_s"]) + " 秒"
        if m["slot"] == "ult":
            cd = "怒氣滿"
        key = KEYS[m["action"]] + (f"（第 {m['slot'][-1]} 段）" if m["slot"].startswith("normal") else "")
        L.append(f"| {key} | {m['name_zh']} | {cd} | {ss} | {dm} | {stun} | {launch} | {br} | {kd} | {m['desc']} |")
    L.append("")
L += ["## 4. 實作順序", "",
      "1. ✅ 狀態邏輯（`CombatState`）、招式資料與冒煙測試",
      "2. 第三人稱鏡頭與角色模型（Quaternius 通用假人，CC0），移動、閃避、跳躍動作",
      "3. 南宮逸：普攻四段、七技能、大招，全部接上狀態、打擊感與音效",
      "4. 敵人接上六種狀態（挑空、倒地追打、精英首領霸體），敵人的攻擊補上五個屬性",
      "5. 拿掉選兵器／掉落／主副武器，調整鐵匠、天機輪、介面與按鍵說明",
      "6. 韓天狼、唐七", "",
      "## 5. 動作來源與預覽", "",
      "- 模型與初版動作：Quaternius Universal Animation Library 1、2（CC0）。UE5 假人依 Epic 授權只能在 Unreal 引擎內使用，所以不採用。",
      "- 動作預覽與修改：MotionStage（https://github.com/jbang2004/motion-stage，MIT）。需要在你的電腦上執行（Node.js 22+）：`node skill/scripts/start.mjs --project <遊戲資料夾>`，在瀏覽器裡播放動作、暫停標記問題，再把任務交給我修改。"]
(ROOT / "docs" / "combat-design.md").write_text("\n".join(L) + "\n", encoding="utf-8")
print(len(L), "行")
