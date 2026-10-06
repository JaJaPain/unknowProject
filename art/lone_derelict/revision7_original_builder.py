"""Reusable 300 m derelict working hauler; Blender MCP builder."""
import bpy,bmesh,math,random,json
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/CodingProjects/spacegame');OUT=ROOT/'art/lone_derelict';OUT.mkdir(parents=True,exist_ok=True)
rng=random.Random(7300)
scene=bpy.data.scenes.new('A Lone Derelict Ship');bpy.context.window.scene=scene
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
collection=bpy.data.collections.new('Lone Derelict | Export');scene.collection.children.link(collection)
batches={}
def material(name, color, metal, rough, emission=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    else:
        v = m.node_tree.nodes.new('ShaderNodeVertexColor')
        v.layer_name = 'Patina'
        m.node_tree.links.new(v.outputs['Color'], p.inputs['Base Color'])
    return m

def add(key, vs, fs, tint=1):
    vertices, faces, shades = batches.setdefault(key, ([],[],[]))
    base = len(vertices)
    vertices.extend(vs)
    faces.extend([tuple(base+i for i in f) for f in fs])
    c = colors[key[1]]
    if isinstance(tint, tuple): c = tint
    else: c = tuple(min(1,v*tint) for v in c)
    shades.extend([(*c,1)]*len(vs))

def box(key, center, size, angle=0, tint=1):
    x,y,z = center; sx,sy,sz = (v/2 for v in size)
    vs = []
    for a,b,c in [(-sx,-sy,-sz),(sx,-sy,-sz),(sx,sy,-sz),(-sx,sy,-sz),
                  (-sx,-sy,sz),(sx,-sy,sz),(sx,sy,sz),(-sx,sy,sz)]:
        vs.append((x+a*math.cos(angle)-b*math.sin(angle),y+a*math.sin(angle)+b*math.cos(angle),z+c))
    add(key,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],tint)

def beam(key, p, q, radius, sides=8, tint=1):
    p,q=Vector(p),Vector(q)
    axis=(q-p).normalized()
    u=axis.cross(Vector((0,0,1)))
    if u.length<.01: u=axis.cross(Vector((0,1,0)))
    u.normalize(); v=axis.cross(u).normalized()
    vs=[tuple(c+radius*(math.cos(i*math.tau/sides)*u+math.sin(i*math.tau/sides)*v)) for c in [p,q] for i in range(sides)]
    fs=[tuple(reversed(range(sides))),tuple(sides+i for i in range(sides))]
    fs.extend((i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides))
    add(key,vs,fs,tint)
colors=[(.29,.31,.32),(.15,.22,.21),(.055,.06,.065),(.17,.18,.18),(.43,.46,.47),(.8,.16,.035),(.32,.65,.8)]
materials=[material('LD Neutral hull tint',colors[0],.55,.65),material('LD Muted accent tint',colors[1],.4,.6),material('LD Scorched recesses',colors[2],.25,.85),material('LD Interior steel',colors[3],.6,.64),material('LD Frost and exposed edges',colors[4],.15,.8),material('LD Emergency emission',colors[5],.05,.4,.6),material('LD Beacon emission',colors[6],.05,.4,.8)]
# Multiply vertex weathering by a user-editable base colour for reusable material tints.
for i in [0,1]:
 m=materials[i];p=m.node_tree.nodes.get('Principled BSDF');v=next(n for n in m.node_tree.nodes if n.bl_idname=='ShaderNodeVertexColor')
 mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[2].default_value=(*colors[i],1);mix.label='Hull tint' if i==0 else 'Accent tint'
 m.node_tree.links.new(v.outputs['Color'],mix.inputs[1]);m.node_tree.links.new(mix.outputs[0],p.inputs['Base Color'])
# Hollow shell built from solid individual panels. The breached side is genuinely absent.
stations=[(-123,23,17),(-91,34,24),(-68,34,24),(-35,34,24),(0,34,24),(38,34,24),(68,32,23),(104,25,21),(139,15,13),(150,3,7)]
section=[(-1,-.58),(-.7,-1),(.7,-1),(1,-.58),(1,.58),(.7,1),(-.7,1),(-1,.58)]
def panel(key,points,thickness=1.7):
 inner=[(x,y*(1-thickness/34),z*(1-thickness/24)) for x,y,z in points]
 add(key,points+inner,[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)])
for j in range(len(stations)-1):
 x,w,h=stations[j];xx,ww,hh=stations[j+1]
 for i in range(8):
  if 2<=j<=5 and i in [6,7]:continue
  k=(i+1)%8
  # Small local dents preserve an ordinary ship silhouette away from the breach.
  dent=.6 if j in [1,7] and i in [3,4] else 0
  pts=[(x,section[i][0]*w,section[i][1]*h-dent),(x,section[k][0]*w,section[k][1]*h),(xx,section[k][0]*ww,section[k][1]*hh),(xx,section[i][0]*ww,section[i][1]*hh-dent)]
  panel(('Outer hull',0),pts)
# Intact nose and aft pressure bulkheads cap the spine, not the cargo bay opening.
beam(('Outer hull',0),(147,0,0),(150,0,0),6,8)
add(('Outer hull',0),[(150,y*3,z*7) for y,z in section],[tuple(range(8))])
box(('Aft bulkhead',3),(-121,0,0),(3,43,31))
# Cargo hold floor, far wall, longitudinal rails, overhead beams.
box(('Interior decks',3),(-1,2,-17),(169,57,2))
box(('Interior decks',3),(0,24,2),(144,12,2))
box(('Interior bulkheads',2),(0,29,0),(176,2,34))
for x in [-78,-48,-18,12,42,72]:
 for y in [-27,27]:beam(('Interior frames',3),(x,y,-16),(x,y,17),1.3,6)
 beam(('Interior frames',3),(x,-26,19),(x,26,19),1.3,6)
 # Half-width partitions leave the long portside passage unobstructed.
 if x in [-48,12,72]:box(('Interior bulkheads',3),(x,19,-7),(2,18,18))
for y in [-20,-7,7,21]:beam(('Interior frames',3),(-80,y,-15),(83,y,-15),.5,6)
for z in [-9,9]:beam(('Interior frames',4),(-78,27,z),(78,27,z),.5,6,.6)
# Real jagged lips follow the missing shell, with torn sheet fragments peeling outwards.
for top in [False,True]:
 z=17 if top else -15;y=-25 if top else -33
 xs=[-68,-56,-43,-29,-13,4,19,36,52,68]
 for a,b in zip(xs,xs[1:]):
  jz=rng.uniform(-4,4);jy=rng.uniform(-3,2)
  pts=[(a,y,z),(b,y,z),(b-2,y-5+jy,z+jz+(-4 if top else 5)),(a+3,y-7+jy,z+jz)]
  panel(('Torn hull lips',4),pts,.9)
  beam(('Breach scorching',2),(a,y+.2,z+.8),(b,y+.2,z+.8),1.8,5)
for x in [-69,68]:
 for j in range(5):
  z=-14+j*6
  p=[(x,-33,z),(x,-33,z+6),(x+rng.uniform(-9,9),-40,z+4),(x+rng.uniform(-5,5),-38,z)]
  panel(('Torn hull lips',4),p,1)
# Neutral hull panel lines, a single muted stripe and a few neat utility housings.
for x in [-112,-88,80,103,121]:
 box(('Hull detailing',2),(x,0,22 if x<104 else 18),(1,37,1))
for side in [-1,1]:
 for x in [-108,86,109]:box(('Hull accent',1),(x,side*(26 if x<100 else 21),3),(18,2,9))
box(('Hull accent',1),(4,8,25),(139,17,2))
for x in [-54,-13,29,63]:box(('Hull detailing',2),(x,8,26),(1,18,1))
# Low practical bridge with dead glazed apertures, no identifying marks.
box(('Bridge',0),(105,0,29),(41,31,19))
box(('Bridge',1),(105,0,40),(43,33,3))
for y in [-9,0,9]:box(('Bridge windows',2),(126,y,31),(1,6,5))
for side in [-1,1]:
 for x in [94,106,117]:box(('Bridge windows',2),(x,side*16,31),(6,1,4))
# Back-mounted cold engines; cracked structural neck, slight asymmetric engine tilt.
box(('Engine structure',2),(-128,0,0),(14,35,25))
for y in [-17,17]:
 p=Vector((-132,y,0));q=Vector((-150,y+(-2 if y<0 else 1),-2 if y<0 else 0))
 beam(('Engines',0),p,q,11,16)
 beam(('Engine structure',2),q,q+Vector((1.4,0,0)),8.5,16)
 # Narrow rim surrounding a recessed dark nozzle, rather than luminous exhaust.
 for i in range(16):
  a=i*math.tau/16;b=(i+1)*math.tau/16
  beam(('Engines',3),(q.x,q.y+9.7*math.cos(a),q.z+9.7*math.sin(a)),(q.x,q.y+9.7*math.cos(b),q.z+9.7*math.sin(b)),.9,6)
for y in [-14,14]:beam(('Engine structure',3),(-120,y,-9),(-136,y,-9),2.2,8)
# Sparse frost on the underside and far-side edges, not a uniform white coat.
for j in range(22):
 x=rng.uniform(-92,83);y=rng.uniform(8,21)
 box(('Frost deposits',4),(x,y,-23.2),(rng.uniform(2,8),rng.uniform(2,5),.35),rng.uniform(-.3,.3),rng.uniform(.55,.8))
# Only tiny emergency fixtures deep inside and one optional transmitting beacon.
for x in [-54,-14,31,64]:
 box(('Emergency lights',5),(x,26,-4),(1.2,.5,1.2))
beam(('Hull detailing',2),(99,0,41),(99,0,46),.8,8)
box(('Beacon light',6),(99,0,47),(1.5,1.5,1.5))
# A few remaining tied-down cargo boxes, leaving the breach lane clear.
for x in [-48,-7,35]:
 box(('Interior cargo',1),(x,18,-10),(17,13,12))
 for dx in [-6,6]:box(('Interior frames',3),(x+dx,18,-10),(1,14,13))
# Two independent containers float just outside the torn side.
for i,(p,a) in enumerate([((-28,-53,-4),.14),((21,-65,4),-.19)]):
 name='DriftingCargo_%02d'%(i+1)
 box((name,1),p,(17,11,10),a)
 for dx in [-6,0,6]:
  box((name,3),(p[0]+dx*math.cos(a),p[1]+dx*math.sin(a),p[2]),(1,12,11),a)
# Build and batch static hull/interior sections; debris keeps individual centred pivots.
root=bpy.data.objects.new('LoneDerelict',None);collection.objects.link(root)
objects=[]
for (name,mi),(vs,fs,cs) in batches.items():
 lo=Vector(tuple(min(v[i] for v in vs) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vs) for i in range(3)));pivot=(lo+hi)/2
 mesh=bpy.data.meshes.new(name);mesh.from_pydata([Vector(v)-pivot for v in vs],[],fs);mesh.materials.append(materials[mi]);mesh.update()
 attr=mesh.color_attributes.new(name='Patina',type='FLOAT_COLOR',domain='POINT')
 for v,datum,color in zip(vs,attr.data,cs):
  f=.83+.08*math.sin(v[0]*.12)+rng.uniform(-.025,.025)
  datum.color=(f,f,f,1) if mi in [0,1] else tuple(c*f for c in color[:3])+(1,)
 bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
 o=bpy.data.objects.new(name+' | '+materials[mi].name[3:],mesh);collection.objects.link(o);o.parent=root;o.location=pivot;objects.append(o)
for section,names in [('Hull',['Outer hull','Aft bulkhead','Torn hull lips','Breach scorching','Hull detailing','Hull accent','Bridge','Bridge windows','Engine structure','Engines','Frost deposits']),('Interior',['Interior decks','Interior bulkheads','Interior frames','Interior cargo'])]:
 for mi in range(5):
  parts=[o for o in collection.objects if o.type=='MESH' and any(o.name.startswith(n+' |') for n in names) and o.data.materials[0]==materials[mi]]
  if not parts:continue
  bpy.ops.object.select_all(action='DESELECT')
  for o in parts:o.select_set(True)
  bpy.context.view_layer.objects.active=parts[0]
  if len(parts)>1:bpy.ops.object.join()
  o=parts[0];o.name=section+' | '+materials[mi].name[3:]
  lo=Vector(tuple(min(v.co[i] for v in o.data.vertices) for i in range(3)));hi=Vector(tuple(max(v.co[i] for v in o.data.vertices) for i in range(3)));offset=(lo+hi)/2
  for v in o.data.vertices:v.co-=offset
  o.location+=offset
for name in ['DriftingCargo_01','DriftingCargo_02']:
 parts=[o for o in collection.objects if o.type=='MESH' and o.name.startswith(name+' |')]
 bpy.ops.object.select_all(action='DESELECT')
 for o in parts:o.select_set(True)
 bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();parts[0].name=name
objects=[o for o in collection.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in collection.objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
# Export grayscale weathering directly; encode the tint as the standard glTF factor.
for m in materials[:2]:
 v=next(n for n in m.node_tree.nodes if n.bl_idname=='ShaderNodeVertexColor')
 m.node_tree.links.new(v.outputs['Color'],m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/landmarks/lone_derelict.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_cameras=False,export_lights=False,export_yup=True)
import struct
path=ROOT/'assets/landmarks/lone_derelict.glb';raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);tail=raw[20+size:]
for entry in doc['materials']:
 for i in [0,1]:
  if entry['name']==materials[i].name:entry.setdefault('pbrMetallicRoughness',{})['baseColorFactor']=[*colors[i],1]
payload=json.dumps(doc,separators=(',',':')).encode();payload+=b' '*((-len(payload))%4)
path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(payload)+len(tail))+struct.pack('<I4s',len(payload),b'JSON')+payload+tail)
for m in materials[:2]:
 mix=next(n for n in m.node_tree.nodes if n.bl_idname=='ShaderNodeMixRGB')
 m.node_tree.links.new(mix.outputs[0],m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
studio=bpy.data.collections.new('Derelict preview only');scene.collection.children.link(studio)
def aim(o,target=(0,0,0)):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('Derelict overview');cam=bpy.data.objects.new('Derelict overview',d);studio.objects.link(cam);cam.location=(270,-480,280);aim(cam);d.type='ORTHO';d.ortho_scale=380;d.clip_end=10000;scene.camera=cam
for name,loc,power,size,color in [('Key',(50,-250,370),1900000,340,(.8,.88,1)),('Rim',(-220,220,200),2400000,300,(1,.8,.56)),('Breach fill',(0,-200,30),330000,230,(.6,.7,1))]:
 data=bpy.data.lights.new('LD '+name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
 o=bpy.data.objects.new('LD '+name,data);studio.objects.link(o);o.location=loc;aim(o)
world=bpy.data.worlds.new('Derelict darkness');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.01,.016,.025,1);world.node_tree.nodes['Background'].inputs[1].default_value=.2;scene.world=world
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True;scene.render.resolution_x=1800;scene.render.resolution_y=1200;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'lone_derelict_preview.png');scene.view_settings.view_transform='AgX'
bpy.ops.object.select_all(action='DESELECT')
for o in studio.objects:o.hide_set(True)
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   s=area.spaces.active;s.clip_end=10000;s.region_3d.view_distance=380;s.region_3d.view_location=(0,0,0);s.region_3d.view_rotation=cam.rotation_euler.to_quaternion();s.shading.color_type='MATERIAL';s.overlay.show_floor=False;s.overlay.show_axis_x=False;s.overlay.show_axis_y=False
bpy.context.view_layer.update();points=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
stats={'meshes':len(objects),'materials':7,'material_surfaces':sum(len(o.data.materials) for o in objects),'vertices':sum(len(o.data.vertices) for o in objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),'blender_dimensions_m':[max(v[i] for v in points)-min(v[i] for v in points) for i in range(3)],'nominal_hull_length_m':300,'breach_length_m':136,'separate_drifting_containers':2,'emergency_points':4,'beacon_points':1}
(OUT/'counts.json').write_text(json.dumps(stats,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'lone_derelict.blend'));print(json.dumps(stats));bpy.ops.render.render(write_still=True)
