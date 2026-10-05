"""Original Humming Gate geometry. Execute inside Blender; metres, no textures."""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector

ROOT = Path('D:/CodingProjects/spacegame')
OUT = ROOT / 'art/humming_gate'
OUT.mkdir(parents=True, exist_ok=True)
scene = bpy.data.scenes.new('Humming Gate')
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
asset = bpy.data.collections.new('Humming Gate | Export')
scene.collection.children.link(asset)

def material(name, color, metal=0.0, rough=.35, glow=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    if glow:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = glow
    return m

mats = [material('HG Pale ceramic alloy', (.72,.79,.82), .65,.28),
        material('HG Recessed titanium', (.065,.095,.12),.8,.32),
        material('HG Satin edge alloy', (.35,.46,.51),.8,.23),
        material('HG Warm precision inserts', (.40,.29,.16),.72,.3),
        material('HG Inner resonance emission', (.27,.8,1),.15,.25,3),
        material('HG Segment point emission', (.55,.9,1),.1,.25,2)]
batches = {}

def add(key, verts, faces):
    vs, fs = batches.setdefault(key, ([], []))
    offset = len(vs)
    vs.extend(verts)
    fs.extend([tuple(offset+i for i in face) for face in faces])

def sweep(key, profile, start=0, end=math.tau, steps=256):
    # Closed cross section swept about Blender Z; ring lives in XY.
    vs = [(r*math.cos(a), r*math.sin(a), z)
          for a in [start+(end-start)*i/steps for i in range(steps+1)]
          for r,z in profile]
    n = len(profile)
    fs = []
    for i in range(steps):
        for j in range(n):
            k = (j+1)%n
            fs.append((i*n+j,i*n+k,(i+1)*n+k,(i+1)*n+j))
    fs += [tuple(reversed(range(n))), tuple(steps*n+j for j in range(n))]
    add(key, vs, fs)

def rect(r0,r1,z0,z1,b=1):
    return [(r0+b,z0),(r1-b,z0),(r1,z0+b),(r1,z1-b),
            (r1-b,z1),(r0+b,z1),(r0,z1-b),(r0,z0+b)]

def blade(key, angle, sections):
    # sections = radial distance, tangential half-width, z centre, half-depth
    vs=[]
    for r,w,z,d in sections:
        for t,h in [(-w,-d),(w,-d),(w,d),(-w,d)]:
            vs.append((r*math.cos(angle)-t*math.sin(angle),
                       r*math.sin(angle)+t*math.cos(angle), z+h))
    fs=[(3,2,1,0)]
    for i in range(len(sections)-1):
        for j in range(4):
            fs.append((i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j))
    q=(len(sections)-1)*4
    fs.append((q,q+1,q+2,q+3))
    add(key,vs,fs)

# Continuous structural spine behind 48 precision shell segments.
sweep(('Main structure',1), rect(518,586,-32,32,5))
for i in range(48):
    a=math.tau*i/48
    lo=a+.0017
    hi=a+math.tau/48-.0017
    sweep(('Main pale shell',0), rect(512,600,-40,40,8),lo,hi,12)
    # Inset face tracks and fine triple service panels on both faces.
    for side in [-1,1]:
        z=side*40
        sweep(('Main face inlays',2),rect(542,547,z-.5,z+.5,.2),lo+.005,hi-.005,10)
        sweep(('Main warm inserts',3),rect(581,584,z-.6,z+.6,.2),lo+.016,hi-.016,10)
        for j in range(3):
            p=a+.029+j*.027
            sweep(('Main recessed panels',1),rect(556,574,z-.7,z+.7,.3),p,p+.017,3)
            sweep(('Main segment lights',5),rect(520,524,z-.9,z+.9,.3),p,p+.008,3)
# Thin continuous lips make the finely divided shell read as one immaculate machine.
for z in [-33,33]:
    sweep(('Main face inlays',2),rect(597,601,z-2,z+2,.6))
sweep(('Main bore inlays',2),rect(511,514,-24,24,1))

# Six outward crown pylons, forked at their roots, integrated into the main shell.
for i in range(6):
    a=math.tau*i/6+math.pi/6
    blade(('Crown structure',1),a,[(570,25,0,25),(645,21,0,20),(765,3,0,5)])
    for sign in [-1,1]:
        blade(('Crown pale shell',0),a+sign*.023,
              [(580,10,sign*19,16),(641,14,sign*15,13),(733,6,sign*8,7),(773,1,sign*3,2)])
    blade(('Crown inlays',2),a,[(606,6,25,2),(651,7,21,2),(751,1,8,1)])
    blade(('Crown points',5),a,[(629,2,24,1),(660,2,20,1),(704,1,14,1)])
    # Radial bridges hold the inset halo clear of the main ring.
    blade(('Halo support bridges',2),a,[(479,6,30,7),(501,9,15,10),(526,13,0,14)])

# Independently pivoted halo, 26 m in front of the main ring.
sweep(('InnerRing alloy',0),rect(462,483,21,39,3),steps=384)
sweep(('InnerRing trim',2),rect(480,484,25,35,1),steps=384)
sweep(('InnerRing glow',4),rect(459.5,463,24,36,1),steps=384)
for i in range(96):
    a=math.tau*i/96
    sweep(('InnerRing trim',2),rect(465,479,38.9,39.4,.1),a,a+.0017,1)

root=bpy.data.objects.new('HummingGate',None)
asset.objects.link(root)
halo=bpy.data.objects.new('InnerRing_Pivot',None)
asset.objects.link(halo)
halo.parent=root
halo.location.z=30
objects=[]
for (name,mi),(vs,fs) in batches.items():
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vs,[],fs)
    mesh.materials.append(mats[mi])
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    asset.objects.link(obj)
    obj.parent=halo if name.startswith('InnerRing') else root
    if obj.parent==halo:
        for v in mesh.vertices: v.co.z-=30
    # Recalculate normals for export, preserving crisp panel edges.
    import bmesh
    bm=bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free()
    objects.append(obj)

# Inner ring is one mesh with three material surfaces; rotate its parent pivot.
bpy.ops.object.select_all(action='DESELECT')
inner=[o for o in objects if o.name.startswith('InnerRing')]
for o in inner: o.select_set(True)
bpy.context.view_layer.objects.active=inner[0]
bpy.ops.object.join()
inner[0].name='InnerRing'
objects=[o for o in asset.objects if o.type=='MESH']

# Selected-only GLB never includes the presentation camera or lights.
bpy.ops.object.select_all(action='DESELECT')
for o in asset.objects: o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
glb=ROOT/'assets/landmarks/humming_gate.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,
                         export_cameras=False,export_lights=False,export_yup=True)

studio=bpy.data.collections.new('Preview only | Not exported')
scene.collection.children.link(studio)
def point_at(o): o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new('Preview camera')
cam=bpy.data.objects.new('Preview camera',camdata); studio.objects.link(cam)
cam.location=(850,-1250,2350); point_at(cam)
camdata.type='ORTHO'; camdata.ortho_scale=1900; camdata.clip_end=10000
scene.camera=cam
for name,loc,power,size,color in [
    ('Large soft key',(200,-500,1300),160000000,1500,(.82,.91,1)),
    ('Warm rim',(-1100,200,400),110000000,1100,(1,.78,.52)),
    ('Cool fill',(800,900,-200),140000000,1000,(.35,.65,1))]:
    d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.shape='DISK'; d.size=size; d.color=color
    o=bpy.data.objects.new(name,d); studio.objects.link(o); o.location=loc; point_at(o)
world=bpy.data.worlds.new('Deep space preview'); world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.008,.015,.025,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.25
scene.world=world
scene.render.engine='CYCLES'; scene.cycles.samples=32
scene.render.resolution_x=1600; scene.render.resolution_y=1400; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(OUT/'humming_gate_preview.png')
scene.view_settings.view_transform='AgX'
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.clip_end=20000
            area.spaces.active.region_3d.view_distance=1900
            area.spaces.active.region_3d.view_location=(0,0,0)
            area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
            area.spaces.active.shading.color_type='MATERIAL'
            area.spaces.active.overlay.show_floor=False
            area.spaces.active.overlay.show_axis_x=False
            area.spaces.active.overlay.show_axis_y=False
stats={'meshes':len(objects),'materials':len(mats),
       'vertices':sum(len(o.data.vertices) for o in objects),
       'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),
       'main_ring_diameter_m':1202,'crown_tip_diameter_m':1546,'clear_aperture_m':919,
       'depth_m':80,'inner_ring_offset_m':30}
(OUT/'counts.json').write_text(json.dumps(stats,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'humming_gate.blend'))
print(json.dumps(stats))
bpy.ops.render.render(write_still=True)
