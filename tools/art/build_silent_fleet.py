"""Original Silent Fleet settlement; execute in Blender using blender_rpc.py."""
import bpy
import bmesh
import math
import random
import json
from pathlib import Path
from mathutils import Vector

ROOT=Path('D:/CodingProjects/spacegame')
OUT=ROOT/'art/silent_fleet'
OUT.mkdir(parents=True,exist_ok=True)
rng=random.Random(6307)
scene=bpy.data.scenes.new('The Silent Fleet')
bpy.context.window.scene=scene
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1
collection=bpy.data.collections.new('Silent Fleet | Export')
scene.collection.children.link(collection)
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

# Palette is intentionally subdued; only inhabited windows and gardens emit.
colors=[(.14,.18,.19),(.075,.09,.105),(.29,.27,.22),(.09,.18,.17),
        (.04,.055,.07),(.7,.36,.12),(.17,.43,.23)]
materials=[material('SF Faded hull paint',colors[0],.55,.58),
           material('SF Structural graphite',colors[1],.7,.46),
           material('SF Reclaimed pale panels',colors[2],.4,.65),
           material('SF Muted green repairs',colors[3],.35,.58),
           material('SF Radiator carbon',colors[4],.35,.73),
           material('SF Dim warm windows',colors[5],.1,.4,.65),
           material('SF Greenhouse glow',colors[6],.05,.4,.55)]

def hull(key, transform, stations, tint=1):
    # Chamfered octagonal section: recognisable ship hulls, not floating boxes.
    section=[(-.72,-1),(.72,-1),(1,-.65),(1,.65),(.72,1),(-.72,1),(-1,.65),(-1,-.65)]
    vs=[transform((x,y*w,z*h)) for x,w,h in stations for y,z in section]
    fs=[tuple(reversed(range(8))),tuple((len(stations)-1)*8+i for i in range(8))]
    for j in range(len(stations)-1):
        for k in range(8):fs.append((j*8+k,j*8+(k+1)%8,(j+1)*8+(k+1)%8,(j+1)*8+k))
    add(key,vs,fs,tint)

def tube(key,p,q,r,sides=12,tint=1):
    beam(key,p,q,r,sides,tint)

def rope(p,q,sag=32):
    p,q=Vector(p),Vector(q)
    for j in range(16):
        def at(t):return p.lerp(q,t)+Vector((0,0,-sag*math.sin(math.pi*t)))
        tube(('Utility lashings',1),at(j/16),at((j+1)/16),1.15,6)

ships=[
 ('Colony ark',(-410,310,35),1.36,590,136,'ark'),
 ('Terraced transport',(290,370,70),1.72,520,125,'terrace'),
 ('Container freighter',(-705,-85,-20),1.52,430,128,'cargo'),
 ('Twin tank carrier',(655,10,-15),1.77,580,154,'tanker'),
 ('Spine freighter',(-110,-505,30),1.26,475,125,'spine'),
 ('Workshop tender',(420,-430,-65),1.90,345,100,'tender'),
 ('Long range passenger ark',(-20,675,-5),1.57,400,99,'passenger'),
 ('Old colony ferry',(-525,-520,5),1.06,320,110,'ferry')]
transforms=[]
for index,(name,origin,angle,L,W,kind) in enumerate(ships):
    c,s=math.cos(angle),math.sin(angle)
    def T(p,origin=origin,c=c,s=s):
        x,y,z=p;return (origin[0]+c*x-s*y,origin[1]+s*x+c*y,origin[2]+z)
    transforms.append(T)
    section='Ship %02d %s'%(index+1,name)
    shell=(section,0);details=(section,1);patches=(section,2)
    tint=rng.uniform(.77,1.20)
    half=W/2
    hull(shell,T,[(-L*.5,half*.62,19),(-L*.4,half,31),(L*.24,half,29),(L*.43,half*.7,23),(L*.5,half*.15,9)],tint)
    # Longitudinal seam rails, keel and cold engines.
    for side in [-1,1]:
        tube(details,T((-L*.36,side*half*.96,12)),T((L*.24,side*half*.96,12)),2.1,8)
        tube(details,T((-L*.36,side*half*.65,-29)),T((L*.26,side*half*.65,-29)),2.3,8)
        # Sealed engine shrouds have dark caps and absolutely no emission.
        tube(details,T((-L*.51,side*half*.4,0)),T((-L*.43,side*half*.4,0)),13,16)
        tube(patches,T((-L*.513,side*half*.4,0)),T((-L*.515,side*half*.4,0)),10,16,.65)
    # Broad replaced plates alternate with narrow structural bands on the hull roof.
    for k in range(8):
        x=-L*.33+k*L*.072
        box(details,T((x,0,31)),(2.0,W*.88,1.6),angle)
        if k%3==index%3:
            box(patches,T((x+8,half*.25,32)),(L*.05,W*.32,1.8),angle,rng.uniform(.55,.95))
    if kind in ['ark','passenger']:
        # Nested rounded habitation volumes and high longitudinal galleries.
        for y in [-W*.23,W*.23]:
            tube(shell,T((-L*.29,y,48)),T((L*.26,y,48)),21 if kind=='ark' else 16,16,tint*.9)
            for k in range(7):
                box(patches,T((-L*.24+k*L*.07,y,68 if kind=='ark' else 63)),(L*.046,24,2),angle,.72)
        hull(shell,lambda p:T((p[0],p[1],p[2]+68)),[(-L*.12,18,13),(L*.15,18,13),(L*.24,9,6)],tint)
    elif kind=='terrace':
        for tier in range(3):
            box(shell,T((-tier*20,0,41+tier*21)),(L*(.63-tier*.14),W*(.8-tier*.17),20),angle,tint*(1-tier*.1))
            for side in [-1,1]:
                for k in range(9-tier*2):
                    if k%3!=0:continue
                    x=-L*(.27-tier*.05)+k*L*.055
                    box(('Inhabited windows',5),T((x,side*W*(.4-tier*.085),44+tier*21)),(4,1.8,2.4),angle)
    elif kind in ['cargo','spine']:
        for k in range(5 if kind=='cargo' else 7):
            for side in [-1,1]:
                x=-L*.30+k*L*(.14 if kind=='cargo' else .095)
                y=side*W*.24
                box(shell,T((x,y,47)),(L*.10,W*.35,29),angle,tint*rng.uniform(.7,1.3))
                box(patches,T((x,y,62)),(L*.075,W*.28,1.2),angle,rng.uniform(.55,.85))
                for rib in [-1,0,1]:box(details,T((x+rib*L*.033,y,48)),(1.4,W*.36,30),angle)
        box(details,T((0,0,62)),(L*.78,9,5),angle)
    elif kind=='tanker':
        # Three stout axial tanks, with caretaker cabins grafted between them.
        for y in [-W*.32,0,W*.32]:
            tube(shell,T((-L*.33,y,52)),T((L*.31,y,52)),24,24,tint*.85)
            for x in [-L*.29,-L*.1,L*.1,L*.28]:
                tube(details,T((x-2,y,52)),T((x+2,y,52)),25,24)
        box(patches,T((L*.27,0,89)),(70,64,25),angle,.65)
    elif kind=='tender':
        hull(shell,lambda p:T((p[0],p[1],p[2]+40)),[(-L*.29,half*.8,12),(L*.19,half*.8,12),(L*.31,half*.5,5)],tint)
        for side in [-1,1]:
            box(details,T((0,side*W*.64,8)),(L*.43,16,15),angle)
            for x in [-L*.18,L*.18]:tube(details,T((x,0,0)),T((x,side*W*.7,8)),4,8)
    else:
        for x in [-L*.2,L*.12]:
            box(shell,T((x,0,48)),(L*.26,W*.8,32),angle,tint)
        box(patches,T((0,0,70)),(L*.22,W*.38,10),angle,.75)
    # Sparse living lights, deliberately not a normal station's rows of lamps.
    for side in [-1,1]:
        for k in range(12):
            if (k+index)%4!=0:continue
            x=-L*.32+k*L*.049
            box(('Inhabited windows',5),T((x,side*half*1.006,10)),(5,1.3,3),angle)
    # A sealed access collar on the side facing the later central hub.
    p=Vector(origin);towards=Vector((-p.x,-p.y,0)).normalized()
    q=p+towards*(half+12)
    tube(details,p,q,11,12)

# Later-built town centre: low, irregular clustered modules in scavenged plate.
hub=(0,35,0)
tube(('Common hub',1),(0,35,-40),(0,35,42),96,12)
tube(('Common hub',2),(0,35,40),(0,35,53),88,12,.72)
for i in range(6):
    a=i*math.tau/6
    box(('Common hub',2),(math.cos(a)*81,35+math.sin(a)*81,16),(64,43,37),a,rng.uniform(.6,.95))
    for j in [-1,1]:
        box(('Inhabited windows',5),(math.cos(a)*113-math.sin(a)*j*9,35+math.sin(a)*113+math.cos(a)*j*9,22),(1.5,4,3),a)
for k in range(9):
    box(('Common hub',3),((k%3-1)*46,35+(k//3-1)*39,56),(42,34,3),0,rng.uniform(.6,1))

def bridge(p,q,width=9):
    p,q=Vector(p),Vector(q)
    tube(('Habitable bridges',1),p,q,width+2,8)
    tube(('Habitable bridges',2),p,q,width,8,.66)
    direction=(q-p).normalized();side=direction.cross(Vector((0,0,1))).normalized()
    # External service catwalks with an exposed triangulated backbone.
    for sign in [-1,1]:
        offset=side*(width+7)*sign
        tube(('Bridge trusses',1),p+offset-Vector((0,0,12)),q+offset-Vector((0,0,12)),1.6,6)
        tube(('Bridge trusses',1),p+offset,q+offset,1,6)
        for k in range(10):
            x=p.lerp(q,k/10)+offset;y=p.lerp(q,(k+1)/10)+offset
            tube(('Bridge trusses',1),x,y-Vector((0,0,12)),1,6)
            tube(('Bridge trusses',1),x,x-Vector((0,0,12)),1,6)

# Eight radial routes plus five hull-to-hull alleys tie the ships into one town.
for i,(_,origin,a,L,W,kind) in enumerate(ships):
    p=Vector(origin)
    dest=Vector(hub)+Vector((0,0,8 if i%2 else -8))
    bridge(p,dest,8 if i%2 else 10)
    rope(p+Vector((0,0,45)),dest+Vector((0,0,36)),28)
for i,j in [(0,2),(0,6),(6,1),(3,5),(4,7)]:
    p=Vector(ships[i][1])+Vector((0,0,-9));q=Vector(ships[j][1])+Vector((0,0,-9))
    bridge(p,q,6)
    rope(p+Vector((0,0,45)),q+Vector((0,0,45)),42)

# Shared radiator fields on perimeter trusses. No blue solar-panel glow.
for side,y,z in [(-1,85,-75),(1,-40,-95)]:
    x=side*805
    tube(('Radiator frames',1),(side*670,y,z+60),(side*925,y,z),5,8)
    for bank in range(2):
        for row in range(7):
            cx=x+side*bank*78;cy=y+(row-3)*49
            box(('Radiator frames',1),(cx,cy,z),(74,46,4))
            box(('Radiator fields',4),(cx,cy,z+2.3),(68,42,1))
            for k in range(5):box(('Radiator frames',1),(cx-27+k*13,cy,z+3),(1,42,.6))
    for yy in [y-155,y+155]:
        tube(('Radiator frames',1),(side*675,y,z+48),(side*920,yy,z),2,8)

# Three small shared gardens: gently glowing pitched roofs with dark frame mullions.
for p,angle in [((-20,40,60),.15),((296,330,165),1.72),((-410,310,118),1.36)]:
    c,s=math.cos(angle),math.sin(angle)
    def G(v):
        x,y,z=v;return(p[0]+x*c-y*s,p[1]+x*s+y*c,p[2]+z)
    vs=[G(v) for v in [(-40,-17,0),(40,-17,0),(40,17,0),(-40,17,0),(-40,-17,13),(40,-17,13),(40,17,13),(-40,17,13),(-40,0,24),(40,0,24)]]
    add(('Greenhouses',6),vs,[(0,1,5,4),(1,2,6,9,5),(2,3,7,6),(3,0,4,8,7),(4,5,9,8),(8,9,6,7)])
    box(('Greenhouse frames',1),p,(84,38,4),angle)
    for x in [-40,-20,0,20,40]:
        for aa,bb in [((x,-17,0),(x,-17,13)),((x,-17,13),(x,0,24)),((x,0,24),(x,17,13)),((x,17,13),(x,17,0))]:
            tube(('Greenhouse frames',1),G(aa),G(bb),1,6)
    tube(('Greenhouse frames',1),G((-40,0,24)),G((40,0,24)),1.3,6)

# Exact two-kilometre maximum planar extent; preserve metre scale in the exported nodes.
all_vertices=[v for vs,fs,cs in batches.values() for v in vs]
lo=Vector(tuple(min(v[i] for v in all_vertices) for i in range(3)))
hi=Vector(tuple(max(v[i] for v in all_vertices) for i in range(3)))
centre=(lo+hi)/2;scale=2000/max(hi.x-lo.x,hi.y-lo.y)
root=bpy.data.objects.new('SilentFleet',None);collection.objects.link(root)
objects=[]
for (name,mi),(vs,fs,cs) in batches.items():
    transformed=[(Vector(v)-centre)*scale for v in vs]
    low=Vector(tuple(min(v[i] for v in transformed) for i in range(3)))
    high=Vector(tuple(max(v[i] for v in transformed) for i in range(3)))
    pivot=(low+high)/2
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([v-pivot for v in transformed],[],fs);mesh.materials.append(materials[mi]);mesh.update()
    attr=mesh.color_attributes.new(name='Patina',type='FLOAT_COLOR',domain='POINT')
    for datum,color in zip(attr.data,cs):datum.color=color
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    obj=bpy.data.objects.new(name+' | '+materials[mi].name[3:],mesh);collection.objects.link(obj);obj.parent=root;obj.location=pivot;objects.append(obj)

# Reduce minor infrastructure into one mesh per shared material, leaving each ship distinct.
for matindex in [1,2]:
    names=['Utility lashings','Habitable bridges','Bridge trusses','Greenhouse frames','Radiator frames']
    parts=[o for o in collection.objects if o.type=='MESH' and any(o.name.startswith(n) for n in names) and o.data.materials[0]==materials[matindex]]
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    if parts:
        bpy.context.view_layer.objects.active=parts[0]
        if len(parts)>1:bpy.ops.object.join()
        parts[0].name='Shared infrastructure | '+materials[matindex].name[3:]
        obj=parts[0]
        low=Vector(tuple(min(v.co[i] for v in obj.data.vertices) for i in range(3)))
        high=Vector(tuple(max(v.co[i] for v in obj.data.vertices) for i in range(3)))
        offset=(low+high)/2
        for v in obj.data.vertices:v.co-=offset
        obj.location+=offset
objects=[o for o in collection.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in collection.objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/landmarks/silent_fleet.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_cameras=False,export_lights=False,export_yup=True)

studio=bpy.data.collections.new('Silent Fleet preview only');scene.collection.children.link(studio)
def aim(o):o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('Silent Fleet overview');cam=bpy.data.objects.new('Silent Fleet overview',d);studio.objects.link(cam)
cam.location=(1350,-2000,2500);aim(cam);d.type='ORTHO';d.ortho_scale=2700;d.clip_end=20000;scene.camera=cam
for name,loc,power,size,color in [('Key',(200,-700,1800),125000000,1800,(.85,.92,1)),('Rim',(-1300,800,1000),105000000,1200,(.52,.70,1)),('Fill',(1300,800,900),60000000,1600,(1,.8,.6))]:
    data=bpy.data.lights.new('SF '+name,'AREA');data.energy=power*.28;data.shape='DISK';data.size=size;data.color=color
    o=bpy.data.objects.new('SF '+name,data);studio.objects.link(o);o.location=loc;aim(o)
world=bpy.data.worlds.new('Silent Fleet darkness');world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.009,.013,.02,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.2;scene.world=world
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1800;scene.render.resolution_y=1600;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'silent_fleet_preview.png');scene.view_settings.view_transform='AgX'
bpy.ops.object.select_all(action='DESELECT')
for o in studio.objects:o.hide_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            s=area.spaces.active;s.clip_end=20000;s.region_3d.view_distance=2600;s.region_3d.view_location=(0,0,0);s.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
            s.shading.color_type='MATERIAL';s.overlay.show_floor=False;s.overlay.show_axis_x=False;s.overlay.show_axis_y=False
stats={'ships':8,'meshes':len(objects),'materials':7,'material_surfaces':sum(len(o.data.materials) for o in objects),
       'vertices':sum(len(o.data.vertices) for o in objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),
       'blender_dimensions_m':list((hi-lo)*scale),'greenhouses':3,'radiator_fields':2,'inhabited_bridges':13}
(OUT/'counts.json').write_text(json.dumps(stats,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'silent_fleet.blend'))
print(json.dumps(stats))
bpy.ops.render.render(write_still=True)
