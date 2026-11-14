"""Bake curated combat clips onto each enemy body. Requires NumPy and SciPy; see docs/enemy-motion.md.

Bodies come from assets/models/enemy-bodies/<ID>.glb (tools/build_enemy_bodies.py); enemies without one use the UAL mannequin.
Clips named legacy:<clip> are retargeted from <donors>/<ID>_legacy.glb (the archer's former 16-bone rig).
B04 needs <donors>/bird.glb; without it the existing B04.glb is kept."""
from pathlib import Path
import argparse
import csv
import json
import struct
from copy import deepcopy

import numpy as np
from scipy.spatial.transform import Rotation as R, Slerp

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "assets/models"
OUT = MODEL / "enemy-motion"
BANDITS: set = set()           # 舊的 16 骨山寨模型已換成 enemy-bodies；保留機制給 legacy 片段
BODIES = MODEL / "enemy-bodies"
KEEP_TRANSLATION = {"root", "pelvis"}   # 其他骨頭只套旋轉，保留各身體自己的骨長
IDENTITY = [0, 0, 0, 1]


class Glb:
    def __init__(self, path):
        raw = path.read_bytes()
        length = struct.unpack_from("<I", raw, 12)[0]
        self.doc = json.loads(raw[20:20 + length])
        self.bin = bytearray(raw[28 + length:])
        self.names = {n.get("name"): i for i, n in enumerate(self.doc["nodes"])}
        self.clips = {a["name"]: a for a in self.doc.get("animations", [])}

    def read(self, idx):
        a = self.doc["accessors"][idx]
        v = self.doc["bufferViews"][a["bufferView"]]
        assert a["componentType"] == 5126 and "byteStride" not in v
        cols = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[a["type"]]
        return np.frombuffer(self.bin, "<f4", a["count"] * cols,
                             v.get("byteOffset", 0) + a.get("byteOffset", 0)).reshape(-1, cols).copy()

    def add(self, values):
        v = np.ascontiguousarray(values, dtype="<f4")
        view = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": v.nbytes}
        a = {"bufferView": len(self.doc["bufferViews"]), "componentType": 5126,
             "count": len(v), "type": {1: "SCALAR", 3: "VEC3", 4: "VEC4"}[v.shape[1]],
             "min": v.min(axis=0).tolist(), "max": v.max(axis=0).tolist()}
        self.bin.extend(v.tobytes())
        self.doc["bufferViews"].append(view)
        self.doc["accessors"].append(a)
        return len(self.doc["accessors"]) - 1

    def write(self, path):
        # Compact the buffer so discarded source actions leave no hidden curves.
        d = deepcopy(self.doc)
        acc_refs = []
        for m in d["meshes"]:
            for p in m["primitives"]:
                acc_refs.extend((p["attributes"], k) for k in p["attributes"])
                if "indices" in p:
                    acc_refs.append((p, "indices"))
        for s in d["skins"]:
            acc_refs.append((s, "inverseBindMatrices"))
        for a in d["animations"]:
            for s in a["samplers"]:
                acc_refs.extend([(s, "input"), (s, "output")])
        def compact(items, refs):
            ids = sorted({obj[key] for obj, key in refs})
            mapping = {old: new for new, old in enumerate(ids)}
            for obj, key in refs:
                obj[key] = mapping[obj[key]]
            return [items[i] for i in ids]
        d["accessors"] = compact(d["accessors"], acc_refs)
        refs = [(a, "bufferView") for a in d["accessors"] + d.get("images", []) if "bufferView" in a]
        d["bufferViews"] = compact(d["bufferViews"], refs)
        data = bytearray()
        for v in d["bufferViews"]:
            data.extend(bytes(-len(data) % 4))
            off = v.get("byteOffset", 0)
            v["byteOffset"] = len(data)
            data.extend(self.bin[off:off + v["byteLength"]])
        d["buffers"] = [{"byteLength": len(data)}]
        data.extend(bytes(-len(data) % 4))
        header = json.dumps(d, separators=(",", ":"), ensure_ascii=False).encode()
        header += b" " * (-len(header) % 4)
        path.write_bytes(struct.pack("<4sIII4s", b"glTF", 2, 28 + len(header) + len(data), len(header), b"JSON") +
                         header + struct.pack("<I4s", len(data), b"BIN\0") + data)


def pose(model, clip, phase):
    nodes = model.doc["nodes"]
    local = {}
    if clip:
        a = model.clips[clip]
        duration = max(model.read(s["input"])[-1, 0] for s in a["samplers"])
        for ch in a["channels"]:
            s = a["samplers"][ch["sampler"]]
            t = model.read(s["input"])[:, 0]
            v = model.read(s["output"])
            key = ch["target"]["path"]
            at = np.clip(phase * duration, t[0], t[-1])
            if key == "rotation" and len(t) > 1:
                values = Slerp(t, R.from_quat(v))(at).as_quat()
            else:
                values = np.column_stack([np.interp(at, t, col) for col in v.T])
            local[ch["target"]["node"], key] = values
    world = {}
    def visit(i, parent):
        n = nodes[i]
        m = np.broadcast_to(np.eye(4), (len(phase),4,4)).copy()
        m[:, :3, :3] = R.from_quat(local.get((i,"rotation"), n.get("rotation",IDENTITY))).as_matrix() * np.asarray(local.get((i,"scale"),n.get("scale",[1]*3)))[...,None,:]
        m[:, :3, 3] = local.get((i,"translation"),n.get("translation",[0]*3))
        world[i] = parent @ m
        for child in n.get("children",[]):
            visit(child,world[i])
    for root in model.doc["scenes"][0]["nodes"]:
        visit(root,np.eye(4))
    return world,local


def mapping(kay):
    names = {"Hips":"hips","Spine":"spine","Chest":"chest","Head":"head"} if kay else {"Hips":"pelvis","Spine":"spine_01","Chest":"spine_03","Head":"Head"}
    for side,suffix in [("Right","r"),("Left","l")]:
        for target,ual,kk in [("UpLeg","thigh","upperleg"),("Leg","calf","lowerleg"),("Foot","foot","foot"),("Arm","upperarm","upperarm"),("ForeArm","lowerarm","lowerarm"),("Hand","hand","hand")]:
            names[side+target] = kk+"."+suffix if kay else ual+"_"+suffix
    return names


def rotation(m):
    axes=m[:,:3,:3]
    return R.from_matrix(axes / np.linalg.norm(axes,axis=1,keepdims=True))


def retarget(target, source, clip, phases, kay, names=None):
    names=names or mapping(kay)
    base,_=pose(source,None,np.array([0]))
    rest,_=pose(target,None,np.array([0]))
    animated,_=pose(source,clip,phases)
    turn=R.from_euler("y",180,degrees=True)
    result={}
    def visit(i,parent):
        node=target.doc["nodes"][i]
        name=node.get("name")
        orient=parent*R.from_quat(node.get("rotation",IDENTITY))
        if name in names:
            k=source.names[names[name]]
            # Align bone axes from target bind pose to source bind direction first
            # (the mountain bandits have lowered arms, the donors use a T pose).
            bind=rotation(rest[i])
            children=[c for c in node.get("children",[]) if target.doc["nodes"][c].get("name") in names]
            corr=R.identity()
            if len(children)==1:
                c=children[0]
                sk=source.names[names[target.doc["nodes"][c]["name"]]]
                x=rest[c][0,:3,3]-rest[i][0,:3,3]
                y=turn.apply(base[sk][0,:3,3]-base[k][0,:3,3])
                corr,_=R.align_vectors([y/np.linalg.norm(y)],[x/np.linalg.norm(x)])
            orient=turn*rotation(animated[k])*rotation(base[k]).inv()*turn.inv()*corr*bind
            result[i,"rotation"]=(parent.inv()*orient).as_quat()
        for c in node.get("children",[]):
            visit(c,orient)
    for i in target.doc["scenes"][0]["nodes"]:
        visit(i,R.identity())
    return result


def bake(row,target,sources,bandit):
    name,src,seconds=row["action"],row["source_clip"],float(row["seconds"])
    times=np.linspace(0,seconds,max(3,round(seconds*30)+1))
    phase=np.interp(times/seconds,[0,float(row["beat"]),1],[0,float(row["source_beat"]),1])
    if src.startswith("legacy:"):
        # 舊骨架（16 骨山寨模型）上的片段轉到 UAL 骨架：骨名對照反過來用
        source=sources["legacy:"+row["enemy_id"]]
        clip=src.split(":",1)[1]
        names={ual:old for old,ual in mapping(False).items()}
        tracks=retarget(target,source,clip,phase,False,names)
        return _write(name,times,tracks,target)
    source=sources[src]
    if bandit:
        if src=="Ranged_Bow_Draw":
            before=times<=1.15
            left=retarget(target,source,src,np.interp(times[before],[0,.18,.95,1.15],[.31,.31,.90,1]),True)
            right=retarget(target,source,"Ranged_Bow_Release",np.clip((times[~before]-1.15)/.65,0,1),True)
            tracks={k:np.concatenate((v,right[k])) for k,v in left.items()}
        else:
            tracks=retarget(target,source,src,phase,"hips" in source.names)
    else:
        _,local=pose(source,src,phase)
        tracks={(target.names[source.doc["nodes"][i]["name"]],kind):v for (i,kind),v in local.items()
                if source.doc["nodes"][i]["name"] in target.names
                and (kind!="translation" or source.doc["nodes"][i]["name"] in KEEP_TRANSLATION)}
    return _write(name,times,tracks,target)


def _write(name,times,tracks,target):
    result={"name":name,"samplers":[],"channels":[]}
    ta=target.add(times[:,None])
    for (i,kind),values in tracks.items():
        if kind=="rotation":
            values=R.from_quat(values).as_quat()
            for k in range(1,len(values)):
                if np.dot(values[k-1],values[k])<0: values[k]*=-1
        sa=len(result["samplers"])
        result["samplers"].append({"input":ta,"output":target.add(values)})
        result["channels"].append({"sampler":sa,"target":{"node":i,"path":kind}})
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("donors",type=Path,help="Folder with ranged.glb and bird.glb")
    args=parser.parse_args()
    sources={}
    for p in [MODEL/"character/UAL1.glb",MODEL/"character/UAL2.glb",args.donors/"ranged.glb",args.donors/"bird.glb"]:
        if not p.exists():
            print("skip missing donor", p.name)
            continue
        model=Glb(p)
        sources.update({clip:model for clip in model.clips})
    for p in args.donors.glob("*_legacy.glb"):
        sources["legacy:"+p.stem.split("_")[0]]=Glb(p)
    rows=list(csv.DictReader((ROOT/"data/enemy_motion.csv").open(encoding="utf-8-sig")))
    OUT.mkdir(exist_ok=True)
    for eid in dict.fromkeys(r["enemy_id"] for r in rows):
        bandit=eid in BANDITS
        body=BODIES/(eid+".glb")
        path=MODEL/"greenwood"/(eid+".glb") if bandit else (body if body.exists() else MODEL/"character/UAL1.glb")
        bird=eid=="B04"
        if bird and not (args.donors/"bird.glb").exists():
            print("keep existing", eid)
            continue
        target=Glb(args.donors/"bird.glb" if bird else path)
        target.doc["animations"]=[bake(r,target,sources,bandit) for r in rows if r["enemy_id"]==eid]
        if not bandit:
            # Source humanoids face +Z; the enemy controller faces -Z.
            roots=target.doc["scenes"][0]["nodes"]
            wrapper={"name":"Facing","children":roots,"rotation":IDENTITY if bird else [0,1,0,0]}
            if bird: wrapper.update(scale=[2.6]*3,translation=[0,.1,0])
            target.doc["scenes"][0]["nodes"]=[len(target.doc["nodes"])]
            target.doc["nodes"].append(wrapper)
            tint=next(r["tint"] for r in rows if r["enemy_id"]==eid)
            for material in ([] if body.exists() else target.doc["materials"]):
                mat=material.setdefault("pbrMetallicRoughness",{})
                mat["baseColorFactor"]=[int(tint[i:i+2],16)/255 for i in (0,2,4)]+[1]
        target.write(OUT/(eid+".glb"))


if __name__=="__main__":
    main()


