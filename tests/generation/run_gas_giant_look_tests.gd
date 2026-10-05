extends SceneTree

## Gas giant V2 (ChatGPT's prototype, wired in 2026-10-04 per
## docs/prototypes/gas_giant_v2_claude_handoff.md): seeded profiles across six
## families and eight palettes, a surface + atmosphere pair per planet, one
## shell and one controller however often the look is applied, a clock that
## stops when paused, and a body that never moves.
##   Godot --headless --path . --script res://tests/generation/run_gas_giant_look_tests.gd --log-file <path>

const Look := preload("res://scripts/generation/GasGiantLook.gd")
const Profiles := preload("res://scripts/generation/GasGiantProfiles.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	# Profiles: repeatable, varied, every family and palette reachable.
	_check(str(Profiles.profile_for_seed(42)) == str(Profiles.profile_for_seed(42)), "the same seed, the same profile")
	var families := {}
	var palettes := {}
	for s in 500:
		var p: Dictionary = Profiles.profile_for_seed(s)
		families[str(p["archetype"])] = true
		palettes[str(p["palette"])] = true
		var count := int(p["storm_count"])
		var expected: int = [2, 0, 1, 1, 0, 3][Profiles.ARCHETYPES.find(str(p["archetype"]))]
		_check(count == expected, "storm count follows the family: %s %d" % [p["archetype"], count])
	_check(families.size() == 6, "all six families turn up (%d)" % families.size())
	_check(palettes.size() == 8, "all eight palettes turn up (%d)" % palettes.size())

	# Abe, 2026-10-04: ice giants are rare, and only further out.
	var ice_near := 0
	var ice_far := 0
	for s in 1000:
		if Look.ICE_FAMILIES.has(Look.family_for(s, 0)) or Look.ICE_FAMILIES.has(Look.family_for(s, 1)):
			ice_near += 1
		if Look.ICE_FAMILIES.has(Look.family_for(s, 3)):
			ice_far += 1
	_check(ice_near == 0, "no ice giants in the start system or the first ring (%d)" % ice_near)
	_check(ice_far > 50 and ice_far < 200, "about one in eight further out (%d/1000)" % ice_far)
	_check(Look.family_for(77, 3) == Look.family_for(77, 3), "a planet's family is steady")

	# Applying: one body, one shell, one controller, unique materials.
	var a := _planet(3000.0)
	var b := _planet(3000.0)
	var body_xform: Transform3D = Look.body_of(a).transform
	Look.apply(a, 11)
	Look.apply(a, 11)
	Look.apply(b, 12)
	var body_a := Look.body_of(a)
	_check(body_a != null and body_a.name == "MeshInstance3D", "the body is the planet's own mesh")
	_check(body_a.find_children("*", "MeshInstance3D", true, false).size() == 1, "one atmosphere shell after two applies")
	_check(a.find_children("GasGiantVisual", "", false, false).size() == 1, "one controller after two applies")
	var shell := body_a.get_node("GasGiantAtmosphere") as MeshInstance3D
	_check(shell.mesh == body_a.mesh and is_equal_approx(shell.scale.x, 1.012) and shell.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the shell shares the mesh, a touch larger, no shadow")
	_check(not shell.is_in_group("celestial") and shell.get_children().is_empty(), "the shell is cosmetic only")
	var sa := body_a.material_override as ShaderMaterial
	var sb := Look.body_of(b).material_override as ShaderMaterial
	_check(sa != null and sb != null and sa != sb and sa.shader == Profiles.SURFACE, "each planet its own surface material")
	_check(shell.material_override is ShaderMaterial and (shell.material_override as ShaderMaterial).shader == Profiles.ATMOSPHERE, "the shell wears the atmosphere")
	_check(Look.body_of(a).transform == body_xform, "the body doesn't move")

	# The clock: runs, and stops while the game is paused.
	var visual = a.get_node("GasGiantVisual")
	await create_timer(0.3).timeout
	var t1 := float(sa.get_shader_parameter("planet_time"))
	_check(t1 > 0.1, "the clouds turn (%.2f)" % t1)
	var gs := root.get_node_or_null("GlobalState")
	if gs != null:
		gs.set("paused", true)
		var held := float(sa.get_shader_parameter("planet_time"))
		await create_timer(0.3).timeout
		_check(is_equal_approx(float(sa.get_shader_parameter("planet_time")), held), "paused, the clouds hold still")
		gs.set("paused", false)
	_check(Look.body_of(a).transform == body_xform, "still hasn't moved")

	# Lighting: the system's sun, +Z toward it.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 2.0
	a.get_parent().add_child(sun)
	sun.look_at_from_position(Vector3(0, 0, 50000), Vector3.ZERO, Vector3.UP)
	visual.call("_refresh_light")
	var dir: Vector3 = sa.get_shader_parameter("sun_direction")
	_check(dir.distance_to(Vector3(0, 0, 1)) < 0.01, "lit from the sun's side: %s" % str(dir))
	_check(float(sa.get_shader_parameter("sun_intensity")) == 2.0, "the sun's strength")

	if _failures.is_empty():
		print("[PASS] Gas giant looks")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _planet(radius: float) -> Node3D:
	var system := Node3D.new()
	root.add_child(system)
	var planet := StaticBody3D.new()
	planet.add_to_group("celestial")
	system.add_child(planet)
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var body := MeshInstance3D.new()
	body.name = "MeshInstance3D"
	body.mesh = mesh
	planet.add_child(body)
	return planet


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
