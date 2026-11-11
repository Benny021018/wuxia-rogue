"""Run with Blender --background --factory-startup --python tools/build_tachi.py from the project root."""
import math
from pathlib import Path
import bpy, bmesh

folder = Path.cwd() / "assets/models/weapons"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(folder / "W001.glb"))
grip = next(o for o in bpy.context.scene.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = grip
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bm = bmesh.new()
bm.from_mesh(grip.data)
bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                       plane_co=(0,.052,0), plane_no=(0,1,0), clear_outer=True)
bm.to_mesh(grip.data)
bm.free()
grip.name = "OriginalGrip"

def material(name, rgb, metallic, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"].inputs
    p["Base Color"].default_value = (*rgb,1)
    p["Metallic"].default_value = metallic
    p["Roughness"].default_value = rough
    return m

steel = material("Blue steel", (.34,.49,.62),.64,.32)
edge = material("Honed edge", (.88,.95,.99),.45,.23)
lacquer = material("Indigo lacquer", (.029,.051,.083),.28,.26)
brass = material("Aged brass", (.56,.31,.085),.66,.3)
dark = material("Dark iron", (.055,.058,.069),.6,.31)

def loft(name, rings, materials, per_side=None, cap=True):
    n=len(rings[0]); faces=[]; indices=[]
    for j in range(len(rings)-1):
        for i in range(n):
            k=(i+1)%n
            faces.append((j*n+i,(j+1)*n+i,(j+1)*n+k,j*n+k))
            indices.append(per_side[i] if per_side else 0)
    if cap:
        faces += [tuple(range(n)), tuple(reversed(range((len(rings)-1)*n,len(rings)*n)))]
        indices += [0,0]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(sum(rings,[]),[],faces)
    for m in materials: mesh.materials.append(m)
    for f,i in zip(mesh.polygons,indices): f.material_index=i
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
    return o

def oval(y,x,z,curve=0):
    return [(x*math.cos(i*math.tau/24),y,curve+z*math.sin(i*math.tau/24)) for i in range(24)]

loft("Guard",[oval(y,.054,.066) for y in [.048,.056]], [dark])
loft("GuardRim",[oval(y,.055,.067) for y in [.05,.053]], [brass])
loft("Collar",[oval(y,.011,.03) for y in [.056,.082]], [brass])
length=.73
def bend(t): return .078*t*t
rings=[]
for i in range(25):
    t=i/24; w=.023*(1-.20*t);tip=max(0,(t-.88)/.12)
    rings.append([(x*(1-.97*tip),.082+length*t,bend(t)+z*(1-tip)+w*tip) for x,z in [(0,-w),(.005,-w*.28),(.004,w),(-.004,w),(-.005,-w*.28)]])
loft("Blade",rings,[steel,edge],[1,0,0,0,1])
# Scabbard has a recessed mouth and follows the same blade centreline.
path=[oval(.071,.015,.032),oval(.058,.015,.032),oval(.058,.024,.041)]
for i in range(25):
    t=i/24;path.append(oval(.082+length*t,.023-.005*t,.04-.007*t,bend(t)))
path.append(oval(.824,.004,.007,bend(1)))
saya=loft("Saya",path,[lacquer])
for j,t in enumerate([0,.095,.13,.94]):
    y=.058 if j==0 else .082+length*t
    band=loft("SayaTrim%d"%j,[oval(y+dy,.025-.005*t,.042-.007*t,bend(t)) for dy in [0,.014]], [brass])
    band.parent=saya
assert len(grip.data.vertices)>0 and rings[-1][0][1] < .824
bpy.ops.export_scene.gltf(filepath=str(folder/"Tachi.glb"),export_format="GLB",export_yup=True)
