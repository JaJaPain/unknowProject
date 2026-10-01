extends Node

## Screenshots per campaign (Abe, 2026-10-01). F12 takes one; Shift+F12 takes
## one without the HUD. They go in the campaign's own folder,
## <campaign>/screenshots/, named by in-game day, system and time, and the
## pause menu's Gallery shows them. A subtle flash and a shutter click confirm.

const KEY := KEY_F12
const FOLDER := "screenshots"

var _busy := false
static var _shutter: AudioStreamWAV = null


## The active campaign's screenshot folder ("" with no campaign).
static func folder() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var root = tree.current_scene if tree != null else null
	if root == null or not root.has_method("_campaign_slot_path"):
		return ""
	var slot := str(root.get("active_campaign_slot_id"))
	var base := str(root.call("_campaign_slot_path", slot))
	return "" if base.is_empty() else base.path_join(FOLDER)


## Shots in the folder, newest first (full paths).
static func list() -> Array[String]:
	var out: Array[String] = []
	var dir_path := folder()
	if dir_path.is_empty():
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.get_extension().to_lower() == "png":
			out.append(dir_path.path_join(file))
	out.sort_custom(func(a: String, b: String) -> bool:
		return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	return out


static func delete(path: String) -> void:
	if path.begins_with(folder()) and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## "Day004_Greywake_0830" for now.
static func base_name() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var clock: Node = tree.root.get_node_or_null("CampaignClock") if tree != null else null
	var minutes := int(clock.get("total_minutes")) if clock != null else 0
	var day := minutes / 1440 + 1
	var hour := (minutes % 1440) / 60
	var minute := minutes % 60
	var system := "Space"
	var ui = tree.root.get_node_or_null("GlobalState").get_ui_manager() if tree != null and tree.root.get_node_or_null("GlobalState") != null else null
	if ui != null and ui.has_method("_get_current_system_display_name"):
		system = str(ui.call("_get_current_system_display_name"))
	var clean := RegEx.create_from_string("[^A-Za-z0-9]+").sub(system.strip_edges(), "", true)
	return "Day%03d_%s_%02d%02d" % [day, clean if not clean.is_empty() else "Space", hour, minute]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY:
		get_viewport().set_input_as_handled()
		take((event as InputEventKey).shift_pressed)


## Saves the screen (without the HUD when `clean`). Returns the path, or "".
func take(clean: bool = false) -> String:
	if _busy:
		return ""
	var dir_path := folder()
	if dir_path.is_empty():
		return ""
	_busy = true
	DirAccess.make_dir_recursive_absolute(dir_path)
	var hidden: Array = []
	if clean:
		for layer in _hud_layers():
			if layer.visible:
				layer.visible = false
				hidden.append(layer)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	for layer in hidden:
		if is_instance_valid(layer):
			layer.visible = true
	var path := dir_path.path_join(base_name() + ".png")
	var n := 2
	while FileAccess.file_exists(path):
		path = dir_path.path_join("%s_%d.png" % [base_name(), n])
		n += 1
	var err := image.save_png(path)
	_busy = false
	if err != OK:
		return ""
	_flash()
	_click()
	var gs := get_node_or_null("/root/GlobalState")
	if gs != null:
		gs.emit_chatter("SYSTEM", "Screenshot saved: %s (Esc > Gallery)." % path.get_file(), Color(0.7, 0.8, 0.9))
	return path


## The HUD to hide for a clean shot: the UI manager and screen-space layers.
func _hud_layers() -> Array:
	var out: Array = []
	var gs := get_node_or_null("/root/GlobalState")
	var ui = gs.get_ui_manager() if gs != null else null
	if ui != null:
		out.append(ui)
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.layer > 0 and layer.layer < 100:
			out.append(layer)
	return out


func _flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 125
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 0.35)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	var tween := rect.create_tween()
	tween.tween_property(rect, "color:a", 0.0, 0.25)
	tween.tween_callback(layer.queue_free)


## A two-part shutter click, synthesized once.
func _click() -> void:
	if _shutter == null:
		_shutter = _make_shutter()
	var player := AudioStreamPlayer.new()
	player.stream = _shutter
	player.volume_db = -8.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


static func _make_shutter() -> AudioStreamWAV:
	var rate := 22050
	var length := int(rate * 0.12)
	var data := PackedByteArray()
	data.resize(length * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var smooth := 0.0
	for i in length:
		var t := float(i) / rate
		# Two short bursts: the shutter opening and closing.
		var env := exp(-t * 180.0) + 0.7 * exp(-maxf(0.0, t - 0.055) * 160.0) * (1.0 if t > 0.055 else 0.0)
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.35)
		var v := clampi(int(smooth * env * 26000.0), -32768, 32767)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
