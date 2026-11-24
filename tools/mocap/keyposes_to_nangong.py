"""把手寫的關鍵姿勢擺到南宮骨架上，匯出給 Cascadeur 繼續修（也可匯出 GLB 給遊戲預覽）。

用法（Blender 或 pip 的 bpy 模組皆可）：
    blender -b --factory-startup --python keyposes_to_nangong.py -- poses.json
    python keyposes_to_nangong.py poses.json

poses.json：
{
  "glb": "Nangong.glb 路徑",
  "fps": 30,
  "fbx_dir": "輸出 FBX 的資料夾",      # 每個 clip 一個 FBX，只有關鍵幀（階梯式），方便在 Cascadeur 補間
  "glb_out": "預覽用 GLB（可省略）",    # 關鍵幀之間用平滑補間，給遊戲 ModelCapture 截圖對照
  "clips": [{"name": "NGK_Atk", "keys": [{"t": 0.0, ...姿勢...}, ...]}]
}

姿勢欄位（座標一律用角色空間：r＝角色右方、f＝前方、u＝上方，單位公尺／度）：
  hips:   {"drop": 下蹲, "r": 左右移, "f": 前後移, "yaw": 轉身（正＝向左轉）, "pitch": 前傾, "roll": 側傾}
  chest:  {"yaw": 上身再轉, "pitch": 上身再前傾, "roll": 側彎}      # 平均分給 spine_01～03
  head_yaw: 頭相對前方的轉角（預設 0＝一直看前方的敵人）
  feet:   {"l": [r, f, 轉角], "r": [r, f, 轉角]}                   # 腳踝位置（貼地）
  rhand:  {"p": [r, f, u], "blade": [r, f, u], "edge": [r, f, u]}  # 右手位置、刀尖方向、刃（刀弧凸面）朝向
  lhand:  {"p": [r, f, u]}
手伸不到的位置會自動拉回手臂長度內。
"""
import json
import math
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv
args = argv[argv.index("--") + 1:] if "--" in argv else argv[1:]
job = json.load(open(args[0], encoding="utf-8"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=job["glb"])
A = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
for a in list(bpy.data.actions):
    a.use_fake_user = False
if A.animation_data:
    A.animation_data.action = None
    for tr in list(A.animation_data.nla_tracks):
        A.animation_data.nla_tracks.remove(tr)
sc = bpy.context.scene
sc.render.fps = int(job.get("fps", 30))

# 角色空間：Blender 裡南宮面向 -Y、右手在 -X
R_ = Vector((-1, 0, 0))
F_ = Vector((0, -1, 0))
U_ = Vector((0, 0, 1))


def cv(v):
    return R_ * v[0] + F_ * v[1] + U_ * v[2]


def rot(axis, deg):
    return Quaternion(axis, math.radians(deg))


bpy.context.view_layer.objects.active = A
bpy.ops.object.mode_set(mode="POSE")
P = A.pose.bones
D = A.data.bones
for pb in P:
    pb.rotation_mode = "QUATERNION"


def rest_m(n):
    return D[n].matrix_local.copy()


def upd():
    bpy.context.view_layer.update()


def set_world(n, q, head=None):
    """把骨頭在骨架空間的朝向設成 q × 預設朝向；head 給定時也移動位置。"""
    pb = P[n]
    m0 = rest_m(n)
    pos = head if head is not None else pb.matrix.translation.copy()
    pb.matrix = Matrix.Translation(pos) @ (q.to_matrix().to_4x4() @ m0.to_3x3().to_4x4())
    upd()


# ---------- 刀：以刀柄→刀尖連線為軸轉正，讓凸面（刃）朝指根方向（與遊戲 fighter_model._align_blade 相同）
blade = bpy.data.objects.get("DrawnBlade")
hand_m = rest_m("hand_r")
knuckle_w = (D["middle_01_r"].head_local - D["hand_r"].head_local)
if blade:
    vs = [blade.matrix_world @ v.co for v in blade.data.vertices]
    ys = [p.y for p in vs]
    lo, hi = min(ys), max(ys)
    band = (hi - lo) * 0.02
    a = [p for p in vs if p.y > hi - band]           # 刀柄端（+Y，靠手）
    b = [p for p in vs if p.y < lo + band]           # 刀尖端
    root = sum(a, Vector()) / len(a)
    tip = sum(b, Vector()) / len(b)
    axis = (tip - root).normalized()
    length = (tip - root).length
    bulge = Vector()
    for p in vs:
        al = (p - root).dot(axis)
        if length * 0.3 < al < length * 0.7:
            bulge += (p - root) - axis * al
    want = knuckle_w - axis * knuckle_w.dot(axis)
    ang = bulge.normalized().rotation_difference(want.normalized())
    turn = ang.to_matrix()
    inv = blade.matrix_world.inverted()
    for v, p in zip(blade.data.vertices, vs):
        v.co = inv @ (root + turn @ (p - root))
    blade.data.update()
    BLADE_AXIS = axis
else:
    BLADE_AXIS = Vector((0, -1, 0))
EDGE_REST = (knuckle_w - BLADE_AXIS * knuckle_w.dot(BLADE_AXIS)).normalized()

# 握刀的手指：取 NG_RaiseSlash 中段的手指姿勢
FINGERS = [n for n in P.keys() if any(k in n for k in ("thumb", "index", "middle", "ring", "pinky"))]
finger_pose = {}
src = bpy.data.actions.get("NG_RaiseSlash")
if src:
    A.animation_data_create()
    A.animation_data.action = src
    sc.frame_set(int((src.frame_range[0] + src.frame_range[1]) / 2))
    for n in FINGERS:
        finger_pose[n] = P[n].rotation_quaternion.copy()
    A.animation_data.action = None
for pb in P:
    pb.matrix_basis = Matrix.Identity(4)
upd()

# ---------- IK
def empty(name):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    return e


IK = {}
for side, chain_end in (("r", "lowerarm_r"), ("l", "lowerarm_l"), ("fr", "calf_r"), ("fl", "calf_l")):
    t, p = empty("T_" + side), empty("P_" + side)
    c = P[chain_end].constraints.new("IK")
    c.target, c.pole_target, c.chain_count = t, p, 2
    IK[side] = (t, p, c)

ARM = (D["upperarm_r"].head_local - D["lowerarm_r"].head_local).length + \
      (D["lowerarm_r"].head_local - D["hand_r"].head_local).length
LEG = (D["thigh_r"].head_local - D["calf_r"].head_local).length + \
      (D["calf_r"].head_local - D["foot_r"].head_local).length
TORSO = ["pelvis", "spine_01", "spine_02", "spine_03"]


def pose(k):
    for pb in P:
        pb.matrix_basis = Matrix.Identity(4)
    upd()
    h = k.get("hips", {})
    yaw = rot(U_, h.get("yaw", 0))
    q_p = yaw @ rot(R_, -h.get("pitch", 0)) @ rot(F_, h.get("roll", 0))
    ph = D["pelvis"].head_local + cv([h.get("r", 0), h.get("f", 0), -h.get("drop", 0)])
    set_world("pelvis", q_p, ph)
    c = k.get("chest", {})
    for i, n in enumerate(TORSO[1:], 1):
        f = i / 3.0
        q = q_p @ rot(U_, c.get("yaw", 0) * f) @ rot(R_, -c.get("pitch", 0) * f) @ rot(F_, c.get("roll", 0) * f)
        set_world(n, q)
    q_chest = q_p @ rot(U_, c.get("yaw", 0)) @ rot(R_, -c.get("pitch", 0)) @ rot(F_, c.get("roll", 0))
    for n in ("clavicle_r", "clavicle_l"):
        set_world(n, q_chest)
    set_world("neck_01", q_chest)
    # 頭：轉回看前方，只保留 head_yaw
    set_world("Head", rot(U_, k.get("head_yaw", 0)) @ rot(R_, -k.get("head_pitch", 0)))
    # 腳
    ft = k.get("feet", {})
    for s, foot in (("r", "foot_r"), ("l", "foot_l")):
        rest = D[foot].head_local
        d = ft.get(s, [rest.dot(R_), rest.dot(F_), 0])
        target = cv([d[0], d[1], 0]) + U_ * rest.z
        hip = P["thigh_" + s].head
        if (target - hip).length > LEG * 0.995:
            target = hip + (target - hip).normalized() * LEG * 0.995
        t, p, _ = IK["f" + s]
        t.location = target
        knee_dir = rot(U_, d[2] if len(d) > 2 else 0) @ F_
        p.location = (hip + target) / 2 + knee_dir * 0.6
    # 手
    for s in ("r", "l"):
        hk = k.get(s + "hand")
        t, p, _ = IK[s]
        sh = P["upperarm_" + s].head.copy()
        if hk:
            target = cv(hk["p"])
        else:
            target = sh + cv([0.12 if s == "r" else -0.12, 0.05, -ARM * 0.95])
        if (target - sh).length > ARM * 0.97:
            target = sh + (target - sh).normalized() * ARM * 0.97
        t.location = target
        side = R_ if s == "r" else -R_
        p.location = (sh + target) / 2 + side * 0.4 - U_ * 0.3 - F_ * 0.15
    upd()
    # 右手掌朝向：刀尖方向與刃的朝向
    hk = k.get("rhand")
    if hk:
        d = cv(hk["blade"]).normalized()
        e = cv(hk.get("edge", [0, 1, 0]))
        e = (e - d * e.dot(d))
        if e.length < 1e-4:
            e = U_ - d * U_.dot(d)
        e.normalize()
        src_b = Matrix((BLADE_AXIS, EDGE_REST, BLADE_AXIS.cross(EDGE_REST))).transposed()
        dst_b = Matrix((d, e, d.cross(e))).transposed()
        q = (dst_b @ src_b.inverted()).to_quaternion()
        set_world("hand_r", q, P["hand_r"].head.copy())
    if k.get("lhand"):
        set_world("hand_l", q_chest @ rot(F_, -20), P["hand_l"].head.copy())
    for n, q in finger_pose.items():
        P[n].rotation_quaternion = q
    # 腳掌貼平、跟著腳的轉角
    for s in ("r", "l"):
        d = ft.get(s)
        set_world("foot_" + s, rot(U_, d[2] if d and len(d) > 2 else 0), P["foot_" + s].head.copy())
    upd()


def snapshot():
    return {pb.name: pb.matrix.copy() for pb in P}


def bake_clip(clip):
    fps = sc.render.fps
    shots = []
    for k in clip["keys"]:
        pose(k)
        shots.append((int(round(k["t"] * fps)), snapshot()))
    return shots


# 先試出 IK 的 pole_angle（讓手肘、膝蓋落在 pole 那一側）
def best_pole(side, mid_bone):
    t, p, c = IK[side]
    best = None
    for ang in (-180, -90, 0, 90):
        c.pole_angle = math.radians(ang)
        upd()
        d = (P[mid_bone].head - p.location).length
        if best is None or d < best[1]:
            best = (ang, d)
    c.pole_angle = math.radians(best[0])
    return best[0]


first = job["clips"][0]["keys"][0]
pose(first)
for side, mid in (("r", "lowerarm_r"), ("l", "lowerarm_l"), ("fr", "calf_r"), ("fl", "calf_l")):
    print("POLE", side, best_pole(side, mid))

baked = [(clip, bake_clip(clip)) for clip in job["clips"]]

# 拿掉 IK，把記下的姿勢寫成關鍵幀
for pb in P:
    for c in list(pb.constraints):
        pb.constraints.remove(c)
for e in [o for o in bpy.data.objects if o.type == "EMPTY" and o.name[:2] in ("T_", "P_")]:
    bpy.data.objects.remove(e)
upd()

order = [b.name for b in A.data.bones if b.parent is None]
i = 0
while i < len(order):
    order += [c.name for c in D[order[i]].children]
    i += 1

actions = []
for clip, shots in baked:
    act = bpy.data.actions.new(clip["name"])
    A.animation_data_create()
    A.animation_data.action = act
    for frame, snap in shots:
        for pb in P:
            pb.matrix_basis = Matrix.Identity(4)
        for n in order:
            P[n].matrix = snap[n]
            upd()
        for n in order:
            P[n].keyframe_insert("rotation_quaternion", frame=frame)
            if n in ("root", "pelvis"):
                P[n].keyframe_insert("location", frame=frame)
    act.use_fake_user = True
    actions.append(act)
    print("CLIP", clip["name"], "KEYFRAMES", [f for f, _ in shots])


def fcurves_of(act):
    if hasattr(act, "fcurves"):
        return act.fcurves
    from bpy_extras import anim_utils
    return anim_utils.action_ensure_channelbag_for_slot(act, act.slots[0]).fcurves


bpy.ops.object.mode_set(mode="OBJECT")
keep = {"Armature", "Body", "Face", "Hair", "DrawnBlade", "FlatSaya", "Spring_01_ponytail", "Spring_02_skirt"}
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name not in keep:
        bpy.data.objects.remove(o)

# 給 Cascadeur：每個 clip 一個 FBX，關鍵姿勢之間用平滑補間、逐幀烘焙。
# FBX 存不了補間方式，Cascadeur 匯入後用「Animation Unbaking」可轉回關鍵幀＋補間；關鍵姿勢的幀號會印在 KEYFRAMES 行
if job.get("fbx_dir"):
    import os
    os.makedirs(job["fbx_dir"], exist_ok=True)
    for act in actions:
        A.animation_data.action = act
        for fc in fcurves_of(act):
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
        f0, f1 = (int(v) for v in act.frame_range)
        sc.frame_start, sc.frame_end = f0, f1
        out = os.path.join(job["fbx_dir"], act.name + ".fbx")
        bpy.ops.export_scene.fbx(filepath=out, use_selection=False, object_types={"ARMATURE", "MESH"},
                                 add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False,
                                 bake_anim_use_nla_strips=False, bake_anim_force_startend_keying=True,
                                 bake_anim_simplify_factor=float(job.get("simplify", 0.0)), path_mode="COPY", embed_textures=True,
                                 armature_nodetype="NULL", primary_bone_axis="Y", secondary_bone_axis="X")
        print("FBX", out)

# 給遊戲預覽：平滑補間
if job.get("glb_out"):
    for act in actions:
        for fc in fcurves_of(act):
            for kp in fc.keyframe_points:
                kp.interpolation = "BEZIER"
    A.animation_data.action = None
    for a in list(bpy.data.actions):
        if a not in actions:
            bpy.data.actions.remove(a)
    bpy.ops.export_scene.gltf(filepath=job["glb_out"], export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_materials="NONE",
                              export_image_format="NONE", export_force_sampling=True)
    print("GLB", job["glb_out"])
print("KEYPOSES_DONE")
