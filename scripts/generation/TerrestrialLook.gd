extends RefCounted

## What a rocky planet looks like (ChatGPT's terrestrial shaders, wired in
## 2026-10-04 per docs/prototypes/terrestrial_planets_claude_handoff.md):
## cratered rock worlds and ocean worlds with clouds that change shape.
## apply() dresses a planet's body and, for ocean worlds, adds a cloud shell
## and an atmosphere shell; a TerrestrialVisual controller runs the clock and
## the sunlight. Applying again reuses everything. Visual only: the planet's
## kind, collision and navigation don't change.

const ProfilesType := preload("res://scripts/generation/TerrestrialProfiles.gd")
const CLOUD_SHELL := "TerrestrialClouds"
const ATMOSPHERE_SHELL := "TerrestrialAtmosphere"
const CLOUD_SCALE := 1.008
const ATMOSPHERE_SCALE := 1.025
## How often each family turns up: rock worlds most of the time (lunar, iron
## desert, frozen moon), oceans about a third (pure, archipelago, storm).
const FAMILY_WEIGHTS := [25, 25, 15, 12, 12, 11]


## The family for a planet, steady per seed (its own RNG; the system
## generator's sequence is untouched).
static func family_for(seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("terrestrial_family:%d" % seed_value)
	var total := 0
	for w in FAMILY_WEIGHTS:
		total += int(w)
	var roll := rng.randi() % total
	for i in FAMILY_WEIGHTS.size():
		roll -= int(FAMILY_WEIGHTS[i])
		if roll < 0:
			return i
	return 0


static func apply(planet: Node3D, seed_value: int, family: int = -1) -> void:
	if planet == null:
		return
	var body := body_of(planet)
	if body == null:
		return
	if family < 0:
		family = family_for(seed_value)
	var profile: Dictionary = ProfilesType.profile_for_seed(hash("terrestrial:%d" % seed_value), family)
	# Game distances: the middle quality tier.
	profile["quality_level"] = 1
	var mats: Dictionary = ProfilesType.materials_for(profile)
	var surface: ShaderMaterial = mats["surface"]
	surface.set_meta("family", str(profile.get("name", "")))
	body.material_override = surface
	var ocean := bool(profile.get("is_ocean", false))
	var clouds: ShaderMaterial = mats["clouds"] if ocean else null
	var atmosphere: ShaderMaterial = mats["atmosphere"] if ocean else null
	_shell(body, CLOUD_SHELL, CLOUD_SCALE, clouds)
	_shell(body, ATMOSPHERE_SHELL, ATMOSPHERE_SCALE, atmosphere)
	var visual := planet.get_node_or_null("TerrestrialVisual")
	if visual == null:
		visual = load("res://scripts/visuals/TerrestrialVisual.gd").new()
		visual.name = "TerrestrialVisual"
		planet.add_child(visual)
	visual.call("bind", surface, clouds, atmosphere)


## A shell around the body sharing its mesh: shown with `material`, or
## hidden (and released) when the world has none (rock worlds).
static func _shell(body: MeshInstance3D, shell_name: String, scale: float, material: ShaderMaterial) -> void:
	var shell := body.get_node_or_null(shell_name) as MeshInstance3D
	if material == null:
		if shell != null:
			shell.visible = false
			shell.material_override = null
		return
	if shell == null:
		shell = MeshInstance3D.new()
		shell.name = shell_name
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(shell)
	shell.mesh = body.mesh
	shell.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * scale)
	shell.material_override = material
	shell.visible = true


## The planet's body mesh: its "MeshInstance3D" child, never a shell.
static func body_of(planet: Node3D) -> MeshInstance3D:
	var body := planet.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if body != null:
		return body
	for child in planet.find_children("*", "MeshInstance3D", true, false):
		if not str(child.name) in [CLOUD_SHELL, ATMOSPHERE_SHELL]:
			return child as MeshInstance3D
	return null
