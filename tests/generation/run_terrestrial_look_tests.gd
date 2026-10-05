extends SceneTree

## Rocky and ocean planets (ChatGPT's terrestrial shaders, wired in
## 2026-10-04 per docs/prototypes/terrestrial_planets_claude_handoff.md).
##   Godot --headless --path . --script res://tests/generation/run_terrestrial_look_tests.gd --log-file <path>

const Look := preload("res://scripts/generation/TerrestrialLook.gd")
const Profiles := preload("res://scripts/generation/TerrestrialProfiles.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	await process_frame
	_check(str(Profiles.profile_for_seed(9, 4)) == str(Profiles.profile_for_seed(9, 4)), "the same seed, the same world")
	var seen := {}
	var oceans := 0
	for s in 1000:
		var f := Look.family_for(s)
		seen[f] = true
		if f >= 3:
			oceans += 1
	_check(seen.size() == 6, "all six families turn up (%d)" % seen.size())
	_check(oceans > 250 and oceans < 450, "oceans about a third (%d/1000)" % oceans)

	var planet := _planet()
	var body := Look.body_of(planet)
	var xform := body.transform
	# An ocean world: clouds and atmosphere shells.
	Look.apply(planet, 5, 5)
	Look.apply(planet, 5, 5)
	var clouds := body.get_node_or_null(Look.CLOUD_SHELL) as MeshInstance3D
	var atmo := body.get_node_or_null(Look.ATMOSPHERE_SHELL) as MeshInstance3D
	_check(clouds != null and clouds.visible and atmo != null and atmo.visible, "an ocean world has clouds and air")
	_check(body.get_children().size() == 2 and planet.find_children("TerrestrialVisual", "", false, false).size() == 1, "one of each after two applies")
	_check(is_equal_approx(clouds.scale.x, 1.008) and is_equal_approx(atmo.scale.x, 1.025) and clouds.mesh == body.mesh, "shells share the mesh at their radii")
	_check(clouds.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and clouds.get_children().is_empty(), "shells are cosmetic")
	var surface := body.material_override as ShaderMaterial
	var cloud_mat := clouds.material_override as ShaderMaterial
	_check(surface.shader == Profiles.OCEAN and cloud_mat.shader == Profiles.CLOUD, "ocean surface and cloud shaders")
	# The clock runs on the surface and the clouds, and stops when paused.
	await create_timer(0.3).timeout
	var t := float(cloud_mat.get_shader_parameter("planet_time"))
	_check(t > 0.1 and is_equal_approx(t, float(surface.get_shader_parameter("planet_time"))), "one clock for surface and clouds (%.2f)" % t)
	var gs := root.get_node_or_null("GlobalState")
	if gs != null:
		gs.set("paused", true)
		var held := float(cloud_mat.get_shader_parameter("planet_time"))
		await create_timer(0.3).timeout
		_check(is_equal_approx(float(cloud_mat.get_shader_parameter("planet_time")), held), "paused, the weather holds")
		gs.set("paused", false)
	# Switching to a rock world hides the shells.
	Look.apply(planet, 5, 0)
	_check(not clouds.visible and not atmo.visible and clouds.material_override == null, "a rock world has no clouds or air")
	_check((body.material_override as ShaderMaterial).shader == Profiles.ROCK, "rock surface shader")
	_check(body.transform == xform, "the body never moves")
	# Lit from the system's sun (+Z toward it).
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	planet.get_parent().add_child(sun)
	sun.look_at_from_position(Vector3(50000, 0, 0), Vector3.ZERO, Vector3.UP)
	planet.get_node("TerrestrialVisual").call("_refresh_light")
	var dir: Vector3 = (body.material_override as ShaderMaterial).get_shader_parameter("sun_direction")
	_check(dir.distance_to(Vector3(1, 0, 0)) < 0.01, "lit from the sun's side: %s" % str(dir))
	if _failures.is_empty():
		print("[PASS] Terrestrial looks")
		quit(0)
		return
	for f in _failures:
		push_error("[FAIL] %s" % f)
	quit(1)


func _planet() -> Node3D:
	var system := Node3D.new()
	root.add_child(system)
	var planet := StaticBody3D.new()
	system.add_child(planet)
	var mesh := SphereMesh.new()
	mesh.radius = 1250.0
	mesh.height = 2500.0
	var body := MeshInstance3D.new()
	body.name = "MeshInstance3D"
	body.mesh = mesh
	planet.add_child(body)
	return planet


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
