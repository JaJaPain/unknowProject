"""Original signal anomaly set piece. Execute inside Blender via blender_rpc.py."""
import bpy,bmesh,math,random,json
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/CodingProjects/spacegame');OUT=ROOT/'art/signal_anomaly';OUT.mkdir(parents=True,exist_ok=True)
rng=random.Random(8150)
scene=bpy.data.scenes.new('A Signal Anomaly Site');bpy.context.window.scene=scene
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
collection=bpy.data.collections.new('Signal Anomaly | Export');scene.collection.children.link(collection)
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
colors=[(.009,.015,.023),(.048,.060,.070),(.12,.52,.72),(.16,.45,.62)]
materials=[material('SA Almost black shard',colors[0],.68,.25),material('SA Groove dust',colors[1],.15,.85),material('SA Cold seam emission',colors[2],.1,.35,1.8),material('SA Central faint glow',colors[3],0,.5,.6)]
glow=materials[3];p=glow.node_tree.nodes.get('Principled BSDF');p.inputs['Alpha'].default_value=.16
if hasattr(glow,'surface_render_method'):glow.surface_render_method='DITHERED'
glow.diffuse_color=(*colors[3],.16);glow.use_backface_culling=False

# Asymmetrical six-sided tapered blades, varied heights, off-axis growth and unequal spacing.
profiles=[(-.5,.03),(-.37,.63),(.17,1),(.39,.50),(.5,.015)]
def shard(key,centre,height,width,angle,lean,etched=False):
    cross=[(1,.25),(.35,1),(-.7,.7),(-1,-.2),(-.25,-1),(.8,-.62)]
    rings=[]
    for t,r in profiles:
        twist=angle+.09*t
        points=[]
        for x,y in cross:
            xx=x*width*r;yy=y*width*.61*r
            points.append(Vector((centre[0]+xx*math.cos(twist)-yy*math.sin(twist)+lean[0]*t,
                                  centre[1]+xx*math.sin(twist)+yy*math.cos(twist)+lean[1]*t,
                                  centre[2]+t*height)))
        rings.append(points)
    verts=[tuple(v) for ring in rings for v in ring];faces=[]
    for j in range(4):
        for i in range(6):faces.append((j*6+i,j*6+(i+1)%6,(j+1)*6+(i+1)%6,(j+1)*6+i))
    faces += [tuple(reversed(range(6))),tuple(24+i for i in range(6))]
    add(key,verts,faces)
    if not etched:return
    # Fine longitudinal inlays follow the actual facets. Uneven ends avoid glyph patterns.
    for face_index in [0,2,4]:
        for fraction in [.29,.68]:
            for j in range(1,4):
                if j==3 and fraction>.5:continue
                a=rings[j][face_index];b=rings[j][(face_index+1)%6]
                c=rings[j+1][face_index];d=rings[j+1][(face_index+1)%6]
                edge=(b-a).normalized();normal=edge.cross(c-a).normalized()
                u=a.lerp(b,fraction);v=c.lerp(d,fraction)
                mid=(u+v)/2
                if normal.dot(Vector((mid.x-centre[0],mid.y-centre[1],0)))<0:normal=-normal
                # Dust settles beside a thin emission strip, with no floating broad tubes.
                def strip(name,mi,w,offset):
                    vs=[u-edge*w/2+normal*offset,u+edge*w/2+normal*offset,v+edge*w/2+normal*offset,v-edge*w/2+normal*offset]
                    add((name,mi),[tuple(p) for p in vs],[(0,1,2,3)])
                strip('Etched groove margins',1,.27,.025)
                if fraction<.5 and face_index!=2:strip('Cold longitudinal seams',2,.085,.045)
    # Short, unlit parallel scars on the widest facet, like settled dust in hairline cuts.
    j=1;idx=3
    for f in [.43,.49,.56]:
        a=rings[j][idx].lerp(rings[j][idx+1],f);b=rings[j+1][idx].lerp(rings[j+1][idx+1],f)
        u=a.lerp(b,.38);v=a.lerp(b,.66);side=(rings[j][idx+1]-rings[j][idx]).normalized()
        normal=side.cross(b-a).normalized()
        add(('Etched groove margins',1),[tuple(u-side*.055+normal*.02),tuple(u+side*.055+normal*.02),tuple(v+side*.055+normal*.02),tuple(v-side*.055+normal*.02)],[(0,1,2,3)])

for i,(a,r,h,w,z) in enumerate([(0.10,43,130,7,-3),(.89,48,94,6,12),(1.88,39,117,8,-7),(2.70,51,83,5.4,8),(3.58,42,143,8.2,0),(4.49,47,102,6.3,-12),(5.51,38,121,7.1,7)]):
    centre=(r*math.cos(a),r*math.sin(a),z)
    shard(('Primary shard cluster',0),centre,h,w,a+.42,(-12*math.cos(a)+4,-12*math.sin(a)-3),True)
# Separate floating fragments, related in shape but not regularly arranged.
for i,(p,h,w,a) in enumerate([((63,-25,33),22,3.5,.2),((-55,-37,-31),16,2.6,1.8),((5,61,53),25,3.1,3.2)]):
    shard(('LooseShard_%02d'%(i+1),0),p,h,w,a,(8,-5),False)
# A small translucent faceted glimmer leaves the centre predominantly empty.
vs=[];steps=20
for j in range(1,10):
    t=math.pi*j/10
    for i in range(steps):
        a=i*math.tau/steps;vs.append((3.4*math.sin(t)*math.cos(a),3.4*math.sin(t)*math.sin(a),5.5*math.cos(t)))
vs.extend([(0,0,5.5),(0,0,-5.5)]);fs=[]
for j in range(8):
    for i in range(steps):fs.append((j*steps+i,j*steps+(i+1)%steps,(j+1)*steps+(i+1)%steps,(j+1)*steps+i))
for i in range(steps):fs.extend([(180,(i+1)%steps,i),(181,160+i,160+(i+1)%steps)])
add(('CentreGlow',3),vs,fs)
allverts=[v for vs,fs,cs in batches.values() for v in vs]
lo=Vector(tuple(min(v[i] for v in allverts) for i in range(3)));hi=Vector(tuple(max(v[i] for v in allverts) for i in range(3)));scale=150/max(hi-lo)
root=bpy.data.objects.new('SignalAnomaly',None);collection.objects.link(root)
objects=[]
for (name,mi),(vs,fs,cs) in batches.items():
    verts=[Vector(v)*scale for v in vs]
    low=Vector(tuple(min(v[i] for v in verts) for i in range(3)));high=Vector(tuple(max(v[i] for v in verts) for i in range(3)));pivot=(low+high)/2
    if name=='CentreGlow':pivot=Vector((0,0,0))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([v-pivot for v in verts],[],fs);mesh.materials.append(materials[mi]);mesh.update()
    attr=mesh.color_attributes.new(name='Patina',type='FLOAT_COLOR',domain='POINT')
    for datum,color in zip(attr.data,cs):datum.color=color
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    obj=bpy.data.objects.new(name,mesh);collection.objects.link(obj);obj.parent=root;obj.location=pivot;objects.append(obj)
bpy.ops.object.select_all(action='DESELECT')
for o in collection.objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/landmarks/signal_anomaly.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_cameras=False,export_lights=False,export_yup=True)
studio=bpy.data.collections.new('Anomaly preview only');scene.collection.children.link(studio)
def aim(o):o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('Anomaly overview');cam=bpy.data.objects.new('Anomaly overview',d);studio.objects.link(cam);cam.location=(215,-305,165);aim(cam);d.type='ORTHO';d.ortho_scale=220;d.clip_end=10000;scene.camera=cam
for name,loc,power,size,color in [('Key',(-120,-150,240),530000,200,(.72,.85,1)),('Rim',(90,150,120),700000,140,(.3,.6,1)),('Fill',(150,-60,40),220000,170,(.8,.88,1))]:
    data=bpy.data.lights.new('SA '+name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    o=bpy.data.objects.new('SA '+name,data);studio.objects.link(o);o.location=loc;aim(o)
world=bpy.data.worlds.new('Anomaly empty space');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.006,.011,.02,1);world.node_tree.nodes['Background'].inputs[1].default_value=.2;scene.world=world
scene.render.engine='CYCLES';scene.cycles.samples=64;scene.cycles.use_denoising=True;scene.cycles.transparent_max_bounces=12
scene.render.resolution_x=1500;scene.render.resolution_y=1700;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'signal_anomaly_preview.png');scene.view_settings.view_transform='AgX'
bpy.ops.object.select_all(action='DESELECT')
for o in studio.objects:o.hide_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            s=area.spaces.active;s.clip_end=10000;s.region_3d.view_distance=220;s.region_3d.view_location=(0,0,0);s.region_3d.view_rotation=cam.rotation_euler.to_quaternion();s.shading.color_type='MATERIAL';s.overlay.show_floor=False;s.overlay.show_axis_x=False;s.overlay.show_axis_y=False
stats={'meshes':len(objects),'materials':4,'material_surfaces':len(objects),'vertices':sum(len(o.data.vertices) for o in objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),'blender_dimensions_m':list((hi-lo)*scale),'main_shards':7,'separate_loose_shards':3,'independent_centre_glow':True}
(OUT/'counts.json').write_text(json.dumps(stats,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'signal_anomaly.blend'));print(json.dumps(stats));bpy.ops.render.render(write_still=True)
