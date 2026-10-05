extends Node

## Runs a gas giant's V2 look (docs/prototypes/gas_giant_v2_claude_handoff.md):
## advances the surface shader's own clock (the clouds turn in the shader; no
## node rotates) and keeps the shaders lit by the system's real sun. Both
## shaders are unshaded and do their own lighting, so they need the
## DirectionalLight's direction and colour handed to them.
##
## One per gas giant, a child of the planet, named "GasGiantVisual". Applying
## the look again reuses it with the new materials.

var surface: ShaderMaterial
var atmosphere: ShaderMaterial
var _time := 0.0
var _light: DirectionalLight3D
var _light_check_s := 0.0
## Re-read the light this often (a system's sun is set after its planets).
const LIGHT_REFRESH_S := 1.0
## How far the star's colour is pulled toward white on the clouds (0 = full tint).
const SUN_TINT_SOFTEN := 0.5


func bind(surface_material: ShaderMaterial, atmosphere_material: ShaderMaterial) -> void:
	surface = surface_material
	atmosphere = atmosphere_material
	_light = null
	_light_check_s = 0.0
	if surface != null:
		surface.set_shader_parameter("planet_time", _time)
	_refresh_light()


func _process(delta: float) -> void:
	if surface == null:
		return
	_light_check_s -= delta
	if _light_check_s <= 0.0:
		_light_check_s = LIGHT_REFRESH_S
		_refresh_light()
	# Frozen with the game: tree pause and the game's own pause flag.
	if get_tree().paused:
		return
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null and bool(gs.get("paused")):
		return
	_time += delta
	surface.set_shader_parameter("planet_time", _time)


## The system's DirectionalLight3D (SystemAmbience.add_sun), found from the
## planet's system root. Its +Z points toward the sun.
func _refresh_light() -> void:
	if _light == null or not is_instance_valid(_light) or not _light.is_inside_tree():
		_light = _find_light()
	if _light == null:
		return
	var to_sun: Vector3 = _light.global_basis.z.normalized()
	# The star's colour, softened halfway to white: a warm sun at full tint
	# turned a cyan ice giant olive. Its tint still shows; the palette survives.
	var sun_tint: Color = _light.light_color.lerp(Color.WHITE, SUN_TINT_SOFTEN)
	if surface != null:
		surface.set_shader_parameter("sun_direction", to_sun)
		surface.set_shader_parameter("sun_color", sun_tint)
		surface.set_shader_parameter("sun_intensity", _light.light_energy)
	if atmosphere != null:
		atmosphere.set_shader_parameter("sun_direction", to_sun)
		atmosphere.set_shader_parameter("sun_color", sun_tint)


func _find_light() -> DirectionalLight3D:
	if not is_inside_tree():
		return null
	var node: Node = get_parent()
	var best: DirectionalLight3D = null
	# The nearest ancestor that has a directional light under it: the system.
	while node != null and node != get_tree().root:
		for light in node.find_children("*", "DirectionalLight3D", true, false):
			if (light as DirectionalLight3D).visible:
				best = light
				break
		if best != null:
			return best
		node = node.get_parent()
	return null
