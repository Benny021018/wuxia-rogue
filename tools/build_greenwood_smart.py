"""Build the Greenwood pack from Tripo Smart Mesh P2.0 FBX exports in the directory after --."""
import sys, math
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector,Matrix
ROOT=Path.cwd(); SRC=Path(sys.argv[-1]); DEST=ROOT/'assets/models/greenwood'
DEST.mkdir(exist_ok=True)
sizes={'Gate':(6,.6,4),'palisade':(6,2,3),'platform':(7,7,1),'shrine':(1.2,.50,2.6),'cart':(3,2,1.2),'crate':(2,2,1.2),'ring':(4,4,1),'gallery':(6,2,1),'stairs':(3,4,1),'throne':(1.35,1.05,1.70),'brazier':(1.45,1.45,.80),'cover':(6,1.5,3)}
donors={'H01':'bandit','H02':'archer','H03':'shield','H07':'bandit','H08':'shield'}
def color(hexstr):
    c=np.array([int(hexstr[i:i+2],16)/255 for i in (0,2,4)])
    return np.where(c<=.04045,c/12.92,((c+.055)/1.055)**2.4)**.68
def paint(o,co,key):
    # Per-face stepped values keep the mesh legible without additional textures or draw calls.
    m=bpy.data.materials.new('Ink_'+key);m.use_nodes=True
    sh=m.node_tree.nodes.get('Principled BSDF');sh.inputs['Roughness'].default_value=.76
    attr=m.node_tree.nodes.new('ShaderNodeVertexColor');attr.layer_name='Ink'
    m.node_tree.links.new(attr.outputs['Color'],sh.inputs['Base Color'])
    o.data.materials.clear();o.data.materials.append(m);o.data.update()
    layer=o.data.color_attributes.new(name='Ink',type='BYTE_COLOR',domain='CORNER')
    colors=np.ones((len(o.data.loops),4),'f')
    span=np.maximum(np.ptp(co,axis=0),1e-8);low=co.min(0)
    wood=['342f34','59483f','826d55','ac9673']; stone=['303940','495863','71828b','adbac0']
    cloth={'H01':'41495a','H02':'31565a','H03':'505963','H07':'7b363e','H08':'433c50'}.get(key)
    pal={h:color(h) for h in set(wood+stone+['272b36','53323b','a34241','be9258','cda99a','685752','859498','2d3e4a']+([cloth] if cloth else []))}
    for face in o.data.polygons:
        p=(np.array(face.center)-low)/span
        x,y,z=p;n=face.normal
        if cloth:
            hue=cloth
            if z<.13 or z>.949: hue='272b36'
            elif z>.842 and abs(x-.5)<.067: hue='cda99a' if z<.929 and y>.50 else '272b36'
            elif .487<z<.517 and abs(x-.5)<.13: hue='a34241' if key!='H07' else 'be9258'
            elif abs(x-.5)>.449 and .63<z<.89 and key not in ('H03','H08'): hue='cda99a'
            elif z>.69 and abs(x-.5)>.13: hue='859498' if key in ['H03','H08'] else '685752'
            shade=.70 if n.z<-.3 else (1.19 if n.z>.45 else .96)
        else:
            palette=stone if key in ['stairs','shrine','brazier'] else wood
            idx=2 if n.z>.45 else 1 if n.z>-.35 else 0
            if z<.14: idx=max(0,idx-1)
            hue=palette[idx]
            if key=='shrine' and z>.85: hue='be9258'
            if key=='brazier' and .55<z<.8:hue='a34241'
            shade=.88+.12*(1+math.sin(x*28+y*16+z*9))
        colors[face.loop_start:face.loop_start+face.loop_total,:3]=np.clip(pal[hue]*shade,0,1)
        face.material_index=0
    layer.data.foreach_set('color',colors.ravel())
def fit(key,target):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(SRC/(key+'_SmartMesh_P20.fbx')))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    if len(meshes)>1:bpy.ops.object.join()
    o=bpy.context.object;mw=o.matrix_world.copy();o.parent=None;o.data.transform(mw);o.matrix_world=Matrix.Identity(4)
    budget=(8600 if key in ('H08','H07') else 6300) if key in donors else (2800 if key in ('Gate','gallery','platform','shrine') else 1600)
    triangles=sum(len(p.vertices)-2 for p in o.data.polygons)
    lod=o.modifiers.new('Runtime triangle budget','DECIMATE');lod.ratio=min(1,budget/triangles)
    bpy.ops.object.modifier_apply(modifier=lod.name)
    co=np.array([v.co[:] for v in o.data.vertices]);lo=co.min(0);dims=np.ptp(co,axis=0)
    co-=np.array([lo[0]+dims[0]/2,lo[1]+dims[1]/2,lo[2]])
    rig=None
    if key in donors:
        co[:,:2]*=-1;co*=1.8/dims[2]
        o.data.vertices.foreach_set('co',co.astype('f').ravel());o.data.update();paint(o,co,key)
        bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/models'/(donors[key]+'.glb')))
        rig=next(r for r in bpy.context.scene.objects if r.type=='ARMATURE')
        # Map capture T-pose into the actual game bind pose before inheriting the motion clips.
        bones=list(rig.data.bones);scores=[];deforms=[]
        for bone in bones:
            name=bone.name
            A=np.array(rig.matrix_world@bone.head_local);B=np.array(rig.matrix_world@bone.tail_local)
            a=A.copy();b=B.copy();a[1]=0;b[1]=0
            arm=next((k for k in ['ForeArm','Hand','Arm'] if name.endswith(k)),None)
            if arm:
                sign=1 if name.startswith('Right') else -1
                extent=np.max(abs(co[:,0]));start,end={'Arm':(.23,.56),'ForeArm':(.56,.81),'Hand':(.81,1)}[arm]
                z=np.median(co[abs(co[:,0])>extent*.86,2]);a=np.array([sign*extent*start,0,z]);b=np.array([sign*extent*end,0,z])
            d=b-a;q=np.clip(((co-a)@d)/(d@d+1e-9),0,1)
            dist=np.linalg.norm(co-a-q[:,None]*d,axis=1)
            scores.append((.002+dist**2)**-3.8)
            rot=np.array(Vector(d).rotation_difference(Vector(B-A)).to_matrix()) if np.linalg.norm(d)>1e-6 else np.eye(3)
            deforms.append(A+((co-a)@rot.T)+(q[:,None]*(B-A-(rot@d))))
        weights=np.array(scores).T;cut=np.sort(weights,axis=1)[:,-4];weights[weights<cut[:,None]]=0;weights/=weights.sum(1)[:,None]
        posed=(np.array(deforms).transpose(1,0,2)*weights[:,:,None]).sum(1)
        # Keep the original face, neck, skirt and legs intact. Only the arms need to
        # come down from the generated T-pose into the shared animation bind pose.
        blend=np.clip((np.abs(co[:,0])-.17)/.15,0,1)*np.clip((co[:,2]-.95)/.22,0,1)
        torso=co.copy();torso[:,1]+=float((rig.matrix_world@rig.data.bones['Chest'].head_local).y)
        posed=torso+(posed-torso)*blend[:,None]
        posed[:,2]-=posed[:,2].min();posed[:,2]*=1.8/posed[:,2].max()
        o.data.vertices.foreach_set('co',posed.astype('f').ravel())
        for j,b in enumerate(bones):
            group=o.vertex_groups.new(name=b.name)
            for idx in np.flatnonzero(weights[:,j]):group.add([int(idx)],float(weights[idx,j]),'REPLACE')
        o.data.update()
        sys.path.insert(0,str(ROOT/'tools'))
        from sculpt_camp_faces import sculpt
        sculpt(o,key)
        o.parent=rig;o.matrix_parent_inverse=rig.matrix_world.inverted();mod=o.modifiers.new('Skin','ARMATURE');mod.object=rig
    else:
        if target[0]>target[1]*1.7 and dims[1]>dims[0]:
            co=co[:,[1,0,2]].copy();co[:,0]*=-1;dims=dims[[1,0,2]]
        co*=np.array(target)/dims
        o.data.vertices.foreach_set('co',co.astype('f').ravel());o.data.update();paint(o,co,key)
    o.name='Smart_'+key
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True)
    if rig:rig.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(DEST/(key+'.glb')),use_selection=True,export_animations=bool(rig),export_animation_mode='NLA_TRACKS',export_frame_range=False)
    print('SMART',key,len(o.data.polygons),sum(len(p.vertices)-2 for p in o.data.polygons),flush=True)
for key,target in (sizes|dict.fromkeys(donors)).items():
    if "--faces" not in sys.argv or key in donors: fit(key,target)
