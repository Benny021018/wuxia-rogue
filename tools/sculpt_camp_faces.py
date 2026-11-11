"""Add surface-fitted graphic facial planes to the existing skinned mesh in Blender."""
import bpy,bmesh,math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
# Centre, eye line, half width, vertical scale; measured per enemy in bind pose.
LANDMARKS={'H01':(.003,1.607,.081,.104),'H02':(.001,1.656,.063,.094),
           'H03':(-.080,1.665,.065,.091),'H07':(-.008,1.623,.069,.100),'H08':(-.007,1.625,.071,.101)}
def sculpt(o,key):
    cx,h,w,s=LANDMARKS[key]
    o.data.update()
    tree=BVHTree.FromPolygons([v.co.copy() for v in o.data.vertices],[list(p.vertices) for p in o.data.polygons])
    detail_mat=o.data.materials[0].copy();detail_mat.name="FaceInk_"+key;o.data.materials.append(detail_mat)
    bm=bmesh.new();bm.from_mesh(o.data)
    ink=bm.loops.layers.color.get('Ink')
    deform=bm.verts.layers.deform.verify();head=o.vertex_groups['Head'].index
    tones={'skin':(.65,.415,.325,1),'cheek':(.53,.30,.235,1),'light':(.78,.54,.43,1),'eye':(.84,.80,.73,1),'brow':(.067,.050,.063,1),'iris':(.10,.085,.08,1),'lip':(.38,.18,.16,1)}
    # One gently convex surface: separately ray-projecting eyelids and pupils onto coarse
    # polygons can bury the nearer layer at one corner and break up the expression.
    hits=[]
    for x in [-.55,0,.55]:
        for z in [-.48,0,.32]:
            hit=tree.ray_cast(Vector((cx+x*w,1.8,h+z*s)),Vector((0,-1,0)))[0]
            if hit: hits.append(hit.y+.028*x*x+.018*z*z)
    base=max(hits)
    def uv(x,z,depth):
        return (cx+x*w,base-.012*x*x-.007*z*z+depth*.65,h+z*s)
    def patch(coords,tone,depth=.011):
        vs=[bm.verts.new(uv(x,z,depth)) for x,z in coords]
        for v in vs:v[deform][head]=1.
        # Surface following triangles with outward-facing normals.
        for i in range(1,len(vs)-1):
            face=bm.faces.new([vs[0],vs[i],vs[i+1]])
            face.material_index=1
            face.normal_update()
            if face.normal.y<0:face.normal_flip()
            for loop in face.loops:loop[ink]=tuple(v**(1/2.2) for v in tones[tone][:3])+(1,)
    # Broad forehead and cheek planes also give the shield guard a readable exposed face.
    for sign in [-1,1]:
        def side(pts,col,d):patch([(sign*x,y) for x,y in pts],col,d)
        side([(0,.46),(.65,.38),(.85,.08),(.79,-.40),(.48,-.77),(0,-.91)],'skin',.009)
        side([(.79,-.18),(.78,-.45),(.45,-.76),(.28,-.74),(.45,-.34)],'cheek',.015)
        tilt={'H01':.08,'H02':.03,'H03':.02,'H07':.14,'H08':.10}[key]
        side([(.10,.04),(.29,.19),(.70,.19+tilt),(.67,.105+tilt),(.30,.10)],'brow',.024)
        side([(.12,-.07),(.31,.03),(.66,.064),(.54,-.083),(.29,-.12)],'brow',.025)
        side([(.18,-.067),(.34,.004),(.61,.032),(.50,-.071),(.30,-.084)],'eye',.029)
        side([(.315,-.004),(.42,.009),(.414,-.075),(.33,-.082)],'iris',.035)
    patch([(-.064,.01),(.048,.034),(.16,-.34),(.015,-.40),(-.10,-.33)],'cheek',.031)
    patch([(-.065,-.03),(.026,-.04),(-.015,-.30),(-.12,-.33)],'light',.037)
    patch([(-.37,-.54),(-.09,-.51),(.095,-.52),(.33,-.53),(.11,-.597),(-.13,-.592)],'lip',.035)
    patch([(-.30,-.548),(.01,-.545),(.29,-.539),(.09,-.566),(-.12,-.568)],'brow',.039)
    bm.to_mesh(o.data);bm.free()
