extends Node

## Runs a rocky or ocean planet's look (docs/prototypes/terrestrial_planets_claude_handoff.md):
## one clock for the surface and the clouds (the planet turns and the weather
## changes shape in the shaders; no node rotates), frozen while the game is
## paused, and the system's real sun on every layer (all three shaders are
## unshaded and light themselves). Same pattern as GasGiantVisual.
##
## One per planet, a child named "TerrestrialVisual"; applying the look again
## rebinds it.

var surface: ShaderMaterial
var clouds: ShaderMaterial
var atmosphere: ShaderMaterial
var _time := 0.0
var _light: DirectionalLight3D
var _light_check_s := 0.0
const LIGHT_REFRESH_S := 1.0
## The star's colour pulled toward white, as for gas giants: a warm star
## tints the world without drowning its own colours.
const SUN_TINT_SOFTEN := 0.5


func bind(surface_material: ShaderMaterial, cloud_material: ShaderMaterial, atmosphere_material: ShaderMaterial) -> void:
	surface = surface_material
	clouds = cloud_material
	atmosphere = atmosphere_material
	_light = null
	_light_check_s = 0.0
	_set_time()
	_refresh_light()


func _process(delta: float) -> void:
	if surface == null:
		return
	_light_check_s -= delta
	if _light_check_s <= 0.0:
		_light_check_s = LIGHT_REFRESH_S
		_refresh_light()
	if get_tree().paused:
		return
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null and bool(gs.get("paused")):
		return
	_time += delta
	_set_time()


func _set_time() -> void:
	for m in [surface, clouds]:
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("planet_time", _time)


func _refresh_light() -> void:
	if _light == null or not is_instance_valid(_light) or not _light.is_inside_tree():
		_light = _find_light()
	if _light == null:
		return
	var to_sun: Vector3 = _light.global_basis.z.normalized()
	var tint: Color = _light.light_color.lerp(Color.WHITE, SUN_TINT_SOFTEN)
	for m in [surface, clouds, atmosphere]:
		if m != null:
			(m as ShaderMaterial).set_shader_parameter("sun_direction", to_sun)
			(m as ShaderMaterial).set_shader_parameter("sun_color", tint)
			(m as ShaderMaterial).set_shader_parameter("sun_intensity", _light.light_energy)


func _find_light() -> DirectionalLight3D:
	if not is_inside_tree():
		return null
	var node: Node = get_parent()
	while node != null and node != get_tree().root:
		for light in node.find_children("*", "DirectionalLight3D", true, false):
			if (light as DirectionalLight3D).visible:
				return light
		node = node.get_parent()
	return null
