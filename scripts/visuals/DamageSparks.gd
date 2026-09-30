extends Node3D

## Sparks off a badly hurt hull (next_level_plan P2): once the parent ship is
## under LOW_HULL of its health, a small burst of sparks pops from a random
## point on it every so often, faster as it gets worse. Works on PlayerShip and
## NPCShip (both have health / max_health / destroyed).

const LOW_HULL := 0.35

var radius := 4.0
var _timer := 0.0


func _process(delta: float) -> void:
	var ship := get_parent() as Node3D
	if ship == null or ship.get("destroyed") == true or ship.get("is_docked") == true:
		return
	var max_h = ship.get("max_health")
	var h = ship.get("health")
	if max_h == null or h == null or float(max_h) <= 0.0:
		return
	var frac := float(h) / float(max_h)
	if frac >= LOW_HULL or frac <= 0.0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	# 0.35 hull: every ~1.4 s; near zero: every ~0.35 s.
	_timer = lerpf(0.35, 1.4, frac / LOW_HULL) * randf_range(0.7, 1.3)
	var offset := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)).normalized() * radius * randf_range(0.4, 0.9)
	var parent := ship.get_parent() as Node3D
	if parent != null:
		ImpactEffect.spawn_hit(parent, ship.global_position + offset, Color(1.0, 0.55, 0.2), 0.45)
