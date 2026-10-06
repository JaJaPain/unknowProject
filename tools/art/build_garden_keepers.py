"""Original Garden keepers station. Run inside Blender via blender_rpc.py."""
import bpy,bmesh,math,random,json
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/CodingProjects/spacegame');OUT=ROOT/'art/garden_keepers'
OUT.mkdir(parents=True,exist_ok=True)
rng=random.Random(5600)
scene=bpy.data.scenes.new('The Garden Keepers Station');bpy.context.window.scene=scene
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
collection=bpy.data.collections.new('Garden Keepers | Export');scene.collection.children.link(collection)
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
colors=[(.63,.64,.55),(.23,.32,.28),(.34,.60,.49),(.055,.105,.17),(.11,.24,.09),(.18,.5,.22),(1,.5,.20),(.27,.75,1)]
materials=[material('GK Warm ivory hull',colors[0],.35,.45),material('GK Sage frames and armour',colors[1],.5,.42),
 material('GK Tinted greenhouse glass',colors[2],.1,.17),material('GK Solar cells',colors[3],.45,.32),
 material('GK Crop masses',colors[4],.0,.8),material('GK Growing light',colors[5],.0,.4,1.2),
 material('GK Living windows',colors[6],.0,.4,1.5),material('GK Dock navigation',colors[7],.0,.3,2)]
glass=materials[2];p=glass.node_tree.nodes.get('Principled BSDF')
for link in list(glass.node_tree.links):glass.node_tree.links.remove(link)
glass.node_tree.links.new(p.outputs['BSDF'],glass.node_tree.nodes.get('Material Output').inputs['Surface'])
p.inputs['Base Color'].default_value=(*colors[2],1);p.inputs['Alpha'].default_value=.19
p.inputs['Metallic'].default_value=.05;p.inputs['Roughness'].default_value=.16
if hasattr(glass,'surface_render_method'):glass.surface_render_method='DITHERED'
glass.diffuse_color=(*colors[2],.19);glass.use_backface_culling=False
# Compact pressure spine and the protected seed vault at its centre.
beam(('Hub spine',0),(-172,0,0),(149,0,0),17,24)
for x in [-145,-94,-36,20,78,131]:beam(('Hub details',1),(x-2,0,0),(x+2,0,0),18.2,24)
box(('Seed vault',1),(18,0,3),(82,65,56))
box(('Seed vault',0),(18,0,33),(74,57,5))
for y in [-34,34]:
 box(('Seed vault',0),(18,y,3),(73,4,45))
 for x in [-9,18,45]:box(('Seed vault',1),(x,y*1.04,3),(4,4,47))
# A deep inset rectangular access hatch, thick surrounding armour; no symbols.
box(('Seed vault',1),(61,0,3),(3,43,42))
box(('Seed vault',0),(63,0,3),(3,27,28))
box(('Seed vault',1),(65,0,3),(1,2,28))
# Two neatly matched living/service pods behind the vault.
for x in [-124,-79]:
 beam(('Living modules',0),(x,-26,0),(x,26,0),20,24)
 for y in [-20,20]:beam(('Hub details',1),(x,y-1,0),(x,y+1,0),20.5,24)
 for side in [-1,1]:
  for j in [-1,0,1]:box(('Warm windows',6),(x+j*8,side*26.4,7),(4,1,3))
 box(('Hub details',1),(x,0,20),(24,30,2))

def crop(center,scale,tint):
 vs=[];steps=8
 for j in range(1,5):
  t=math.pi*j/5
  for i in range(steps):
   a=math.tau*i/steps
   vs.append((center[0]+scale[0]*math.sin(t)*math.cos(a),center[1]+scale[1]*math.sin(t)*math.sin(a),center[2]+scale[2]*math.cos(t)))
 vs.extend([(center[0],center[1],center[2]+scale[2]),(center[0],center[1],center[2]-scale[2])]);fs=[]
 for j in range(3):
  for i in range(steps):fs.append((j*steps+i,j*steps+(i+1)%steps,(j+1)*steps+(i+1)%steps,(j+1)*steps+i))
 for i in range(steps):fs.extend([(32,(i+1)%steps,i),(33,24+i,24+(i+1)%steps)])
 add(('Simple planted masses',4),vs,fs,tint)

# Barrel-roof greenhouses branch from the spine; consistent ribs, deliberately unequal lengths.
greenhouses=[(-57,1,151,23),(-57,-1,119,23),(29,1,185,26),(29,-1,160,26),(113,1,118,21),(113,-1,92,21)]
for idx,(x,side,length,r) in enumerate(greenhouses):
 start=31;end=start+length;y0=side*(start+end)/2
 beam(('Greenhouse connectors',1),(x,0,0),(x,side*(start+5),0),9,16)
 box(('Greenhouse bases',0),(x,y0,2),(r*2+6,length+6,11))
 box(('Greenhouse frames',1),(x,y0,8),(r*2+2,length+2,2))
 # Transparent roof and semicircular end caps; growing lights are genuinely inside.
 verts=[];steps=20
 for y in [side*start,side*end]:
  for i in range(steps+1):
   a=math.pi*i/steps;verts.append((x+r*math.cos(a),y,9+r*math.sin(a)))
 faces=[(i,i+1,steps+2+i,steps+1+i) for i in range(steps)]
 faces.extend([tuple(reversed(range(steps+1))),tuple(steps+1+i for i in range(steps+1))])
 add(('Greenhouse glass',2),verts,faces)
 for y in [side*(start+j*length/8) for j in range(9)]:
  for i in range(steps):
   a=math.pi*i/steps;b=math.pi*(i+1)/steps
   beam(('Greenhouse frames',1),(x+r*math.cos(a),y,9+r*math.sin(a)),(x+r*math.cos(b),y,9+r*math.sin(b)),.65,6)
 for dx,z in [(-r,9),(r,9),(0,9+r)]:beam(('Greenhouse frames',1),(x+dx,side*start,z),(x+dx,side*end,z),.8,8)
 # Paired crop beds around a clear central service aisle.
 for row in [-1,1]:
  box(('Crop beds',1),(x+row*r*.48,y0,10),(r*.68,length-12,2))
  for j in range(int(length/14)):
   y=side*(start+9+j*14)
   crop((x+row*r*.48,y,15),(r*.3,5.5,4.5),rng.uniform(.8,1.5))
  box(('Growing lights',5),(x+row*r*.83,y0,12),(1.2,length-10,1))
 # Reinforced end door and small landing / maintenance ledge.
 box(('Greenhouse bases',0),(x,side*(end+1),13),(12,3,19))
 box(('Greenhouse frames',1),(x,side*(end+3),13),(8,1,14))
 box(('Greenhouse bases',0),(x,side*(end+8),5),(24,14,3))
# Water and nutrient tanks nest beneath the protected hub.
for x in [-19,12,43]:
 beam(('Life support tanks',0),(x,-19,-37),(x,19,-37),10,20)
 for y in [-15,15]:beam(('Life support tanks',1),(x,y-1,-37),(x,y+1,-37),10.8,20)
 beam(('Life support tanks',1),(x,0,-37),(x,0,-16),2,8)
# Suspended supply pods with visible cargo straps and short securing lines.
for x,y in [(-114,-17),(-77,15),(85,-12)]:
 box(('Supply pods',0),(x,y,-43),(22,17,20))
 for dx in [-7,7]:
  box(('Supply straps',1),(x+dx,y,-43),(1,18,22))
  beam(('Supply straps',1),(x+dx,y,-32),(x+dx,y*.55,-13),.7,6)
# Twin solar wings have independent pivots along their span axis (Blender Y).
for side,label in [(-1,'Port'),(1,'Starboard')]:
 beam(('Solar '+label,1),(-162,side*8,0),(-162,side*300,0),3,12)
 for j in range(8):
  y=side*(48+j*32)
  box(('Solar '+label,1),(-162,y,0),(101,30,3))
  box(('Solar '+label,3),(-162,y,2),(96,27,1))
  for k in range(8):box(('Solar '+label,1),(-204+k*12,y,2.6),(.45,27,.25))
  for xx in [-192,-132]:box(('Solar '+label,1),(xx,y,2.6),(1,27,.3))
# Docking ring in the YZ plane at the spine's forward end, with two opposed berths.
R=32;steps=96;verts=[]
for i in range(steps):
 a=math.tau*i/steps
 for j in range(8):
  b=math.tau*j/8;rr=R+4*math.cos(b)
  verts.append((178+4*math.sin(b),rr*math.cos(a),rr*math.sin(a)))
faces=[]
for i in range(steps):
 for j in range(8):faces.append((i*8+j,i*8+(j+1)%8,((i+1)%steps)*8+(j+1)%8,((i+1)%steps)*8+j))
add(('Docking ring',0),verts,faces)
for y in [-32,32]:
 beam(('Docking ring',1),(137,0,0),(178,y,0),3,10)
 beam(('Docking ring',1),(176,y,0),(192,y,0),7,16)
 box(('Dock navigation',7),(182,y,7),(2,3,2))
box(('Docking ring',0),(178,0,-33),(27,43,3))
# Tidy repair plates are subtle, same palette rather than mismatched scrap.
for x in [-142,-91,73]:box(('Hub details',1),(x,0,18),(13,9,1))
root=bpy.data.objects.new('GardenKeepersStation',None);collection.objects.link(root)
pivots={}
for side,label in [(-1,'Port'),(1,'Starboard')]:
 o=bpy.data.objects.new('Solar'+label+'_Pivot',None);collection.objects.link(o);o.parent=root;o.location=(-162,side*27,0);pivots[label]=o
objects=[]
for (name,mi),(vs,fs,cs) in batches.items():
 low=Vector(tuple(min(v[i] for v in vs) for i in range(3)));high=Vector(tuple(max(v[i] for v in vs) for i in range(3)))
 pivot=(low+high)/2;parent=root
 if name.startswith('Solar '):parent=pivots[name.split()[1]];pivot=parent.location.copy()
 mesh=bpy.data.meshes.new(name);mesh.from_pydata([Vector(v)-pivot for v in vs],[],fs);mesh.materials.append(materials[mi]);mesh.update()
 if mi!=2:
  attr=mesh.color_attributes.new(name='Patina',type='FLOAT_COLOR',domain='POINT')
  for datum,color in zip(attr.data,cs):datum.color=color
 bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
 o=bpy.data.objects.new(name+' | '+materials[mi].name[3:],mesh);collection.objects.link(o);o.parent=parent
 if parent==root:o.location=pivot
 objects.append(o)
# Combine same-material fixed sections into greenhouse, hub/vault, life support and docking batches.
for section,names in [('Hub and vault',['Hub spine','Hub details','Seed vault','Living modules']),('Greenhouse structure',['Greenhouse connectors','Greenhouse bases','Greenhouse frames','Crop beds']),('Life support',['Life support tanks','Supply pods','Supply straps'])]:
 for mi in [0,1]:
  parts=[o for o in collection.objects if o.type=='MESH' and any(o.name.startswith(n+' |') for n in names) and o.data.materials[0]==materials[mi]]
  if not parts:continue
  bpy.ops.object.select_all(action='DESELECT')
  for o in parts:o.select_set(True)
  bpy.context.view_layer.objects.active=parts[0]
  if len(parts)>1:bpy.ops.object.join()
  o=parts[0];o.name=section+' | '+materials[mi].name[3:]
  low=Vector(tuple(min(v.co[i] for v in o.data.vertices) for i in range(3)));high=Vector(tuple(max(v.co[i] for v in o.data.vertices) for i in range(3)));offset=(low+high)/2
  for v in o.data.vertices:v.co-=offset
  o.location+=offset
objects=[o for o in collection.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in collection.objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/landmarks/garden_keepers.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_cameras=False,export_lights=False,export_yup=True)
studio=bpy.data.collections.new('Garden preview only');scene.collection.children.link(studio)
def aim(o):o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('Garden overview');cam=bpy.data.objects.new('Garden overview',d);studio.objects.link(cam);cam.location=(640,-760,820);aim(cam);d.type='ORTHO';d.ortho_scale=790;d.clip_end=10000;scene.camera=cam
for name,loc,power,size,color in [('Key',(150,-400,650),13500000,700,(1,.91,.76)),('Rim',(-400,300,400),11000000,600,(.64,.81,1)),('Fill',(500,400,250),6000000,550,(.8,1,.86))]:
 data=bpy.data.lights.new('GK '+name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
 o=bpy.data.objects.new('GK '+name,data);studio.objects.link(o);o.location=loc;aim(o)
world=bpy.data.worlds.new('Garden orbit');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.012,.023,.032,1);world.node_tree.nodes['Background'].inputs[1].default_value=.25;scene.world=world
scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=True;scene.cycles.transparent_max_bounces=16
scene.render.resolution_x=1800;scene.render.resolution_y=1500;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'garden_keepers_preview.png');scene.view_settings.view_transform='AgX'
bpy.ops.object.select_all(action='DESELECT')
for o in studio.objects:o.hide_set(True)
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   s=area.spaces.active;s.clip_end=10000;s.region_3d.view_distance=760;s.region_3d.view_location=(0,0,0);s.region_3d.view_rotation=cam.rotation_euler.to_quaternion();s.shading.color_type='MATERIAL';s.overlay.show_floor=False;s.overlay.show_axis_x=False;s.overlay.show_axis_y=False
bpy.context.view_layer.update();points=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
stats={'meshes':len(objects),'materials':8,'material_surfaces':sum(len(o.data.materials) for o in objects),'vertices':sum(len(o.data.vertices) for o in objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),'blender_dimensions_m':[max(v[i] for v in points)-min(v[i] for v in points) for i in range(3)],'greenhouses':6,'solar_wings':2,'docking_berths':2,'supply_pods':3,'life_support_tanks':3}
(OUT/'counts.json').write_text(json.dumps(stats,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'garden_keepers.blend'));print(json.dumps(stats));bpy.ops.render.render(write_still=True)
