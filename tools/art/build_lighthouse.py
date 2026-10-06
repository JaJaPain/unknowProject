"""Original Lighthouse set piece. Execute in Blender through blender_rpc.py."""
import bpy
import bmesh
import math
import random
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path('D:/CodingProjects/spacegame')
OUT = ROOT / 'art/lighthouse'
OUT.mkdir(parents=True, exist_ok=True)
rng = random.Random(2419)
scene = bpy.data.scenes.new('The Lighthouse')
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
collection = bpy.data.collections.new('Lighthouse | Export')
scene.collection.children.link(collection)

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

colors = [(.58,.59,.52), (.075,.105,.12), (.31,.105,.045),
          (.13,.28,.27), (.055,.095,.20), (.42,.85,1), (1,.42,.105), (1,.065,.018)]
materials = [material('LH Weathered pale alloy', colors[0], .32,.68),
             material('LH Dark structural steel', colors[1], .7,.49),
             material('LH Oxidised salvage', colors[2], .4,.75),
             material('LH Faded clan paint', colors[3], .3,.64),
             material('LH Solar cells', colors[4], .5,.32),
             material('LH Beacon emission', colors[5], .1,.3,4),
             material('LH Warm windows emission', colors[6], .1,.4,2.5),
             material('LH Navigation emission', colors[7], .1,.3,4)]
batches = {}

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

def radial(r,a,z): return (r*math.cos(a),r*math.sin(a),z)

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

def lathe(key, profile, steps=96, tint=1):
    # Open axial profiles are capped at both ends.
    if key[0] in ('Ancient tower', 'Lantern housing'):
        fine=[]
        for (r,z),(r2,z2) in zip(profile,profile[1:]):
            count=max(1,math.ceil(abs(z2-z)/8))
            fine.extend((r+(r2-r)*i/count,z+(z2-z)*i/count) for i in range(count))
        profile=fine+[profile[-1]]
    vs=[(r*math.cos(i*math.tau/steps),r*math.sin(i*math.tau/steps),z) for r,z in profile for i in range(steps)]
    fs=[]
    for j in range(len(profile)-1):
        for i in range(steps): fs.append((j*steps+i,j*steps+(i+1)%steps,(j+1)*steps+(i+1)%steps,(j+1)*steps+i))
    if profile[0] != profile[-1]:
        fs += [tuple(reversed(range(steps))),tuple((len(profile)-1)*steps+i for i in range(steps))]
    add(key,vs,fs,tint)

def ring(key,r,z,width,depth,steps=128):
    lathe(key,[(r-width/2,z-depth/2),(r+width/2,z-depth/2),
               (r+width/2,z+depth/2),(r-width/2,z+depth/2),(r-width/2,z-depth/2)],steps)

def cable(p,q):
    p,q=Vector(p),Vector(q)
    for i in range(12):
        def at(t): return p.lerp(q,t)+Vector((0,0,-12*math.sin(math.pi*t)))
        beam(('Clan infrastructure',1),at(i/12),at((i+1)/12),.65,6)

# Ancient continuous spindle, still legible between the settlement's platforms.
lathe(('Ancient tower',0),[(5,-450),(18,-427),(29,-396),(44,-352),
      (47,-300),(41,-215),(33,-90),(29,80),(25,190),(29,253),(47,279),(65,294)],128)
lathe(('Ancient foot',1),[(5,-450),(12,-430),(17,-399),(28,-374)],64)
for z,r in [(-350,44),(-270,46),(-170,39),(-60,32),(60,30),(165,27),(250,31)]:
    ring(('Ancient collars',1),r,z,2,3)
    ring(('Ancient tower',0),r+1,z+5,4,3)
# Eight elegant ribs trace the old tower without turning it into a cylinder.
for i in range(8):
    a=i*math.tau/8
    points=[radial(r,a,z) for r,z in [(19,-425),(46,-350),(45,-245),(35,-100),(31,75),(28,190),(34,258),(62,291)]]
    for p,q in zip(points,points[1:]): beam(('Ancient ribs',0),p,q,3,8,.82)
    for z in [138,180,222]:
        p=radial(28,a,z)
        box(('Ancient collars',1),p,(2,3,20),a)

# Large lantern: luminous fluted core inside an open, sculpted cage.
lathe(('Lantern housing',0),[(39,269),(72,284),(87,296),(87,302),(64,308)],128)
lathe(('Lantern structure',1),[(35,301),(41,313),(36,323)],96)
lathe(('Beacon core',5),[(20,317),(28,330),(29,355),(23,380)],96)
for z,r in [(326,29),(340,30),(354,30),(368,27)]: ring(('Lantern structure',1),r,z,3,2)
for i in range(8):
    a=i*math.tau/8
    ps=[radial(r,a,z) for r,z in [(76,296),(83,318),(81,366),(65,391),(43,408)]]
    for p,q in zip(ps,ps[1:]): beam(('Lantern housing',0),p,q,4,8)
lathe(('Lantern housing',0),[(78,388),(79,395),(60,403),(36,420),(15,440),(3,450)],128)
ring(('Lantern structure',1),76,393,7,4)
ring(('Emitter ring',1),65,347,7,5)
ring(('Emitter glow',5),65,348,8,2)
for i in range(6):
    a=i*math.tau/6
    box(('Emitter ring',1),radial(65,a,347),(13,18,9),a)
    box(('Emitter glow',5),radial(72,a,347),(1,12,5),a)

# Generations of additions: partial decks preserve glimpses of the pale core.
module_sites=[]
for level,z in enumerate([-330,-244,-157,-73,14,94]):
    count=[5,6,5,6,4,3][level]
    for j in range(count):
        a=j*math.tau/count + level*.48
        r=rng.uniform(73,108) if level<4 else rng.uniform(58,84)
        length=rng.uniform(37,66); width=rng.uniform(24,39); height=rng.uniform(20,33)
        center=Vector(radial(r,a,z))
        idx=[2,3,0,3,2,0][(j+level)%6]
        key=('Clan homes',idx)
        tint=rng.uniform(.62,1.35)
        box(key,center,(length,width,height),a,tint)
        # Foundation, offset roof patch and thin welded plate borders.
        box(('Clan infrastructure',1),center+Vector((0,0,-height/2-2)),(length+7,width+8,3),a)
        box(('Clan patch plates',2),center+Vector((0,0,height/2+.6)),(length*.63,width*.52,1.2),a,rng.uniform(.7,1.4))
        for patch in range(3):
            offset=rng.uniform(-length*.34,length*.34)
            v=center+Vector((math.cos(a)*offset-math.sin(a)*(width/2+.65),math.sin(a)*offset+math.cos(a)*(width/2+.65),rng.uniform(-height*.2,height*.25)))
            box(('Clan patch plates',2),v,(rng.uniform(3,10),.7,rng.uniform(4,10)),a,rng.uniform(.55,1.1))
        end=radial(r+length/2+1,a,z)
        box(('Clan infrastructure',1),end,(2,width*.83,height*.8),a)
        # Windows on outward-facing end; additional side windows reveal life at oblique angles.
        for w in range(4):
            tangent=(w-1.5)*width*.17
            v=Vector(end)+Vector((-math.sin(a)*tangent,math.cos(a)*tangent,2))
            if rng.random()<.8: box(('Settlement windows',6),v,(2.5,3.4,4),a)
        for k in range(3):
            offset=(k-1)*length*.25
            v=center+Vector((math.cos(a)*offset-math.sin(a)*(width/2+.4),math.sin(a)*offset+math.cos(a)*(width/2+.4),2))
            box(('Settlement windows',6),v,(4,1.2,3.4),a)
        # Container corrugations and salvaged exterior stiffeners.
        for k in range(7):
            offset=(k-3)*length/8
            v=center+Vector((math.cos(a)*offset,math.sin(a)*offset,0))
            box(('Clan ribs',idx),v,(1,width+1,height+1),a,tint*.7)
        beam(('Clan infrastructure',1),radial(31,a,z-9),radial(r,a,z-9),3.5)
        beam(('Clan infrastructure',1),radial(36,a,z-40),radial(r,a,z-12),2)
        # External tank and exhaust stack, unrelated ages/sizes.
        side=a+.23
        beam(('Clan tanks',idx),radial(r,side,z+height/2+2),radial(r,side,z+height/2+14),5,12,tint*.8)
        module_sites.append((r,a,z))
    rr=67 if level<4 else 53
    ring(('Clan walkways',1),rr,z-18,10,2,96)
    for i in range(32):
        a=i*math.tau/32
        beam(('Clan infrastructure',1),radial(rr+5,a,z-17),radial(rr+5,a,z-11),.65,6)
        beam(('Clan infrastructure',1),radial(rr+5,a,z-11),radial(rr+5,a+math.tau/32,z-11),.55,6)
for i in range(0,len(module_sites)-6,5):
    r,a,z=module_sites[i]; r2,a2,z2=module_sites[i+6]
    cable(radial(r,a,z+18),radial(r2,a2,z2+18))

# Asymmetrical solar farms: interrupted rows, faded cell patches, welded repair strips.
for wing,(a,z,rows,cols) in enumerate([(.15,-192,3,7),(math.pi+.15,-116,3,6),(2.0,51,2,5)]):
    beam(('Solar frames',1),radial(39,a,z),radial(300 if wing<2 else 237,a,z),3,8)
    for j in range(cols):
        for k in range(rows):
            if (wing,j,k) in [(0,5,0),(1,1,2),(2,3,1)]: continue
            r=124+j*24; t=(k-(rows-1)/2)*35
            center=Vector(radial(r,a,z))+Vector((-math.sin(a)*t,math.cos(a)*t,0))
            box(('Solar frames',1),center,(23,34,2),a)
            box(('Solar cells',4),center+Vector((0,0,1.2)),(21,32,.6),a,rng.uniform(.7,1.6))
            for c in range(4):
                p=center+Vector((-math.sin(a)*(c-1.5)*8,math.cos(a)*(c-1.5)*8,1.7))
                box(('Solar grid',1),p,(21,.35,.25),a)
            if rng.random()<.15:
                box(('Solar repairs',2),center+Vector((0,0,2)),(3,34,.5),a)
    for r in [118,190,260 if wing<2 else 220]:
        beam(('Solar frames',1),radial(42,a,z-40),radial(r,a,z),1.6)
    box(('Navigation points',7),radial(294 if wing<2 else 238,a,z+3),(3,3,3))

# Three permanently docked old shuttle hulls converted into long houses.
for n,(a,z) in enumerate([(5.05,-265),(2.6,-51),(.9,-352)]):
    r=154
    # Radially oriented tapering hull, rectangular cross sections.
    vs=[]
    for rr,w,h in [(r-42,14,10),(r-31,21,16),(r+28,19,15),(r+52,6,6)]:
        for t,dz in [(-w,-h),(w,-h),(w,h),(-w,h)]:
            vs.append((rr*math.cos(a)-t*math.sin(a),rr*math.sin(a)+t*math.cos(a),z+dz))
    fs=[(3,2,1,0),(12,13,14,15)]
    for j in range(3):
        for k in range(4):fs.append((j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k))
    add(('Docked hull homes',3 if n!=1 else 0),vs,fs,.8)
    beam(('Clan infrastructure',1),radial(43,a,z),radial(r-35,a,z),6,12)
    beam(('Clan infrastructure',1),radial(43,a,z-43),radial(r,a,z-16),2.5)
    box(('Docked hull patches',2),radial(r,a,z+16),(38,25,1.2),a)
    for k in range(6):
        rr=r-25+k*10
        for side in [-1,1]:
            p=Vector(radial(rr,a,z+4))+Vector((-math.sin(a)*20*side,math.cos(a)*20*side,0))
            box(('Settlement windows',6),p,(4,2,4),a)
    # Dark sealed engine caps communicate permanent conversion, no exhaust or flying craft.
    for side in [-1,1]:
        p=Vector(radial(r-43,a,z))+Vector((-math.sin(a)*9*side,math.cos(a)*9*side,0))
        beam(('Clan infrastructure',1),p,p-Vector((math.cos(a)*6,math.sin(a)*6,0)),5,12)

# Three antenna masts, a few isolated red navigation points.
for a,z in [(1.1,120),(3.3,65),(5.3,-295)]:
    beam(('Clan infrastructure',1),radial(70,a,z),radial(70,a,z+47),1,8)
    beam(('Clan infrastructure',1),radial(61,a,z+34),radial(79,a,z+34),.8,6)
    box(('Navigation points',7),radial(70,a,z+48),(2.5,2.5,2.5))

root=bpy.data.objects.new('Lighthouse',None); collection.objects.link(root)
emitter=bpy.data.objects.new('EmitterRing_Pivot',None); collection.objects.link(emitter)
emitter.parent=root; emitter.location.z=347
objects=[]
for (name,mi),(vs,fs,cs) in batches.items():
    mesh=bpy.data.meshes.new('LH '+name)
    mesh.from_pydata(vs,[],fs); mesh.materials.append(materials[mi]); mesh.update()
    attr=mesh.color_attributes.new(name='Patina',type='FLOAT_COLOR',domain='POINT')
    for vertex,datum,color in zip(mesh.vertices,attr.data,cs):
        if name in ('Ancient tower','Lantern housing'):
            x,y,z=vertex.co
            a=math.atan2(y,x)
            patina=.80+.11*math.sin(a*17+math.sin(z*.011))+.07*math.sin(z*.16+a*5)+rng.uniform(-.045,.045)
            datum.color=tuple(v*patina for v in color[:3])+(1,)
        else: datum.color=color
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    obj=bpy.data.objects.new('LH '+name,mesh);collection.objects.link(obj)
    if name.startswith('Emitter'):
        obj.parent=emitter
        for v in mesh.vertices:v.co.z-=347
    else:
        obj.parent=root
        # Section origin at its bounds centre, with coordinates preserved in world space.
        lo=Vector(tuple(min(v.co[i] for v in mesh.vertices) for i in range(3)))
        hi=Vector(tuple(max(v.co[i] for v in mesh.vertices) for i in range(3)))
        centre=(lo+hi)/2
        for v in mesh.vertices:v.co-=centre
        obj.location=centre
    objects.append(obj)

# Batch all repeated components sharing a material within each major section.
groups={}
for obj in objects:
    if obj.parent==emitter: continue
    name=obj.name[3:]
    section=('Ancient tower' if name.startswith('Ancient') else
             'Lantern' if name.startswith('Lantern') else
             'Solar wings' if name.startswith('Solar') else
             'Converted hull homes' if name.startswith('Docked') else
             'Clan settlement' if name.startswith(('Clan','Settlement')) else name)
    groups.setdefault((section,obj.data.materials[0].name),[]).append(obj)
for (section,matname),parts in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:obj.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    if len(parts)>1:bpy.ops.object.join()
    obj=parts[0];obj.name='LH '+section+' | '+matname[3:]
    # Re-centre the joined section, retaining all vertex colours and world placement.
    lo=Vector(tuple(min(v.co[i] for v in obj.data.vertices) for i in range(3)))
    hi=Vector(tuple(max(v.co[i] for v in obj.data.vertices) for i in range(3)))
    centre=(lo+hi)/2
    for v in obj.data.vertices:v.co-=centre
    obj.location+=centre

# One rotating emitter mesh with two separately editable materials.
bpy.ops.object.select_all(action='DESELECT')
rotating=[o for o in collection.objects if o.parent==emitter]
for o in rotating:o.select_set(True)
bpy.context.view_layer.objects.active=rotating[0];bpy.ops.object.join();rotating[0].name='EmitterRing'
objects=[o for o in collection.objects if o.type=='MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in collection.objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/landmarks/lighthouse.glb'),export_format='GLB',
                         use_selection=True,use_active_scene=True,export_cameras=False,export_lights=False,export_yup=True)

# Presentation rig is not part of the selected-only export.
studio=bpy.data.collections.new('Lighthouse preview only');scene.collection.children.link(studio)
def aim(o,target=(0,0,0)):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('Lighthouse preview');cam=bpy.data.objects.new('Lighthouse preview',d);studio.objects.link(cam)
cam.location=(1250,-1850,900);aim(cam,(0,0,0));d.type='ORTHO';d.ortho_scale=1130;d.clip_end=10000;scene.camera=cam
for name,loc,power,size,color in [('Key',(400,-700,900),42000000,950,(.88,.94,1)),
    ('Rim',(-650,250,400),48000000,750,(.44,.67,1)),('Fill',(300,600,-120),27000000,800,(1,.73,.47))]:
    data=bpy.data.lights.new('LH '+name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    o=bpy.data.objects.new('LH '+name,data);studio.objects.link(o);o.location=loc;aim(o)
world=bpy.data.worlds.new('Lighthouse deep space');world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.012,.021,.034,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.3;scene.world=world
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1500;scene.render.resolution_y=1800;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'lighthouse_preview.png')
scene.view_settings.view_transform='AgX'
bpy.ops.object.select_all(action='DESELECT')
for o in studio.objects:o.hide_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active;space.clip_end=20000;space.region_3d.view_distance=1250
            space.region_3d.view_location=(0,0,0);space.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
            space.shading.color_type='MATERIAL';space.overlay.show_floor=False
            space.overlay.show_axis_x=False;space.overlay.show_axis_y=False
bpy.context.view_layer.update()
corners=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
dimensions=[max(v[i] for v in corners)-min(v[i] for v in corners) for i in range(3)]
stats={'meshes':len(objects),'materials':8,'material_surfaces':sum(len(o.data.materials) for o in objects),
       'vertices':sum(len(o.data.vertices) for o in objects),
       'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),
       'blender_dimensions_m':dimensions,'height_m':dimensions[2],'habitat_modules':len(module_sites),
       'converted_docked_hulls':3,'solar_wings':3,'emitter_pivot_blender_z_m':347}
(OUT/'counts.json').write_text(json.dumps(stats,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'lighthouse.blend'))
print(json.dumps(stats))
bpy.ops.render.render(write_still=True)
