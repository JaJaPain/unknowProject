"""Brief 7b detail pass, executed in the main builder's geometry namespace."""
def shaped(key,stations):
 cross=[(-1,-.55),(-.72,-1),(.72,-1),(1,-.55),(1,.55),(.72,1),(-.72,1),(-1,.55)]
 vs=[(x,y*w,z0+z*h) for x,w,h,z0 in stations for y,z in cross]
 fs=[tuple(reversed(range(8))),tuple((len(stations)-1)*8+i for i in range(8))]
 for j in range(len(stations)-1):
  for k in range(8):fs.append((j*8+k,j*8+(k+1)%8,(j+1)*8+(k+1)%8,(j+1)*8+k))
 add(key,vs,fs)

def axial_ring(key,x,y,z,profile,steps=20,tilt=0):
 vs=[(x+dx,y+r*math.cos(i*math.tau/steps),z+r*math.sin(i*math.tau/steps)+tilt*dx) for dx,r in profile for i in range(steps)]
 fs=[]
 for j in range(len(profile)-1):
  for i in range(steps):fs.append((j*steps+i,j*steps+(i+1)%steps,(j+1)*steps+(i+1)%steps,(j+1)*steps+i))
 add(key,vs,fs)

def cable(points,key=('Interior frames',2),r=.22):
 for a,b in zip(points,points[1:]):beam(key,a,b,r,6)

# Raised, stepped dorsal keel and chamfered machinery fairings.
shaped(('Outer hull',0),[(-115,8,2,21),(-98,12,5,27),(-68,12,5,29),(61,10,5,29),(83,8,3,25)])
for x in [-93,-60,-27,7,41,69]:
 box(('Hull detailing',2),(x,0,34),(1.1,20,1))
 box(('Hull accent',1),(x+4,0,34),(5,16,.6))
for x in [-91,-54,-13,26,63]:
 # Offset roof plates and inset channels on the intact starboard roof.
 box(('Outer hull',0),(x,17,25.3),(27,11,1.8))
 box(('Hull detailing',2),(x+14,17,25.5),(.8,12,.5))
 for xx in [-9,9]:box(('Hull detailing',3),(x+xx,17,26.4),(1,8,.7))
# Ribbing traces the roof and intact side, stopping at the torn shoulder.
for x in [-83,-57,-28,4,36,66]:
 points=[(x,-18,26),(x,21,26),(x,35,13),(x,35,-13),(x,23,-25)]
 for a,b in zip(points,points[1:]):beam(('Hull detailing',0),a,b,1.25,6)
 for y,z in [(21,26),(35,12)]:box(('Hull detailing',1),(x,y,z),(4,3,3))
# Layered, tapering bow cheeks; no new crest or faction-specific silhouette.
for side in [-1,1]:
 pts=[(81,side*29,3),(110,side*24,1),(142,side*10,-3),(132,side*15,-11),(94,side*28,-11)]
 beam(('Hull detailing',2),(86,side*28,5),(121,side*20,1),.7,6)
 box(('Hull detailing',1),(112,side*22,0),(14,1.5,4))
shaped(('Outer hull',0),[(121,13,1,16),(133,10,2,13),(143,6,2,11),(148,2,1,8)])
# Integrated bridge: splayed base, chamfered rear, sloped forward glazing.
shaped(('Bridge',0),[(78,10,2,23),(84,18,9,29),(106,18,10,30),(124,13,5,25),(130,8,2,21)])
# Raised window band along both shoulders and the raked front face.
for side in [-1,1]:
 for x in [88,95,102,109]:
  z=34 if x<106 else 32
  box(('Bridge windows',2),(x,side*17.9,z),(5.4,.7,4))
 front=[(114,-10,36),(114,10,36),(122,8,31.5),(122,-8,31.5)]
add(('Bridge windows',2),front,[(0,1,2,3)])
for y in [-6,0,6]:beam(('Bridge',0),(114,y,36.2),(122,y*.8,31.7),.5,6)
shaped(('Bridge',1),[(82,12,1,39),(86,18,1.2,41),(106,18,1.2,41),(112,13,1,37)])
# Small sensor dish and aerials above the bridge, plus an aft comms mast.
beam(('Hull detailing',3),(90,0,42),(90,0,54),.6,8)
# Dish faces obliquely forward; shallow concentric octagonal surface.
vs=[]
for r,x in [(0,91),(2,90.5),(5,88.5)]:
 for i in range(12):
  a=i*math.tau/12;vs.append((x,r*math.cos(a),54+r*math.sin(a)))
fs=[(i,(i+1)%12,12+(i+1)%12,12+i) for i in range(12)]+[(12+i,12+(i+1)%12,24+(i+1)%12,24+i) for i in range(12)]
add(('Hull detailing',3),vs,fs)
beam(('Hull detailing',2),(89,0,54),(95,0,54),.25,6)
for x,y,height in [(-100,4,18),(-97,-5,12),(84,12,11)]:
 beam(('Hull detailing',3),(x,y,31 if x<0 else 40),(x+1,y,31+height if x<0 else 40+height),.35,6)
# Pressure bottles recessed along the starboard spine, with cradle straps.
for x in [-57,-17,26]:
 axial_ring(('Hull detailing',0),x,17,32,[(-9,1),(-7,4),(-5,5),(5,5),(7,4),(9,1)],16)
 for dx in [-5,5]:axial_ring(('Hull detailing',3),x+dx,17,32,[(-.5,5.15),(.5,5.15)],16)
 beam(('Hull detailing',2),(x-7,17,29),(x-7,17,24),1,6)
# Service radiators on aft upper shoulders, sized like ship fittings rather than wings.
for side in [-1,1]:
 for j in range(7):
  x=-119+j*3.4
  box(('Hull detailing',2),(x,side*21,25),(1.1,13,9))
 beam(('Hull detailing',3),(-120,side*21,22),(-96,side*21,22),1,8)
# Docking clamps, hatches, handrails and clustered attitude jets.
for x in [-84,74]:
 for side in [-1,1]:
  box(('Hull detailing',3),(x,side*31,-6),(10,4,9))
  box(('Hull detailing',2),(x,side*34,-6),(5,3,5))
  for yy,zz in [(0,3),(0,-3),(3,0),(-3,0)]:
   beam(('Hull detailing',2),(x+yy,side*34,-6+zz),(x+yy,side*36,-6+zz),1,8)
for x,y,z in [(-105,0,23),(62,16,27),(135,0,14)]:
 box(('Hull detailing',2),(x,y,z),(11,9,.6))
 box(('Outer hull',0),(x,y,z+.5),(9,7,.7))
 for dx in [-3,3]:box(('Hull detailing',3),(x+dx,y,z+1),(1,3,.8))
for y in [13,23]:
 for x in [-75,-60,-45,-30]:beam(('Hull detailing',3),(x,y,26),(x,y,29),.22,6)
 beam(('Hull detailing',3),(-75,y,29),(-30,y,29),.24,6)
# Shaped hollow engine bells with concentric inner rings; no illuminated exhaust.
shaped(('Engine structure',0),[(-128,26,15,0),(-119,28,16,0),(-112,25,14,0)])
for side in [-1,1]:
 y=side*17;z=-2 if side<0 else 0;tilt=.08 if side<0 else 0
 axial_ring(('Engines',0),-136,y,z,[(9,7),(6,10),(0,10),(-8,13),(-14,13),(-14,10.5),(-7,8),(0,5)],24,tilt)
 axial_ring(('Engines',3),-136,y,z,[(-13.8,13.2),(-12.2,13.2),(-12.2,10.4)],24,tilt)
 axial_ring(('Engine structure',2),-136,y,z,[(-9,8.8),(-7.8,8.8)],24,tilt)
 beam(('Engine structure',2),(-136,y,z),(-135,y,z),4.8,16)
 for a in [0,math.pi/2,math.pi,math.pi*1.5]:
  beam(('Engine structure',3),(-130,y+10*math.cos(a),z+10*math.sin(a)),(-145,y+12.8*math.cos(a),z+12.8*math.sin(a)),.65,6)
for y in [-14,14]:beam(('Engine structure',3),(-118,y,-8),(-134,y,-8),2,8)
# Broken neck seams and small external damage beyond the main breach.
for x,y,z in [(-125,-19,10),(-120,-24,3),(-104,19,22),(80,18,21)]:
 box(('Breach scorching',2),(x,y,z),(8,3,1),.28)
for x in [-52,16]:
 # A shallow dented square roof panel: rim intact, centre depressed above shell.
 vv=[];ff=[]
 for j in range(7):
  for i in range(7):
   u=(i-3)/3;v=(j-3)/3;zz=27-2.4*math.exp(-(u*u+v*v)*4)
   vv.append((x+u*7,7+v*5,zz))
 for j in range(6):
  for i in range(6):k=j*7+i;ff.append((k,k+1,k+8,k+7))
 add(('Outer hull',0),vv,ff)
 beam(('Breach scorching',2),(x-6,12,25),(x+7,12,25),.3,6)
# Missing access panel with exposed brackets; scorch ribbons along torn rim.
box(('Hull detailing',2),(-101,10,25),(12,8,1))
for y in [7,10,13]:beam(('Hull detailing',3),(-106,y,25.8),(-97,y,25.8),.3,6)
for x in [-70,59,83]:
 pts=[(x,-26,14),(x+12,-26,15),(x+5,-29,11),(x-2,-29,10)]
 add(('Breach scorching',2),pts,[(0,1,2,3)])
# Curling multi-segment sheets peel outward at the breach rather than flat sawteeth.
for x,width,top in [(-52,11,True),(-18,14,True),(25,9,True),(52,12,False),(-40,9,False)]:
 vv=[]
 for j in range(6):
  t=j/5;y=(-25 if top else -33)-14*t;z=(18 if top else -15)+(9*math.sin(t*2.4) if top else -8*math.sin(t*2.4))
  vv.extend([(x-width/2*(1-.3*t),y,z),(x+width/2*(1-.5*t),y,z+1.1*t)])
 ff=[(j*2,j*2+1,j*2+3,j*2+2) for j in range(5)];add(('Torn hull lips',4),vv,ff)
# Ceiling services, side compartment door frames, a ladder and readable upper-deck rail.
for y,z in [(5,17),(11,16),(21,15)]:
 beam(('Interior frames',3),(-75,y,z),(70,y,z),.7,8)
 for x in [-65,-25,15,55]:box(('Interior frames',2),(x,y,z),(1.4,2.5,2.5))
for x in [-46,14,65]:
 for y in [9,25]:beam(('Interior frames',4),(x,y,-15),(x,y,0),.5,6,.6)
 beam(('Interior frames',4),(x,9,0),(x,25,0),.5,6,.6)
for x in [48,53]:beam(('Interior frames',3),(x,25,-15),(x,25,9),.45,6)
for z in range(-14,10,3):beam(('Interior frames',3),(48,25,z),(53,25,z),.35,6)
for x in range(-64,66,12):beam(('Interior frames',3),(x,17,3),(x,17,7),.3,6)
beam(('Interior frames',3),(-64,17,7),(68,17,7),.3,6)
for x in [-62,-24,26]:
 box(('Interior frames',3),(x,25,10),(13,6,1))
 for xx in [-5,5]:beam(('Interior frames',3),(x+xx,25,3),(x+xx,25,17),.35,6)
 for z in [7,13]:box(('Interior cargo',1),(x,25,z),(8,4,4))
# Loose cables are kept outside the protected 6 x 6 m flight cross-section.
for x in [-36,18,56]:
 cable([(x-5,-24,17),(x-3,-26,10),(x,-27,3),(x+3,-26,0),(x+6,-24,5),(x+8,-22,15)])
 cable([(x+2,7,18),(x+5,5,12),(x+6,5,7)],('Interior frames',3),.4)
