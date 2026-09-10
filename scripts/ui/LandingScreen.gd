extends Control

const STAR_COUNT := 180
const COMET_INTERVAL_MIN := 7.0
const COMET_INTERVAL_MAX := 14.0

var _stars: Array[Dictionary] = []
var _comets: Array[Dictionary] = []
var _planets: Array[Dictionary] = []
var _slot_list: VBoxContainer
var _status_label: Label
var _confirm_dialog: ConfirmationDialog
var _pending_delete_slot := ""
var _action_in_progress := false
var _preserve_landing_music_for_loading := false
var _rng := RandomNumberGenerator.new()
var _next_comet_at := 0.0
var _elapsed := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.seed = 924173
	_seed_backdrop()
	_build_interface()
	AudioManager.enter_landing_music()
	call_deferred("refresh_slots")


func _exit_tree() -> void:
	# Launching a campaign frees this screen, but the landing track should carry
	# through the loading sequence. UIManager hands it off at cinematic/start.
	if not _preserve_landing_music_for_loading and is_instance_valid(AudioManager):
		AudioManager.exit_landing_music()


func _seed_backdrop() -> void:
	var viewport_size := get_viewport_rect().size
	for star_index in range(STAR_COUNT):
		_stars.append({
			"position": Vector2(
				_rng.randf_range(0.0, viewport_size.x),
				_rng.randf_range(0.0, viewport_size.y)
			),
			"speed": _rng.randf_range(3.0, 18.0),
			"size": _rng.randf_range(0.5, 2.2),
			"brightness": _rng.randf_range(0.25, 0.9),
		})
	_planets = [
		{"position": Vector2(-160.0, 170.0), "radius": 150.0, "speed": 2.5, "color": Color("273a72")},
		{"position": Vector2(viewport_size.x + 140.0, viewport_size.y - 135.0), "radius": 104.0, "speed": 4.0, "color": Color("8d513e")},
	]
	_next_comet_at = _rng.randf_range(COMET_INTERVAL_MIN, COMET_INTERVAL_MAX)


func _build_interface() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.005, 0.012, 0.04, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_CENTER)
	layout.position = Vector2(-300.0, -405.0)
	layout.size = Vector2(600.0, 810.0)
	layout.add_theme_constant_override("separation", 14)
	add_child(layout)

	var title := Label.new()
	title.text = "ASTRA ARCANA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 62)
	title.add_theme_color_override("font_color", Color("d8f7ff"))
	title.add_theme_color_override("font_shadow_color", Color(0.08, 0.65, 1.0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	layout.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "CHART YOUR COURSE THROUGH THE UNKNOWN"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color("87bbd8"))
	layout.add_child(subtitle)

	var divider := HSeparator.new()
	layout.add_child(divider)

	var instruction := Label.new()
	instruction.text = "SELECT A CAMPAIGN"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 19)
	instruction.add_theme_color_override("font_color", Color("b8d8e8"))
	layout.add_child(instruction)

	_slot_list = VBoxContainer.new()
	_slot_list.add_theme_constant_override("separation", 10)
	_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_slot_list)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 44.0
	_status_label.add_theme_color_override("font_color", Color("b8d8e8"))
	layout.add_child(_status_label)

	var footer := Label.new()
	footer.text = "Astra Arcana  •  Working Title"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(0.45, 0.58, 0.7, 0.8))
	layout.add_child(footer)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Delete Campaign"
	_confirm_dialog.confirmed.connect(_confirm_delete)
	add_child(_confirm_dialog)


func refresh_slots() -> void:
	if _slot_list == null:
		return
	for child in _slot_list.get_children():
		child.queue_free()
	var game_root := get_tree().current_scene
	if game_root == null or not game_root.has_method("get_campaign_ui_state"):
		_status_label.text = "Campaign storage is still initializing..."
		return
	var state: Dictionary = game_root.get_campaign_ui_state()
	if not bool(state.get("ok", false)):
		_status_label.text = str(state.get("error", "Campaign storage is unavailable."))
		return
	var slots: Array = state.get("slots", [])
	var name_counts: Dictionary = {}
	for slot in slots:
		if bool((slot as Dictionary).get("occupied", false)):
			var campaign_name := str((slot as Dictionary).get("display_name", ""))
			name_counts[campaign_name] = int(name_counts.get(campaign_name, 0)) + 1
	for slot in slots:
		_add_slot_card(slot as Dictionary, name_counts)
	_status_label.text = "Three campaign constellations are available."


func _add_slot_card(slot: Dictionary, name_counts: Dictionary = {}) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 142.0
	panel.add_theme_stylebox_override("panel", _card_style(bool(slot.get("occupied", false))))
	_slot_list.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var slot_id := str(slot.get("slot_id", "slot"))
	var slot_number := slot_id.replace("slot_0", "SLOT ")
	var heading := Label.new()
	heading.text = slot_number
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("63ddff"))
	content.add_child(heading)
	var occupied := bool(slot.get("occupied", false))
	var name_label := Label.new()
	var campaign_name := str(slot.get("display_name", "Untitled Campaign"))
	if occupied and int(name_counts.get(campaign_name, 0)) > 1:
		campaign_name += "  —  Campaign %d" % (
			int(str(slot.get("slot_id", "slot_01")).trim_prefix("slot_"))
		)
	name_label.text = campaign_name if occupied else "Uncharted"
	name_label.add_theme_font_size_override("font_size", 23)
	name_label.add_theme_color_override("font_color", Color("eefaff") if occupied else Color("96aabd"))
	content.add_child(name_label)
	var detail := Label.new()
	if occupied:
		var summary: Dictionary = slot.get("checkpoint_summary", {})
		detail.text = "Continue from %s" % str(summary.get("system_id", "the last safe point")).replace("system.", "").capitalize()
	else:
		detail.text = "Begin a new expedition in this slot"
	detail.add_theme_color_override("font_color", Color("a2b5c6"))
	content.add_child(detail)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	content.add_child(actions)
	var primary := Button.new()
	primary.text = "CONTINUE" if occupied else "BEGIN EXPEDITION"
	primary.disabled = _action_in_progress
	primary.pressed.connect(_activate_slot.bind(slot_id, occupied))
	actions.add_child(primary)
	if occupied:
		var delete_button := Button.new()
		delete_button.text = "DELETE"
		delete_button.disabled = _action_in_progress
		delete_button.pressed.connect(_request_delete.bind(slot_id, str(slot.get("display_name", "this campaign"))))
		actions.add_child(delete_button)


func _card_style(occupied: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.105, 0.92)
	style.border_color = Color("2389ae") if occupied else Color(0.22, 0.37, 0.48, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style


func _activate_slot(slot_id: String, occupied: bool) -> void:
	if _action_in_progress:
		return
	_action_in_progress = true
	_status_label.text = "Opening star chart..."
	var game_root := get_tree().current_scene
	var result: Dictionary = await game_root.launch_campaign_from_landing(
		slot_id,
		occupied
	)
	if not bool(result.get("ok", false)):
		_status_label.text = str(result.get("error", "Campaign could not be opened."))
		_action_in_progress = false
		refresh_slots()
		return
	_finish_launch(occupied)


func _finish_launch(loaded_campaign: bool) -> void:
	var game_root := get_tree().current_scene
	game_root.startup_save_loaded = loaded_campaign
	game_root.startup_load_finished = true
	game_root.startup_load_completed.emit(loaded_campaign)
	_preserve_landing_music_for_loading = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	await tween.finished
	queue_free()


func _request_delete(slot_id: String, display_name: String) -> void:
	if _action_in_progress:
		return
	_pending_delete_slot = slot_id
	_confirm_dialog.dialog_text = "Delete '%s' and every checkpoint in it? This cannot be undone." % display_name
	_confirm_dialog.popup_centered()


func _confirm_delete() -> void:
	if _pending_delete_slot.is_empty():
		return
	_action_in_progress = true
	var game_root := get_tree().current_scene
	var result: Dictionary = game_root.delete_campaign_slot(_pending_delete_slot)
	_status_label.text = "Campaign deleted." if bool(result.get("ok", false)) else str(result.get("error", "Campaign could not be deleted."))
	_pending_delete_slot = ""
	_action_in_progress = false
	refresh_slots()


func _process(delta: float) -> void:
	_elapsed += delta
	var viewport_size := get_viewport_rect().size
	for star in _stars:
		star["position"].x -= float(star["speed"]) * delta
		if star["position"].x < -4.0:
			star["position"].x = viewport_size.x + 4.0
			star["position"].y = _rng.randf_range(0.0, viewport_size.y)
	for planet in _planets:
		planet["position"].x -= float(planet["speed"]) * delta
		if planet["position"].x < -float(planet["radius"]) * 2.0:
			planet["position"].x = viewport_size.x + float(planet["radius"]) * 2.0
	if _elapsed >= _next_comet_at:
		_comets.append({"position": Vector2(viewport_size.x + 160.0, _rng.randf_range(70.0, viewport_size.y * 0.65)), "life": 0.0})
		_next_comet_at = _elapsed + _rng.randf_range(COMET_INTERVAL_MIN, COMET_INTERVAL_MAX)
	for comet in _comets:
		comet["position"] += Vector2(-520.0, 180.0) * delta
		comet["life"] += delta
	_comets = _comets.filter(func(comet: Dictionary) -> bool: return comet["life"] < 3.8)
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("020714"))
	for star in _stars:
		var brightness := float(star["brightness"]) * (0.78 + sin(_elapsed * 1.5 + float(star["speed"])) * 0.22)
		draw_circle(star["position"], float(star["size"]), Color(0.72, 0.9, 1.0, brightness))
	for planet in _planets:
		var position: Vector2 = planet["position"]
		var radius := float(planet["radius"])
		draw_circle(position, radius + 16.0, Color(planet["color"], 0.08))
		draw_circle(position, radius, Color(planet["color"], 0.84))
		draw_circle(position - Vector2(radius * 0.24, radius * 0.20), radius * 0.43, Color(0.6, 0.8, 1.0, 0.12))
	for comet in _comets:
		var head: Vector2 = comet["position"]
		draw_line(head + Vector2(190.0, -68.0), head, Color(0.45, 0.82, 1.0, 0.12), 7.0)
		draw_line(head + Vector2(115.0, -40.0), head, Color(0.75, 0.94, 1.0, 0.72), 2.5)
		draw_circle(head, 4.0, Color("e6fbff"))
