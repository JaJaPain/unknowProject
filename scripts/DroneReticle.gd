extends Control
## Green drone-cam HUD overlay: corner frame, fixed center crosshair, and a
## tracking target bracket locked onto the enemy. Shown only during the drone
## strike POV (PlayerShip toggles visibility and feeds the target screen pos).

const COL      := Color(0.25, 1.0, 0.45, 0.95)
const COL_DIM  := Color(0.25, 1.0, 0.45, 0.35)

var target_pos: Vector2 = Vector2.ZERO   # enemy position in screen space
var has_target: bool = false

func _ready() -> void:
	# Full-screen, never eat input (see Godot mouse-filter gotcha for CanvasLayers).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_target_screen(p: Vector2, on_target: bool) -> void:
	target_pos = p
	has_target = on_target
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var inset := Vector2(w * 0.09, h * 0.11)
	var arm := minf(w, h) * 0.05
	# Corner frame brackets (the "viewport" of the drone cam).
	var corners := [
		[Vector2(inset.x, inset.y), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(w - inset.x, inset.y), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(inset.x, h - inset.y), Vector2(1, 0), Vector2(0, -1)],
		[Vector2(w - inset.x, h - inset.y), Vector2(-1, 0), Vector2(0, -1)],
	]
	for c in corners:
		var o: Vector2 = c[0]
		draw_line(o, o + (c[1] as Vector2) * arm, COL_DIM, 2.0)
		draw_line(o, o + (c[2] as Vector2) * arm, COL_DIM, 2.0)

	# Fixed center crosshair.
	var ctr := Vector2(w, h) * 0.5
	var g := minf(w, h) * 0.012   # center gap
	var cl := minf(w, h) * 0.03   # arm length
	draw_line(ctr + Vector2(-g - cl, 0), ctr + Vector2(-g, 0), COL, 1.5)
	draw_line(ctr + Vector2(g, 0), ctr + Vector2(g + cl, 0), COL, 1.5)
	draw_line(ctr + Vector2(0, -g - cl), ctr + Vector2(0, -g), COL, 1.5)
	draw_line(ctr + Vector2(0, g), ctr + Vector2(0, g + cl), COL, 1.5)

	# Tracking target box locked on the enemy.
	if has_target:
		var b := minf(w, h) * 0.06   # half box size
		var t := b * 0.45            # corner tick length
		var tl := target_pos + Vector2(-b, -b)
		var tr := target_pos + Vector2(b, -b)
		var bl := target_pos + Vector2(-b, b)
		var br := target_pos + Vector2(b, b)
		draw_line(tl, tl + Vector2(t, 0), COL, 2.0); draw_line(tl, tl + Vector2(0, t), COL, 2.0)
		draw_line(tr, tr + Vector2(-t, 0), COL, 2.0); draw_line(tr, tr + Vector2(0, t), COL, 2.0)
		draw_line(bl, bl + Vector2(t, 0), COL, 2.0); draw_line(bl, bl + Vector2(0, -t), COL, 2.0)
		draw_line(br, br + Vector2(-t, 0), COL, 2.0); draw_line(br, br + Vector2(0, -t), COL, 2.0)
		# Locked dot.
		draw_circle(target_pos, 2.5, COL)
