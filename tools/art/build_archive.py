"""Brief #9: original suspended Archive. Run in Blender via blender_rpc.py."""
import bpy, bmesh, math, random, json
from pathlib import Path
from mathutils import Vector

ROOT = Path('D:/CodingProjects/spacegame')
OUT = ROOT / 'art/archive'
OUT.mkdir(parents=True, exist_ok=True)
rng = random.Random(9600)
# Rebuild only this builder's scene; preserve unrelated open Blender scenes.
old = bpy.data.scenes.get('The Archive')
if old is not None and old.get('archive_builder'):
    owned = list(old.objects)
    old_collections = list(old.collection.children)
    old_materials = {m for o in owned if o.type=='MESH' for m in o.data.materials}
    other = next((s for s in bpy.data.scenes if s!=old), None)
    bpy.context.window.scene = other if other is not None else bpy.data.scenes.new('Archive rebuild staging')
    bpy.data.scenes.remove(old)
    for o in owned:
        data=o.data
        bpy.data.objects.remove(o,do_unlink=True)
        if isinstance(data,bpy.types.Mesh) and data.users==0: bpy.data.meshes.remove(data)
    for c in old_collections:
        if c.users==0: bpy.data.collections.remove(c)
    for m in old_materials:
        if m.users==0: bpy.data.materials.remove(m)
scene = bpy.data.scenes.new('The Archive')
scene['archive_builder'] = True
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
collection = bpy.data.collections.new('Archive | Export')
scene.collection.children.link(collection)
batches = {}
colors = [(0.66,0.53,0.37), (0.20,0.115,0.055), (0.49,0.43,0.32),
          (0.025,0.037,0.043), (1.0,0.61,0.26), (1.0,0.76,0.43), (0.7,0.025,0.012)]
materials = []
for i, (name, metal, rough, emission) in enumerate([
    ('AR Warm limestone hull',0.12,0.78,0), ('AR Aged bronze framing',0.7,0.48,0),
    ('AR Matte woven envelopes',0,0.94,0), ('AR Recessed glazing',0.25,0.34,0),
    ('AR Reading windows',0,0.4,1.6), ('AR Walkway lamps',0,0.5,1.2),
    ('AR Dim red navigation',0,0.5,0.65)]):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*colors[i],1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*colors[i],1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*colors[i],1)
        p.inputs['Emission Strength'].default_value = emission
    else:
        v = m.node_tree.nodes.new('ShaderNodeVertexColor')
        v.layer_name = 'Patina'
        m.node_tree.links.new(v.outputs['Color'],p.inputs['Base Color'])
    materials.append(m)

def add(key, vs, fs, tint=1):
    verts, faces, shades = batches.setdefault(key, ([],[],[]))
    offset = len(verts)
    verts.extend(tuple(v) for v in vs)
    faces.extend(tuple(offset+j for j in f) for f in fs)
    color = tuple(min(1,c*tint) for c in colors[key[1]])
    shades.extend([(*color,1)]*len(vs))

def box(key, center, size, angle=0, tint=1):
    x,y,z = center
    a,b,c = [s/2 for s in size]
    vs = [(x+u*math.cos(angle)-v*math.sin(angle), y+u*math.sin(angle)+v*math.cos(angle),z+w)
          for u,v,w in [(-a,-b,-c),(a,-b,-c),(a,b,-c),(-a,b,-c),(-a,-b,c),(a,-b,c),(a,b,c),(-a,b,c)]]
    add(key,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],tint)

def beam(key, p, q, radius, sides=8, tint=1):
    p,q = Vector(p),Vector(q)
    axis = (q-p).normalized()
    u = axis.cross(Vector((0,0,1)))
    if u.length < .01: u = axis.cross(Vector((0,1,0)))
    u.normalize()
    v = axis.cross(u).normalized()
    vs = [c+radius*(math.cos(j*math.tau/sides)*u+math.sin(j*math.tau/sides)*v) for c in [p,q] for j in range(sides)]
    fs = [tuple(reversed(range(sides))),tuple(sides+j for j in range(sides))]
    fs += [(j,(j+1)%sides,(j+1)%sides+sides,j+sides) for j in range(sides)]
    add(key,vs,fs,tint)

def lathe(key, xy, profile, sides=32, tint=1, cap=True):
    vs = [(xy[0]+r*math.cos(j*math.tau/sides),xy[1]+r*math.sin(j*math.tau/sides),z)
          for z,r in profile for j in range(sides)]
    fs = [(k*sides+j,k*sides+(j+1)%sides,(k+1)*sides+(j+1)%sides,(k+1)*sides+j)
          for k in range(len(profile)-1) for j in range(sides)]
    if cap: fs += [tuple(reversed(range(sides))),tuple((len(profile)-1)*sides+j for j in range(sides))]
    add(key,vs,fs,tint)

def annulus(key, xy, z, outer, inner, depth, sides=48):
    lathe(key,xy,[(z-depth/2,inner),(z-depth/2,outer),(z+depth/2,outer),(z+depth/2,inner),(z-depth/2,inner)],sides,cap=False)

def pane(key, xy, r, angle, z, width, height):
    # A tangent quad on a cylinder, slightly proud of its masonry face.
    radial = Vector((math.cos(angle),math.sin(angle),0))
    tangent = Vector((-math.sin(angle),math.cos(angle),0))
    c = Vector((xy[0],xy[1],z))+radial*r
    up = Vector((0,0,height/2))
    side = tangent*width/2
    add(key,[c-side-up,c+side-up,c+side+up,c-side+up],[(0,1,2,3)])

# Seven unequal stacks: tall shelved reading rooms, not generic station drums.
stacks = [(-132,-57,-232,145,31), (119,-65,-264,130,29), (0,88,-210,172,37),
          (-100,91,-163,116,26), (112,94,-196,148,27), (-17,-103,-286,90,34),
          (0,4,-240,181,24)]
for index,(x,y,bottom,top,r) in enumerate(stacks):
    xy = (x,y)
    lathe(('Archive stacks',0),xy,[(bottom,r*.62),(bottom+11,r*.88),(bottom+24,r),(top-13,r),(top-5,r*.91),(top,r*.7)],32,tint=rng.uniform(.93,1.08))
    # Stepped cornices, bronze foot collars, narrow vertical pilasters.
    for z in [bottom+22,top-15]:
        lathe(('Stack frames',1),xy,[(z-3,r),(z-2,r+2.2),(z+2,r+2.2),(z+3,r)],32)
    lathe(('Archive stacks',0),xy,[(top-8,r+1),(top-3,r+3),(top+2,r+3),(top+6,r*.73)],32)
    levels = int((top-bottom-48)/20)
    for level in range(levels):
        z = bottom+36+level*20
        annulus(('Stack frames',1),xy,z-8,r+.65,r-.3,1.1,32)
        for j in range(12):
            a = math.tau*(j+.5)/12
            pane(('Window recesses',3),xy,r+.2,a,z,6.0,10.5)
            # A few shuttered windows give inhabited variation without bright solid bands.
            if (j+level+index)%11 != 0:
                pane(('Reading windows',4),xy,r+.28,a,z,3.1,7.0)
            beam(('Stack frames',1),(x+(r+.4)*math.cos(a),y+(r+.4)*math.sin(a),z-5),
                 (x+(r+.4)*math.cos(a),y+(r+.4)*math.sin(a),z+5),.16,4)
    for j in range(6):
        a = j*math.tau/6
        beam(('Stack frames',1),(x+(r+.5)*math.cos(a),y+(r+.5)*math.sin(a),bottom+24),
             (x+(r+.5)*math.cos(a),y+(r+.5)*math.sin(a),top-13),.8,6)
    # Neatly replaced masonry panels at a few bases, with no markings.
    for j in range(3):
        a = math.tau*(j+.25)/3
        pane(('Archive stacks',0),xy,r+.1,a,bottom+29,7,5)

# Central structural spine and radial enclosed bridges at staggered reading levels.
beam(('Spine masonry',0),(0,0,-326),(0,0,205),14,24)
for z in [-280,-180,-75,35,150,201]:
    annulus(('Spine bronze',1),(0,0),z,20,13,4,32)

def bridge(p,q,width=13):
    p,q = Vector(p),Vector(q)
    d = q-p
    length = d.length
    angle = math.atan2(d.y,d.x)
    center = (p+q)/2
    box(('Enclosed bridges',0),center+Vector((0,0,-4)),(length,width,3),angle)
    box(('Bridge glazing',3),center+Vector((0,0,2)),(length,width-1,9),angle)
    box(('Enclosed bridges',0),center+Vector((0,0,8)),(length,width+2,3),angle)
    u = Vector((-math.sin(angle),math.cos(angle),0))
    for side in [-1,1]:
        for dz in [-3,7]:
            beam(('Bridge bronze',1),p+u*(width/2)*side+Vector((0,0,dz)),q+u*(width/2)*side+Vector((0,0,dz)),.7,6)
    for n in range(1,int(length/16)):
        c = p+d*(n*16/length)
        for side in [-1,1]:
            at = c+u*(width/2+.2)*side
            beam(('Bridge bronze',1),at+Vector((0,0,-4)),at+Vector((0,0,8)),.65,6)
            box(('Walkway lamps',5),at+Vector((0,0,5)),(2,1.2,1.6),angle)

for i,(x,y,b,t,r) in enumerate(stacks[:6]):
    direction = Vector((x,y,0)).normalized()
    for z in [-108 if b<-180 else -55, 53 if t>130 else 25]:
        bridge((direction.x*15,direction.y*15,z),(x-direction.x*r,y-direction.y*r,z))
# Exterior balcony on the forward reading tower and two maintained linking catwalks.
annulus(('Balcony floors',0),(-17,-103),-193,44,32,3,48)
for z in [-186,-190]: annulus(('Bridge bronze',1),(-17,-103),z,43.6,42.8,.8,48)
for j in range(24):
    a=j*math.tau/24
    beam(('Bridge bronze',1),(-17+43*math.cos(a),-103+43*math.sin(a),-193),(-17+43*math.cos(a),-103+43*math.sin(a),-186),.4,5)

# Three buoyant fabric envelopes, packed above the towers with suspension air gaps.
# Each entire assembly (fabric, gores, navigation light) uses a centred animation pivot.
envelopes = [(-155,5,306,145,90,113),(155,5,321,145,90,113),(0,173,335,125,101,124)]
for idx,(cx,cy,cz,rx,ry,rz) in enumerate(envelopes):
    group = 'Envelope%02d'%(idx+1)
    def point(t,a,offset=0):
        return Vector((cx+(rx+offset)*math.sin(t)*math.cos(a),cy+(ry+offset)*math.sin(t)*math.sin(a),cz+(rz+offset)*math.cos(t)))
    # Individual cloth gores use restrained shades. Surface is matte and slightly faceted.
    sides, rows = 40,20
    for j in range(sides):
        a,b = j*math.tau/sides,(j+1)*math.tau/sides
        vs = [point(k*math.pi/rows,angle) for k in range(1,rows) for angle in [a,b]]
        vs += [point(0,0),point(math.pi,0)]
        fs = [(k*2,k*2+1,k*2+3,k*2+2) for k in range(rows-2)]
        fs += [(38,1,0),(39,36,37)]
        add((group,2),vs,fs,tint=.94+.08*(.5+.5*math.cos(j*1.7+idx)))
    # Sewn longitudinal seams and a broad fabric equatorial reinforcement band.
    for j in range(16):
        a=j*math.tau/16
        for k in range(1,20):
            beam((group,2),point((k-.5)*math.pi/20,a,.4),point((k+.5)*math.pi/20,a,.4),.52,5,tint=.77)
    for j in range(64):
        a,b=j*math.tau/64,(j+1)*math.tau/64
        vs=[point(math.pi/2+d,ang,.3) for d,ang in [(-.025,a),(-.025,b),(.025,b),(.025,a)]]
        add((group,2),vs,[(0,1,2,3)],tint=.83)
    # Small metal suspension shoe under each envelope, held by four belly straps.
    beam((group,1),(cx,cy,cz-rz-9),(cx,cy,cz-rz+3),11,20)
    for a in [math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4]:
        p=point(math.pi*.73,a,1)
        beam((group,1),p,(cx+8*math.cos(a),cy+8*math.sin(a),cz-rz-9),1.15,6)
    if idx<2:
        beam((group,1),(cx,cy,cz+rz-1),(cx,cy,cz+rz+4),2.1,10)
        beam((group,6),(cx,cy,cz+rz+4),(cx,cy,cz+rz+7),2.0,12)
    # Fixed suspension bundles visibly carry the central crosshead and library towers.
    joint = [(-143,0,160),(143,0,160),(0,135,172)][idx]
    beam(('Crown crosshead',1),(joint[0]-7,joint[1],joint[2]),(joint[0]+7,joint[1],joint[2]),2,8)
    for side in [-1,1]:
        beam(('Suspension cables',1),(cx+side*6,cy,cz-rz-8),(joint[0]+side*6,joint[1],joint[2]),.9,6)

beam(('Crown crosshead',1),(-143,0,160),(143,0,160),5,12)
beam(('Crown crosshead',1),(0,0,160),(0,135,172),5,12)
for x,y,b,t,r in stacks[:6]:
    beam(('Crown crosshead',1),(x*.88-r*.26,y*.83,max(t+32,176)),(x*.88+r*.26,y*.83,max(t+32,176)),1.8,8)
    for dx in [-r*.65,r*.65]:
        beam(('Suspension cables',1),(x+dx,y,t+4),(x*.88+dx*.4,y*.83,max(t+32,176)),1.1,6)
    beam(('Crown crosshead',1),(0,0,180),(x*.88,y*.83,max(t+32,176)),2.3,8)

# A small, genuinely open horizontal docking ring hangs at the bottom of the spine.
annulus(('Dock masonry',0),(0,-22),-325,51,37,9,64)
annulus(('Dock bronze',1),(0,-22),-319,52,49,2,64)
annulus(('Dock bronze',1),(0,-22),-331,51,47,3,64)
for a in [math.pi/6,5*math.pi/6,3*math.pi/2]:
    x,y=44*math.cos(a),-22+44*math.sin(a)
    beam(('Dock bronze',1),(0,0,-282),(x,y,-320),2.4,8)
for side in [-1,1]:
    box(('Dock masonry',0),(side*60,-22,-325),(27,20,9))
    for y in [-30,-14]:
        box(('Dock bronze',1),(side*73,y,-321),(5,3,10))
        box(('Walkway lamps',5),(side*73,y,-315),(2,2,1.4))
for j in range(12):
    a=j*math.tau/12
    box(('Walkway lamps',5),(50*math.cos(a),-22+50*math.sin(a),-318),(2.1,2.1,1))

# Batch by material within structural sections; all mesh origins are bounds-centred.
root=bpy.data.objects.new('Archive',None)
collection.objects.link(root)
pivots={}
for idx,values in enumerate(envelopes):
    label='Envelope%02d'%(idx+1)
    obj=bpy.data.objects.new(label+'_Pivot',None)
    collection.objects.link(obj)
    obj.parent=root
    obj.location=values[:3]
    pivots[label]=obj
objects=[]
for (name,mi),(vs,fs,cs) in batches.items():
    low=Vector(tuple(min(v[i] for v in vs) for i in range(3)))
    high=Vector(tuple(max(v[i] for v in vs) for i in range(3)))
    pivot=(low+high)/2
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata([Vector(v)-pivot for v in vs],[],fs)
    mesh.materials.append(materials[mi])
    mesh.update()
    attr=mesh.color_attributes.new(name='Patina',type='FLOAT_COLOR',domain='POINT')
    for datum,c in zip(attr.data,cs): datum.color=c
    bm=bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj=bpy.data.objects.new(name+' | '+materials[mi].name[3:],mesh)
    collection.objects.link(obj)
    obj.parent=pivots.get(name,root)
    obj.location=pivot-(obj.parent.location if obj.parent!=root else Vector((0,0,0)))
    objects.append(obj)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for obj in collection.objects: obj.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/landmarks/archive.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_cameras=False,export_lights=False,export_yup=True)
points=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
stats={'meshes':len(objects),'materials':len(materials),'material_surfaces':len(objects),
       'vertices':sum(len(o.data.vertices) for o in objects),
       'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),
       'blender_dimensions_m':[max(v[i] for v in points)-min(v[i] for v in points) for i in range(3)],
       'blender_bounds_min':[min(v[i] for v in points) for i in range(3)],
       'blender_bounds_max':[max(v[i] for v in points) for i in range(3)],
       'archive_towers':7,'independent_envelopes':3,'emissive_materials':3,'docking_berths':2}
(OUT/'counts.json').write_text(json.dumps(stats,indent=2))

# Presentation only: never selected for export. No planet or clouds in the asset.
studio=bpy.data.collections.new('Archive preview only')
scene.collection.children.link(studio)
target=Vector((0,35,55))
def aim(obj): obj.rotation_euler=(target-obj.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.cameras.new('Archive overview')
cam=bpy.data.objects.new('Archive overview',data)
studio.objects.link(cam)
cam.location=(1080,-1640,810)
aim(cam)
data.type='ORTHO'
data.ortho_scale=1030
data.clip_end=10000
scene.camera=cam
for name,loc,power,size,color in [('Key',(-600,-650,950),24000000,700,(1,.86,.69)),('Rim',(500,500,850),22000000,600,(.73,.85,1)),('Fill',(400,-600,20),11000000,650,(.85,.91,1))]:
    d=bpy.data.lights.new('AR '+name,'AREA')
    d.energy=power;d.shape='DISK';d.size=size;d.color=color
    o=bpy.data.objects.new('AR '+name,d)
    studio.objects.link(o);o.location=loc;aim(o)
world=bpy.data.worlds.new('Archive blue dusk')
world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.024,.035,.052,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.35
scene.world=world
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1500;scene.render.resolution_y=1700;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'archive_preview.png')
scene.view_settings.view_transform='AgX'
bpy.ops.object.select_all(action='DESELECT')
for o in studio.objects:o.hide_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            s=area.spaces.active;s.clip_end=10000;s.region_3d.view_distance=1100
            s.region_3d.view_location=target;s.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
            s.shading.color_type='MATERIAL';s.overlay.show_floor=False;s.overlay.show_axis_x=False;s.overlay.show_axis_y=False
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'archive.blend'))
print(json.dumps(stats))
bpy.ops.render.render(write_still=True)
