extends Area3D

const RuntimeTraceType := preload(
	"res://scripts/diagnostics/RuntimeTrace.gd"
)

@export var speed: float = 85.0
var direction: Vector3 = Vector3.FORWARD
var damage: float = 10.0
var faction: String = "player"
var color: Color = Color.CYAN
var lifetime: float = 3.0
var spent: bool = false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

## A glowing bolt along its flight and a flash at the gun (next_level_plan
## P2); set false for shots that shouldn't flash (none yet).
var muzzle_flash := true


func _ready():
	# A bright, stretched bolt that glows (bloom) instead of a flat dot.
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color.lightened(0.35)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 5.0
	var bolt := CapsuleMesh.new()
	bolt.radius = 0.14
	bolt.height = 2.6
	bolt.radial_segments = 8
	bolt.rings = 2
	mesh_instance.mesh = bolt
	mesh_instance.set_surface_override_material(0, mat)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 1.2
	glow.omni_range = 7.0
	glow.shadow_enabled = false
	add_child(glow)
	# Position and direction are set right after add_child, so aim and flash
	# a frame later.
	_aim_and_flash.call_deferred()

	# Connect collision signals
	body_entered.connect(_on_body_entered)


func _aim_and_flash() -> void:
	if not is_inside_tree():
		return
	if direction.length_squared() > 0.0001:
		# The capsule's long axis is Y: point it along the flight.
		mesh_instance.global_basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	if muzzle_flash and get_parent() is Node3D:
		ImpactEffect.spawn_hit(get_parent(), global_position, color, 0.55)

func _physics_process(delta: float):
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node):
	if spent or body == self or body.is_in_group("projectile"):
		return
		
	# Check faction
	if body.has_method("take_damage"):
		var body_faction = body.get("faction")
		if body_faction != faction:
			spent = true
			set_deferred("monitoring", false)
			RuntimeTraceType.event("combat", "projectile_hit", {
				"projectile_faction": faction,
				"target": str(body.name),
				"target_faction": str(body_faction),
				"damage": damage,
			})
			body.take_damage(damage, faction)
			ImpactEffect.spawn_hit(get_parent(), global_position, color)
			queue_free()
	elif body.is_in_group("asteroid") and faction == "player":
		spent = true
		set_deferred("monitoring", false)
		ImpactEffect.spawn_hit(get_parent(), global_position, Color(0.7, 0.7, 0.7))
		queue_free()
