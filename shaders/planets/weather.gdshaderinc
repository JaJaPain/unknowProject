uniform float cloud_coverage = .5;
uniform float cloud_speed = .013;
uniform float cloud_evolution_speed = 1.0;
uniform vec4 cyclone = vec4(-.25,.3,.92,.25);
uniform float cyclone_strength = 1.0;
vec3 cloud_coords(vec3 p) {
 p=rotate_y(p,rotation_phase+planet_time*cloud_speed);
 vec3 c=normalize(cyclone.xyz);vec3 u=normalize(cross(vec3(0,1,0),c));vec3 v=cross(c,u);
 vec2 xy=vec2(dot(p,u),dot(p,v))/cyclone.w;
 float evolution=planet_time*cloud_evolution_speed;
 float r=length(xy);float twist=(2.8+.22*sin(evolution*.027))*cyclone_strength*exp(-r*r*.8)*smoothstep(0.0,.4,dot(p,c));
 vec2 q=mat2(vec2(cos(twist),sin(twist)),vec2(-sin(twist),cos(twist)))*xy;
 return normalize(p+u*(q.x-xy.x)*cyclone.w+v*(q.y-xy.y)*cyclone.w);
}
float cloud_field(vec3 original) {
 if(cloud_coverage<=0.0) {return 0.0;}
 float evolution=planet_time*cloud_evolution_speed;
 vec3 p=cloud_coords(original);
 vec3 q=p*5.0+seed_offset+vec3(7,13,3);
 // Different temporal flow at each scale changes shape, not only longitude.
 float broad=fbm(q+evolution*vec3(.008,-.005,.003));
 float warp=fbm(q*1.9+vec3(9.4)+evolution*vec3(-.009,.007,.005));
 float weather=fbm(p*vec3(15,21,15)+seed_offset+vec3(warp,broad,warp-broad)*4.0+evolution*vec3(.018,.012,-.014));
 float wisps=fbm(p*vec3(65,95,65)+seed_offset+weather*5.0+evolution*vec3(-.027,.017,.021));
 float field=broad*.52+weather*.34+wisps*.14;
 float threshold=mix(.66,.34,cloud_coverage);
 return smoothstep(threshold-.055,threshold+.10,field);
}
