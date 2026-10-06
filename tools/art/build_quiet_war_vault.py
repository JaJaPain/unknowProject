"""Original Quiet War cache vault, generated in the live Blender session."""
import bpy,bmesh,math,random,json
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/CodingProjects/spacegame');OUT=ROOT/'art/quiet_war_vault';OUT.mkdir(parents=True,exist_ok=True)
rng=random.Random(6500)
scene=bpy.data.scenes.new('The Quiet War Cache Vault');bpy.context.window.scene=scene
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
collection=bpy.data.collections.new('Quiet War Vault | Export');scene.collection.children.link(collection)
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
colors=[(.085,.10,.115),(.20,.155,.09),(.035,.04,.045),(.18,.19,.185),(.5,.085,.015),(.7,.28,.07)]
materials=[material('QW Gunmetal armour',colors[0],.75,.6),material('QW Dull bronze armour',colors[1],.7,.65),
 material('QW Scorched recesses',colors[2],.35,.9),material('QW Exposed fracture metal',colors[3],.65,.6),
 material('QW Faint core status',colors[4],.05,.5,.45),material('QW Sealed door seam',colors[5],.05,.5,.8)]
# Sealed eight-sided core with a real recessed entrance vestibule at the front.
profile=[(118,-58),(158,-37),(174,-12),(170,25),(138,54),(88,66)]
vs=[(r*math.cos(math.pi/8+i*math.tau/8),r*math.sin(math.pi/8+i*math.tau/8),z) for r,z in profile for i in range(8)]
fs=[tuple(reversed(range(8))),tuple((len(profile)-1)*8+i for i in range(8))]
for j in range(len(profile)-1):
 for i in range(8):
  if i==5 and j in [1,2,3]:continue
  fs.append((j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i))
add(('Core shell',0),vs,fs)
# Shallow dark vestibule behind the closed door, with an intact sealed inner bulkhead.
box(('Entrance recess',2),(0,-109,1),(116,5,87))
for x in [-57,57]:box(('Entrance recess',2),(x,-136,1),(5,59,87))
for z in [-41,43]:box(('Entrance recess',2),(0,-136,z),(116,59,5))

# True impact depressions in the thick upper plates, never penetrating their base.
def armour_sector(index,inner,outer,z,thickness,mi):
 a0=index*math.tau/8+math.pi/8+.018;a1=a0+math.tau/8-.036
 na=14;nr=9;vv=[];ff=[]
 centres=[(rng.uniform(.22,.78),rng.uniform(.2,.8),rng.uniform(3,7),rng.uniform(.10,.17)) for _ in range(2)]
 for radial in range(nr+1):
  t=radial/nr;r=inner+(outer-inner)*t
  for angular in range(na+1):
   s=angular/na;a=a0+(a1-a0)*s
   dent=sum(depth*math.exp(-(((s-u)/width)**2+((t-v)/(width*1.4))**2)*2) for u,v,depth,width in centres)
   # An elongated gouge crosses several plates without going through them.
   scar=2.7*math.exp(-((s-.46-t*.18)/.035)**2)*math.sin(math.pi*t)**2 if index in [1,4,6] else 0
   vv.append((r*math.cos(a),r*math.sin(a),z+3*t-dent-scar))
 for j in range(nr):
  for i in range(na):
   k=j*(na+1)+i;ff.append((k,k+1,k+na+2,k+na+1))
 border=list(range(na+1))+[j*(na+1)+na for j in range(1,nr+1)]+[nr*(na+1)+i for i in range(na-1,-1,-1)]+[j*(na+1) for j in range(nr-1,0,-1)]
 bottom=[]
 for k in border:bottom.append(len(vv));x,y,_=vv[k];vv.append((x,y,z-thickness))
 ff.append(tuple(reversed(bottom)))
 for i,k in enumerate(border):n=(i+1)%len(border);ff.append((k,border[n],bottom[n],bottom[i]))
 add(('Overlapping armour',mi),vv,ff)
for i in range(8):
 armour_sector(i,78,135,61,13,1 if i%3==0 else 0)
 if i!=5:armour_sector(i,129,169,33,15,0 if i%2 else 1)
# Dense central armoured cap, faceted rather than a dome.
beam(('Core shell',0),(0,0,50),(0,0,76),83,8)
beam(('Core trim',1),(0,0,72),(0,0,78),76,8)
# Buttress ribs reach over the shoulders and around the core's belly.
for i in range(8):
 a=i*math.tau/8+math.pi/8
 points=[(r*math.cos(a),r*math.sin(a),z) for r,z in [(99,63),(141,49),(177,13),(173,-21),(128,-56)]]
 for p,q in zip(points,points[1:]):beam(('Buttress ribs',0),p,q,8,8)
 for r,z in [(146,44),(175,10)]:box(('Buttress joints',1),(r*math.cos(a),r*math.sin(a),z),(22,16,9),a)
# A single monumental hatch, layered but shut; later animation uses its centre pivot.
box(('Door',0),(0,-169,0),(94,18,76))
box(('Door',1),(0,-180,0),(80,6,64))
for x in [-30,0,30]:box(('Door',0),(x,-185,0),(12,5,62))
for z in [-26,26]:box(('Door',3),(0,-185,z),(78,4,4))
for x in [-62,62]:box(('Door frame',0),(x,-160,0),(28,34,102))
for z in [-49,49]:box(('Door frame',0),(0,-160,z),(151,34,18))
for x in [-49,49]:box(('Door seam',5),(x,-180,0),(1.2,1,78))
for z in [-39,39]:box(('Door seam',5),(0,-180,z),(99,1,1.2))
# Mechanical locking dogs; no rune-like symbols or writing.
for side in [-1,1]:
 for z in [-26,0,26]:box(('Door frame',1),(side*53,-184,z),(12,10,10))
# Few surviving dim status lamps, deliberately no working perimeter lights.
for x in [-64,64]:
 for z in [-10,0,10]:box(('Core status lights',4),(x,-178,z),(1.6,1,1.6))
# Anchor arms and five dead defence islands leave the entrance unobstructed.
platforms=[]
for i,a in enumerate([.12,1.23,2.38,3.32,5.55]):
 r=220;z=-23+[0,7,-6,1,-8][i];p=Vector((r*math.cos(a),r*math.sin(a),z));platforms.append(tuple(p))
 base=Vector((145*math.cos(a),145*math.sin(a),-30))
 for side in [-1,1]:
  off=Vector((-math.sin(a)*side*7,math.cos(a)*side*7,0))
  beam(('Anchor arms',0),base+off,p+off,4,8)
  beam(('Anchor arms',2),base+off-Vector((0,0,14)),p+off-Vector((0,0,14)),2,6)
  for k in range(5):
   c=base.lerp(p,k/5)+off;d=base.lerp(p,(k+1)/5)+off
   beam(('Anchor arms',2),c,d-Vector((0,0,14)),1.3,6)
 # Broken platform is a clipped irregular slab with chunks missing from its edge.
 pts=[(-27,-22),(-2,-27),(24,-20),(28,0),(13,8),(20,19),(-2,24),(-29,13)]
 verts=[]
 for zz in [-8,3]:
  for x,y in pts:verts.append((p.x+x*math.cos(a)-y*math.sin(a),p.y+x*math.sin(a)+y*math.cos(a),p.z+zz))
 faces=[tuple(reversed(range(8))),tuple(8+k for k in range(8))]
 for k in range(8):faces.append((k,(k+1)%8,(k+1)%8+8,k+8))
 add(('Dead platforms',0),verts,faces,.7)
 beam(('Dead platforms',2),p+Vector((0,0,3)),p+Vector((0,0,12)),17,12)
 # Disabled angular mount, tipped barrel or jagged empty socket.
 box(('Dead mounts',1),p+Vector((0,0,15)),(25,22,15),a+.14)
 direction=Vector((math.cos(a),math.sin(a),-.65)).normalized()
 if i in [0,2,4]:
  start=p+Vector((0,0,17));end=start+direction*(35 if i!=2 else 22)
  beam(('Dead mounts',0),start,end,4.2,10)
  beam(('Fractured edges',3),end-direction*2,end,4.6,10)
  beam(('Dead mounts',2),end+direction*.25,end+direction*.7,3.1,10)
 else:
  for k in range(4):
   angle=a+k*math.tau/4
   start=p+Vector((math.cos(angle)*7,math.sin(angle)*7,20));end=start+Vector((math.cos(angle)*rng.uniform(3,8),math.sin(angle)*rng.uniform(3,8),rng.uniform(4,9)))
   beam(('Fractured edges',3),start,end,2,5)
 # Burned, torn panels on the platforms, much rougher than the intact core.
 for k in range(6):
  box(('Platform scars',2),p+Vector((rng.uniform(-19,19),rng.uniform(-15,15),4)),(rng.uniform(4,12),rng.uniform(2,7),1.2),a+rng.uniform(-.8,.8))
# Bare anchor stubs reach into the surrounding wreck field without adding ships.
for a in [1.83,4.01]:
 beam(('Anchor arms',0),(150*math.cos(a),150*math.sin(a),-35),(242*math.cos(a),242*math.sin(a),-38),5,8)
 for side in [-1,1]:beam(('Anchor arms',2),(225*math.cos(a),225*math.sin(a),-38),(247*math.cos(a)-side*5*math.sin(a),247*math.sin(a)+side*5*math.cos(a),-41),2,6)
# Three loose plates remain separate for optional slow drift.
for i,(p,size,a) in enumerate([((-202,-120,10),(25,18,4),.6),((93,212,30),(18,23,3),-.4),((200,110,-56),(24,14,4),1.2)]):
 box(('LoosePlate_%02d'%(i+1),0),p,size,a,.7)
# Uniform scale brings the complete envelope to exactly 500 m across.
allv=[v for vs,fs,cs in batches.values() for v in vs]
low=Vector(tuple(min(v[i] for v in allv) for i in range(3)));high=Vector(tuple(max(v[i] for v in allv) for i in range(3)));scale=500/max(high.x-low.x,high.y-low.y)
root=bpy.data.objects.new('QuietWarVault',None);collection.objects.link(root)
doorpivot=bpy.data.objects.new('VaultDoor_Pivot',None);collection.objects.link(doorpivot);doorpivot.parent=root;doorpivot.location=(0,-173*scale,0)
objects=[]
for (name,mi),(vs,fs,cs) in batches.items():
 verts=[Vector(v)*scale for v in vs];lo=Vector(tuple(min(v[i] for v in verts) for i in range(3)));hi=Vector(tuple(max(v[i] for v in verts) for i in range(3)))
 pivot=(lo+hi)/2;parent=root
 if name=='Door':pivot=doorpivot.location.copy();parent=doorpivot
 mesh=bpy.data.meshes.new(name);mesh.from_pydata([v-pivot for v in verts],[],fs);mesh.materials.append(materials[mi]);mesh.update()
 attr=mesh.color_attributes.new(name='Patina',type='FLOAT_COLOR',domain='POINT')
 for v,datum,color in zip(verts,attr.data,cs):
  if mi<4:
   f=.77+.13*math.sin(v.x*.10+v.z*.07)+.08*math.sin(v.y*.14)+rng.uniform(-.035,.035)
   datum.color=tuple(max(.003,c*f) for c in color[:3])+(1,)
  else:datum.color=color
 bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
 o=bpy.data.objects.new(name+' | '+materials[mi].name[3:],mesh);collection.objects.link(o);o.parent=parent
 if parent==root:o.location=pivot
 objects.append(o)
# Batch by material within core armour and ruined perimeter; retain door and loose plates.
for section,names in [('Core armour',['Core shell','Core trim','Overlapping armour','Buttress ribs','Buttress joints','Door frame']),('Dead perimeter',['Anchor arms','Dead platforms','Dead mounts','Fractured edges','Platform scars'])]:
 for mi in range(4):
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
parts=[o for o in collection.objects if o.type=='MESH' and o.parent==doorpivot]
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();parts[0].name='VaultDoor'
objects=[o for o in collection.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in collection.objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/landmarks/quiet_war_vault.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_cameras=False,export_lights=False,export_yup=True)
studio=bpy.data.collections.new('Vault preview only');scene.collection.children.link(studio)
def aim(o):o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('Vault overview');cam=bpy.data.objects.new('Vault overview',d);studio.objects.link(cam);cam.location=(470,-760,550);aim(cam);d.type='ORTHO';d.ortho_scale=660;d.clip_end=10000;scene.camera=cam
for name,loc,power,size,color in [('Key',(-250,-400,620),7000000,570,(.83,.91,1)),('Rim',(300,350,380),10500000,440,(1,.72,.41)),('Fill',(480,-160,190),2200000,500,(.6,.72,1))]:
 data=bpy.data.lights.new('QW '+name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
 o=bpy.data.objects.new('QW '+name,data);studio.objects.link(o);o.location=loc;aim(o)
world=bpy.data.worlds.new('Quiet War darkness');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.008,.013,.021,1);world.node_tree.nodes['Background'].inputs[1].default_value=.2;scene.world=world
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1800;scene.render.resolution_y=1500;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'quiet_war_vault_preview.png');scene.view_settings.view_transform='AgX'
bpy.ops.object.select_all(action='DESELECT')
for o in studio.objects:o.hide_set(True)
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   s=area.spaces.active;s.clip_end=10000;s.region_3d.view_distance=660;s.region_3d.view_location=(0,0,0);s.region_3d.view_rotation=cam.rotation_euler.to_quaternion();s.shading.color_type='MATERIAL';s.overlay.show_floor=False;s.overlay.show_axis_x=False;s.overlay.show_axis_y=False
stats={'meshes':len(objects),'materials':6,'material_surfaces':sum(len(o.data.materials) for o in objects),'vertices':sum(len(o.data.vertices) for o in objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),'blender_dimensions_m':list((high-low)*scale),'dead_platforms':5,'loose_armour_plates':3,'door_pivot_blender_m':list(doorpivot.location),'door_material_surfaces':len(parts[0].data.materials)}
(OUT/'counts.json').write_text(json.dumps(stats,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'quiet_war_vault.blend'));print(json.dumps(stats));bpy.ops.render.render(write_still=True)
