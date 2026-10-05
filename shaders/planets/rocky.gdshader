shader_type spatial;
render_mode unshaded, fog_disabled;
#include "common.gdshaderinc"
uniform vec3 highland_color : source_color = vec3(.48,.47,.45);
uniform vec3 lowland_color : source_color = vec3(.22,.23,.24);
uniform float maria_amount = .5;
uniform float relief = 1.0;
uniform float crater_density = .85;
uniform vec4 craters[48];
uniform float ray_strength = .22;
uniform float ice_amount = 0.0;

vec3 hash3(vec3 p) {
 p=vec3(dot(p,vec3(127.1,311.7,74.7)),dot(p,vec3(269.5,183.3,246.1)),dot(p,vec3(113.5,271.9,124.6)));
 return fract(sin(p)*43758.5453);
}
float crater_shape(float r) {
 float bowl=-.12*(1.0-smoothstep(.30,1.0,r));
 float rim=.045*exp(-pow((r-.99)*7.0,2.0));
 float peak=.027*exp(-r*r*65.0);
 return bowl+rim+peak;
}
float crater_slope(float r) {
 float t=clamp((r-.30)/.70,0.0,1.0);
 float bowl=.12*6.0*t*(1.0-t)/.70;
 float rim=-.09*(r-.99)*49.0*exp(-pow((r-.99)*7.0,2.0));
 float peak=-.054*r*65.0*exp(-r*r*65.0);
 return bowl+rim+peak;
}
vec4 small_craters(vec3 p,float scale) {
 vec3 cell=floor(p*scale);vec3 gradient=vec3(0.0);float dust=0.0;
 for(int x=-1;x<=1;x++) {for(int y=-1;y<=1;y++) {for(int z=-1;z<=1;z++) {
  vec3 id=cell+vec3(float(x),float(y),float(z));
  vec3 rnd=hash3(id+seed_offset);
  vec3 center=id+rnd;
  if(abs(length(center)-scale)>.55 || rnd.z>crater_density) {continue;}
  float radius=mix(.15,.48,rnd.x);
  vec3 delta=p-normalize(center);
  float r=length(delta)*scale/radius;
  vec3 direction=delta/max(length(delta),1e-6);
  gradient+=crater_slope(r)*(direction-p*dot(p,direction));
  dust+=exp(-pow((r-1.15)*2.0,2.0))*.1;
 }}}
 return vec4(gradient,dust);
}
void vertex() {sphere_position=VERTEX;radial_world=MODEL_NORMAL_MATRIX*NORMAL;}
void fragment() {
 vec3 n=normalize(radial_world);
 vec3 p=rotate_y(normalize(sphere_position),rotation_phase+planet_time*rotation_rate);
 vec3 s=seed_offset;
 float geology=fbm(p*3.6+s);
 float terrain=fbm(p*18.0+s+vec3(geology)*2.5);
 float micro=fbm(p*130.0+s);
 float maria=smoothstep(.47,.64,geology)*maria_amount;
 float h=(terrain-.5)*.0018+(micro-.5)*.00015;
 float ejecta=0.0;float cavity=0.0;vec3 gradient=vec3(0.0);
 for(int i=0;i<48;i++) {
  vec3 c=craters[i].xyz;float radius=craters[i].w;
  float r=length(p-c)/radius;
  if(r>3.5) {continue;}
  float rr=r;
  vec3 direction=(p-c)/max(length(p-c),1e-6);
  gradient+=crater_slope(rr)*(direction-p*dot(p,direction))*(1.0-maria*.65);
  cavity=max(cavity,(1.0-smoothstep(.65,1.0,rr))*.18);
  vec3 u=normalize(cross(c,vec3(.01,1,.01)));vec3 v=cross(c,u);
  float angle=atan(dot(p,v),dot(p,u));
  float rays=pow(max(0.0,sin(angle*19.0+float(i))+sin(angle*31.0)*.35),5.0);
  ejecta+=exp(-pow((rr-1.04)*3.0,2.0))*.10;
  if(i<6) {ejecta+=rays*exp(-r*1.2)*smoothstep(.9,1.15,r)*ray_strength;}
 }
 vec4 fine=small_craters(p,31.0);
 float medium_fade=1.0-smoothstep(.003,.012,length(fwidth(p)));
 gradient+=fine.xyz*(1.0-maria*.92)*medium_fade;ejecta+=fine.w*.5;
 if(quality_level>0) {
  vec4 tiny=small_craters(p,83.0);
  float fade=1.0-smoothstep(.0015,.006,length(fwidth(p)));
  gradient+=tiny.xyz*fade*(1.0-maria*.95)*.55;ejecta+=tiny.w*.25*fade;
 }
 vec3 base=mix(highland_color,lowland_color,maria);
 base*=.85+terrain*.30+(micro-.5)*.17;
 base*=1.0-cavity;base+=highland_color*ejecta;
 float ice=smoothstep(.65,.93,abs(p.y)+(terrain-.5)*.25)*ice_amount;
 base=mix(base,vec3(.72,.78,.82),ice);
 vec3 world_gradient=MODEL_NORMAL_MATRIX*rotate_y(gradient,-rotation_phase-planet_time*rotation_rate)/length(MODEL_NORMAL_MATRIX[0]);
 vec3 bn=normalize(relief_normal(n,h,relief)-world_gradient*relief);
 vec3 light=normalize(sun_direction);
 float mu=max(dot(bn,light),0.0);
 float horizon=smoothstep(-.025,.065,dot(n,light));
 vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
 // Rough regolith, restrained backscatter, no plastic specular reflection.
 float lunar=mu/(max(mu+max(dot(bn,view_world),0.0),.1));
 float lighting=mix(mu,lunar,.25)*horizon;
 ALBEDO=base*sun_color*sun_intensity*(lighting+.0015);
}
