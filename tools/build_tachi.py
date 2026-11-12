"""Blender --background --python tools/build_tachi.py -- path/to/Tachi_SmartMesh_P20.fbx
Normalize the Tripo asset around its guard, preserve UVs, and fit a separate saya.
"""
import bpy, bmesh, numpy as np, math, sys
from mathutils import Matrix
from pathlib import Path

source = Path(sys.argv[sys.argv.index('--')+1])
out = Path.cwd()/'assets/models/weapons/Tachi.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(source))
parts=[o for o in bpy.context.scene.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active=parts[0]
if len(parts)>1: bpy.ops.object.join()
obj=bpy.context.object
world=obj.matrix_world.copy(); obj.parent=None
obj.data.transform(world); obj.matrix_world=Matrix.Identity(4)
mesh=obj.data
v=np.empty((len(mesh.vertices),3),'f')
mesh.vertices.foreach_get('co',v.ravel())
# Principal length/width axes, with the hilt identified by the widened guard.
v-=v.mean(0)
_,axes=np.linalg.eigh(np.cov(v.T))
q=v@axes[:,::-1]
length=np.ptp(q[:,0])
u=(q[:,0]-q[:,0].min())/length
def guard_location():
    widths=[]
    for t in np.linspace(.04,.96,150):
        band=q[abs(u-t)<.012,1:]
        widths.append(np.prod(np.ptp(band,axis=0)) if len(band)>3 else 0)
    return np.linspace(.04,.96,150)[np.argmax(widths)]
g=guard_location()
if g>.5: u=1-u;g=1-g
print("GUARD",g,flush=True)
assert .08<g<.48
hilt=q[abs(u-(g*.60))<.016,1:].mean(0)
scale=.735/((1-g)*length)
xyz=np.column_stack(((q[:,2]-hilt[1])*scale,(u-g)*length*scale+.070,(q[:,1]-hilt[0])*scale))
# Keep the cutting edge arc consistently visible.
if xyz[u>.97,2].mean()<xyz[abs(u-.50)<.025,2].mean(): xyz[:,2]*=-1
# The smart mesh draft has a broad, straight double-edged silhouette.
# Narrow its profile, shorten the oversized grip, and introduce a progressive curved spine.
progress=np.clip((xyz[:,1]-.082)/.73,0,1)
xyz[:,2]*=.54;xyz[:,0]*=.73
xyz[:,2]+=.085*progress**1.8
xyz[:,1]=np.where(xyz[:,1]<.07,.07+(xyz[:,1]-.07)*.64,xyz[:,1])
# The guard flares beyond the first blade ring. Collapse its distal ornaments into the collar
# and keep the entire moving blade inside a slim curved sheath envelope.
raw=xyz[:,1].copy()
xyz[:,1]=np.interp(raw,[raw.min(),.035,.16,.8057],[raw.min(),.035,.082,.8057])
t=np.clip((xyz[:,1]-.082)/.724,0,1)
is_blade=raw>=.16
tip=np.clip((1-t)*14,.035,1)
xyz[is_blade,0]=np.clip(xyz[is_blade,0],-.006,.006)*tip[is_blade]
curve=.085*t**1.8
xyz[is_blade,2]=curve[is_blade]+np.clip(xyz[is_blade,2]-.085*progress[is_blade]**1.8,-.024,.024)*tip[is_blade]
mesh.vertices.foreach_set('co',xyz.astype('f').ravel());mesh.update()
if np.linalg.det(np.linalg.lstsq(v[::64],xyz[::64]-xyz.mean(0),rcond=None)[0])<0: mesh.flip_normals()
bpy.context.view_layer.objects.active=obj
m=obj.modifiers.new('Game LOD','DECIMATE');m.ratio=min(1,4300/sum(len(f.vertices)-2 for f in mesh.polygons))
bpy.ops.object.modifier_apply(modifier=m.name)
blade=obj.copy();blade.data=obj.data.copy();bpy.context.collection.objects.link(blade)
for o,name,outer in [(obj,'TachiGrip',True),(blade,'Blade',False)]:
    o.name=name
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),plane_co=(0,.082,0),plane_no=(0,1,0),clear_outer=outer,clear_inner=not outer)
    bm.to_mesh(o.data);bm.free()
    assert len(o.data.polygons)>10
# Octagonal lacquer sheath, with rings following the actual generated blade rather than a stock curve.
def material(name,c,metal):
    m=bpy.data.materials.new(name);m.use_nodes=True
    inputs=m.node_tree.nodes['Principled BSDF'].inputs
    inputs['Base Color'].default_value=(*c,1); inputs['Metallic'].default_value=metal
    inputs['Roughness'].default_value=.32
    return m
lacquer=material('Indigo lacquer',(.025,.069,.077),.34)
brass=material('Moon brass',(.45,.25,.08),.65)
steel=material('Cold edge',(.45,.59,.67),.65)
ridge=material('Ink spine',(.16,.25,.31),.56)
cord=material('Teal binding',(.022,.095,.10),.13)
for o in (obj,blade):
    o.data.materials.clear()
    for mat in [steel,ridge,cord,brass]:o.data.materials.append(mat)
    for f in o.data.polygons:
        y=f.center.y
        f.material_index=(0 if abs(f.normal.z)>.25 else 1) if o==blade else (3 if y>.035 or y<-.11 else 2)
ys=np.linspace(.082,.823,42)
rings=[]
for i,y in enumerate(ys):
    # Smooth conservative envelope for this blade, not separate noisy per-ring extrema.
    t=np.clip((y-.082)/.73,0,1)
    c=np.array([0.0,.085*t**1.8])
    local=xyz[(xyz[:,1]>.105)&(xyz[:,1]<.79)]
    gap=local[:,[0,2]]-np.column_stack((np.zeros(len(local)),.085*np.clip((local[:,1]-.082)/.73,0,1)**1.8))
    r=np.array([.012,.034])*(1-.065*t)
    if i==0: first=(c,r)
    rings.append([(c[0]+r[0]*math.cos(j*math.tau/16),y,c[1]+r[1]*math.sin(j*math.tau/16)) for j in range(16)])
c,r=first
rings.insert(0,[(c[0]+r[0]*.78*math.cos(j*math.tau/16),.086,c[1]+r[1]*.78*math.sin(j*math.tau/16)) for j in range(16)])
n=16
faces=[(i*n+j,(i+1)*n+j,(i+1)*n+(j+1)%n,i*n+(j+1)%n) for i in range(len(rings)-1) for j in range(n)]
faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)))
sm=bpy.data.meshes.new('Saya');sm.from_pydata(sum(rings,[]),[],faces)
sm.materials.append(lacquer);sm.materials.append(brass)
for f in sm.polygons: f.material_index=int(f.index//n in [0,1,5,7,40,41,42])
bm=bmesh.new();bm.from_mesh(sm);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(sm);bm.free()
saya=bpy.data.objects.new('Saya',sm);bpy.context.collection.objects.link(saya)
bpy.ops.object.select_all(action='DESELECT')
for o in [obj,blade,saya]: o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out),use_selection=True,export_image_format='JPEG',export_image_quality=85,export_animations=False)
print('FITTED',[(o.name,len(o.data.polygons)) for o in [obj,blade,saya]],flush=True)
