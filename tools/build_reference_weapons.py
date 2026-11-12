"""Blender procedural source for the three view models. Axes: +Y along blade, +Z up."""
import bpy, math
from pathlib import Path
from mathutils import Vector
dest=Path.cwd()/'assets/models/weapons'
def reset(): bpy.ops.wm.read_factory_settings(use_empty=True)
def material(name,rgb,metal=0,rough=.52):
 m=bpy.data.materials.new(name);m.diffuse_color=(*rgb,1);m.use_nodes=True;p=m.node_tree.nodes['Principled BSDF'].inputs;p['Base Color'].default_value=(*rgb,1);p['Metallic'].default_value=metal;p['Roughness'].default_value=rough;return m
def loft(name,rings,mats,idx=None):
 n=len(rings[0]);faces=[tuple(reversed(range(n)))];inds=[0]
 for j in range(len(rings)-1):
  for k in range(n):
   l=(k+1)%n;faces.append((j*n+k,j*n+l,(j+1)*n+l,(j+1)*n+k));inds.append(idx(j,k) if idx else 0)
 faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)));inds.append(0)
 m=bpy.data.meshes.new(name);m.from_pydata(sum(rings,[]),[],faces);m.update()
 for mat in mats:m.materials.append(mat)
 for p,i in zip(m.polygons,inds):p.material_index=i
 import bmesh
 bm=bmesh.new();bm.from_mesh(m);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(m);bm.free()
 o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o);return o
def oval(y,rx,rz,cz=0,n=24):return [(rx*math.cos(i*math.tau/n),y,cz+rz*math.sin(i*math.tau/n)) for i in range(n)]
def band(name,a,b,rx,rz,mat,cz=0):return loft(name,[oval(a,rx,rz,cz),oval(b,rx,rz,cz)],[mat])
def line(name,pts,r,mat,parent=None):
 c=bpy.data.curves.new(name,'CURVE');c.dimensions='3D';c.bevel_depth=r;c.bevel_resolution=1;s=c.splines.new('POLY');s.points.add(len(pts)-1)
 for p,at in zip(s.points,pts):p.co=(*at,1)
 o=bpy.data.objects.new(name,c);bpy.context.collection.objects.link(o);o.data.materials.append(mat);o.parent=parent;return o
def export(n):
 folder=Path.cwd()/'tools/blender_sources';folder.mkdir(exist_ok=True);(folder/'.gdignore').touch()
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(folder/(n+'.blend')),compress=True)
 # Keep only the moving parts independent in the runtime asset; the source retains the individual fittings.
 def merge(root,items):
  bpy.ops.object.select_all(action='DESELECT')
  for ob in items:ob.select_set(True)
  bpy.context.view_layer.objects.active=root
  bpy.ops.object.convert(target='MESH')
  bpy.ops.object.join()
 if n!='W007':
  sheath=bpy.data.objects['Saya' if n=='Tachi' else 'Scabbard']
  merge(sheath,[sheath]+list(sheath.children_recursive))
  grip=bpy.data.objects['Grip' if n=='Tachi' else '柄']
  pieces=[o for o in bpy.context.scene.objects if o not in [sheath,bpy.data.objects['Blade']]]
  merge(grip,pieces)
 bpy.ops.export_scene.gltf(filepath=str(dest/(n+'.glb')),export_format='GLB',export_animations=False)
 # Studio proof of the exported geometry, including both accessories outside their storage positions.
 import os
 from mathutils import Quaternion
 if n!='W007':
  sheath.location.z=-.15 if n=='Tachi' else -.35
 else:
  bow.data.shape_keys.key_blocks['Draw'].value=0
  line('PreviewString',[(0,-.156,-.62),(0,-.156,.62)],.0018,black)
 scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH'
 sh=scene.display.shading;sh.color_type='MATERIAL';sh.light='STUDIO';sh.show_shadows=True;sh.show_cavity=True;sh.cavity_type='WORLD'
 sh.background_type='WORLD';scene.world=bpy.data.worlds.new('Studio');scene.world.color=(.075,.084,.098)
 target=Vector((0,.36,-.032)) if n=='Tachi' else Vector((0,.45,-.15)) if n=='W301' else Vector((0,-.08,0))
 cam=bpy.data.objects.new('PreviewCamera',bpy.data.cameras.new('Ortho'));scene.collection.objects.link(cam);scene.camera=cam
 cam.location=target+Vector((3,-.22,.55));q=(target-cam.location).to_track_quat('-Z','Y');cam.rotation_euler=(q@Quaternion((0,0,1),1.48 if n=='W007' else -.19)).to_euler()
 cam.data.type='ORTHO';cam.data.ortho_scale={'Tachi':1.14,'W007':1.40,'W301':1.78}[n]
 scene.render.resolution_x=800;scene.render.resolution_y=330;scene.render.resolution_percentage=100
 scene.render.filepath=str(Path(os.environ['TEMP'])/'wuxia-tools'/('ref-'+n+'.png'))
 bpy.ops.render.render(write_still=True)
reset()
steel=material('磨銀刃',(.52,.59,.67),.61,.26);edge=material('亮刃',(.85,.88,.9),.55,.22)
iron=material('黑鐵',(.027,.022,.024),.58);cord=material('紫褐柄繩',(.065,.031,.044));core=material('深棕柄芯',(.17,.09,.072))
gold=material('銅鎺',(.46,.27,.088),.62);wood=material('淺木鞘',(.56,.355,.20),0,.53);grain=material('木紋',(.42,.25,.13))
band('Grip',-.17,.055,.019,.027,core)
for sign in [-1,1]:
 pts=[(.020*math.cos(sign*i*.16),-.167+i*.22/260,.028*math.sin(sign*i*.16)) for i in range(261)]
 line('菱卷',pts,.0038,cord)
band('Pommel',-.18,-.17,.021,.028,iron);band('Tsuba',.055,.066,.049,.056,iron);band('Habaki',.066,.083,.012,.023,gold)
def bend(t):return .06*t*t
rings=[]
for i in range(33):
 t=i/32;w=.023*(1-.25*t);tip=max(0,(t-.91)/.09)
 rings.append([(x*(1-.97*tip),.082+.728*t,bend(t)+z*(1-tip)+w*tip) for x,z in [(0,-w),(.005,-w*.24),(.004,w),(-.004,w),(-.005,-w*.24)]])
loft('Blade',rings,[steel,edge],lambda j,k:int(k in (0,4)))
saya=loft('Saya',[oval(.068+.755*i/32,.016*(1-.20*i/32),.032*(1-.21*i/32),bend(i/32)) for i in range(33)],[wood])
for i in range(7):
 ang=math.tau*i/7+.2
 pts=[(.0162*(1-.2*t)*math.cos(ang+.02*math.sin(8*t)),.068+.755*t,bend(t)+.0321*(1-.21*t)*math.sin(ang+.02*math.sin(8*t))) for t in [j/32 for j in range(33)]]
 line('鞘木理',pts,.00055,grain,saya)
for i in range(4):band('鞘紐',.11+i*.006,.114+i*.006,.017,.034,cord).parent=saya
line('下緒',[(.016,.122,.012),(.04,.148,.025),(.062,.17,.018)],.0045,cord,saya)
export('Tachi')
reset()
honey=material('橘紅層木',(.40,.115,.036));black=material('深色弓腹',(.035,.023,.019));wrap=material('黑纏把',(.026,.021,.022));highlight=material('木邊',(.58,.26,.084))
rings=[]
for i in range(65):
 t=(i-32)/32;a=abs(t);z=t*.62;y=-.19*a**1.9+.034*max(0,(a-.87)/.13)
 w=.021*(1-.77*a)+.003;d=.012*(1-.58*a)+.002
 rings.append([(w*math.cos(j*math.tau/12),y+d*math.sin(j*math.tau/12),z) for j in range(12)])
bow=loft('BowLimbs',rings,[honey,black,highlight],lambda i,k:1 if k in (1,2,3,4,7,8,9,10) else (2 if k==0 else 0))
bow.shape_key_add(name='Basis');sk=bow.shape_key_add(name='Draw')
for p in sk.data:
 t=p.co.z/.62;p.co.y-=.112*t*t;p.co.z-=p.co.z*.12*t*t
loft('GripWrap',[[(.030*math.cos(j*math.tau/18),.022*math.sin(j*math.tau/18),z) for j in range(18)] for z in [-.072,.072]],[wrap])
sk.value=0
export('W007')
reset()
dark=material('烏鋼',(.036,.041,.05),.65,.31);bev=material('冷磨稜',(.21,.23,.25),.77,.26);silver=material('古銀刻紋',(.37,.39,.40),.66);leather=material('黑革',(.028,.023,.025))
band('柄',-.235,.085,.024,.03,dark);band('柄首',-.257,-.232,.032,.038,bev)
for j in range(12):band('握柄節',-.22+j*.023,-.215+j*.023,.025,.031,bev)
rings=[]
for t,w in [(0,.065),(.05,.078),(.16,.069),(.67,.055),(.88,.043),(.96,.028),(1,.002)]:
 rings.append([(x,.105+1.04*t,z*w) for x,z in [(0,-1),(.009,-.84),(.011,.84),(0,1),(-.011,.84),(-.009,-.84)]])
loft('Blade',rings,[dark,bev],lambda j,k:0 if k in (1,4) else 1)
for sign in [-1,1]:
 pts=[(.0,.077,0),(.0,.142,.062*sign),(.0,.123,.092*sign),(.0,.058,.147*sign)]
 for a,b in zip(pts,pts[1:]):
  v=Vector(b)-Vector(a);bpy.ops.mesh.primitive_cube_add(size=1,location=(Vector(a)+Vector(b))/2);o=bpy.context.object;o.name='折角護手';o.rotation_euler=v.to_track_quat('Y','Z').to_euler();o.scale=(.04,v.length+.012,.038);o.data.materials.append(dark)
 line('護手銀線',[(.021,y,z) for _,y,z in pts],.003,silver)
for x in [-.012,.012]:
 for i in range(5):
  y=.19+i*.068;line('回紋',[(x,y,-.023),(x,y,.022),(x,y+.05,.022),(x,y+.05,-.021),(x,y+.015,-.021),(x,y+.015,.008),(x,y+.033,.008)],.0025,silver)
 line('劍脊銘',[(x,.15,-.032),(x,.51,-.028),(x,.59,0),(x,.51,.028),(x,.15,.032)],.0024,silver)
saya=loft('Scabbard',[oval(y,rx,rz) for y,rx,rz in [(.093,.021,.089),(.15,.021,.092),(.99,.017,.062),(1.15,.014,.028),(1.17,.012,.013)]],[leather])
for i in range(9):
 for sign in [-1,1]:
  y=.15+i*.112;z=sign*(.077-.032*i/8);bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=.005,location=(.011,y,z));o=bpy.context.object;o.name='鞘鉚';o.data.materials.append(silver);o.parent=saya
for j in range(28):
 t=j/27;y=.17+.82*t;z=.088+.23*math.sin(t*math.pi)
 bpy.ops.mesh.primitive_torus_add(major_segments=12,minor_segments=5,location=(.012,y,z),rotation=(0,math.pi/2 if j%2==0 else .65,0),major_radius=.016,minor_radius=.0035);o=bpy.context.object;o.scale.y=1.35;o.name='掛鏈';o.data.materials.append(dark);o.parent=saya
export('W301')
