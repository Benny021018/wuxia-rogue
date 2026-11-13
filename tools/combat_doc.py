"""由 data/moves.csv、move_hits.csv、combat_state_config.csv 產生 docs/combat-design.md。

    python3 tools/combat_doc.py
"""
import csv
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
rd = lambda n: list(csv.DictReader((ROOT / "data" / f"{n}.csv").open(encoding="utf-8")))
moves, hits, cfg = rd("moves"), rd("move_hits"), {r["key"]: r for r in rd("combat_state_config")}
chars = {r["char_id"]: r for r in rd("characters")}
feel = {r["key"]: r for r in rd("feel_config")}
KEYS = {"attack": "左鍵", "skill1": "右鍵", "skill2": "Q", "skill3": "E", "skill4": "R", "skill5": "1", "skill6": "2", "skill7": "3", "ult": "V"}
WEAPON = {"nangong": "太刀", "han": "巨劍", "tang": "柳葉飛刀"}
STYLE = {"nangong": "快、連段長、擅長把敵人挑空追打；靠無敵招閃避，破霸體手段少（拔刀・一閃、大招）。",
         "han": "慢、每一下都重、出招大多帶霸體可以硬換；破霸體手段最多（衝撞、擒殺、大招）。",
         "tang": "遠程、靠陷阱與毒霧控場、近身用燕返脫離；破霸體靠穿雲錐與大招。"}
SELF = {"": "", "armor": "霸體", "invincible": "無敵"}
f = lambda v: ("%g" % float(v))
c = lambda k: f(cfg[k]["value"])
by = {}
for h in hits:
    by.setdefault(h["move_id"], []).append(h)
NAME = {cid: chars[cid]["name_zh"] for cid in ("nangong", "han", "tang")}
ROLE = {"nangong": "連段型", "han": "霸體重擊型", "tang": "遠程控場型"}
PLAN = {"nangong": "用挑月或普攻第三段起手，把對手留在空中打完整連段；危險時靠無敵招閃開。",
        "han": "頂著霸體硬換招，用破霸體招式拆掉對手的霸體，再用擊倒與範圍浮空收割。",
        "tang": "保持距離，用毒霧與絲網限制走位；被貼身時用燕返踢開並後撤。"}
WEAK = {"nangong": "破霸體手段只有拔刀・一閃與大招，遇到霸體對手要等冷卻。",
        "han": "出招慢、除了大招沒有無敵招式，打不到人時容易被繞背或風箏。",
        "tang": "沒有霸體，被近身後只有燕返與影遁兩招能脫身。"}


def key_of(m):
    return KEYS[m["action"]] + (f"（第 {m['slot'][-1]} 段）" if m["slot"].startswith("normal") else "")


def has(m, col):
    return any(h[col] == "1" for h in by.get(m["move_id"], []))


def count(cid, pred):
    return sum(1 for m in moves if m["char_id"] == cid and pred(m))


n_moves, n_hits = len(moves), len(hits)
L = ["# 《天魔劫》戰鬥設計文件", "",
     "第三人稱動作遊戲《天魔劫》的戰鬥規則。狀態體系參考《疾風之刃》的霸體、無敵與浮空連段，再依自己的需求調整。",
     f"目前有三個角色、{n_moves} 招、{n_hits} 段判定，可以單人闖關、區網雙人合作，以及區網 1v1 三命單挑。", "",
     "> 這份文件由 `tools/combat_doc.py` 從遊戲實際使用的資料表產生，文件上的數字就是遊戲裡的數字。", "",
     "## 目錄", "",
     "1. [設計目標](#1-設計目標)",
     "2. [六種角色狀態](#2-六種角色狀態)",
     "3. [每一下攻擊的五個屬性](#3-每一下攻擊的五個屬性)",
     "4. [防無限連與防圍毆](#4-防無限連與防圍毆)",
     "5. [霸體攻防](#5-霸體攻防)",
     "6. [擊退與站位](#6-擊退與站位)",
     "7. [三個角色的定位](#7-三個角色的定位)",
     "8. [浮空與連段](#8-浮空與連段)",
     "9. [1v1 單挑與雙人合作](#9-1v1-單挑與雙人合作)",
     "10. [完整招式表](#10-完整招式表)",
     "11. [操作](#11-操作)",
     "12. [附錄：資料與實作](#12-附錄資料與實作)", "",
     "## 1. 設計目標", "",
     "- **每一下攻擊都有明確後果。** 打中之後對手會硬直多久、會不會浮空、會不會倒地，都由招式資料決定，玩家可以預期。",
     "- **連段可以很長，但一定會結束。** 浮空高度逐下衰減，起身有無敵，被連的人總有機會回到場上。",
     "- **霸體與破霸體是核心攻防。** 霸體讓角色能硬吃攻擊出招，破霸體招式是它的解法；三個角色擁有的數量不同，形成各自的打法。",
     "- **玩家與敵人同一套規則。** 敵人會被挑空、追打，也能把玩家打出硬直與浮空；同一套規則直接用在玩家對玩家。", "",
     "## 2. 六種角色狀態", "",
     "```mermaid", "stateDiagram-v2", "    direction LR",
     '    state "正常" as N', '    state "受擊" as H', '    state "浮空" as A', '    state "倒地" as D', '    state "霸體" as R', '    state "無敵" as I',
     "    N --> H: 被打中", "    N --> A: 被浮空招打中", "    N --> D: 被擊倒招打中",
     "    H --> N: 硬直結束", "    H --> A: 被浮空招打中",
     "    A --> A: 空中再被打（高度衰減）", "    A --> D: 落地",
     "    D --> A: 倒地時被打", f"    D --> I: {c('hit_down_time_s')} 秒沒被打，起身",
     "    I --> N: 無敵結束", "    N --> I: 閃避或無敵招",
     "    N --> R: 使用霸體招", "    R --> N: 霸體結束", "    R --> H: 被破霸體招打中",
     "```", "",
     "| 狀態 | 能否操控 | 被打到會怎樣 | 怎麼結束 |", "|---|---|---|---|",
     "| 正常 | 可以 | 依招式進入受擊、浮空或倒地 | — |",
     "| 受擊 | 不行 | 重新計算硬直；浮空招照樣打浮空 | 硬直時間到，回到正常 |",
     f"| 浮空 | 不行 | 再往上彈，每多一下高度 ×{c('juggle_decay')} | 落地後進入倒地 |",
     f"| 倒地 | 不行 | 重新浮空，至少彈起 {c('down_hit_launch_h_m')} 公尺 | {c('hit_down_time_s')} 秒內沒被打就起身，起身無敵 {c('getup_invincible_s')} 秒 |",
     "| 霸體 | 可以 | 照樣受傷並有頓幀，但不會被打斷 | 霸體時間到，或被破霸體招式打中 |",
     "| 無敵 | 可以 | 打不到、不受傷 | 無敵時間到 |", "",
     "## 3. 每一下攻擊的五個屬性", "",
     "一招可以有很多段判定，每一段各自設定下面五個屬性。", "",
     "| 屬性 | 作用 | 設計用途 |", "|---|---|---|",
     "| 硬直時間 | 對手被打中後不能操控的秒數 | 決定這一下之後還能不能接下一招 |",
     "| 是否浮空 | 是否把站著的對手打上半空 | 區分連段起手招與一般招式 |",
     "| 浮空高度 | 打上去多高（公尺） | 越高，後面能接的招越多 |",
     "| 是否破霸體 | 能否打斷霸體中的對手 | 霸體的解法，數量少、冷卻長 |",
     "| 是否擊倒 | 是否讓站著的對手直接倒地 | 連段收尾，或製造倒地追打的機會 |", "",
     "「擊倒」是後來才加的屬性。最初只有浮空，而浮空落地就會起身，沒有任何招式能讓站著的對手進入倒地，倒地追打這條規則用不到，所以補上擊倒。", "",
     "## 4. 防無限連與防圍毆", "",
     "| 規則 | 數值 | 目的 |", "|---|---|---|",
     f"| 浮空高度衰減 | 每多打一下 ×{c('juggle_decay')} | 連段越長越難接，自然結束 |",
     f"| 浮空最低高度 | 低於 {c('juggle_min_h_m')} 公尺就不再彈起 | 給連段一個硬性終點 |",
     f"| 空中被一般招式打到 | 只小彈 {c('air_hit_pop_h_m')} 公尺 | 不帶浮空的招式也能續連，但效率較差 |",
     f"| 起身無敵 | {c('getup_invincible_s')} 秒 | 倒地的人起身時不會被壓制到死 |",
     f"| 受擊保護 | 從受擊恢復後 {c('player_hit_guard_s')} 秒內再被打，只受傷、不硬直 | 玩家被一群敵人圍住時仍然能動 |",
     f"| 閃避 | 無敵 {c('dodge_invincible_s')} 秒，冷卻 {c('dodge_cd_s')} 秒 | 每個角色都有的基本脫身手段 |", "",
     "## 5. 霸體攻防", "",
     "- 玩家的霸體來自招式：招式資料標明霸體從第幾秒開始、到第幾秒結束。",
     f"- 精英與首領常駐霸體。被破霸體招式打中後有 {c('armor_break_s')} 秒空窗，這段時間可以打出硬直、浮空與倒地。",
     f"- 精英的硬直時間 ×{c('hitstun_elite_mult')}、首領 ×{c('hitstun_boss_mult')}，即使破了霸體，也不能像小怪一樣連到底。",
     f"- 大招全程無敵並帶破霸體，靠怒氣施放：命中 +{c('rage_per_hit')}、受擊 +{c('rage_per_hurt')}，集滿 {c('rage_max')}。", "",
     "## 6. 擊退與站位", "",
     "被打中的一方會往後退，退多遠由攻擊者這一下攻擊決定（招式表的「擊退」欄）。受擊、浮空、倒地被追打時都會退。", "",
     "| 規則 | 內容 | 目的 |", "|---|---|---|",
     "| 擊退方向 | 近戰往攻擊者的出招方向推；範圍招從中心往外推；飛行道具往飛行方向推 | 近戰連打時對手一直留在正前方 |",
     "| 擊退與位移配對 | 普攻每一段的擊退距離，不超過下一段往前踏的距離 | 連打時不會把對手推出攻擊範圍 |",
     f"| 位移不穿過目標 | 出招往前踏時，停在離目標邊緣 {c('lunge_stop_gap_m')} 公尺處 | 不會走到對手身後而揮空 |",
     "| 穿越招例外 | " + "、".join(m["name_zh"] for m in moves if m.get("lunge_pass") == "1") + " 可以穿過目標 | 保留繞背與脫身的手段 |",
     f"| 霸體減免 | 霸體吃招、或玩家受擊保護期間，只退原本的 {float(feel['knock_armor_mult']['value']) * 100:g}% | 霸體的人站得住 |",
     f"| 體型減免 | 精英只退 {float(feel['knock_mass_elite']['value']) * 100:g}%、首領 {float(feel['knock_mass_boss']['value']) * 100:g}% | 大型敵人不會被推著跑 |", "",
     f"敵人打玩家同樣有擊退：一般敵人 {c('enemy_push_m')} 公尺、精英 {c('enemy_push_elite_m')} 公尺、首領 {c('enemy_push_boss_m')} 公尺。", "",
     "## 7. 三個角色的定位", "",
     "| | " + " | ".join(f"{NAME[k]}（{WEAPON[k]}）" for k in NAME) + " |", "|---|---|---|---|",
     "| 定位 | " + " | ".join(ROLE[k] for k in NAME) + " |",
     "| 普攻段數 | " + " | ".join(str(count(k, lambda m: m["slot"].startswith("normal"))) for k in NAME) + " |",
     "| 自帶霸體的招式 | " + " | ".join(str(count(k, lambda m: m["self_state"] == "armor")) for k in NAME) + " |",
     "| 自帶無敵的招式 | " + " | ".join(str(count(k, lambda m: m["self_state"] == "invincible")) for k in NAME) + " |",
     "| 破霸體的招式 | " + " | ".join(str(count(k, lambda m: has(m, "break_armor"))) for k in NAME) + " |",
     "| 能浮空的招式 | " + " | ".join(str(count(k, lambda m: has(m, "launch"))) for k in NAME) + " |",
     "| 能擊倒的招式 | " + " | ".join(str(count(k, lambda m: has(m, "knockdown"))) for k in NAME) + " |",
     "| 打法 | " + " | ".join(PLAN[k] for k in NAME) + " |",
     "| 弱點 | " + " | ".join(WEAK[k] for k in NAME) + " |", "",
     "招式數量含普攻與大招。", ""]
# ---- 浮空與連段
L += ["## 8. 浮空與連段", "",
      "浮空有三個來源：", "",
      "1. **起手招**：把站著的對手打上半空。浮空高度決定後面能接幾下。",
      f"2. **托空招**：對手已經在空中時把它托住。任何攻擊打到浮空的對手都會讓它再彈起 {c('air_hit_pop_h_m')} 公尺；帶浮空屬性的招式用自己的高度。",
      f"3. **倒地追打**：對手倒地時被任何攻擊打到，都會彈起至少 {c('down_hit_launch_h_m')} 公尺，可以重新起連段。", "",
      "霸體中的對手不會被打浮空。", "",
      "| 角色 | 招式 | 按鍵 | 浮空高度 | 類型 | 用途 |", "|---|---|---|---|---|---|"]
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
    opener = "起手" if max(hs) >= 1.0 else "托空"
    L.append(f"| {chars[m['char_id']]['name_zh']} | {m['name_zh']} | {key_of(m)} | {'～'.join(f(x) for x in hs)} m{'×' + str(len(la)) if len(la) > 1 else ''} | {opener} | {PURPOSE.get(m['move_id'], '')} |")
L += ["", "**連段範例（南宮逸）**", "",
      "1. 左鍵 ×3：第三段上撩把對手帶離地面。",
      "2. 左鍵第四段：縱劈追打。",
      "3. 右鍵挑月：重新挑高。",
      "4. E 追風連斬：五下托空。",
      "5. 左鍵追打，落地前用 R 落雁斬收尾。", "",
      "對手倒地後再補一刀會重新彈起，可以再接挑月；但浮空高度已經衰減，能接的招數比第一輪少。", "",
      f"敵人打玩家：一般近戰與飛行道具只造成硬直；地上有預警圈的範圍攻擊會把玩家打浮空 {c('enemy_aoe_launch_h_m')} 公尺。", "",
      "## 9. 1v1 單挑與雙人合作", "",
      "**問劍坪單挑（1v1）**", "",
      "| 項目 | 規則 |", "|---|---|",
      f"| 勝負 | 每人 {c('lan_lives')} 條命，先讓對手用完的一方獲勝 |",
      f"| 氣血 | 每條命 {c('lan_duel_hp')} |",
      "| 每命結束 | 雙方回到出生點，氣血、怒氣、技能冷卻與場上暗器全部重置 |",
      "| 同時倒下 | 最後一命同時倒下時進入加賽 |",
      f"| 開戰 | 倒數 {c('lan_round_delay')} 秒 |",
      f"| 場地 | {f(float(cfg['lan_arena_half']['value']) * 2)} 公尺見方，開局間距 {c('lan_spawn_gap')} 公尺 |", "",
      "每命重置冷卻與怒氣，是為了讓每一命都從相同條件開始，上一命的優勢不會滾到下一命。", "",
      "**雙人合作**", "",
      "兩人共闖原本的四張地圖。武學與成長各自計算；倒下時觀戰，隊友清完當前區域後復起，兩人都倒下才結算。", "",
      "**連線方式**", "",
      f"區域網路連線。戰鬥判定由房主執行，房主每秒送出 {c('lan_snapshot_hz')} 次狀態；另一方先在本機預測自己的移動與出招，再依房主的結果校正，自己的操作會立即有反應。", "",
      "## 10. 完整招式表", "",
      "傷害是基礎攻擊力的百分比。「自身狀態」是出招者在招式第幾秒到第幾秒帶有霸體或無敵。「擊退」是打中後對手後退的距離，多段招式是每一段的距離。", "",
      "![三個角色的招式姿勢](previews/hero-moves.jpg)", ""]
for cid in ("nangong", "han", "tang"):
    L += [f"### {NAME[cid]}（{WEAPON[cid]}）：{ROLE[cid]}", "", STYLE[cid], "",
          "| 按鍵 | 招式 | 冷卻 | 自身狀態 | 段數×傷害 | 硬直 | 浮空 | 擊退 | 破霸體 | 擊倒 | 說明 |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    for m in [m for m in moves if m["char_id"] == cid]:
        hs = by.get(m["move_id"], [])
        dm = "—"
        if hs:
            ds = [f(h["dmg_pct"]) for h in hs]
            dm = f"{len(ds)}×{ds[0]}%" if len(set(ds)) == 1 else "＋".join(sorted(set(f"{ds.count(d)}×{d}%" for d in ds), key=lambda s_: -int(s_.split('×')[0])))
        stun = "—" if not hs else "～".join(sorted({f(h["hitstun_s"]) for h in hs}, key=float)) + " 秒"
        la = [h for h in hs if h["launch"] == "1"]
        launch = "—" if not la else "～".join(sorted({f(h["launch_h_m"]) for h in la}, key=float)) + " m"
        ps = sorted({float(h["push_m"]) for h in hs})
        push = "—" if not hs or max(ps) == 0 else "～".join(f(x) for x in ps) + " m"
        br = "✓" if has(m, "break_armor") else ""
        kd = "✓" if has(m, "knockdown") else ""
        ss = SELF[m["self_state"]]
        if ss:
            ss += f" {f(m['self_from_s'])}–{f(m['self_to_s'])} 秒"
        cd = "—" if float(m["cooldown_s"]) == 0 else f(m["cooldown_s"]) + " 秒"
        if m["slot"] == "ult":
            cd = "怒氣滿"
        L.append(f"| {key_of(m)} | {m['name_zh']} | {cd} | {ss} | {dm} | {stun} | {launch} | {push} | {br} | {kd} | {m['desc']} |")
    L.append("")
L += ["## 11. 操作", "",
      "| 按鍵 | 功能 |", "|---|---|", "| WASD／滑鼠 | 移動／轉動鏡頭（越肩第三人稱） |", "| 左鍵 | 普攻（連按接下一段） |",
      "| 右鍵、Q、E、R、1、2、3 | 技能一～七 |", "| V | 大招 |", "| Shift | 閃避（短暫無敵） |", "| 空白鍵 | 跳 |", "| F | 互動（參悟、鐵匠、商人） |", "| K | 經脈 |", "",
      "每個角色固定一把兵器，技能開局全部可用，只受冷卻限制。", "",
      "## 12. 附錄：資料與實作", "",
      "| 內容 | 位置 |", "|---|---|",
      "| 招式（動作、時間、位移、冷卻、自身狀態） | `data/moves.csv` |",
      "| 每一段判定的五個屬性與傷害 | `data/move_hits.csv` |",
      "| 狀態相關數值（衰減、無敵時間、空窗、擂台規則） | `data/combat_state_config.csv` |",
      "| 擊退衰減與減免、頓幀、震屏 | `data/feel_config.csv` |",
      "| 六種狀態的邏輯（玩家與敵人共用） | `scripts/combat_state.gd` |",
      "| 招式執行（連段、輸入緩衝、冷卻、怒氣） | `scripts/move_runner.gd` |",
      "| 區網連線 | `scripts/lan_session.gd` |",
      "| 自動化測試 | `tests/smoke_test.gd`、`tests/lan_integration.gd` |", "",
      "改完資料表後執行 `python3 tools/combat_doc.py` 重新產生這份文件。", "",
      "**尚未完成**", "",
      "- 敵人各招式個別設定五個屬性（目前依階級與攻擊種類給預設值）。",
      "- 鎖定目標。",
      "- 數值為初版，尚未做完整的對戰平衡。", "",
      "**素材來源**", "",
      "- 角色模型與基礎動作：Quaternius Universal Animation Library 1、2（CC0）。",
      "- 動作預覽工具：[MotionStage](https://github.com/jbang2004/motion-stage)（MIT）。"]
(ROOT / "docs" / "combat-design.md").write_text("\n".join(L) + "\n", encoding="utf-8")
print(len(L), "行")
