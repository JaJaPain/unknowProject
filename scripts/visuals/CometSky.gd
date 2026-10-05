extends Node3D

## A distant comet crossing the sky (Gemini + ChatGPT's refined comet,
## test_comet/refined/Comet.gd; docs/prototypes/comet_refined_claude_handoff.md).
## Painted on a shell RADIUS out that follows the camera's position (keeping
## world orientation), so it's behind every planet, station and ship (a
## system's far side is ~28k away) and in front of the sun, nebula and stars
## (40-46k): never near the player, never approachable.
##
## Production changes from the lab: no schedule of its own (CometDirector
## starts passes), each pass has its own fixed path basis (framed where the
## camera was looking when it began), nothing is rebuilt while paused.
## Visual design untouched: tiny head, gas following the head's earlier path,
## detached dust, slow turbulence driven by event_time only.

const RADIUS := 38000.0
const DURATION := 90.0
const TRAIL_SECONDS := 23.0
const FADE_IN := 7.0
const FADE_OUT := 12.0

var observer: Camera3D
var age := 0.0
var event := 0
var running := false
var path_basis := Basis.IDENTITY
var _gas_mat: ShaderMaterial
var visual: MeshInstance3D
var _mesh := ArrayMesh.new()
var _dust_mesh := ArrayMesh.new()


func _ready() -> void:
	_gas_mat = ShaderMaterial.new()
	_gas_mat.shader = preload("res://shaders/comet_gas.gdshader")
	_gas_mat.render_priority = 1
	visual = MeshInstance3D.new()
	visual.name = "CometGas"
	visual.mesh = _mesh
	visual.material_override = _gas_mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.custom_aabb = AABB(-Vector3.ONE * RADIUS * 1.1, Vector3.ONE * RADIUS * 2.2)
	add_child(visual)
	var dust := MeshInstance3D.new()
	dust.name = "FineDust"
	dust.mesh = _dust_mesh
	var dust_mat := ShaderMaterial.new()
	dust_mat.shader = preload("res://shaders/comet_dust.gdshader")
	dust_mat.render_priority = 1
	dust.material_override = dust_mat
	dust.custom_aabb = visual.custom_aabb
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(dust)
	visual.visible = false


## A new pass along `basis` (its -Z is the middle of the arc).
func begin(event_index: int, basis: Basis) -> void:
	event = event_index
	path_basis = basis.orthonormalized()
	age = 0.0
	running = true


func end() -> void:
	running = false
	if visual != null:
		visual.visible = false


## Once a frame. Follows the observer even while paused; time, gas and dust
## only move when not. Returns false once the pass is over.
func advance(delta: float, paused: bool) -> bool:
	if not running:
		return false
	if observer == null or not is_instance_valid(observer):
		visual.visible = false
		return true
	global_position = observer.global_position
	global_basis = Basis.IDENTITY
	visual.visible = true
	if paused and _mesh.get_surface_count() > 0:
		return true
	if not paused:
		age += delta
	if age >= DURATION:
		end()
		return false
	_rebuild()
	return true


## Where the head is now, as a direction from the observer.
func head_direction() -> Vector3:
	return _direction(age / DURATION)


func _direction(p: float) -> Vector3:
	# Historical path samples keep their own place as the head moves on.
	var x := lerpf(-0.72, 0.72, p)
	var y := 0.07 + 0.23 * (1.0 - pow(2.0 * p - 1.0, 2.0))
	var tilt := sin(float(event) * 2.3) * 0.16
	return path_basis * Vector3(x, y + x * tilt, -1.0).normalized()


func _rebuild() -> void:
	var progress := age / DURATION
	_gas_mat.set_shader_parameter("event_time", age)
	var envelope := smoothstep(0.0, FADE_IN, age) * (1.0 - smoothstep(DURATION - FADE_OUT, DURATION, age))
	_gas_mat.set_shader_parameter("visibility", envelope)
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in 193:
		var s := float(i) / 192.0
		var u := (s - 0.08) / 0.92
		var p := progress - u * TRAIL_SECONDS / DURATION
		var center := _direction(p)
		var tangent := (_direction(p - 0.001) - _direction(p + 0.001)).normalized()
		var across := center.cross(tangent).normalized()
		for side in [-1.0, 1.0]:
			verts.append((center + across * side * 0.038).normalized() * RADIUS)
			uv.append(Vector2(s, (side + 1.0) * 0.5))
		if i < 192:
			var a := i * 2
			indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_rebuild_dust(envelope)


func _rebuild_dust(envelope: float) -> void:
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 91271 + event
	for i in 64:
		var lifetime := rng.randf_range(8.0, 14.0)
		var elapsed := fposmod(age + rng.randf() * lifetime, lifetime)
		var life := elapsed / lifetime
		# Each mote stays where it was shed; it doesn't follow the head.
		var birth := age - elapsed
		var p := (birth - TRAIL_SECONDS * rng.randf_range(0.72, 0.93)) / DURATION
		var center := _direction(p)
		var backward := (_direction(p - 0.001) - _direction(p + 0.001)).normalized()
		var across := center.cross(backward).normalized()
		var spread := rng.randf_range(-1.0, 1.0)
		center = (center + across * spread * (0.006 + elapsed * 0.0007) + backward * elapsed * 0.0007).normalized()
		var size := rng.randf_range(0.00030, 0.00060)
		var fade := smoothstep(0.0, 0.16, life) * (1.0 - smoothstep(0.22, 1.0, life)) * envelope
		var tint := Color(0.68, 0.73, 0.70, fade * rng.randf_range(0.12, 0.26))
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			verts.append((center + across * corner.y * size + backward * corner.x * size).normalized() * RADIUS)
			uv.append((corner + Vector2.ONE) * 0.5)
			colors.append(tint)
		var a := i * 4
		indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_dust_mesh.clear_surfaces()
	_dust_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
