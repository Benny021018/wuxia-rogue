# 第一人稱武器：模型與出招

17 件模型分別由 Tripo Studio 生成。遊戲版在 Blender 減面、縮貼圖並以握點為原點重新定位；紅纓槍另補槍桿，九節鞭另加 Lash 形變。第一人稱動作在 Godot 播放，左右手各有自己的時間軸。攻擊間隔與每輪總段數沿用 weapons.csv，傷害、刀光與發射在對應動作節拍觸發。多段武器首拍觸發單輪附加效果。

[全部武器實拍](previews/weapon-set.jpg) · [四種出招動畫](previews/weapon-attacks.gif)

- [鐵刀（W001，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/c956c7b4-182b-4272-b6ca-cc9d9b8a06c6)：側提斜斬、刀背回收。
- [齊眉棍（W002，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/a9be4ff8-43a2-4604-966e-a7b848dd96f2)：轉腕蓄勢、平棍橫掃。
- [鐵拳套（W003，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/2fc5d658-d7d0-4113-b245-b74cfc935970)：短縮拳、快速前送。
- [青鋼劍（W004，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/54580822-6855-4689-9c75-2025827ce83c)：收劍、直刺回鋒。
- [紅纓槍（W005，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/1f89e6e5-e452-4b2e-be63-24540c11d53f)：收桿蓄力、槍尖前送。
- [柳葉飛刀（W006，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/88e01c0f-7eeb-4cb2-a4f0-80be83b6fa28)：提腕甩刀、飛刀離手後補回。
- [竹弓（W007，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/ffcc48c7-73b8-464a-b61d-1624bea39fff)：舉弓引弦、箭離弦、收勢搭箭。
- [鬼頭大刀（W101，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/8517675d-30d6-4f70-b714-1a7612cedd80)：舉重刀、斜向下劈。
- [鐵骨扇（W102，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/9d706c26-fc4e-4649-b535-0511d4482d7a)：展扇翻腕、切出扇風。
- [袖箭（W103，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/87050449-ceb7-45df-8ff3-a009b27c2252)：抬腕、三拍連發。
- [雙鉤（W201，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/cc628bf9-fe49-469a-ace2-7aa0779e09f8)：雙鉤交錯、分兩次命中。
- [九節鞭（W202，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/552ff64a-fd9e-49e6-8a4b-9bb40a44aa9f)：環掃甩鞭、鞭梢延後回彈。
- [暴雨針匣（W203，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/a50abb9c-8095-47d2-beb0-586698e78385)：針匣前送、五針齊發。
- [霸王槍（W204，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/100edc4f-a922-47bf-bf6f-39a9ea721999)：轉槍橫起與直起交替、槍尖前刺。
- [開天巨劍（W301，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/42e15f3b-9b31-4c84-ade2-ae192616203f)：重劍高舉、下劈沉腕。
- [驚鴻劍（W302，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/ae69b298-9e3d-4fea-a2a4-270670e1b41e)：接連兩次刺擊。
- [天機弩（W303，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/d946d2c3-d6c0-4795-ae60-d0897c03b29d)：舉弩瞄準、三次回彈。
