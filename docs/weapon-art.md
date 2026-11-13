# 第一人稱武器：模型與出招

目前開局和參悟武器池只開放太刀 W001、弓 W007、大劍 W301。這三把按參考圖在 Blender 重建；[三把模型預覽](previews/blender-reference-weapons.jpg)，可編輯原檔位於 tools/blender_sources。太刀與大劍有獨立刀鞘，弓身有 Draw 形變。武器分主武器與副武器，同時只拿一把、都握在慣用手。

[太刀拔刀斬實拍](previews/tachi-draw.gif)

太刀首擊從鞘中拔出，揮過準星後在右側持刀。架勢中再點按或持續按住可接下斬、上撩；停手約 1.35 秒再納刀。攻擊節奏參考 [Bullet-Time Ninja 遊玩示範](https://www.youtube.com/watch?v=fu1vDGwul4s&t=18s)，姿勢與時序按本作第一人稱視角重新編排。竹弓從側傾搭箭轉至接近直立的滿弓姿勢，按住左鍵拉弓、放開射出。這些傾角為第一人稱畫面構圖所設。動畫節奏參考 [Techland 的近戰動畫開發日誌](https://outpost.dyinglightgame.com/news/dev-blog-they-tried-to-break-him)、[Exouch 的第一人稱弓動畫](https://forums.unrealengine.com/t/exouch-first-person-bow-animation-pack/2691165)。

- [太刀（W001，Tripo Smart Mesh 原稿）](https://studio.tripo3d.ai/workspace/generate/0876dc0a-fc44-4152-8188-f8adb9b862a5)：Blender 修形與配鞘，遊戲實作拔斬與連段。[第一批美術規格](greenwood-art.md)。
- [竹弓（W007，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/ffcc48c7-73b8-464a-b61d-1624bea39fff)：舉弓引弦、箭離弦、收勢搭箭。
- [巨劍（W301，Tripo 原稿）](https://studio.tripo3d.ai/zh/workspace/generate/42e15f3b-9b31-4c84-ade2-ae192616203f)：重劍高舉、下劈沉腕。
