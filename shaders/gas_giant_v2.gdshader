shader_type spatial;
render_mode unshaded, fog_disabled;

// Object-space weather; geometry and normals never rotate.
uniform sampler3D noise_volume : filter_linear, repeat_enable;
uniform sampler2D band_lut : source_color, filter_linear, repeat_disable;
uniform vec3 seed_offset = vec3(0.0);
uniform float planet_time = 0.0;
uniform float rotation_phase = 0.0;
uniform float rotation_rate = 0.015;
uniform float jet_shear = 0.12;
uniform float turbulence = 0.65;
uniform float fine_strength = 0.4;
uniform float haze_density = 0.12;
uniform float polar_haze = 0.12;
uniform vec3 haze_color : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.93);
uniform vec3 sun_direction = vec3(-0.6, 0.35, 0.7);
uniform float sun_intensity = 1.2;
uniform int storm_count = 1;
uniform vec4 storm_center_size[4];
uniform vec4 storm_shape[4]; // aspect, spin, contrast, wake
uniform vec4 storm_tint[4] : source_color;
uniform int quality_level = 2;
uniform bool debug_grid = false;
varying vec3 sphere_position;
varying vec3 world_normal;

float noise3(vec3 p) {
 vec3 i = floor(p);
 vec3 f = fract(p);
 f = f*f*f*(f*(f*6.0-15.0)+10.0);
 return texture(noise_volume, (i+f+0.5)/32.0).r;
}
float fbm(vec3 p) {
 float v=0.0; float amplitude=0.5; float weight=0.0;
 for(int i=0;i<6;i++) {
  if(i>2 && quality_level==0) { break; }
  if(i>3 && quality_level==1) { break; }
  v+=amplitude*noise3(p); weight+=amplitude;
  p=p*2.03+vec3(5.1,1.7,9.2); amplitude*=0.5;
 }
 return v/weight;
}
vec3 spin_y(vec3 p,float a) {
 float c=cos(a);float s=sin(a);
 return vec3(c*p.x-s*p.z,p.y,s*p.x+c*p.z);
}
void vertex() {
 sphere_position=VERTEX;
 world_normal=(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
 vec3 n=normalize(world_normal);
 vec3 p=normalize(sphere_position);
 p=spin_y(p,rotation_phase+planet_time*rotation_rate);
 vec3 rigid_p=p;
 // Slow bounded shear avoids unbounded winding and long-run precision loss.
 float shear=jet_shear*sin(p.y*29.0+noise3(vec3(p.y*9.0,3,7))*4.0);
 p=spin_y(p,shear*sin(planet_time*0.008));
 float storm_masks[4];
 float storm_radii[4];
 vec2 storm_points[4];
 for(int i=0;i<4;i++) {
  storm_masks[i]=0.0;storm_radii[i]=0.0;storm_points[i]=vec2(0.0);
  if(i>=storm_count) { continue; }
  vec3 c=normalize(storm_center_size[i].xyz);
  float sz=max(storm_center_size[i].w,0.005);
  vec3 u=normalize(cross(vec3(0,1,0),c)+vec3(0.00001,0,0));
  vec3 v=cross(c,u);
  vec2 xy=vec2(dot(rigid_p,u)/storm_shape[i].x,dot(rigid_p,v))/sz;
  float edge_noise=noise3(vec3(xy*2.3,float(i)*7.0)+seed_offset)-.5;
  float r=length(xy)+edge_noise*.20;
  float front=smoothstep(0.0,0.3,dot(rigid_p,c));
  float envelope=(1.0-smoothstep(0.7,1.9,r))*front;
  float twist=envelope*(2.1+edge_noise*.65+0.12*sin(planet_time*0.06))*storm_shape[i].y;
  vec2 q=mat2(vec2(cos(twist),sin(twist)),vec2(-sin(twist),cos(twist)))*xy;
  p=normalize(p+u*(q.x-xy.x)*sz*storm_shape[i].x+v*(q.y-xy.y)*sz);
  storm_masks[i]=(1.0-smoothstep(0.72,1.18,r))*front;
  storm_radii[i]=r;
  storm_points[i]=q;
  // Local latitude displacement trailing each oval.
  float wake=exp(-abs(xy.y)*2.5)*exp(-abs(xy.x)*0.45)*smoothstep(1.0,2.0,abs(xy.x))*front;
  p.y+=sin(xy.x*3.5+xy.y*2.0)*wake*sz*storm_shape[i].w*0.25;
  p=normalize(p);
 }
 vec3 seed=seed_offset;
 vec3 broad=vec3(p.x*4.5,p.y*12.0,p.z*4.5)+seed;
 float w1=fbm(broad);
 float w2=fbm(broad*1.83+vec3(9.2,3.7,6.1));
 vec3 weather=vec3(p.x*12.0,p.y*35.0,p.z*12.0)+seed;
 weather+=vec3(w2,w1,w2-w1)*3.8*turbulence;
 float billow=fbm(weather);
 float curls=fbm(weather*2.6+vec3(billow,w2,w1)*3.5);
 float latitude=p.y + turbulence*((w1-.5)*.07+(billow-.5)*.04+(curls-.5)*.012);
 vec3 base=texture(band_lut,vec2(clamp(latitude*.5+.5,0.001,.999),.5)).rgb;
 // Fine longitudinal filaments, attenuated by pixel footprint at distance.
 float footprint=length(fwidth(p));
 float detail_fade=1.0-smoothstep(.008,.025,footprint);
 float fibers=fbm(vec3(p.x*38.0,latitude*270.0,p.z*38.0)+seed+vec3(w1,billow,w2)*9.0);
 float detail=(billow-.5)*.27+(curls-.5)*.20+(fibers-.5)*.23*detail_fade;
 base*=1.0+detail*fine_strength*2.0;
 float white_cloud=smoothstep(.53,.73,curls+.10*(fibers-.5))*fine_strength;
 base=mix(base,vec3(.78,.79,.78),white_cloud*.22);
 for(int i=0;i<4;i++) {
  if(i>=storm_count) { continue; }
  float r=storm_radii[i];vec2 q=storm_points[i];
  float a=atan(q.y,q.x)+storm_shape[i].y*(r*5.0-planet_time*.012);
  vec3 swirl=vec3(cos(a)*r*9.0,sin(a)*r*9.0,float(i)*11.0)+seed;
  float churn=fbm(swirl+vec3(fbm(swirl*.4)*2.0));
  float filaments=fbm(swirl*4.0+vec3(churn*4.0));
  vec3 tint=storm_tint[i].rgb*(.72+churn*.55+(filaments-.5)*.24);
  float rim=exp(-pow((r-.85)*7.0,2.0));
  tint=mix(tint,texture(band_lut,vec2(clamp(latitude*.5+.52,0.0,1.0),.5)).rgb,rim*.45);
  base=mix(base,tint,storm_masks[i]*storm_shape[i].z);
 }
 float polar=smoothstep(.65,.98,abs(p.y))*polar_haze;
 base=mix(base,haze_color,clamp(haze_density+polar,0.0,.88));
 if(debug_grid) {
  float longitude=atan(rigid_p.z,rigid_p.x);
  float grid=max(1.0-smoothstep(.018,.035,abs(sin(longitude*12.0))),1.0-smoothstep(.018,.035,abs(sin(rigid_p.y*30.0))));
  base=mix(base,vec3(.08,.7,.9),grid*.6);
 }
 float mu=dot(n,normalize(sun_direction));
 // A diffuse cloud scattering approximation, no metallic/specular surface.
 float illumination=pow(max(mu,0.0),.72);
 float limb=pow(1.0-clamp(dot(normalize(NORMAL),VIEW),0.0,1.0),3.0);
 vec3 reflected=base*sun_color*sun_intensity*(illumination+.003);
 vec3 scatter=haze_color*limb*.075*smoothstep(-.10,.40,mu)*sun_color;
 ALBEDO=reflected+scatter;
}
