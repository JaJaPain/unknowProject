uniform sampler3D noise_volume : filter_linear, repeat_enable;
uniform vec3 seed_offset = vec3(0.0);
uniform float planet_time = 0.0;
uniform float rotation_rate = .008;
uniform float rotation_phase = 0.0;
uniform vec3 sun_direction = vec3(-.55,.30,.78);
uniform vec3 sun_color : source_color = vec3(1.0,.97,.93);
uniform float sun_intensity = 1.4;
uniform int quality_level = 2;
varying vec3 sphere_position;
varying vec3 radial_world;

float noise3(vec3 p) {
 vec3 f=fract(p);f=f*f*f*(f*(f*6.0-15.0)+10.0);
 return texture(noise_volume,(floor(p)+f+.5)/32.0).r;
}
float fbm(vec3 p) {
 float value=0.0;float amp=.5;float total=0.0;
 for(int i=0;i<6;i++) {
  if(i>=3+quality_level) {break;}
  value+=noise3(p)*amp;total+=amp;p=p*2.03+vec3(5.1,1.7,9.2);amp*=.5;
 }
 return value/total;
}
vec3 rotate_y(vec3 p,float a) {
 return vec3(cos(a)*p.x-sin(a)*p.z,p.y,sin(a)*p.x+cos(a)*p.z);
}
// Derivative-based surface gradient: detail follows shader rotation, no UV seams.
vec3 relief_normal(vec3 n,float height,float strength) {
 vec3 dx=dFdx(n);vec3 dy=dFdy(n);
 vec3 r1=cross(dy,n);vec3 r2=cross(n,dx);
 float det=dot(dx,r1);
 vec3 gradient=(r1*dFdx(height)+r2*dFdy(height))/max(abs(det),1e-10)*sign(det);
 return normalize(n-gradient*strength);
}
