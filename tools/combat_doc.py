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
WEAPON = {"nangong": "太刀", "han": "巨劍", "tang": "柳葉飛刀"}
STYLE = {"nangong": "快、連段長、擅長把敵人挑空追打；靠無敵招閃避，破霸體手段少（拔刀・一閃、大招）。",
         "han": "慢、每一下都重、出招大多帶霸體可以硬換；破霸體手段最多（衝撞、擒殺、大招）。",
         "tang": "遠程、靠陷阱與毒霧控場、近身用燕返脫離；破霸體靠穿雲錐與大招。"}
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
     "| 按鍵 | 功能 |", "|---|---|", "| WASD／滑鼠 | 移動／轉動鏡頭（第三人稱，鏡頭在角色後上方） |", "| 左鍵 | 普攻（連按接下一段） |",
     "| 右鍵、Q、E、R、1、2、3 | 技能一～七 |", "| V | 大招 |", "| Shift | 閃避（短暫無敵） |", "| 空白鍵 | 跳 |", "| F | 互動（參悟、鐵匠、商人；原本的 E 讓給技能） |", "| K | 經脈 |", "",
     "裝備改動：拿掉選兵器、武器掉落、主副武器切換與天機輪的武器候選；南宮逸固定太刀、韓天狼固定巨劍、唐七固定柳葉飛刀。鐵匠改為強化角色的固定兵器。", "",
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
# ---- 浮空設計
L += ["## 4. 浮空設計：哪些攻擊會讓敵人浮空", "",
      "浮空有三個來源：", "",
      "1. **起手招**（把站著的敵人打上半空）：下表「起手」欄打勾的招式。浮空高度決定後面能接幾下。",
      f"2. **托空招**（敵人已經在空中時把它托住）：任何攻擊打到浮空的敵人都會讓它再彈起 {f(cfg['air_hit_pop_h_m']['value'])} 公尺；帶浮空屬性的招式用自己的高度。每多打一下高度 ×{f(cfg['juggle_decay']['value'])}。",
      f"3. **倒地追打**：敵人倒地時被任何攻擊打到，都會彈起至少 {f(cfg['down_hit_launch_h_m']['value'])} 公尺，可以重新起連段。", "",
      "霸體中的敵人（精英、首領未被破霸體時）不會被打浮空。", "",
      "| 角色 | 招式 | 按鍵 | 浮空高度 | 起手 | 用途 |", "|---|---|---|---|---|---|"]
PURPOSE = {"nan_n3": "普攻連段中自然把敵人帶離地面，第四段接著打", "nan_s1": "主要起手，最高，後面可接完整連段",
           "nan_s3": "空中托住：五下每下都把敵人往上帶，連段中段用", "nan_s6": "反擊成功時挑空，反守為攻",
           "nan_ult": "八連斬一路把敵人帶上去，最後一劍劈落倒地",
           "han_s1": "範圍起手：把周圍一圈敵人全部震起", "han_s7": "最高的範圍起手，落點周圍都浮空", "han_ult": "三記橫掃捲上半空，最後一擊劈落倒地",
           "tang_s1": "近身自保：踢飛貼臉的敵人並後撤", "tang_s6": "針雨把浮空的敵人釘在半空，遠距離續連", "tang_ult": "十二輪針雨托空，爆裂暗器炸落倒地"}
for m in moves:
    la = [h for h in by.get(m["move_id"], []) if h["launch"] == "1"]
    if not la:
        continue
    hs = sorted({float(h["launch_h_m"]) for h in la})
    opener = "✓" if max(hs) >= 1.0 else "托空"
    key = KEYS[m["action"]] + (f"（第 {m['slot'][-1]} 段）" if m["slot"].startswith("normal") else "")
    L.append(f"| {chars[m['char_id']]['name_zh']} | {m['name_zh']} | {key} | {'～'.join(f(x) for x in hs)} m{'×' + str(len(la)) if len(la) > 1 else ''} | {opener} | {PURPOSE.get(m['move_id'], '')} |")
L += ["", "南宮逸的基本連段：左鍵 ×3（第三段上撩小浮空）→ 第四段 → 右鍵挑月（挑高）→ E 追風連斬（托空五下）→ 左鍵追打 → 落地前 R 落雁斬收尾。",
      "敵人倒地後再補一刀會重新彈起，可以再接挑月。", "",
      f"敵人打玩家：一般近戰與飛行道具只造成硬直；地上有預警圈的範圍攻擊會把玩家打浮空 {f(cfg['enemy_aoe_launch_h_m']['value'])} 公尺。", ""]
L += ["## 5. 實作順序", "",
      "1. ✅ 狀態邏輯（`CombatState`）、招式資料與冒煙測試",
      "2. ✅ 第三人稱鏡頭與角色模型（Quaternius 通用假人，CC0）：移動、閃避、跳躍、受擊、浮空、倒地、起身",
      "3. ✅ 南宮逸：普攻四段、七技能、大招（初版動作，等用 MotionStage 逐招修）",
      "4. ✅ 敵人接上六種狀態（挑空、倒地追打、精英首領霸體）；敵人的近戰、飛行道具、範圍攻擊會讓玩家硬直或浮空",
      "5. ✅ 拿掉選兵器／掉落／主副武器；鐵匠只強化固定兵器；HUD 技能列與怒氣",
      "6. 韓天狼、唐七：依 CC0 骨架動作取樣，按各段命中時間重編轉身、軀幹、手腕與騰空曲線。各角色招式特效與音效見 moves.csv。",
      "7. 待辦：敵人各招式個別設定五個屬性（目前依階級與攻擊種類給預設值）、鎖定目標、刀鞘與收刀", "",
      "## 6. 動作來源與預覽", "",
      "- 模型與初版動作：Quaternius Universal Animation Library 1、2（CC0）。UE5 假人依 Epic 授權只能在 Unreal 引擎內使用，所以不採用。",
      "- 動作預覽與修改：MotionStage（https://github.com/jbang2004/motion-stage，MIT）。需要在你的電腦上執行（Node.js 22+）：`node skill/scripts/start.mjs --project <遊戲資料夾>`，在瀏覽器裡播放動作、暫停標記問題，再把任務交給我修改。"]
(ROOT / "docs" / "combat-design.md").write_text("\n".join(L) + "\n", encoding="utf-8")
print(len(L), "行")
