shader_type spatial;
render_mode unshaded, fog_disabled;
#include "common.gdshaderinc"
#include "weather.gdshaderinc"
uniform vec3 ocean_color : source_color = vec3(.018,.075,.17);
uniform vec3 shallow_color : source_color = vec3(.045,.34,.36);
uniform vec3 land_color : source_color = vec3(.16,.24,.11);
uniform float land_amount = .12;
uniform float ice_amount = .45;
uniform float ocean_roughness = .24;
uniform bool clouds_enabled = true;
void vertex() {sphere_position=VERTEX;radial_world=MODEL_NORMAL_MATRIX*NORMAL;}
void fragment() {
 vec3 n=normalize(radial_world);vec3 local=normalize(sphere_position);
 vec3 p=rotate_y(local,rotation_phase+planet_time*rotation_rate);
 float broad=fbm(p*3.2+seed_offset);
 float terrain=fbm(p*15.0+seed_offset+vec3(broad)*2.5);
 float land_height=broad*.8+terrain*.2;
 float sea_level=mix(1.05,.43,land_amount);
 float land=smoothstep(sea_level-.004,sea_level+.006,land_height);
 float shelf=smoothstep(sea_level-.06,sea_level,land_height)*(1.0-land);
 float ridges=1.0-abs(fbm(p*68.0+seed_offset)*2.0-1.0);
 vec3 base=mix(ocean_color,shallow_color,shelf*.8);
 vec3 ground=mix(land_color,vec3(.38,.31,.20),smoothstep(.54,.66,terrain));
 ground*=.7+ridges*.4;
 float beach=(1.0-smoothstep(sea_level+.002,sea_level+.005,land_height))*land;
 ground=mix(ground,vec3(.58,.52,.35),beach*.7);
 base=mix(base,ground,land);
 float ice=smoothstep(1.0-ice_amount*.32,1.04-ice_amount*.24,abs(p.y)+(terrain-.5)*.12);
 base=mix(base,vec3(.72,.83,.86),ice);
 float height=land*(land_height-sea_level)*.015+(terrain-.5)*.00004*(1.0-land);
 vec3 bn=relief_normal(n,height,1.0);
 vec3 light=normalize(sun_direction);
 vec3 view_world=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);
 float mu=max(dot(bn,light),0.0);
 float shadow=clouds_enabled ? cloud_field(normalize(local+normalize((inverse(MODEL_NORMAL_MATRIX)*light))*.013)) : 0.0;
 float illumination=pow(mu,.85)*(1.0-shadow*.50);
 vec3 halfv=normalize(light+view_world);
 float nh=max(dot(bn,halfv),0.0);float nv=max(dot(bn,view_world),.001);
 float lh=max(dot(light,halfv),0.0);
 float alpha=ocean_roughness*ocean_roughness;
 float denom=nh*nh*(alpha*alpha-1.0)+1.0;
 float distribution=alpha*alpha/(PI*denom*denom);
 float fresnel=.02+.98*pow(1.0-lh,5.0);
 float k=pow(ocean_roughness+1.0,2.0)/8.0;
 float geometry=(nv/(nv*(1.0-k)+k))*(mu/(mu*(1.0-k)+k));
 float spec=distribution*fresnel*geometry/max(4.0*nv,.01);
 spec*= (1.0-land)*(1.0-ice)*(1.0-shadow*.92)*smoothstep(0.0,.06,dot(n,light));
 float limb=pow(1.0-nv,3.0)*smoothstep(-.08,.3,dot(n,light));
 ALBEDO=(base*(illumination+.001)+vec3(spec))*sun_color*sun_intensity+vec3(.075,.24,.48)*limb*.23;
}
