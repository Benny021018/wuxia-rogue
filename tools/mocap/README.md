# 動作擷取：影片 → 南宮的招式動作

用 [MoCapAnything V2](https://github.com/phongdaot/MocapAnything) 從參考影片擷取動作。它支援「自己的骨架」，
所以直接拿南宮的骨架當參考，輸出的 BVH 骨頭名稱和 `Nangong.glb` 一樣，不需要另外轉骨架。

需要：NVIDIA 顯示卡、Blender 5.x、Git Bash、uv。

## 1. 安裝（只做一次）

```powershell
git clone --depth 1 https://github.com/phongdaot/MocapAnything.git $HOME\MocapAnything
cd $HOME\MocapAnything
uv venv -p 3.11 .venv
uv pip install -p .venv\Scripts\python.exe torch torchvision --index-url https://download.pytorch.org/whl/cu128
uv pip install -p .venv\Scripts\python.exe numpy opencv-python pillow matplotlib scipy scikit-image trimesh roma pyyaml tqdm huggingface_hub transformers gradio imageio-ffmpeg omegaconf einops easydict pygltflib sentencepiece protobuf scikit-learn
.venv\Scripts\python.exe -c "from huggingface_hub import snapshot_download as s; s('kehong/MoCapAnythingV2-weights', local_dir='checkpoints')"
```

Windows 沒有 ffmpeg 指令時，把 `.venv\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-*.exe` 複製成 `bin\ffmpeg.exe`，並把 `bin` 加進 PATH。

Windows 版 ffmpeg 不支援 `-pattern_type glob`，前處理第 9 步會在「把渲染圖合成影片」時失敗。
把 `utils/visualization.py` 的 `convert_images_to_video` 改成先寫一份 concat 清單（`file '<圖>'` + `duration 1/fps`），
再用 `-f concat -safe 0 -i 清單` 讀圖即可。

## 2. 南宮的參考骨架（只做一次）

用 Blender 把 `assets/models/character/Nangong.glb` 匯出成 FBX，放到 `Truebone_Z-OO/Nangong/`：
`Nangong.fbx`（不含動作，檔名要最短）和至少一個動作檔，例如 `Nangong-NG_RaiseSlash.fbx`。

前處理（Git Bash）。**ZOO_ROOT 要用絕對路徑**，否則 Blender 會把渲染圖存到 `C:\zoo`：

```bash
export PATH="$(pwd)/bin:$PATH" PYTHON="$(pwd)/.venv/Scripts/python.exe" BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" PYTHONUTF8=1
ZOO_ROOT="$(pwd -W)/zoo" bash examples/custom_rig/run.sh Nangong
```

## 3. 擷取

1. 影片裁成以**出招的角色**為中心的正方形（512×512），只留出招的部分；檔名用 `Nangong#片段名.mp4` 放在 `videos/`。
   畫面裡有兩個以上的角色時，其他角色（含腳線以下、名牌下方的人）和大片特效要先塗掉，否則去背會把兩個人一起當成前景。
   參考做法：依關鍵幀插值裁切中心與腳線，腳線以下和紫色特效塗成草地色。
   角色要大、全身入鏡、特效越少越好。遊戲錄影裡被大量特效、名牌擋住的角色，擷取品質會明顯變差。
2. `"$PYTHON" -m inference.video2pose2rot --config examples/custom_rig/inference.yaml`
3. 結果在 `outputs/custom_rig/tmp/<片段>/`，取 `*_rot6d_pred.bvh`；同一層的 `*_pose_compare_image.mp4` 可以對照原片檢查。

## 4. 轉成遊戲動作

寫一個 job.json（切段用 BVH 的幀號，從 0 起算，名稱以 `NGM_` 開頭）：

```json
{"glb": ".../Nangong.glb", "out": ".../NangongMocap.glb", "report": ".../report.json",
 "clips": [{"bvh": ".../atk.bvh", "name": "NGM_Atk", "splits": [[0, 10, "NGM_N1"], [10, 18, "NGM_N2"]]}]}
```

```powershell
blender -b --factory-startup --python tools\mocap\mocap_to_nangong.py -- job.json
```

影片推回來的整體朝向（BVH 的 root 旋轉）會跟著鏡頭亂跳，腳本預設把它清掉，只保留骨盆以下的相對轉動；
烘好的四元數會再做一次平滑（`"smooth": 1`，0 為不平滑）。`report.json` 裡有每一幀右手的位置，
用右手速度的低谷切段、速度高峰當判定時間（換算：判定秒數 ＝ 高峰幀在段內的位置 ÷ 段長 × `duration_s`）。

要檢查結果，可逐格截圖：
`xvfb-run godot --path . --rendering-driver opengl3 res://tests/ModelCapture.tscn -- /tmp/out nangong anim NGM_N1 0.1`

把 `NangongMocap.glb` 放到 `assets/models/character/`，`fighter_model.gd` 會自動把裡面的動作加進南宮的動作庫；
再到 `data/moves.csv` 把招式的 `anim` 改成 `NGM_*`，並依新動作調整 `move_hits.csv` 的判定時間。

## 目前的南宮招式

參考影片裡出招的是畫面上方的青衣雙刃角色（下方紫光的角色是被打的一方）。

| 招式 | 動作 | BVH 幀 | 判定 |
|---|---|---|---|
| 普攻一～四段 | NGM_N1～N4 | 4–20、20–33、32–41、41–60 | 各一下 |
| 技能一：挑月 | NGM_S1 | 小技能影片 30–82 | 四下：挑起浮空、空中兩刀、劈落 |

兩段都用 `"exaggerate": 1.6` 放大動作幅度。
