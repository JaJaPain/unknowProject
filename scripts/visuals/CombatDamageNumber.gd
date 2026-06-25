class_name CombatDamageNumber
extends RefCounted

# Spawns a billboard Label3D at a world position that floats up and fades.
# Used for combat hit feedback. Wall-clock tween so slow-mo doesn't stall it.

static func spawn(parent: Node, pos: Vector3, text: String, color: Color, big: bool = false) -> void:
	if not is_instance_valid(parent):
		return
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.modulate = color
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.outline_size = 12
	lbl.font_size = 64 if big else 44
	lbl.pixel_size = 0.006 if big else 0.0045
	lbl.render_priority = 20
	lbl.outline_render_priority = 19
	parent.add_child(lbl)
	lbl.global_position = pos + Vector3(0, 2.0, 0)

	# Float up + fade, then free. ignore_time_scale so it plays during slow-mo.
	var rise := pos + Vector3(0, 9.0 if big else 6.5, 0)
	var tw := lbl.create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position", rise, 0.9).set_ease(Tween.EASE_OUT)
	var fade := lbl.create_tween()
	fade.set_ignore_time_scale(true)
	fade.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.25)
	fade.tween_callback(lbl.queue_free)
