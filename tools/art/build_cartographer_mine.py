"""Cartographer's secret mine: original Blender set piece, metres."""
import bpy
import bmesh
import math
import random
import json
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/CodingProjects/spacegame')
OUT=ROOT/'art/cartographer_mine'
OUT.mkdir(parents=True,exist_ok=True)
rng=random.Random(41500)
scene=bpy.data.scenes.new('The Cartographers Secret Mine')
bpy.context.window.scene=scene
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
collection=bpy.data.collections.new('Cartographer Mine | Export');scene.collection.children.link(collection)
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

colors=[(.095,.083,.068),(.25,.235,.20),(.055,.069,.08),(.28,.34,.36),(.27,.24,.13),(.035,.038,.04),(.66,.82,1),(.8,.37,.09)]
materials=[material('CM Dark asteroid rock',colors[0],.08,.94),material('CM Fresh cut rock and dust',colors[1],.12,.87),
 material('CM Structural graphite',colors[2],.7,.48),material('CM Corporate alloy',colors[3],.65,.38),
 material('CM Mineral flecks',colors[4],.8,.32),material('CM Conveyor rubber',colors[5],.05,.8),
 material('CM Cold worklights',colors[6],.1,.3,2),material('CM Habitat amber',colors[7],.1,.4,1.5)]
N=144;ROWS=64;opening=.67
craters=[(1.13,2.0,.24,.10),(1.40,4.3,.28,.15),(1.0,5.6,.16,.07),(1.8,.5,.32,.11),(2.1,3.3,.27,.12)]
def rockpoint(theta,a):
    u=Vector((math.sin(theta)*math.cos(a),math.sin(theta)*math.sin(a),math.cos(theta)))
    n=1+.075*math.sin(a*3+theta*4)+.04*math.sin(a*7-theta*9)+.018*math.sin(a*19+theta*23)
    for t,p,width,depth in craters:
        v=Vector((math.sin(t)*math.cos(p),math.sin(t)*math.sin(p),math.cos(t)))
        distance=(u-v).length
        n-=depth*math.exp(-(distance/width)**4)
        n+=.025*math.exp(-((distance-width)/(.19*width))**2)
    return Vector((750*u.x*n,610*u.y*n,510*u.z*n))
# Rough exterior wraps around an actual uncapped opening; no rock sphere fills the pit.
vs=[]
for j in range(ROWS):
    t=opening+(math.pi-opening-.035)*j/(ROWS-1)
    for i in range(N):
        a=math.tau*i/N;p=rockpoint(t,a)
        if j>0:p+=Vector((rng.uniform(-5,5),rng.uniform(-5,5),rng.uniform(-5,5)))
        vs.append(tuple(p))
vs.append((0,0,-510));fs=[]
for j in range(ROWS-1):
    for i in range(N):
        a=j*N+i;b=j*N+(i+1)%N;c=(j+1)*N+(i+1)%N;d=(j+1)*N+i
        fs.extend([(a,b,d),(b,c,d)] if (i+j)%2 else [(a,b,c),(a,c,d)])
for i in range(N):fs.append(((ROWS-1)*N+i,(ROWS-1)*N+(i+1)%N,len(vs)-1))
add(('Asteroid exterior',0),vs,fs)
# Keep asteroid's maximum horizontal span at 1500 m before placing the infrastructure.
lo=min(v[0] for v in vs);hi=max(v[0] for v in vs);rockscale=1500/(hi-lo)
rockcenter=(lo+hi)/2
vs0,_,_=batches[('Asteroid exterior',0)]
for i,v in enumerate(vs0):vs0[i]=((v[0]-rockcenter)*rockscale,v[1]*rockscale,v[2]*rockscale)
def rim(a):
    p=rockpoint(opening,a)
    return Vector(((p.x-rockcenter)*rockscale,p.y*rockscale,p.z*rockscale))
# Seven irregular terraces: horizontal bench, near-vertical freshly exposed riser.
profiles=[(1,None),(.96,365),(.84,365),(.82,280),(.69,280),(.67,190),(.54,190),(.52,100),(.39,100),(.37,10),(.24,10),(.22,-80),(.09,-80),(.07,-142)]
pitvs=[]
for fraction,z in profiles:
    for i in range(N):
        a=i*math.tau/N;edge=rim(a)
        if z is None:p=edge
        else:
            p=Vector((edge.x*fraction,edge.y*fraction,z+2*math.sin(a*7)))
        pitvs.append(tuple(p))
pitfs=[]
for j in range(len(profiles)-1):
    for i in range(N):pitfs.append((j*N+i,j*N+(i+1)%N,(j+1)*N+(i+1)%N,(j+1)*N+i))
pitvs.append((0,0,-144))
for i in range(N):pitfs.append(((len(profiles)-1)*N+i,(len(profiles)-1)*N+(i+1)%N,len(pitvs)-1))
add(('Terraced excavation',1),pitvs,pitfs)
# Thin mineral seams sit on exposed risers, restrained metallic glints with no emission.
for band in [2,4,6,8,10]:
    f,z=profiles[band+1]
    for i in range(13,119,4):
        a=i*math.tau/N;b=(i+2)*math.tau/N
        p=rim(a)*f;q=rim(b)*f
        beam(('Mineral seams',4),(p.x,p.y,z+32),(q.x,q.y,z+30),.9,5,rng.uniform(.55,.9))
# Deep extraction head, anchored at the pit floor.
box(('Pit machinery',2),(0,0,-128),(62,38,23))
box(('Pit machinery',3),(0,0,-112),(40,29,10))
for y in [-15,15]:beam(('Pit machinery',2),(-18,y,-122),(30,y,-80),3.5,10)
beam(('Pit machinery',3),(30,-21,-80),(30,21,-80),12,20)
for y in range(-18,19,6):beam(('Pit machinery',2),(30,y,-94),(30,y,-68),2,8)
# Twin enclosed bucket conveyors climb the cut to the rim refinery.
for yoffset in [-30,30]:
    p=Vector((18,yoffset,-90));q=Vector((485,-125+yoffset,420))
    axis=(q-p).normalized();side=axis.cross(Vector((0,0,1))).normalized();up=side.cross(axis)
    def route(t):return p.lerp(q,t)+Vector((0,0,95*math.sin(math.pi*t)))
    for sign in [-1,1]:
        for j in range(24):
            a,b=route(j/24),route((j+1)/24)
            beam(('Conveyor structure',2),a+side*sign*12,b+side*sign*12,2.8,8)
            beam(('Conveyor structure',2),a+side*sign*12-up*14,b+side*sign*12-up*14,2.5,8)
    # Belt is a separate single-material mesh for material scrolling in game.
    verts=[tuple(route(j/24)+side*sign*9) for j in range(25) for sign in [-1,1]]
    add(('Conveyor belts',5),verts,[(2*j,2*j+1,2*j+3,2*j+2) for j in range(24)])
    for j in range(25):
        t=j/24;c=route(t)
        beam(('Conveyor structure',2),c-side*13,c+side*13,1.5,6)
        for sign in [-1,1]:beam(('Conveyor structure',2),c+side*sign*12,c+side*sign*12-up*14,1.2,6)
        if j%3==0:
            beam(('Worklight fixtures',2),c+side*15,c+side*15+Vector((0,0,10)),.7,6)
            box(('Cold worklights',6),c+side*15+Vector((0,0,10)),(4,3,1))
        if j%2==0:beam(('Ore buckets',3),c-side*8+up*3,c+side*8+up*3,2.4,6,.6)
# Standardised refinery block on rock-anchored pylons, with dust near processing.
for x in [445,555,660]:
    for y in [-170,10]:beam(('Refinery structure',2),(x,y,220),(x,y,417),5,10)
box(('Refinery structure',2),(545,-78,416),(268,220,12))
for x,y,sx,sy,sz in [(490,-75,90,135,65),(603,-85,106,145,93),(670,23,55,70,48)]:
    box(('Refinery plating',3),(x,y,426+sz/2),(sx,sy,sz))
    box(('Refinery structure',2),(x,y,428+sz),(sx+3,sy+3,4))
    for k in range(5):box(('Refinery structure',2),(x+(k-2)*sx/5,y,427+sz),(1,sy,2))
    for k in range(4):box(('Refinery plating',1),(x+sx/2+.5,y+(k-1.5)*sy/5,443),(1,sy*.16,14),0,.6)
# Tanks and pipe manifolds use a uniform corporate finish.
for x,y in [(490,90),(558,110),(626,115),(686,110)]:
    beam(('Storage tanks',3),(x,y,345),(x,y,449),23,24)
    for z in [358,395,441]:beam(('Storage tanks',2),(x,y,z-2),(x,y,z+2),24,24)
    beam(('Refinery structure',2),(x,y,359),(x,-12,359),4,10)
# Two loading cranes on the rim and dock: structural trusses, hanging grabs, no weapon shapes.
for base,ang in [((480,-224,411),-.65),((809,0,385),.25)]:
    x,y,z=base;c,s=math.cos(ang),math.sin(ang)
    tip=Vector((x+126*c,y+126*s,z+96));top=Vector((x,y,z+111))
    box(('Loading cranes',3),(x,y,z),(25,25,12))
    for dx in [-8,8]:
        for dy in [-8,8]:beam(('Loading cranes',2),(x+dx,y+dy,z),(x+dx*.5,y+dy*.5,z+112),2,8)
    beam(('Loading cranes',3),top,tip,5,8)
    beam(('Loading cranes',2),top+Vector((0,0,24)),tip,1.7,6)
    beam(('Loading cranes',2),top-Vector((c*29,s*29,-6)),top+Vector((c*12,s*12,17)),3,8)
    box(('Loading cranes',3),(x-24*c,y-24*s,z+109),(26,24,17))
    beam(('Loading cranes',2),tip,tip-Vector((0,0,69)),.9,6)
    box(('Loading cranes',3),tip-Vector((0,0,70)),(21,16,10))
# Small crew habitat is deliberately sunk into the far shoulder of the rock.
box(('Buried habitat',3),(-550,125,280),(112,62,54),-.15)
box(('Buried habitat',2),(-550,125,308),(116,65,3),-.15)
for k in range(7):box(('Habitat windows',7),(-590+k*13,92,294),(4,1.5,3),-.15)
# Covered utility passage follows the rim to the refinery.
for p,q in [((-490,125,278),(-430,330,315)),((-430,330,315),(80,415,315)),((80,415,315),(450,180,335))]:
    beam(('Utility network',2),p,q,7,10)
# In-pit mast lights are sparse and separate from their dark fixtures.
for radius,z in [(.9,365),(.74,280),(.58,190),(.43,100),(.28,10)]:
    for a in [.5,2.3,3.6,5.0]:
        edge=rim(a);x,y=edge.x*radius,edge.y*radius
        beam(('Worklight fixtures',2),(x,y,z),(x,y,z+17),1,8)
        box(('Cold worklights',6),(x,y,z+17),(5,3,1.4),a)
# Docking arm projects from the refinery. All three ore ships are physically moored.
beam(('Docking arm',2),(640,-25,385),(1130,-25,385),12,8)
for x in range(700,1131,70):
    beam(('Docking arm',2),(x,-38,385),(x,-38,355),2,8)
    beam(('Docking arm',2),(x, -12,385),(x,-12,355),2,8)
    if x<1080:beam(('Docking arm',2),(x,-38,355),(x+70,-38,385),2,8)
for i,(x,y,L) in enumerate([(845,-145,185),(1060,100,220),(1110,-173,165)]):
    sect='Moored hauler %d'%(i+1)
    # Ship longitudinal X, with a shallow wedge bow and ribbed ore hoppers.
    stations=[(-L*.5,25,14),(-L*.4,34,22),(L*.3,34,22),(L*.5,12,10)]
    vv=[]
    for xx,w,h in stations:
        vv.extend((x+xx,y+yy,385+zz) for yy,zz in [(-w,-h),(w,-h),(w,h),(-w,h)])
    ff=[(3,2,1,0),(12,13,14,15)]
    for j in range(3):
        for k in range(4):ff.append((j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k))
    add((sect,3),vv,ff,.8)
    for k in range(4):
        xx=x-L*.28+k*L*.16
        box((sect,2),(xx,y,415),(L*.14,55,21))
        box((sect,3),(xx,y,427),(L*.14-3,51,3),0,.72)
    for side in [-1,1]:beam((sect,2),(x-L*.51,y+side*15,385),(x-L*.44,y+side*15,385),8,12)
    beam(('Docking arm',3),(x,-25,385),(x,y,385),5.5,10)
    box(('Docking arm',2),(x,y+(32 if y<0 else -32),385),(19,9,20))
# Fine dust / stone colour variation survives glTF as vertex colours.
root=bpy.data.objects.new('CartographerMine',None);collection.objects.link(root)
objects=[]
for (name,mi),(vs,fs,cs) in batches.items():
    low=Vector(tuple(min(v[i] for v in vs) for i in range(3)));high=Vector(tuple(max(v[i] for v in vs) for i in range(3)))
    pivot=(low+high)/2
    mesh=bpy.data.meshes.new(name);mesh.from_pydata([Vector(v)-pivot for v in vs],[],fs);mesh.materials.append(materials[mi]);mesh.update()
    attr=mesh.color_attributes.new(name='Patina',type='FLOAT_COLOR',domain='POINT')
    for v,datum,color in zip(vs,attr.data,cs):
        if mi in [0,1]:
            xx,yy,zz=v;factor=.83+.14*math.sin(xx*.025+zz*.04)+.10*math.sin(yy*.039-zz*.03)+rng.uniform(-.11,.11)
            datum.color=tuple(max(.005,c*factor) for c in color[:3])+(1,)
        else:datum.color=color
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    if name=='Conveyor belts':
        uv=mesh.uv_layers.new(name='BeltUV')
        for loop in mesh.loops:
            i=loop.vertex_index%50
            uv.data[loop.index].uv=(i%2,(i//2)/24)
    obj=bpy.data.objects.new(name+' | '+materials[mi].name[3:],mesh);collection.objects.link(obj);obj.parent=root;obj.location=pivot;objects.append(obj)
bpy.ops.object.select_all(action='DESELECT')
for o in collection.objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/landmarks/cartographer_mine.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_cameras=False,export_lights=False,export_yup=True)
# Only the Blender presentation rig supplies illumination; GLB contains emission surfaces only.
studio=bpy.data.collections.new('Mine preview only');scene.collection.children.link(studio)
def aim(o,target=(150,0,50)):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
d=bpy.data.cameras.new('Mine overview');cam=bpy.data.objects.new('Mine overview',d);studio.objects.link(cam)
cam.location=(1600,-2400,3100);aim(cam);d.type='ORTHO';d.ortho_scale=2540;d.clip_end=20000;scene.camera=cam
for name,loc,power,size,color in [('Key',(-400,-800,2000),100000000,1300,(.85,.91,1)),('Rim',(-1300,1000,500),95000000,1000,(1,.79,.55)),('Fill',(1600,700,1200),55000000,1500,(.6,.75,1))]:
    data=bpy.data.lights.new('CM '+name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    o=bpy.data.objects.new('CM '+name,data);studio.objects.link(o);o.location=loc;aim(o)
world=bpy.data.worlds.new('Mine hidden space');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.009,.014,.022,1);world.node_tree.nodes['Background'].inputs[1].default_value=.2;scene.world=world
scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.render.resolution_x=1800;scene.render.resolution_y=1500;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(OUT/'cartographer_mine_preview.png');scene.view_settings.view_transform='AgX'
bpy.ops.object.select_all(action='DESELECT')
for o in studio.objects:o.hide_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            s=area.spaces.active;s.clip_end=20000;s.region_3d.view_distance=2400;s.region_3d.view_location=(150,0,50);s.region_3d.view_rotation=cam.rotation_euler.to_quaternion();s.shading.color_type='MATERIAL';s.overlay.show_floor=False;s.overlay.show_axis_x=False;s.overlay.show_axis_y=False
bpy.context.view_layer.update()
points=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box]
dims=[max(v[i] for v in points)-min(v[i] for v in points) for i in range(3)]
stats={'meshes':len(objects),'materials':8,'material_surfaces':sum(len(o.data.materials) for o in objects),'vertices':sum(len(o.data.vertices) for o in objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects),'asteroid_width_m':1500,'blender_dimensions_m':dims,'pit_bench_levels':7,'pit_floor_blender_z_m':-144,'moored_haulers':3,'loading_cranes':2,'storage_tanks':4}
(OUT/'counts.json').write_text(json.dumps(stats,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'cartographer_mine.blend'));print(json.dumps(stats))
bpy.ops.render.render(write_still=True)
