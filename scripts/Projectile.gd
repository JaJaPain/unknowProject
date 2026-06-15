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

func _ready():
	# Configure visual color
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh_instance.set_surface_override_material(0, mat)
	
	# Connect collision signals
	body_entered.connect(_on_body_entered)

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
			# Spawn explosion FX here if desired
			queue_free()
	elif body.is_in_group("asteroid") and faction == "player":
		# Laser bullets hitting asteroids simply vanish
		spent = true
		set_deferred("monitoring", false)
		queue_free()
