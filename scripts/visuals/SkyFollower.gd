extends Node

func _process(_delta: float) -> void:
	var p: Node3D = GlobalState.player
	if p != null and is_instance_valid(p):
		(get_parent() as Node3D).global_position = p.global_position
