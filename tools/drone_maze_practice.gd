extends Node

## Drone maze practice: the survey-drone dive on its own, no campaign needed.
## Each dive is a fresh random rock (or wreck); after it, the haul it would
## have paid in the game is shown (DroneMazeActivity.haul, the real rules).
##   powershell -File tools/play_drone_maze.ps1
## Keys between dives: G = dive a red rock, W = dive a wreck, Esc = quit.

const ViewType := preload("res://scripts/ui/DroneMazeView.gd")
const Activity := preload("res://scripts/story/activities/DroneMazeActivity.gd")

var _label: Label
var _view: Node = null
var _material := ""
var _dives := 0
var _materials_total := 0


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.04, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.92))
	layer.add_child(_label)
	_show_menu("")
	# Straight into the first dive.
	_dive("asteroid")


func _show_menu(result: String) -> void:
	var lines := ["DRONE MAZE PRACTICE", ""]
	if not result.is_empty():
		lines.append(result)
		lines.append("")
	if _dives > 0:
		lines.append("Dives: %d   ·   tech-grade materials so far: %d" % [_dives, _materials_total])
		lines.append("")
	lines.append("In the dive: W/S thrust, A/D turn, E extract, R recall the drone")
	lines.append("")
	lines.append("[G] dive a red rock      [W] dive a wreck      [Esc] quit")
	_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if _view != null or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_G, KEY_ENTER, KEY_SPACE:
			_dive("asteroid")
		KEY_W:
			_dive("wreck")
		KEY_ESCAPE:
			get_tree().quit()


func _dive(kind: String) -> void:
	_material = Activity.TECH_MATERIALS[randi() % Activity.TECH_MATERIALS.size()] if kind == "asteroid" else ""
	_view = ViewType.new()
	add_child(_view)
	_view.finished.connect(_on_finished)
	_view.begin(randi(), kind, false, _material)


func _on_finished(outcome_id: String, state: Dictionary) -> void:
	_view = null
	_dives += 1
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var result := Activity.haul(outcome_id, state, _material, rng)
	var mats: Array = result["materials"]
	_materials_total += mats.size()
	var names: Array[String] = []
	for item in mats:
		names.append(Activity.material_name(str(item)))
	var integrity := int(float(state.get("ore_integrity", 1.0)) * 100.0)
	var text := "Outcome: %s   ·   ore intact %d%%\n%d credits   ·   materials: %s" % [
		outcome_id.to_upper(), integrity, int(result["credits"]), ", ".join(names) if not names.is_empty() else "none"]
	_show_menu(text)
