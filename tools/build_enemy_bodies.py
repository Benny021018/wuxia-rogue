"""以 Quaternius 的 Universal Base Characters 與 Modular Character Outfits - Fantasy（皆 CC0）組出每隻敵人的身體。

    python3.11 tools/build_enemy_bodies.py <素材資料夾>

素材資料夾放兩包解壓後的 Standard 版：
  Universal Base Characters[Standard]/、Modular Character Outfits - Fantasy[Standard]/
需要 Blender 的 Python 模組（pip install bpy，Python 3.11）。
外觀設定在 data/enemy_looks.csv；輸出 assets/models/enemy-bodies/<ID>.glb（只有骨架與網格，動作由 tools/bake_enemy_motion.py 加上）。
骨架與 Universal Animation Library 相同（65 根骨頭），可以直接套用現有動作。
"""
import csv
import sys
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(sys.argv[-1])
UBC = SRC / "Universal Base Characters[Standard]"
OUT_FITS = SRC / "Modular Character Outfits - Fantasy[Standard]"
GLTF = OUT_FITS / "Exports/glTF (Godot-Unreal)/Outfits"
HAIR = UBC / "Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)"
HERO = UBC / "Base Characters/Godot - UE"
DEST = ROOT / "assets/models/enemy-bodies"
TEX = 512
COLORIZE = 0.75          # 服裝、皮膚往 enemy_looks.csv 指定色調靠的比例
OUTFITS = {"peasant_m": "Male_Peasant", "peasant_f": "Female_Peasant", "ranger_m": "Male_Ranger", "ranger_f": "Female_Ranger"}
VARIANT = {("Peasant", "2"): "T_Peasant_2_BaseColor", ("Ranger", "3"): "T_Ranger_3_BaseColor"}


def srgb(hexstr):
    return np.array([int(hexstr[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def imported(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
    return [o for o in bpy.data.objects if o not in before]


def armature_of(objs):
    return next(o for o in objs if o.type == "ARMATURE")


def head_pos(arm):
    return arm.matrix_world @ arm.data.bones["Head"].head_local


def bind(mesh, arm):
    mesh.parent = arm
    mesh.matrix_parent_inverse = arm.matrix_world.inverted()
    mod = next((m for m in mesh.modifiers if m.type == "ARMATURE"), None) or mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


def shift(mesh, delta):
    for v in mesh.data.vertices:
        v.co = v.co + mesh.matrix_world.inverted().to_3x3() @ delta


def keep_head(mesh):
    """只留下以 Head、neck_01 為主要權重的頂點（嫁接到服裝身上）"""
    names = {g.index: g.name for g in mesh.vertex_groups}
    drop = []
    for v in mesh.data.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        if best is None or names[best.group] not in ("Head", "neck_01"):
            drop.append(v.index)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(mesh.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in drop], context="VERTS")
    bm.to_mesh(mesh.data)
    bm.free()


def tinted(img_path, tint, key):
    """縮成 TEX 大小並把色調乘進貼圖（遊戲不用法線貼圖，維持墨感）"""
    name = "%s_%s" % (key, "".join("%02x" % int(c * 255) for c in tint))
    if name in bpy.data.images:
        return bpy.data.images[name]
    src = bpy.data.images.load(str(img_path), check_existing=True)
    src.scale(TEX, TEX)
    px = np.array(src.pixels[:]).reshape(-1, 4)
    if not np.allclose(tint, 1.0):
        # 上色：保留原貼圖的明暗，往指定色調靠（比直接相乘亮，顏色也比較分得開）
        lum = px[:, :3] @ np.array([0.3, 0.59, 0.11])
        colored = np.clip(lum[:, None] * tint[None, :] * 2.2, 0.0, 1.0)
        px[:, :3] = px[:, :3] * (1.0 - COLORIZE) + colored * COLORIZE
    img = bpy.data.images.new(name, TEX, TEX, alpha=True)
    img.pixels[:] = px.ravel()
    img.file_format = "JPEG"
    return img


def find_tex(stem):
    for base in (OUT_FITS / "Textures", UBC, HERO.parent):
        hits = list(base.rglob(stem + ".png"))
        if hits:
            return hits[0]
    raise FileNotFoundError(stem)


def restyle(obj, row):
    """每個材質換成單一貼圖（已縮小、已上色）的 Principled，去掉法線與粗糙度貼圖"""
    for slot in obj.material_slots:
        m = slot.material
        if m is None or not m.use_nodes:
            continue
        tex = next((n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image and "Normal" not in n.image.name and "Rough" not in n.image.name and "ORM" not in n.image.name), None)
        mname = m.name.split(".")[0]
        if "Eye" in mname:
            continue
        if tex is None:
            continue
        stem = Path(tex.image.filepath or tex.image.name).stem.replace("_png", "")
        if "Peasant" in mname:
            stem = VARIANT.get(("Peasant", row["variant"]), "T_Peasant_BaseColor")
            tint = srgb(row["cloth_tint"])
        elif "Ranger" in mname:
            stem = VARIANT.get(("Ranger", row["variant"]), "T_Ranger_BaseColor")
            tint = srgb(row["cloth_tint"])
        elif "Hair" in mname:
            tint = srgb(row["hair_tint"] or "ffffff")
        else:
            tint = srgb(row["skin_tint"])
        img = tinted(find_tex(stem), tint, stem)
        new = bpy.data.materials.new("%s_%s" % (row["enemy_id"], mname))
        new.use_nodes = True
        bsdf = new.node_tree.nodes["Principled BSDF"]
        t = new.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = img
        new.node_tree.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.8
        bsdf.inputs["Metallic"].default_value = 0.0
        slot.material = new


def build(row):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    hero_m = row["outfit"] == "hero_m"
    female = row["outfit"].endswith("_f")
    hero_file = HERO / ("Superhero_Female_FullBody.gltf" if female else "Superhero_Male_FullBody.gltf")
    if hero_m:
        objs = imported(hero_file)
        arm = armature_of(objs)
    else:
        objs = imported(GLTF / (OUTFITS[row["outfit"]] + ".gltf"))
        arm = armature_of(objs)
        if row["hood"] != "1":
            for o in objs:
                if "Hood" in o.name:
                    bpy.data.objects.remove(o)
        # 服裝沒有頭：從同性別的基礎角色取頭、眼睛、眉毛，對齊到服裝骨架的頭骨位置
        hero = imported(hero_file)
        h_arm = armature_of(hero)
        delta = head_pos(arm) - head_pos(h_arm)
        for o in hero:
            if o.type != "MESH":
                continue
            if o.name.startswith(("SuperHero", "Superhero")):
                keep_head(o)
            o.data = o.data.copy()
            shift(o, delta)
            bind(o, arm)
        bpy.data.objects.remove(h_arm)
    for h in [x for x in row["hair"].split("|") if x]:
        parts = imported(HAIR / (h + ".gltf"))
        h_arm = next((o for o in parts if o.type == "ARMATURE"), None)
        delta = head_pos(arm) - (head_pos(h_arm) if h_arm else head_pos(arm))
        for o in parts:
            if o.type == "MESH":
                shift(o, delta)
                bind(o, arm)
        if h_arm:
            bpy.data.objects.remove(h_arm)
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            restyle(o, row)
    DEST.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(DEST / (row["enemy_id"] + ".glb")), export_format="GLB",
                              export_animations=False, export_image_format="JPEG", export_jpeg_quality=80,
                              export_normals=True, export_tangents=False, export_skins=True, export_yup=True)


rows = list(csv.DictReader((ROOT / "data/enemy_looks.csv").open(encoding="utf-8")))
only = [a for a in sys.argv[1:-1] if not a.startswith("-")]
for r in rows:
    if only and r["enemy_id"] not in only:
        continue
    build(r)
    print("built", r["enemy_id"])
