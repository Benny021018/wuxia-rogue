"""把 MoCapAnything 輸出的 BVH 轉成南宮（Nangong.glb）的動作，匯出 NangongMocap.glb 給 Godot。

用法（Blender 背景模式）：
  blender -b --factory-startup --python mocap_to_nangong.py -- <job.json>

job.json：
  {"glb": "...Nangong.glb", "out": "...NangongMocap.glb", "report": "...report.json",
   "clips": [{"bvh": "...atk.bvh", "name": "NGM_Atk", "splits": [[0, 12, "NGM_N1"], ...]}, ...]}
splits 省略時只輸出整段；有 splits 時，整段和每一小段都會輸出（小段依 BVH 幀號切）。

做法：BVH 和 Nangong.glb 骨頭同名（MoCapAnything 是用南宮骨架當參考），
每一幀在世界座標比對「目前姿勢相對預設姿勢的旋轉」，套到南宮的同名骨頭上；
兩邊預設姿勢的朝向差用骨盆算一次。根骨只保留上下位移，水平前衝交給遊戲的 lunge。

影片推回來的整體朝向（BVH 的 root 旋轉）跟著鏡頭亂跳，所以預設把它清成預設姿勢，
只留骨盆以下的相對轉動（job 的 "keep_root_rotation": true 可保留）。
烘好的四元數會先對齊正負號，再做 smooth 幀的平滑（job 的 "smooth"，預設 1 = 前後各 1 幀）。
"""
import bpy, json, sys, math
from mathutils import Matrix, Quaternion, Vector

job = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
report = {"clips": []}
made = []

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=job["glb"])
T = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
T.animation_data_create()
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
T.animation_data.action = None
bpy.context.view_layer.objects.active = T
bpy.ops.object.mode_set(mode="POSE")
for pb in T.pose.bones:
    pb.rotation_mode = "QUATERNION"
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()


def fcurves_of(act, owner=None):
    """Blender 4.4 以後的 Action 改成分層＋slot，fcurves 要從 channelbag 拿。"""
    if hasattr(act, "fcurves"):
        return act.fcurves
    from bpy_extras import anim_utils
    if len(act.slots) == 0:
        act.slots.new(id_type="OBJECT", name=(owner or T).name)
    return anim_utils.action_ensure_channelbag_for_slot(act, act.slots[0]).fcurves


def norm(n):
    return n.lower().replace(" ", "_").replace(":", "_")


def chain(arm):
    out, todo = [], [b for b in arm.data.bones if b.parent is None]
    while todo:
        b = todo.pop(0)
        out.append(b.name)
        todo = list(b.children) + todo
    return out


T_order = chain(T)
T_rest = {n: T.matrix_world @ T.data.bones[n].matrix_local for n in T_order}
ROOT = "pelvis" if "pelvis" in T.data.bones else T_order[0]


def import_bvh(path, keep_root_rotation=False):
    before = set(bpy.data.objects)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.import_anim.bvh(filepath=path, axis_forward="-Z", axis_up="Y", rotate_mode="NATIVE",
                            update_scene_fps=True, update_scene_duration=True, use_fps_scale=False)
    S = [o for o in bpy.data.objects if o not in before and o.type == "ARMATURE"][0]
    top = [b.name for b in S.data.bones if b.parent is None][0]
    if not keep_root_rotation and top != "pelvis":
        for fc in fcurves_of(S.animation_data.action, S):
            if fc.data_path.startswith('pose.bones["%s"].rotation' % top):
                ident = 1.0 if (fc.data_path.endswith("quaternion") and fc.array_index == 0) else 0.0
                for k in fc.keyframe_points:
                    k.co.y = ident
                    k.handle_left.y = ident
                    k.handle_right.y = ident
    return S


def smooth_quats(act, radius):
    """每根骨頭的四元數：先對齊正負號，再做 [1,2,1] 型的平滑，最後正規化。"""
    groups = {}
    for fc in fcurves_of(act):
        if fc.data_path.endswith("rotation_quaternion"):
            groups.setdefault(fc.data_path, [None] * 4)[fc.array_index] = fc
    for fcs in groups.values():
        if None in fcs:
            continue
        n = len(fcs[0].keyframe_points)
        q = [[fcs[i].keyframe_points[f].co.y for i in range(4)] for f in range(n)]
        for f in range(1, n):
            if sum(a * b for a, b in zip(q[f], q[f - 1])) < 0:
                q[f] = [-v for v in q[f]]
        for _ in range(radius):
            q = [[(q[max(f - 1, 0)][i] + 2 * q[f][i] + q[min(f + 1, n - 1)][i]) / 4 for i in range(4)]
                 for f in range(n)]
        for f in range(n):
            l = math.sqrt(sum(v * v for v in q[f])) or 1.0
            for i in range(4):
                fcs[i].keyframe_points[f].co.y = q[f][i] / l
        for fc in fcs:
            fc.update()


def bake(S, name):
    sc = bpy.context.scene
    act = S.animation_data.action
    f0, f1 = (int(round(v)) for v in act.frame_range)
    s_names = {norm(b.name): b.name for b in S.data.bones}
    mapping = {n: s_names[norm(n)] for n in T_order if norm(n) in s_names}
    missing = [n for n in T_order if n not in mapping]
    if ROOT not in mapping:
        raise SystemExit("BVH 沒有骨盆骨頭 %s；BVH 骨頭：%s" % (ROOT, list(s_names.values())[:20]))
    sc.frame_set(f0)
    S_rest = {n: S.matrix_world @ S.data.bones[mapping[n]].matrix_local for n in mapping}
    # 兩邊預設姿勢的朝向差（只取繞上軸的部分，避免把姿勢差也算進去）
    g = (T_rest[ROOT].to_quaternion() @ S_rest[ROOT].to_quaternion().inverted())
    yaw = g.to_euler("XYZ").z
    G = Quaternion((0, 0, 1), yaw)
    # 身高比例：用骨盆到腳的距離
    foot_t = next((n for n in ("foot_l", "foot_r") if n in mapping), None)
    scale = 1.0
    if foot_t:
        st = (S_rest[ROOT].translation - S_rest[foot_t].translation).length
        tt = (T_rest[ROOT].translation - T_rest[foot_t].translation).length
        scale = tt / st if st > 1e-6 else 1.0
    T.animation_data.action = None
    new = bpy.data.actions.new(name)
    T.animation_data.action = new
    root_rest_s = S_rest[ROOT].translation.copy()
    hand = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for n in T_order:
            pb = T.pose.bones[n]
            if n in mapping:
                ms = S.matrix_world @ S.pose.bones[mapping[n]].matrix
                rs = S_rest[n]
                rot = G @ ms.to_quaternion() @ rs.to_quaternion().inverted() @ G.inverted() @ T_rest[n].to_quaternion()
            else:
                parent = pb.parent
                pw = (T.matrix_world @ parent.matrix) if parent else Matrix.Identity(4)
                prw = (T_rest[parent.name]) if parent else Matrix.Identity(4)
                rot = pw.to_quaternion() @ prw.to_quaternion().inverted() @ T_rest[n].to_quaternion()
            if n == ROOT:
                d = G @ ((S.matrix_world @ S.pose.bones[mapping[n]].matrix).translation - root_rest_s) * scale
                pos = T_rest[n].translation + Vector((0.0, 0.0, d.z))     # 只保留上下
            else:
                pw = (T.matrix_world @ pb.parent.matrix) if pb.parent else Matrix.Identity(4)
                local = T_rest[pb.parent.name].inverted() @ T_rest[n] if pb.parent else T_rest[n]
                pos = (pw @ local).translation
            m = Matrix.Translation(pos) @ rot.to_matrix().to_4x4()
            pb.matrix = T.matrix_world.inverted() @ m
            bpy.context.view_layer.update()
            pb.keyframe_insert("rotation_quaternion", frame=f - f0)
            if n == ROOT:
                pb.keyframe_insert("location", frame=f - f0)
        if "hand_r" in T.pose.bones:
            hand.append(list((T.matrix_world @ T.pose.bones["hand_r"].matrix).translation))
    return new, {"name": name, "frames": f1 - f0 + 1, "fps": sc.render.fps / sc.render.fps_base,
                 "missing_bones": missing, "yaw_deg": math.degrees(yaw), "scale": scale, "hand_r": hand}


def sub_action(src, name, a, b):
    act = bpy.data.actions.new(name)
    dst = fcurves_of(act)
    for fc in fcurves_of(src):
        nf = dst.new(fc.data_path, index=fc.array_index)
        for k in fc.keyframe_points:
            if a <= k.co.x <= b:
                nf.keyframe_points.insert(k.co.x - a, k.co.y, options={"FAST"})
    return act


for clip in job["clips"]:
    S = import_bvh(clip["bvh"], job.get("keep_root_rotation", False))
    bpy.context.view_layer.objects.active = T
    bpy.ops.object.mode_set(mode="POSE")
    act, info = bake(S, clip["name"])
    smooth_quats(act, int(job.get("smooth", 1)))
    made.append(act)
    for sp in clip.get("splits", []):
        made.append(sub_action(act, sp[2], sp[0], sp[1]))
    info["splits"] = clip.get("splits", [])
    report["clips"].append(info)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.data.objects.remove(S, do_unlink=True)

# 只匯出這次烘好的動作：清掉匯入時帶進來的 NLA 與其他 action，用 ACTIONS 模式匯出
for tr in list(T.animation_data.nla_tracks):
    T.animation_data.nla_tracks.remove(tr)
T.animation_data.action = None
for a in list(bpy.data.actions):
    if a not in made:
        bpy.data.actions.remove(a)
for a in made:
    a.use_fake_user = True
    fcs = fcurves_of(a)
    pel = [fc for fc in fcs if fc.data_path == 'pose.bones["%s"].rotation_quaternion' % ROOT]
    arm = [fc for fc in fcs if fc.data_path == 'pose.bones["upperarm_r"].rotation_quaternion']
    span = lambda l: round(max(max(k.co.y for k in fc.keyframe_points) - min(k.co.y for k in fc.keyframe_points) for fc in l), 3) if l else None
    print("ACTION", a.name, "fcurves", len(fcs), "pelvis_span", span(pel), "upperarm_r_span", span(arm))
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.export_scene.gltf(filepath=job["out"], export_format="GLB", export_animations=True,
                          export_animation_mode="ACTIONS", export_materials="NONE",
                          export_image_format="NONE", export_force_sampling=True,
                          export_frame_range=False)
json.dump(report, open(job["report"], "w", encoding="utf-8"), ensure_ascii=False)
print("MOCAP_DONE", [c["name"] for c in report["clips"]], [a.name for a in made])
