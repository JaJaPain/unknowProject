extends RefCounted

## Cratered rocky and ocean planets (ChatGPT's prototype,
## prototypes/terrestrial_planets/Profiles.gd; wired in 2026-10-04 per
## docs/prototypes/terrestrial_planets_claude_handoff.md). Families:
## 0 lunar, 1 iron desert, 2 frozen impact moon, 3 pure ocean,
## 4 archipelago, 5 storm ocean.

const ROCK := preload("res://shaders/planets/rocky.gdshader")
const OCEAN := preload("res://shaders/planets/ocean.gdshader")
const CLOUD := preload("res://shaders/planets/clouds.gdshader")
const ATMO := preload("res://shaders/planets/terrestrial_atmosphere.gdshader")
const NAMES := ["Lunar highlands", "Iron desert", "Frozen impact moon", "Pelagic ocean", "Turquoise archipelago", "Storm ocean"]
static var _noise: ImageTexture3D

static func noise_volume() -> ImageTexture3D:
	if _noise != null: return _noise
	var rng:=RandomNumberGenerator.new();rng.seed=912670
	var slices: Array[Image]=[]
	for z in 32:
		var bytes:=PackedByteArray();bytes.resize(1024)
		for i in 1024: bytes[i]=rng.randi_range(0,255)
		slices.append(Image.create_from_data(32,32,false,Image.FORMAT_R8,bytes))
	_noise=ImageTexture3D.new()
	_noise.create(Image.FORMAT_R8,32,32,32,false,slices)
	return _noise

static func profile_for_seed(seed_value: int, family: int=0) -> Dictionary:
	family=clampi(family,0,5)
	var rng:=RandomNumberGenerator.new();rng.seed=seed_value
	var craters:=PackedVector4Array()
	for i in 48:
		var y:=rng.randf_range(-.97,.97)
		var lon:=rng.randf_range(-PI,PI)
		var radius:=rng.randf_range(.025,.09)
		if i<6: radius=rng.randf_range(.095,.16)
		var dir:=Vector3(sin(lon)*sqrt(1-y*y),y,cos(lon)*sqrt(1-y*y))
		# Showcase one large complex crater on the initial lit hemisphere.
		if i==0: dir=Vector3(-.25,-.25,.93).normalized();radius=.12
		craters.append(Vector4(dir.x,dir.y,dir.z,radius))
	return {
		"seed":seed_value,"family":family,"name":NAMES[family],"is_ocean":family>=3,
		"seed_offset":Vector3(rng.randf()*20,rng.randf()*20,rng.randf()*20),
		"rotation_rate":rng.randf_range(.006,.010),"rotation_phase":0.0,
		"cloud_speed":rng.randf_range(.012,.019),"cloud_evolution_speed":1.0,"quality_level":2,
		"sun_direction":Vector3(-.55,.3,.78).normalized(),"sun_color":Color("fff7ed"),"sun_intensity":1.4,
		"highland_color":[Color("8d8983"),Color("b77d59"),Color("a0abb3")][family%3],
		"lowland_color":[Color("41454b"),Color("543c32"),Color("4b5969")][family%3],
		"maria_amount":[.85,.30,.48][family%3],"relief":1.0,"crater_density":.54,
		"ray_strength":.24,"craters":craters,
		"ice_amount":[0.0,.1,.9,.35,.12,.60][family],
		"ocean_color":[Color("082248"),Color("053741"),Color("0a2236")][family%3],
		"shallow_color":[Color("17646e"),Color("1b9f9a"),Color("25666e")][family%3],
		"land_color":Color("43512c"),"land_amount":[0.0,0.0,0.0,0.0,.76,.16][family],
		"cloud_coverage":[0.0,0.0,0.0,.48,.40,.73][family],"ocean_roughness":.26,
		"cyclone":Vector4(rng.randf_range(-.6,.1),rng.randf_range(.1,.5),.92,rng.randf_range(.085,.135)),"cyclone_strength":1.0,"clouds_enabled":true
	}

static func materials_for(profile: Dictionary) -> Dictionary:
	var surface:=ShaderMaterial.new();surface.shader=OCEAN if profile.is_ocean else ROCK
	var clouds:=ShaderMaterial.new();clouds.shader=CLOUD
	var atmosphere:=ShaderMaterial.new();atmosphere.shader=ATMO
	var shared: Array[String]=["seed_offset","rotation_rate","rotation_phase","quality_level","sun_direction","sun_color","sun_intensity"]
	for mat in [surface,clouds]:
		mat.set_shader_parameter("noise_volume",noise_volume())
		for key in shared: mat.set_shader_parameter(key,profile[key])
	for key in ["sun_direction","sun_color","sun_intensity"]: atmosphere.set_shader_parameter(key,profile[key])
	if profile.is_ocean:
		for key in ["ocean_color","shallow_color","land_color","land_amount","ice_amount","ocean_roughness","clouds_enabled"]:
			surface.set_shader_parameter(key,profile[key])
		for mat in [surface,clouds]:
			for key in ["cloud_coverage","cloud_speed","cloud_evolution_speed","cyclone","cyclone_strength"]: mat.set_shader_parameter(key,profile[key])
	else:
		for key in ["highland_color","lowland_color","maria_amount","relief","crater_density","craters","ray_strength","ice_amount"]:
			surface.set_shader_parameter(key,profile[key])
	return {"surface":surface,"clouds":clouds,"atmosphere":atmosphere}
