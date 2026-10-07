extends RefCounted

## Surface detail for set pieces that arrive with flat materials (ChatGPT's
## models use colours and vertex colours, no texture images). Lays generated,
## seamless noise over a material from all sides (triplanar, in world metres):
## colour variation, grime, bump and uneven shine, so a clean surface reads as
## weathered stone, aged metal or woven cloth up close. No texture files.
##
## apply(model, {material name substring: preset}) duplicates each matching
## material for this model only. Presets: "stone", "metal", "fabric", "ice".

const PRESETS := {
	# Pale cut stone: blotchy tone, vertical grime streaks, a little grain.
	"stone": {"tone": [0.74, 1.0], "tone_freq": 0.012, "tone_stretch": Vector3(1.0, 0.18, 1.0),
		"bump_freq": 0.05, "bump": 0.3, "rough": [0.82, 0.97], "metal": 0.0},
	# Aged bronze: patina patches, uneven shine.
	"metal": {"tone": [0.62, 1.0], "tone_freq": 0.03, "tone_stretch": Vector3.ONE,
		"bump_freq": 0.09, "bump": 0.35, "rough": [0.3, 0.75], "metal": 0.7},
	# Frosted ice: broad drifts of brighter and duller frost, a coarse crust
	# bump that breaks up a faceted low-poly surface.
	"ice": {"tone": [0.72, 1.0], "tone_freq": 0.004, "tone_stretch": Vector3.ONE,
		"bump_freq": 0.03, "bump": 0.45, "rough": [0.6, 0.9], "metal": 0.0},
	# Woven envelope cloth: soft tone variation, a fine weave bump.
	"fabric": {"tone": [0.86, 1.0], "tone_freq": 0.008, "tone_stretch": Vector3(1.0, 0.35, 1.0),
		"bump_freq": 0.12, "bump": 0.12, "rough": [0.92, 1.0], "metal": 0.0},
}

static var _cache := {}


static func apply(model: Node3D, recipes: Dictionary) -> int:
	var count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var current := mi.get_surface_override_material(i)
			var m := (current if current != null else mi.mesh.surface_get_material(i)) as StandardMaterial3D
			if m == null:
				continue
			for key in recipes:
				if m.resource_name.contains(str(key)) and PRESETS.has(str(recipes[key])):
					mi.set_surface_override_material(i, detailed(m, str(recipes[key])))
					count += 1
					break
	return count


## A copy of `base` with the preset's detail laid over it.
static func detailed(base: StandardMaterial3D, preset: String) -> StandardMaterial3D:
	var p: Dictionary = PRESETS[preset]
	var m := base.duplicate() as StandardMaterial3D
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 2.0
	m.uv1_scale = Vector3.ONE * float(p["tone_freq"]) * (p["tone_stretch"] as Vector3)
	m.albedo_texture = _tone(preset, p)
	m.normal_enabled = true
	m.normal_texture = _bump(preset, p)
	m.normal_scale = float(p["bump"])
	# Shine varies only within the preset's range (never glossy wet patches).
	m.roughness_texture = _rough(preset, p)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	if float(p["metal"]) >= 0.0:
		m.metallic = float(p["metal"])
	return m


static func _noise(seed_value: int, frequency: float, octaves: int, normal_map := false) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	if normal_map:
		t.as_normal_map = true
		t.bump_strength = 6.0
	return t


## Albedo: a pale-to-full tone ramp (it multiplies the model's own colours).
static func _tone(preset: String, p: Dictionary) -> NoiseTexture2D:
	var key := "tone:" + preset
	if not _cache.has(key):
		var t := _noise(hash(key), 0.012, 5)
		var ramp := Gradient.new()
		var tone: Array = p["tone"]
		ramp.set_color(0, Color.WHITE * float(tone[0]))
		ramp.set_color(1, Color.WHITE * float(tone[1]))
		ramp.set_offset(0, 0.25)
		ramp.set_offset(1, 0.75)
		t.color_ramp = ramp
		_cache[key] = t
	return _cache[key]


## Normal map: finer noise (the triplanar scale makes it much smaller per metre
## than the tone, via a higher frequency here).
static func _bump(preset: String, p: Dictionary) -> NoiseTexture2D:
	var key := "bump:" + preset
	if not _cache.has(key):
		var ratio := float(p["bump_freq"]) / float(p["tone_freq"])
		_cache[key] = _noise(hash(key), 0.012 * ratio, 3, true)
	return _cache[key]


static func _rough(preset: String, p: Dictionary) -> NoiseTexture2D:
	var key := "rough:" + preset
	if not _cache.has(key):
		var t := _noise(hash(key), 0.02, 3)
		var r: Array = p["rough"]
		var ramp := Gradient.new()
		ramp.set_color(0, Color.WHITE * float(r[0]))
		ramp.set_color(1, Color.WHITE * float(r[1]))
		t.color_ramp = ramp
		_cache[key] = t
	return _cache[key]
