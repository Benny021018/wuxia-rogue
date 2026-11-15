"""以 Quaternius 的 Fantasy Props MegaKit 與 Medieval Village MegaKit（皆 CC0）組出場景物件。

    python3.11 tools/build_props.py <素材資料夾>

素材資料夾放兩包解壓後的 Standard 版：props_megakit/（Fantasy Props MegaKit 的 Exports）與 Medieval Village MegaKit[Standard]/。
需要 Blender 的 Python 模組（pip install bpy，Python 3.11）。

輸出覆蓋 assets/models/greenwood/ 與 assets/models/npc/ 裡對應的 GLB：
- 綠林山寨的掩體（world.gd 的 CAMP_ART）：做成剛好填滿指定尺寸、底部置中，遊戲再依格子大小縮放
- 休息區的鐵匠鋪、商人攤：照原尺寸擺放，正面朝 +Z（Blender 的 -Y）
宮殿、石屋等歐式建築不用，避免跟武俠風格衝突。
"""
import math
import sys
from pathlib import Path

import bpy
import mathutils

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(sys.argv[-1])
PROPS = SRC / "props_megakit/glTF"
VILLAGE = SRC / "Medieval Village MegaKit[Standard]/glTF"
TEX = 512


def load(name, at=(0, 0, 0), rot=0.0, scale=1.0):
    f = PROPS / (name + ".gltf")
    if not f.exists():
        f = VILLAGE / (name + ".gltf")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(f))
    new = [o for o in bpy.data.objects if o not in before]
    pivot = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in new:
        if o.parent is None:
            o.parent = pivot
    bpy.context.view_layer.update()
    lo, hi = bounds(new)
    # 每個零件先以底部中心為原點
    for o in new:
        if o.parent == pivot:
            o.location -= mathutils.Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    pivot.rotation_euler.z = math.radians(rot)
    pivot.scale = (scale,) * 3
    pivot.location = at
    bpy.context.view_layer.update()
    return pivot


def meshes():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def bounds(objs=None):
    lo = mathutils.Vector((1e9,) * 3)
    hi = -lo
    for o in objs or meshes():
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            lo = mathutils.Vector(map(min, lo, w))
            hi = mathutils.Vector(map(max, hi, w))
    return lo, hi


def fit(size):
    """整組縮放到剛好填滿 size（Godot 的 x、高、z → Blender 的 x、z、-y），底部置中"""
    bpy.context.view_layer.update()
    lo, hi = bounds()
    root = bpy.data.objects.new("Root", None)
    bpy.context.scene.collection.objects.link(root)
    for o in bpy.data.objects:
        if o.parent is None and o is not root:
            o.parent = root
            o.location -= mathutils.Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    d = hi - lo
    root.scale = (size[0] / d.x, size[2] / d.y, size[1] / d.z)


def shrink_textures():
    for img in bpy.data.images:
        if img.size[0] > TEX:
            img.scale(TEX, TEX)
    for m in bpy.data.materials:
        if not m.use_nodes:
            continue
        nt = m.node_tree
        # 遊戲不用法線貼圖（墨感），拿掉可以讓檔案小很多
        for n in list(nt.nodes):
            if n.type == "NORMAL_MAP":
                nt.nodes.remove(n)


def merge():
    """把整組合成一個網格（同材質一次繪製），場景裡大量重複的掩體才不會拖慢"""
    bpy.context.view_layer.update()
    ms = meshes()
    for o in ms:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in bpy.data.objects:
        o.select_set(o in ms)
    bpy.context.view_layer.objects.active = ms[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)


def export(path):
    merge()
    shrink_textures()
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_animations=False,
                              export_image_format="JPEG", export_jpeg_quality=80, export_yup=True)
    print("wrote", path.relative_to(ROOT))


def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)


GW = ROOT / "assets/models/greenwood"

# 貨箱（2×1.2×2）：兩箱一桶一袋
fresh()
load("Crate_Wooden", (-0.46, -0.46, 0), 4)
load("Crate_Wooden", (0.46, -0.44, 0), -6)
load("Barrel", (0.5, 0.48, 0))
load("Crate_Wooden", (-0.44, 0.5, 0), 3)
fit((2, 1.2, 2))
export(GW / "crate.glb")

# 板車（3×1.2×2）
fresh()
load("Prop_Wagon", (0, 0, 0), 90)
fit((3, 1.2, 2))
export(GW / "cart.glb")

# 一般掩體（6×3×1.5）：疊起來的貨箱牆，前面散放木桶
fresh()
for i in range(6):
    for j in range(3 if i in (1, 2, 3) else 2):
        load("Crate_Wooden", (-2.6 + i * 0.95, 0.2, j * 0.92), (i * 7 + j * 11) % 9 - 4)
load("Barrel", (-2.0, -0.55, 0))
load("Barrel", (1.4, -0.6, 0))
load("Barrel_Holder", (2.6, -0.5, 0)) if (PROPS / "Barrel_Holder.gltf").exists() else None
fit((6, 3, 1.5))
export(GW / "cover.glb")

# 石階（3×1×4）：往 -Z（Blender +Y）升高，跟原本的石階同一方向
fresh()
st = load("Stairs_Exterior_Straight")
lo, hi = bounds()
pts = [o.matrix_world @ v.co for o in meshes() for v in o.data.vertices]
front = [p.z for p in pts if p.y < (lo.y + hi.y) / 2]
back = [p.z for p in pts if p.y >= (lo.y + hi.y) / 2]
if sum(front) / len(front) > sum(back) / len(back):
    st.rotation_euler.z = math.pi
fit((3, 1, 4))
export(GW / "stairs.glb")

NPC = ROOT / "assets/models/npc"
# 鐵匠鋪（約 3.2×2.6×2.2，正面朝 Blender -Y）：後方工作台、前方鐵砧、右邊兵器架、木桶
fresh()
load("Workbench", (0.0, 0.5, 0))
load("Anvil_Log", (-0.85, -0.45, 0))
lo, hi = bounds([o for o in meshes() if o.parent and o.parent.name.startswith("Anvil_Log")])
load("Anvil", (-0.85, -0.45, hi.z))
load("WeaponStand", (0.95, -0.3, 0), -25)
load("Barrel", (-1.2, 0.55, 0))
load("Whetstone", (0.55, -0.6, 0)) if (PROPS / "Whetstone.gltf").exists() else None
export(NPC / "Smith.glb")

# 商人攤：攤車＋蘋果箱、蘋果桶、錢袋、錢堆
fresh()
load("Stall_Cart_Empty", (0, 0, 0))
cart_lo, cart_hi = bounds()
load("FarmCrate_Apple", (-0.95, -0.85, 0), 8)
load("Barrel_Apples", (1.25, -0.75, 0))
load("Bag", (-1.45, 0.2, 0))
export(NPC / "Merchant.glb")
