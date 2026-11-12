"""休息區的鐵匠鋪與商人攤：在 Blender 以幾何體搭建，頂點色分階上色後匯出 GLB。

用法（專案根目錄）：
    blender --background --python tools/build_rest_stops.py
輸出：assets/models/npc/Smith.glb、Merchant.glb（Godot 匯入時由 tools/import_ink_mesh.gd 套用頂點色）

座標：Blender Z 向上，正面朝 -Y（匯出後為 Godot 的 +Z）；原點在地台底部中央。
地台 3.2 × 2.2 m；人物身高約 1.9 m，靜止站姿。爐炭與燈籠另成一個發光網格（*_Ember）。
"""
import math
import os

import bpy
import bmesh
from mathutils import Euler, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "models", "npc")


def srgb(hexstr):
    c = [int(hexstr[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def coll(name):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    return c


def _mesh(kind, seg=10, taper=1.0, rings=8):
    bm = bmesh.new()
    if kind == "box":
        bmesh.ops.create_cube(bm, size=1.0)
    elif kind == "cyl":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=0.5, radius2=0.5 * taper, depth=1.0)
    elif kind == "cone":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=0.5, radius2=0.0, depth=1.0)
    elif kind == "sphere":
        bmesh.ops.create_uvsphere(bm, u_segments=seg if seg != 10 else 12, v_segments=rings, radius=0.5)
    me = bpy.data.meshes.new(kind)
    bm.to_mesh(me)
    bm.free()
    return me


def part(group, name, kind, loc, size, color, rot=(0, 0, 0), emit=0.0, **kw):
    """size：世界尺寸（公尺）；color：十六進位；emit>0 併入發光網格"""
    o = bpy.data.objects.new(name, _mesh(kind, **kw))
    coll(group).objects.link(o)
    o.location = loc
    o.rotation_euler = Euler([math.radians(a) for a in rot])
    o.scale = size
    o["ink"] = color
    o["emit"] = emit
    return o


def npc(g, bx, by, bz, skin, outfit, arms):
    """站姿人物，面向 -Y"""
    def P(name, kind, x, y, z, size, col, rot=(0, 0, 0), **kw):
        return part(g, name, kind, (bx + x, by + y, bz + z), size, col, rot, **kw)
    for s in (-1, 1):
        P("leg", "cyl", 0.11 * s, 0, 0.45, (0.17, 0.18, 0.8), outfit["pants"], taper=0.8, seg=8)
        P("boot", "box", 0.11 * s, -0.03, 0.07, (0.16, 0.26, 0.14), outfit["boots"])
    P("torso", "cyl", 0, 0, 1.17, (0.5, 0.32, 0.62), outfit["top"], taper=1.22, seg=8)
    P("belt", "cyl", 0, 0, 0.9, (0.46, 0.33, 0.09), outfit["belt"], seg=8)
    if outfit.get("apron"):
        P("apron", "box", 0, -0.17, 0.82, (0.44, 0.04, 0.74), outfit["apron"])
    if outfit.get("robe"):
        P("robe", "cyl", 0, 0, 0.55, (0.62, 0.44, 0.8), outfit["robe"], taper=0.72, seg=10)
    P("neck", "cyl", 0, 0, 1.52, (0.13, 0.13, 0.12), skin, seg=8)
    P("head", "sphere", 0, -0.01, 1.7, (0.25, 0.27, 0.3), skin)
    P("nose", "box", 0, -0.14, 1.69, (0.04, 0.05, 0.07), skin)
    for s in (-1, 1):
        P("brow", "box", 0.06 * s, -0.125, 1.75, (0.07, 0.02, 0.018), "1d1b20", rot=(0, 12 * s, 0))
        P("eye", "box", 0.06 * s, -0.125, 1.72, (0.045, 0.015, 0.02), "1d1b20")
    if outfit.get("hair"):
        P("hair", "sphere", 0, 0.02, 1.78, (0.27, 0.28, 0.2), outfit["hair"])
        P("bun", "sphere", 0, 0.04, 1.9, (0.11, 0.11, 0.11), outfit["hair"])
    if outfit.get("band"):
        P("band", "cyl", 0, -0.005, 1.78, (0.27, 0.29, 0.05), outfit["band"], seg=12)
    if outfit.get("beard"):
        P("beard", "cone", 0, -0.11, 1.56, (0.17, 0.1, 0.16), outfit["beard"], rot=(180, 0, 0), seg=8)
    if outfit.get("hat"):
        P("hat_brim", "cyl", 0, 0, 1.86, (0.5, 0.5, 0.03), outfit["hat"], seg=16)
        P("hat_top", "cyl", 0, 0, 1.93, (0.22, 0.22, 0.14), outfit["hat"], taper=0.8, seg=12)
    arms(P, outfit.get("sleeves", skin), skin)


def floor(g):
    part(g, "floor", "box", (0, 0, 0.05), (3.2, 2.2, 0.1), "59483f")
    for i in range(6):
        part(g, "plank", "box", (-1.33 + i * 0.53, 0, 0.102), (0.02, 2.2, 0.01), "342f34")


def build_smith(g="Smith"):
    W = lambda *a, **k: part(g, *a, **k)
    floor(g)
    # 火爐（左後）
    W("forge", "box", (-0.95, 0.5, 0.525), (1.1, 0.9, 0.85), "495863")
    W("forge_rim", "box", (-0.95, 0.5, 0.98), (1.22, 1.0, 0.1), "71828b")
    W("forge_mouth", "box", (-0.95, 0.04, 0.6), (0.6, 0.04, 0.35), "1d1b20")
    W("hood", "cyl", (-0.95, 0.55, 1.62), (1.25, 1.05, 0.62), "303940", rot=(0, 0, 45), taper=0.35, seg=4)
    W("chimney", "cyl", (-0.95, 0.6, 2.3), (0.32, 0.32, 0.9), "303940", seg=8)
    for x in (-1.5, -0.4):
        W("hood_post", "box", (x, 0.1, 1.17), (0.06, 0.06, 0.3), "303940")
    for x, y in [(-1.15, 0.4), (-0.95, 0.55), (-0.75, 0.42), (-1.05, 0.65), (-0.85, 0.3)]:
        W("coal", "sphere", (x, y, 1.05), (0.2, 0.2, 0.1), "ff6a1f", emit=1.0)
    W("coal_mouth", "box", (-0.95, 0.03, 0.55), (0.5, 0.02, 0.22), "ff6a1f", emit=1.0)
    W("bellows", "box", (-1.62, 0.2, 0.55), (0.22, 0.6, 0.35), "6b4a33", rot=(0, 0, 8))
    # 鐵砧與樹墩
    W("stump", "cyl", (0.35, -0.3, 0.38), (0.58, 0.58, 0.56), "826d55")
    W("stump_top", "cyl", (0.35, -0.3, 0.665), (0.56, 0.56, 0.02), "ac9673")
    W("anvil_waist", "box", (0.35, -0.3, 0.75), (0.24, 0.18, 0.16), "2b2d33")
    W("anvil_face", "box", (0.32, -0.3, 0.86), (0.5, 0.24, 0.1), "3a3d45")
    W("anvil_horn", "cone", (0.68, -0.3, 0.86), (0.13, 0.13, 0.26), "3a3d45", rot=(0, 90, 0), seg=8)
    W("blade_hot", "box", (0.3, -0.33, 0.92), (0.5, 0.05, 0.015), "ff8a3a", emit=1.0)
    # 淬火桶
    W("bucket", "cyl", (1.25, -0.45, 0.33), (0.45, 0.45, 0.46), "685752", taper=1.1, seg=12)
    W("bucket_band", "cyl", (1.25, -0.45, 0.45), (0.5, 0.5, 0.05), "2b2d33", seg=12)
    W("water", "cyl", (1.25, -0.45, 0.55), (0.42, 0.42, 0.01), "2d3e4a", seg=12)
    # 工具架與兵器（右後）
    for x in (0.8, 1.5):
        W("rack_post", "box", (x, 0.85, 0.9), (0.08, 0.08, 1.6), "59483f")
    for z in (1.6, 1.0):
        W("rack_bar", "box", (1.15, 0.85, z), (0.8, 0.06, 0.06), "826d55")
    for i, x in enumerate((0.95, 1.15, 1.35)):
        length = 0.8 - i * 0.1
        W("rack_blade", "box", (x, 0.8, 1.55 - length / 2), (0.05, 0.015, length), "859498")
        W("rack_hilt", "box", (x, 0.8, 1.6), (0.1, 0.03, 0.04), "6b4a33")
    W("rack_tongs", "box", (1.15, 0.8, 0.75), (0.04, 0.02, 0.45), "2b2d33", rot=(0, 18, 0))

    def arms(P, sleeve, skin):   # 右手舉錘
        P("arm_L", "cyl", -0.33, 0.0, 1.18, (0.14, 0.14, 0.5), skin, rot=(0, 10, 0), seg=8)
        P("hand_L", "sphere", -0.36, -0.03, 0.9, (0.1, 0.1, 0.1), skin)
        P("arm_R_up", "cyl", 0.33, -0.08, 1.3, (0.15, 0.15, 0.36), skin, rot=(40, 0, 0), seg=8)
        P("arm_R_fore", "cyl", 0.34, -0.25, 1.48, (0.13, 0.13, 0.34), skin, rot=(-25, 0, 0), seg=8)
        P("hand_R", "sphere", 0.34, -0.32, 1.64, (0.11, 0.11, 0.11), skin)
        P("hammer_shaft", "cyl", 0.34, -0.33, 1.78, (0.05, 0.05, 0.42), "6b4a33", rot=(-10, 0, 0), seg=6)
        P("hammer_head", "box", 0.34, -0.35, 1.98, (0.2, 0.12, 0.11), "2b2d33")
    npc(g, 0.38, 0.45, 0.1, "b8836e",
        {"pants": "303542", "top": "b8836e", "belt": "342f34", "boots": "272b36", "apron": "6b4a33",
         "band": "a34241", "beard": "272b36", "hair": "272b36"}, arms)


def build_merchant(g="Merchant"):
    W = lambda *a, **k: part(g, *a, **k)
    floor(g)
    # 櫃檯
    W("counter", "box", (0, -0.5, 0.52), (2.5, 0.7, 0.84), "826d55")
    W("counter_top", "box", (0, -0.5, 0.97), (2.62, 0.82, 0.07), "59483f")
    W("counter_panel", "box", (0, -0.86, 0.5), (2.2, 0.02, 0.5), "685752")
    # 頂棚（拉高到不擋人物頭部）
    for x in (-1.5, 1.5):
        W("post_front", "box", (x, -0.95, 1.375), (0.09, 0.09, 2.55), "59483f")
        W("post_back", "box", (x, 0.95, 1.525), (0.09, 0.09, 2.85), "59483f")
    W("roof", "box", (0, 0, 2.8), (3.4, 2.4, 0.06), "5a2b3a", rot=(-8, 0, 0))
    W("valance", "box", (0, -1.12, 2.57), (3.4, 0.03, 0.3), "a34241")
    for x in (-1.1, -0.55, 0, 0.55, 1.1):
        W("valance_tab", "box", (x, -1.12, 2.37), (0.32, 0.03, 0.12), "a34241")
    for x in (-1.45, 1.45):
        W("lantern", "sphere", (x, -1.05, 2.2), (0.26, 0.26, 0.32), "e2343c", emit=1.0)
        W("lantern_cap", "cyl", (x, -1.05, 2.37), (0.14, 0.14, 0.05), "272b36", seg=8)
    # 櫃檯上的卷軸與秘笈
    for x in (-1.0, -0.82, -0.64):
        W("scroll", "cyl", (x, -0.55, 1.05), (0.12, 0.12, 0.55), "d9c9a8", rot=(90, 0, 0), seg=8)
        W("scroll_cap", "cyl", (x, -0.83, 1.05), (0.14, 0.14, 0.03), "a34241", rot=(90, 0, 0), seg=8)
    for j, (x, col) in enumerate(((0.7, "2d3e4a"), (0.72, "6b4a33"), (0.69, "53323b"))):
        W("manual", "box", (x, -0.5, 1.03 + j * 0.05), (0.32, 0.42, 0.05), col, rot=(0, 0, j * 7 - 6))
    W("manual_open", "box", (1.12, -0.55, 1.02), (0.38, 0.3, 0.02), "e8dcc2", rot=(0, 0, -10))
    W("abacus", "box", (-0.25, -0.62, 1.03), (0.4, 0.18, 0.04), "342f34")
    W("jar", "sphere", (0.25, -0.45, 1.13), (0.22, 0.22, 0.26), "8a6a3a")
    # 後方書架
    W("shelf", "box", (0, 0.85, 0.95), (2.4, 0.38, 1.7), "59483f")
    for z in (0.55, 1.05, 1.5):
        W("shelf_board", "box", (0, 0.66, z), (2.3, 0.02, 0.06), "826d55")
        for k in range(9):
            h = 0.3 if k % 3 else 0.36
            col = ["2d3e4a", "53323b", "6b4a33", "d9c9a8"][k % 4]
            W("book", "box", (-1.0 + k * 0.25, 0.72, z + 0.03 + h / 2), (0.16, 0.22, h), col, rot=(0, (k % 2) * 6 - 3, 0))

    def arms(P, sleeve, skin):   # 雙手攏在袖中
        for s in (-1, 1):
            P("arm_up", "cyl", 0.3 * s, -0.04, 1.22, (0.17, 0.17, 0.36), sleeve, rot=(30, 0, 0), seg=8)
            P("arm_fore", "cyl", 0.16 * s, -0.2, 1.06, (0.18, 0.18, 0.34), sleeve, rot=(0, 90 * s, 0), taper=1.3, seg=8)
        P("hands", "sphere", 0, -0.22, 1.06, (0.16, 0.12, 0.12), skin)
    npc(g, -0.45, 0.1, 0.1, "d6b29a",
        {"pants": "2d3e4a", "top": "2d3e4a", "belt": "be9258", "boots": "272b36", "robe": "3b4a5a",
         "sleeves": "3b4a5a", "hair": "272b36", "hat": "a88b5c", "beard": "272b36"}, arms)


def bake(group, out_name):
    """套用變換、依面朝向塗分階頂點色（Ink）、合併；發光零件另成 *_Ember"""
    objs = [o for o in coll(group).objects if o.type == "MESH"]
    for o in objs:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    result = []
    for subset, suffix in (([o for o in objs if not o["emit"]], ""), ([o for o in objs if o["emit"]], "_Ember")):
        if not subset:
            continue
        for o in subset:
            me = o.data
            layer = me.color_attributes.new(name="Ink", type="BYTE_COLOR", domain="CORNER")
            base = srgb(o["ink"])
            for poly in me.polygons:
                nz = poly.normal.z
                shade = 1.15 if nz > 0.45 else (0.68 if nz < -0.35 else 0.92 + 0.06 * math.sin(poly.center.x * 9 + poly.center.y * 7))
                for li in poly.loop_indices:
                    layer.data[li].color = [min(1, v * shade) for v in base] + [1.0]
        bpy.ops.object.select_all(action="DESELECT")
        for o in subset:
            o.select_set(True)
        bpy.context.view_layer.objects.active = subset[0]
        if len(subset) > 1:
            bpy.ops.object.join()
        j = bpy.context.view_layer.objects.active
        j.name = out_name + suffix
        mat = bpy.data.materials.new("Ink" + suffix)
        mat.use_nodes = True
        nt = mat.node_tree
        sh = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if sh is None:
            sh = nt.nodes.new("ShaderNodeBsdfPrincipled")
            out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or nt.nodes.new("ShaderNodeOutputMaterial")
            nt.links.new(sh.outputs[0], out.inputs["Surface"])
        sh.inputs["Roughness"].default_value = 0.8
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Ink"
        nt.links.new(vc.outputs["Color"], sh.inputs["Base Color"])
        if suffix:
            nt.links.new(vc.outputs["Color"], sh.inputs["Emission Color"])
            sh.inputs["Emission Strength"].default_value = 4.0
        j.data.materials.clear()
        j.data.materials.append(mat)
        result.append(j)
    return result


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT, exist_ok=True)
    for name, build in (("Smith", build_smith), ("Merchant", build_merchant)):
        build(name)
        joined = bake(name, name)
        bpy.ops.object.select_all(action="DESELECT")
        for o in joined:
            o.select_set(True)
        path = os.path.join(OUT, name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
        print("wrote", path, sum(len(p.vertices) - 2 for o in joined for p in o.data.polygons), "tris")


if __name__ == "__main__":
    main()
