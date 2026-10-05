extends RefCounted

## What a gas giant looks like, from a seed (playtest 2026-10-02: every one
## looked like Jupiter; Abe's call: shader only). Picks one of a handful of
## original palettes and varies the band count, turbulence and storms, then
## builds the material from shaders/gas_giant.gdshader.

const SHADER := preload("res://shaders/gas_giant.gdshader")

## Four colours each, light to dark and back; names are for tests and logs.
const PALETTES := {
	"ochre": [Color(0.93, 0.86, 0.72), Color(0.78, 0.62, 0.44), Color(0.62, 0.38, 0.24), Color(0.95, 0.92, 0.85)],
	"ice_blue": [Color(0.80, 0.91, 0.96), Color(0.56, 0.75, 0.88), Color(0.34, 0.54, 0.76), Color(0.90, 0.96, 0.99)],
	"teal_storm": [Color(0.38, 0.72, 0.70), Color(0.20, 0.45, 0.50), Color(0.58, 0.84, 0.76), Color(0.13, 0.29, 0.36)],
	"violet_haze": [Color(0.68, 0.58, 0.82), Color(0.46, 0.36, 0.63), Color(0.82, 0.72, 0.90), Color(0.30, 0.22, 0.45)],
	"rust_ember": [Color(0.78, 0.42, 0.26), Color(0.56, 0.26, 0.18), Color(0.92, 0.62, 0.40), Color(0.36, 0.16, 0.12)],
	"sage_cream": [Color(0.83, 0.85, 0.69), Color(0.62, 0.68, 0.50), Color(0.91, 0.89, 0.79), Color(0.45, 0.50, 0.38)],
	"rose_gold": [Color(0.91, 0.72, 0.63), Color(0.76, 0.51, 0.46), Color(0.96, 0.86, 0.76), Color(0.55, 0.32, 0.30)],
	"slate_storm": [Color(0.62, 0.66, 0.72), Color(0.41, 0.45, 0.53), Color(0.80, 0.82, 0.86), Color(0.25, 0.28, 0.35)],
}


## The look for a seed: {palette, colors, band_count, turbulence,
## band_sharpness, storm_size, storm_dir, storm_color, rim_color, seed_offset}.
static func look_for(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("gas_giant:%d" % seed_value)
	var names := PALETTES.keys()
	var name := str(names[rng.randi() % names.size()])
	var colors: Array = PALETTES[name]
	# A few churning storms (Abe, 2026-10-02: "think Jupiter's storm"): two or
	# three, the first the biggest, each turning its own way.
	var storm_count := rng.randi_range(2, 3)
	var storm_dirs: Array[Vector3] = []
	var sizes := Vector3.ZERO
	var spins := Vector3.ONE
	for i in 3:
		storm_dirs.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-1.0, 1.0)).normalized())
		if i < storm_count:
			sizes[i] = rng.randf_range(0.16, 0.26) if i == 0 else rng.randf_range(0.06, 0.14)
		spins[i] = rng.randf_range(0.6, 1.4) * (1.0 if rng.randf() < 0.5 else -1.0)
	# The storms in the palette's darkest tone or a warm contrast.
	var storm_color: Color = colors[3] if rng.randf() < 0.5 else Color(0.85, 0.45, 0.3).lerp(colors[2], 0.3)
	return {
		"palette": name,
		"colors": colors,
		"band_count": snappedf(rng.randf_range(5.0, 16.0), 0.5),
		"turbulence": rng.randf_range(0.3, 1.2),
		"band_sharpness": rng.randf_range(0.6, 1.2),
		"storm_count": storm_count,
		"storm_dir_1": storm_dirs[0],
		"storm_dir_2": storm_dirs[1],
		"storm_dir_3": storm_dirs[2],
		"storm_sizes": sizes,
		"storm_spins": spins,
		"storm_color": storm_color,
		"rim_color": (colors[1] as Color).lightened(0.35),
		"seed_offset": Vector3(rng.randf_range(0.0, 100.0), rng.randf_range(0.0, 100.0), rng.randf_range(0.0, 100.0)),
	}


static func material_for(seed_value: int) -> ShaderMaterial:
	var look := look_for(seed_value)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var colors: Array = look["colors"]
	material.set_shader_parameter("color_a", colors[0])
	material.set_shader_parameter("color_b", colors[1])
	material.set_shader_parameter("color_c", colors[2])
	material.set_shader_parameter("color_d", colors[3])
	for key in ["band_count", "turbulence", "band_sharpness", "storm_dir_1", "storm_dir_2", "storm_dir_3", "storm_sizes", "storm_spins", "storm_color", "rim_color", "seed_offset"]:
		material.set_shader_parameter(key, look[key])
	material.set_meta("palette", look["palette"])
	return material


## Dresses an existing gas giant with the V2 look (ChatGPT's procedural
## clouds, storms and atmosphere; docs/prototypes/gas_giant_v2_claude_handoff.md):
## a surface material on the body, an atmosphere shell child, and a
## GasGiantVisual controller for its clock and sunlight. Applying again
## (a campaign reseed) reuses the shell and controller. The V1 look_for /
## material_for above stay for the old snapshot and tests.
const ProfilesType := preload("res://scripts/generation/GasGiantProfiles.gd")
const ATMOSPHERE_SHELL := "GasGiantAtmosphere"
const ATMOSPHERE_SCALE := 1.012


static func apply(planet: Node3D, seed_value: int) -> void:
	if planet == null:
		return
	var body := body_of(planet)
	if body == null:
		return
	var profile: Dictionary = ProfilesType.profile_for_seed(hash("gas_giant_v2:%d" % seed_value))
	# Game distances: the middle quality tier (4 octaves).
	profile["quality_level"] = 1
	var pair: Dictionary = ProfilesType.material_pair_for(profile)
	var surface: ShaderMaterial = pair["surface"]
	var atmosphere: ShaderMaterial = pair["atmosphere"]
	surface.set_meta("palette", str(profile.get("palette", "")))
	surface.set_meta("archetype", str(profile.get("archetype", "")))
	body.material_override = surface
	var shell := body.get_node_or_null(ATMOSPHERE_SHELL) as MeshInstance3D
	if shell == null:
		shell = MeshInstance3D.new()
		shell.name = ATMOSPHERE_SHELL
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(shell)
	shell.mesh = body.mesh
	shell.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * ATMOSPHERE_SCALE)
	shell.material_override = atmosphere
	var visual := planet.get_node_or_null("GasGiantVisual")
	if visual == null:
		visual = load("res://scripts/visuals/GasGiantVisual.gd").new()
		visual.name = "GasGiantVisual"
		planet.add_child(visual)
	visual.call("bind", surface, atmosphere)


## The planet's body mesh: its "MeshInstance3D" child, never the atmosphere.
static func body_of(planet: Node3D) -> MeshInstance3D:
	var body := planet.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if body != null:
		return body
	for child in planet.find_children("*", "MeshInstance3D", true, false):
		if str(child.name) != ATMOSPHERE_SHELL:
			return child as MeshInstance3D
	return null
