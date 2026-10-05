shader_type spatial;
// Distant comet gas wake (made by Gemini + ChatGPT, test_comet/refined; wired 2026-10-05).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform float event_time=0.0;
uniform float visibility=1.0;
uniform float turbulence_strength : hint_range(0.0,1.0)=0.22;
// Gradient-noise gas structure adapted from Gemini's comet prototype.
vec2 hash2(vec2 p) {
 p=vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3)));
 return -1.0+2.0*fract(sin(p)*43758.5453123);
}
float noise2d(vec2 p) {
 vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);
 return mix(mix(dot(hash2(i),f),dot(hash2(i+vec2(1,0)),f-vec2(1,0)),u.x),mix(dot(hash2(i+vec2(0,1)),f-vec2(0,1)),dot(hash2(i+vec2(1,1)),f-vec2(1,1)),u.x),u.y);
}
float gas_fbm(vec2 p) {
 return .62*noise2d(p)+.26*noise2d(p*2.08+7.0)+.12*noise2d(p*4.17+19.0);
}
void fragment() {
 float u=(UV.x-.08)/.92;
 float y=UV.y*2.0-1.0;
 float x=max(u,0.0);
 // Motion changes density only: no sinusoidal displacement of the trail spine.
 // Independently evolving domains deform the density field, not the ribbon.
 // Different rates and directions prevent a single scrolling-texture appearance.
 vec2 eddy=vec2(
  gas_fbm(vec2(x*8.0+event_time*.073,y*5.0-event_time*.11)),
  gas_fbm(vec2(x*11.0-event_time*.061+31.0,y*7.0+event_time*.09)));
 float activity=smoothstep(.02,.30,x)*turbulence_strength;
 vec2 warp=eddy*activity*2.5;
 float cloud=gas_fbm(vec2(x*13.0-event_time*.16,y*4.0)+warp);
 float fine=gas_fbm(vec2(x*34.0-event_time*.25,y*12.0)-warp*1.7);
 float boiling=gas_fbm(vec2(x*22.0+eddy.y*2.0,y*9.0+eddy.x*2.0)+vec2(event_time*.045,-event_time*.13));
 float width=.022+pow(x,.72)*.65;
 float cross_profile=exp(-pow(y/max(width,.015),2.0)*2.3);
 float breakup=mix(1.0,smoothstep(-.22,.24,cloud+fine*.3),smoothstep(.10,.85,x)*.85);
 float diffuse=exp(-pow(y/max(width*1.9,.025),2.0)*2.0)*.16;
 float fade=exp(-2.4*x)*(1.0-smoothstep(.50,1.0,x));
 float wake=(cross_profile+diffuse)*breakup*fade*smoothstep(-.008,.022,u);
 wake*=1.0+boiling*activity*1.5;
 float r=length(vec2(u*7.6,y));
 float head=exp(-r*r*4200.0)*3.2+exp(-r*r*380.0)*.22;
 float halo=exp(-r*r*110.0)*.035;
 float ion=exp(-pow((y+width*.40)/(.018+x*.035),2.0))*fade*.017*smoothstep(0.0,.04,u);
 vec3 gas=mix(vec3(.80,.86,.82),vec3(.40,.49,.51),smoothstep(.2,1.0,x));
 float boundary=(1.0-smoothstep(.65,1.0,abs(y)))*smoothstep(0.0,.025,UV.x);
 ALBEDO=(gas*wake*.60+vec3(1.0,.98,.94)*head+vec3(.50,.70,.75)*halo+vec3(.25,.42,.75)*ion)*visibility*boundary;
 ALPHA=1.0;
}
