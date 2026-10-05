extends RefCounted

## Gas giant V2 profiles and materials (ChatGPT's prototype,
## prototypes/gas_giant_v2/Profiles.gd; wired in 2026-10-04 per
## docs/prototypes/gas_giant_v2_claude_handoff.md). Six families, eight
## palettes, up to four storms; procedural clouds rotated in the shader.

const SURFACE := preload("res://shaders/gas_giant_v2.gdshader")
const ATMOSPHERE := preload("res://shaders/gas_giant_atmosphere.gdshader")
const ARCHETYPES := ["active_banded", "quiet_ice", "active_ice", "hot_giant", "cold_haze", "chaotic_giant"]
const LABELS := ["Jovian belts", "Quiet ice giant", "Active ice giant", "Copper giant", "Pearl haze", "Violet turbulence"]
const PALETTES := {
	"ammonia_ochre": ["e4dbc4","c3a88a","946b50","d1ba99","f0e9d7","b48665"],
	"methane_cyan": ["b1d1cd","8db7bb","649499","a4c7c6","c0d6d2","7ca7b0"],
	"neptune_azure": ["729db9","476b9a","334b75","7394ba","b7cddd","557fac"],
	"hot_copper": ["d0a486","9e614b","603d38","c3835f","e7c9ad","8c5547"],
	"cold_pearl": ["d9dedb","a8b9bc","7c929d","c7c9be","e8e9df","a2a5a7"],
	"photochemical_violet": ["b5b4c5","85839f","635c7d","ac929d","ddd0d0","817490"],
	"sulfur_cream": ["ded7b3","b5b38b","818671","cac0a1","eae4cd","aaa080"],
	"carbon_haze": ["9b9eac","6f727d","454d60","96837c","bcb3ad","746c75"]
}
static var _noise: ImageTexture3D

static func noise_volume() -> ImageTexture3D:
	if _noise != null: return _noise
	var rng := RandomNumberGenerator.new()
	rng.seed = 912670
	var slices: Array[Image] = []
	for z in 32:
		var data := PackedByteArray()
		data.resize(32 * 32)
		for i in data.size(): data[i] = rng.randi_range(0, 255)
		slices.append(Image.create_from_data(32, 32, false, Image.FORMAT_R8, data))
	_noise = ImageTexture3D.new()
	_noise.create(Image.FORMAT_R8, 32, 32, 32, false, slices)
	return _noise

static func profile_for_seed(seed_value: int, archetype: String = "", palette: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if archetype.is_empty(): archetype = ARCHETYPES[rng.randi() % ARCHETYPES.size()]
	var index: int = ARCHETYPES.find(archetype)
	if palette.is_empty():
		palette = ["ammonia_ochre", "methane_cyan", "neptune_azure", "hot_copper", "cold_pearl", "photochemical_violet"][index]
		if rng.randf() < .18: palette = PALETTES.keys()[rng.randi() % PALETTES.size()]
	var colors := PackedColorArray()
	for code in PALETTES[palette]: colors.append(Color(code))
	var count: int = [2, 0, 1, 1, 0, 3][index]
	var storms: Array[Dictionary] = []
	for i in 4:
		var latitude: float = [-.23, .38, -.53, .14][i] + rng.randf_range(-.04,.04)
		var longitude: float = [-.28, .75, -1.0, 2.2][i] + rng.randf_range(-.12,.12)
		var dir := Vector3(sin(longitude)*sqrt(1-latitude*latitude),latitude,cos(longitude)*sqrt(1-latitude*latitude))
		var color := Color("ad6849") if index == 0 and i == 0 else colors[4]
		if index == 2 and i == 0: color=Color("284566")
		if index == 5: color=colors[2].lerp(colors[4], i*.23)
		storms.append({"direction":dir,"radius":.095 if i==0 else .04 + rng.randf()*.025,"aspect":1.9 if i==0 else 1.45,"spin":1.0 if i%2==0 else -1.0,"contrast":.85,"wake":.8,"color":color})
	return {"seed":seed_value,"archetype":archetype,"palette":palette,"colors":colors,
		"turbulence":[.9,.15,.5,1.1,.25,1.45][index],"fine_strength":[.7,.10,.35,.55,.22,.75][index],
		"haze_density":[.04,.60,.18,.12,.36,.12][index],"polar_haze":[.12,.23,.14,.10,.22,.16][index],
		"haze_color":colors[0],"band_contrast":[.85,.15,.48,.72,.40,.70][index],
		"rotation_rate":rng.randf_range(.009,.017),"rotation_phase":0.0,"jet_shear":.12,
		"seed_offset":Vector3(rng.randf()*23,rng.randf()*23,rng.randf()*23),
		"storm_count":count,"storms":storms,"quality_level":2,"sun_direction":Vector3(-.55,.3,.78).normalized()}

static func band_texture(profile: Dictionary) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile.seed) + 74931
	var noise := FastNoiseLite.new()
	noise.seed = int(profile.seed)
	noise.frequency = 1.0
	noise.fractal_octaves = 3
	var bands: Array[Vector3] = []
	var latitude := -1.0
	while latitude < 1.0:
		var width := rng.randf_range(.018,.07)
		bands.append(Vector3(latitude,width,rng.randf_range(.12,.8)))
		latitude += width*rng.randf_range(1.1,2.5)
	var image := Image.create(2048, 1, false, Image.FORMAT_RGBA8)
	var colors: PackedColorArray = profile.colors
	for i in 2048:
		var y := float(i)/2047.0*2.0-1.0
		var amount := .18
		for band in bands:
			amount += exp(-pow((y-band.x)/band.y,4.0))*band.z*.65
		# Broad paired belts with independent widths; a pale equatorial zone.
		if profile.archetype == "active_banded":
			amount += .4*exp(-pow((y-.22)/.095,4.0)) + .48*exp(-pow((y+.18)/.07,4.0))
		amount += noise.get_noise_1d(y*72)*.09 + noise.get_noise_1d(y*250)*.035
		amount = clampf(amount*float(profile.band_contrast),0,1)
		var color := colors[0].lerp(colors[1],smoothstep(.08,.4,amount))
		color=color.lerp(colors[2],smoothstep(.40,.92,amount)*.8)
		color=color.lerp(colors[3],(.5+.5*noise.get_noise_1d(y*20+87))*.16)
		color=color.lerp(colors[4],maxf(0,noise.get_noise_1d(y*38+143))*.18)
		image.set_pixel(i,0,color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

static func material_pair_for(profile: Dictionary) -> Dictionary:
	var surface := ShaderMaterial.new()
	surface.shader=SURFACE
	surface.set_shader_parameter("noise_volume",noise_volume())
	surface.set_shader_parameter("band_lut",band_texture(profile))
	for key in ["seed_offset","rotation_rate","rotation_phase","jet_shear","turbulence","fine_strength","haze_density","polar_haze","haze_color","storm_count","quality_level","sun_direction"]:
		surface.set_shader_parameter(key,profile[key])
	var centers := PackedVector4Array()
	var shapes := PackedVector4Array()
	var tints := PackedColorArray()
	for storm in profile.storms:
		var d: Vector3=storm.direction
		centers.append(Vector4(d.x,d.y,d.z,storm.radius))
		shapes.append(Vector4(storm.aspect,storm.spin,storm.contrast,storm.wake))
		tints.append(storm.color)
	surface.set_shader_parameter("storm_center_size",centers)
	surface.set_shader_parameter("storm_shape",shapes)
	surface.set_shader_parameter("storm_tint",tints)
	var atmosphere := ShaderMaterial.new()
	atmosphere.shader=ATMOSPHERE
	atmosphere.set_shader_parameter("haze_color",profile.haze_color)
	atmosphere.set_shader_parameter("sun_direction",profile.sun_direction)
	atmosphere.set_shader_parameter("density",.22+float(profile.haze_density)*.3)
	return {"surface":surface,"atmosphere":atmosphere}
