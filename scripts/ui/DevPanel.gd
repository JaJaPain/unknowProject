extends CanvasLayer
class_name DevPanel

# ── Signals (GameRoot connects these) ─────────────────────────────────────────
signal spawn_boss_requested
signal spawn_squad_requested
signal stores_restock_requested
signal force_dock_rumor_requested
signal ollama_auto_restart_toggled(enabled: bool)
signal force_restart_ollama_requested
signal spawn_test_hostile_requested
signal clear_test_hostiles_requested

# ── Layout refs ───────────────────────────────────────────────────────────────
var _action_vbox: VBoxContainer
var _tab_container: TabContainer
var _root_panel: PanelContainer
var _story_debug_provider: Callable
var _story_status_label: Label
var _story_overarching_text: TextEdit
var _story_input_prompt_text: TextEdit
var _story_bible_text: TextEdit
var _story_context_text: TextEdit
var _story_state_text: TextEdit
var _story_bridge_summary_label: Label
var _story_full_debug_text: TextEdit

# ── Public API ────────────────────────────────────────────────────────────────
## Add a button to the left quick-action sidebar.
func add_action_button(label: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.pressed.connect(callback)
	_style_action_btn(btn)
	_action_vbox.add_child(btn)
	return btn

## Add a new tab to the right panel. Returns the VBoxContainer to populate.
func add_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_tab_container.add_child(scroll)
	_tab_container.set_tab_title(_tab_container.get_tab_count() - 1, title)
	return vbox


func set_story_debug_provider(provider: Callable) -> void:
	_story_debug_provider = provider
	_refresh_story_debug_tab()

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer   = 200
	visible = false
	_build_chrome()
	_build_faction_tuning_tab()
	_build_ship_viewer_tab()
	_build_lounge_layout_tab()
	_build_mechanic_debug_tab()
	_build_dialogue_content_tab()
	_build_dialogue_rules_tab()
	_build_combat_feel_tab()
	_build_story_debug_tab()
	# ── Add more built-in tabs here in future sessions ──
	# var my_tab := add_tab("My Tool")
	# _build_my_tool(my_tab)

func _build_chrome() -> void:
	# Dim backdrop — click outside panel does nothing (no close-on-click).
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_root_panel = PanelContainer.new()
	# Full-rect with a small inset so it fits at any resolution.
	_root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_panel.offset_left   = 30
	_root_panel.offset_right  = -30
	_root_panel.offset_top    = 30
	_root_panel.offset_bottom = -30
	_root_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_root_panel)

	var outer := VBoxContainer.new()
	_root_panel.add_child(outer)

	# ── Title bar ─────────────────────────────────────────────────────────────
	var title_bar := HBoxContainer.new()
	outer.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "  DEV PANEL"
	title_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title_lbl)

	var hint := Label.new()
	hint.text = "Numpad 7 to close  "
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	title_bar.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.pressed.connect(func(): visible = false)
	title_bar.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# ── Body: sidebar + tab content ───────────────────────────────────────────
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	# Left sidebar.
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size = Vector2(180, 0)
	body.add_child(sidebar)

	var sidebar_title := Label.new()
	sidebar_title.text = "QUICK ACTIONS"
	sidebar_title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	sidebar.add_child(sidebar_title)
	sidebar.add_child(HSeparator.new())

	_action_vbox = VBoxContainer.new()
	_action_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(_action_vbox)

	body.add_child(VSeparator.new())

	# Right tab area.
	_tab_container = TabContainer.new()
	_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_container.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	body.add_child(_tab_container)

	# ── Wire built-in action buttons ──────────────────────────────────────────
	add_action_button("Spawn Boss",     func(): emit_signal("spawn_boss_requested"))
	add_action_button("Spawn Squad",    func(): emit_signal("spawn_squad_requested"))
	add_action_button("Restock Stores", func(): emit_signal("stores_restock_requested"))
	# ── Add more quick actions here in future sessions ──

# ── Faction tuning tab ────────────────────────────────────────────────────────
func _build_story_debug_tab() -> void:
	var tab := add_tab("Story Debug")

	var hint := Label.new()
	hint.text = (
		"Read-only story data. Campaign Bible is the main large-story model document. "
		+ "Input Prompt is what would be sent to the large story model for this campaign."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(hint)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh Story View"
	refresh_btn.pressed.connect(_refresh_story_debug_tab)
	tab.add_child(refresh_btn)

	_story_status_label = Label.new()
	_story_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_story_status_label.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	tab.add_child(_story_status_label)

	tab.add_child(HSeparator.new())
	tab.add_child(_story_section_label("Overarching Story Gemma Wrote"))
	_story_overarching_text = _story_readonly_text_edit(220)
	tab.add_child(_story_overarching_text)

	tab.add_child(_story_section_label("Large Story Model Input Prompt"))
	_story_input_prompt_text = _story_readonly_text_edit(220)
	tab.add_child(_story_input_prompt_text)

	tab.add_child(_story_section_label("Campaign Bible JSON / Raw Stored Data"))
	_story_bible_text = _story_readonly_text_edit(300)
	tab.add_child(_story_bible_text)

	tab.add_child(_story_section_label(
		"Campaign Bible Prompt Block (player-safe — what small models actually see)"
	))
	_story_context_text = _story_readonly_text_edit(220)
	tab.add_child(_story_context_text)

	tab.add_child(_story_section_label("Live Story State Prompt Block"))
	_story_state_text = _story_readonly_text_edit(180)
	tab.add_child(_story_state_text)

	tab.add_child(HSeparator.new())
	tab.add_child(_story_section_label("Bridge Status (bible → story state)"))
	_story_bridge_summary_label = Label.new()
	_story_bridge_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_story_bridge_summary_label.add_theme_color_override("font_color", Color(0.55, 0.95, 1.0))
	tab.add_child(_story_bridge_summary_label)

	var force_rumor_btn := Button.new()
	force_rumor_btn.text = "Force Dock Rumor Roll"
	force_rumor_btn.pressed.connect(func(): force_dock_rumor_requested.emit())
	tab.add_child(force_rumor_btn)

	tab.add_child(HSeparator.new())
	tab.add_child(_story_section_label("Ollama Recovery"))
	var auto_restart_hint := Label.new()
	auto_restart_hint.text = (
		"Off by default. When ON, Force Restart may kill a pre-existing "
		+ "(not game-launched) ollama.exe process by name — only enable if you "
		+ "understand that."
	)
	auto_restart_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(auto_restart_hint)
	var auto_restart_check := CheckBox.new()
	auto_restart_check.text = "Allow Ollama Auto-Restart (kill + relaunch)"
	auto_restart_check.toggled.connect(func(enabled: bool): ollama_auto_restart_toggled.emit(enabled))
	tab.add_child(auto_restart_check)
	var force_restart_btn := Button.new()
	force_restart_btn.text = "Force Restart Ollama Now"
	force_restart_btn.pressed.connect(func(): force_restart_ollama_requested.emit())
	tab.add_child(force_restart_btn)

	tab.add_child(_story_section_label(
		"Full Story State (DEBUG ONLY — includes kaelen_hidden_angle / "
		+ "player_does_not_know_yet, which must NEVER appear in the prompt block above)"
	))
	_story_full_debug_text = _story_readonly_text_edit(180)
	tab.add_child(_story_full_debug_text)

	_refresh_story_debug_tab()


func _build_combat_feel_tab() -> void:
	var tab := add_tab("Combat Feel")

	var hint := Label.new()
	hint.text = (
		"Live tuning (this session only). Provoke a hostile and nudge these while "
		+ "you watch it close in. Report the final numbers when they feel right."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(hint)
	tab.add_child(HSeparator.new())

	# N.O.V.A. warn distance — how close a locked hostile gets before she calls it.
	_build_feel_row(
		tab, "N.O.V.A. warn distance", "nova_warn_distance", 50.0, false, "%.0f m"
	)
	# Grace hold — seconds after the warning before combat auto-starts.
	_build_feel_row(
		tab, "Combat grace (warning → fight)", "combat_warning_grace_ms", 500.0, true, "%d ms"
	)

	tab.add_child(HSeparator.new())
	var spawn_hint := Label.new()
	spawn_hint.text = "Spawn an inbound hostile (far ahead, locks on and closes in) to watch the sensor → warn → grace → fight sequence. Destroy it when done."
	spawn_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(spawn_hint)

	var spawn_row := HBoxContainer.new()
	spawn_row.add_theme_constant_override("separation", 8)
	tab.add_child(spawn_row)

	var spawn_btn := Button.new()
	spawn_btn.text = "Spawn Inbound Hostile"
	spawn_btn.pressed.connect(func(): spawn_test_hostile_requested.emit())
	spawn_row.add_child(spawn_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Destroy Test Hostile(s)"
	clear_btn.pressed.connect(func(): clear_test_hostiles_requested.emit())
	spawn_row.add_child(clear_btn)


# One live-tunable GlobalState value with -/+ buttons and a current-value readout.
func _build_feel_row(
	parent: VBoxContainer,
	label_text: String,
	prop: String,
	step: float,
	is_int: bool,
	fmt: String
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(230, 0)
	row.add_child(label)

	var value := Label.new()
	value.custom_minimum_size = Vector2(90, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
	row.add_child(value)

	var refresh := func() -> void:
		value.text = fmt % (int(GlobalState.get(prop)) if is_int else float(GlobalState.get(prop)))
	var nudge := func(delta: float) -> void:
		var next: float = maxf(0.0, float(GlobalState.get(prop)) + delta)
		GlobalState.set(prop, int(next) if is_int else next)
		refresh.call()

	var minus := Button.new()
	minus.text = "-%.0f" % step
	minus.pressed.connect(func() -> void: nudge.call(-step))
	row.add_child(minus)

	var plus := Button.new()
	plus.text = "+%.0f" % step
	plus.pressed.connect(func() -> void: nudge.call(step))
	row.add_child(plus)

	refresh.call()


func _story_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	return label


func _story_readonly_text_edit(height: int) -> TextEdit:
	var editor := TextEdit.new()
	editor.custom_minimum_size = Vector2(0, height)
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.editable = false
	return editor


func _refresh_story_debug_tab() -> void:
	if _story_status_label == null \
			or _story_overarching_text == null \
			or _story_input_prompt_text == null \
			or _story_bible_text == null \
			or _story_context_text == null \
			or _story_state_text == null \
			or _story_bridge_summary_label == null \
			or _story_full_debug_text == null:
		return
	if not _story_debug_provider.is_valid():
		_story_status_label.text = "Story provider not connected yet."
		_story_overarching_text.text = ""
		_story_input_prompt_text.text = ""
		_story_bible_text.text = ""
		_story_context_text.text = ""
		_story_state_text.text = ""
		_story_bridge_summary_label.text = ""
		_story_full_debug_text.text = ""
		return
	var snapshot: Dictionary = _story_debug_provider.call()
	_story_status_label.text = str(snapshot.get("status", "No story status available."))
	_story_overarching_text.text = str(snapshot.get("overarching_story", ""))
	_story_input_prompt_text.text = str(snapshot.get("campaign_bible_input_prompt", ""))
	_story_bible_text.text = str(snapshot.get("campaign_bible_json", ""))
	_story_context_text.text = str(snapshot.get("campaign_bible_context", ""))
	_story_state_text.text = str(snapshot.get("story_state_context", ""))
	_story_bridge_summary_label.text = str(snapshot.get("bridge_summary", ""))
	_story_full_debug_text.text = str(snapshot.get("full_story_state_json", ""))


func _build_lounge_layout_tab() -> void:
	var tab := add_tab("Lounge Layout")

	var hint := Label.new()
	hint.text = (
		"Open a station lounge, then nudge these values. "
		+ "Give Codex the final numbers shown below."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(hint)

	var values := Label.new()
	values.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
	values.text = _lounge_layout_values()
	tab.add_child(values)
	tab.add_child(HSeparator.new())

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 8)
	tab.add_child(slot_row)
	var prev_slot := Button.new()
	prev_slot.text = "Previous Slot"
	prev_slot.pressed.connect(func() -> void:
		values.text = _set_lounge_layout_slot(-1)
	)
	slot_row.add_child(prev_slot)
	var next_slot := Button.new()
	next_slot.text = "Next Slot"
	next_slot.pressed.connect(func() -> void:
		values.text = _set_lounge_layout_slot(1)
	)
	slot_row.add_child(next_slot)
	tab.add_child(HSeparator.new())

	_build_lounge_nudge_row(tab, values, "Portrait X", "portrait", "x")
	_build_lounge_nudge_row(tab, values, "Portrait Y", "portrait", "y")
	_build_lounge_nudge_row(tab, values, "Talk X", "talk", "x")
	_build_lounge_nudge_row(tab, values, "Talk Y", "talk", "y")
	tab.add_child(HSeparator.new())

	var text_values := Label.new()
	text_values.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
	text_values.text = _lounge_text_values()
	tab.add_child(text_values)
	_build_lounge_text_x_row(tab, text_values, "Name 1 X", "name", 0)
	_build_lounge_text_x_row(tab, text_values, "Name 2 X", "name", 1)
	_build_lounge_text_x_row(tab, text_values, "Name 3 X", "name", 2)
	_build_lounge_text_x_row(tab, text_values, "Name 4 X", "name", 3)
	_build_lounge_text_x_row(tab, text_values, "Bartender Lower X", "meta", 0)
	tab.add_child(HSeparator.new())

	var reset := Button.new()
	reset.text = "Reset Lounge Layout"
	reset.pressed.connect(func() -> void:
		var ui := GlobalState.get_ui_manager()
		if ui and ui.has_method("debug_reset_lounge_layout"):
			values.text = ui.debug_reset_lounge_layout()
			text_values.text = _lounge_text_values()
	)
	tab.add_child(reset)


func _build_lounge_nudge_row(
	parent: VBoxContainer,
	values: Label,
	label_text: String,
	target: String,
	axis: String,
	step: float = 0.01
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)

	var minus := Button.new()
	minus.text = "- %.2f" % step
	minus.pressed.connect(func() -> void:
		values.text = _adjust_lounge_layout(target, axis, -step)
	)
	row.add_child(minus)

	var plus := Button.new()
	plus.text = "+ %.2f" % step
	plus.pressed.connect(func() -> void:
		values.text = _adjust_lounge_layout(target, axis, step)
	)
	row.add_child(plus)


func _build_lounge_text_x_row(
	parent: VBoxContainer,
	values: Label,
	label_text: String,
	target: String,
	slot_index: int,
	step: float = 0.01
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)

	var minus := Button.new()
	minus.text = "- %.2f" % step
	minus.pressed.connect(func() -> void:
		values.text = _adjust_lounge_text(target, slot_index, -step)
	)
	row.add_child(minus)

	var plus := Button.new()
	plus.text = "+ %.2f" % step
	plus.pressed.connect(func() -> void:
		values.text = _adjust_lounge_text(target, slot_index, step)
	)
	row.add_child(plus)


func _adjust_lounge_layout(target: String, axis: String, delta: float) -> String:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("debug_adjust_lounge_layout"):
		return ui.debug_adjust_lounge_layout(target, axis, delta)
	return "UIManager not available."


func _adjust_lounge_text(target: String, slot_index: int, delta: float) -> String:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("debug_adjust_lounge_text"):
		return ui.debug_adjust_lounge_text(target, slot_index, delta)
	return "UIManager not available."


func _set_lounge_layout_slot(delta: int) -> String:
	var ui := GlobalState.get_ui_manager()
	if ui == null \
			or not ui.has_method("debug_lounge_layout_values") \
			or not ui.has_method("debug_set_lounge_tuning_slot"):
		return "UIManager not available."
	var current_text: String = ui.debug_lounge_layout_values()
	var slot := 1
	var parts: PackedStringArray = current_text.split(" ")
	if parts.size() >= 2 and str(parts[0]) == "Slot":
		slot = int(parts[1]) - 1
	return ui.debug_set_lounge_tuning_slot(clampi(slot + delta, 0, 3))


func _lounge_layout_values() -> String:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("debug_lounge_layout_values"):
		return ui.debug_lounge_layout_values()
	return "Open the game UI to tune lounge layout."


func _lounge_text_values() -> String:
	var ui := GlobalState.get_ui_manager()
	if ui and ui.has_method("debug_lounge_text_values"):
		return ui.debug_lounge_text_values()
	return "Open the game UI to tune lounge text."


func _build_mechanic_debug_tab() -> void:
	var tab := add_tab("Mechanic Debug")

	var hint := Label.new()
	hint.text = "Dock at the main station, enter maintenance, then refresh this to see why the mechanic pickup offer did or did not appear."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(hint)

	var values := Label.new()
	values.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))
	values.autowrap_mode = TextServer.AUTOWRAP_WORD
	values.text = _mechanic_debug_values()
	tab.add_child(values)

	var refresh := Button.new()
	refresh.text = "Refresh Mechanic Debug"
	refresh.pressed.connect(func() -> void:
		values.text = _mechanic_debug_values()
	)
	tab.add_child(refresh)


func _mechanic_debug_values() -> String:
	var debug: Dictionary = GlobalState.last_mechanic_pickup_roll_debug
	if debug.is_empty():
		return "No mechanic pickup roll recorded yet."
	var station_lane_occupied := QuestManager.is_lane_occupied("STATION")
	var station_data := QuestManager.get_lane_data("STATION")
	var lines: Array[String] = [
		"Offered: %s" % str(bool(debug.get("offered", false))),
		"Reason: %s" % str(debug.get("reason", "")),
		"Roll: %.3f / Chance: %.3f" % [
			float(debug.get("roll", 0.0)),
			float(debug.get("chance", 0.0)),
		],
		"Pickup outposts: %d total, %d valid" % [
			int(debug.get("outpost_count", 0)),
			int(debug.get("valid_outpost_count", 0)),
		],
		"Station lane occupied: %s" % str(station_lane_occupied),
	]
	if station_lane_occupied:
		lines.append("Station lane title: %s" % str(station_data.get("title", "")))
	if bool(debug.get("offered", false)):
		lines.append("Selected: %s / %s / %s" % [
			str(debug.get("selected_outpost", "")),
			str(debug.get("selected_npc", "")),
			str(debug.get("selected_part", "")),
		])
	var valid_outposts: Array = debug.get("valid_outposts", [])
	if not valid_outposts.is_empty():
		var names: Array[String] = []
		for entry in valid_outposts:
			if entry is Dictionary:
				names.append(str(entry.get("display", entry.get("id", ""))))
		lines.append("Valid destinations: %s" % ", ".join(names))
	return "\n".join(lines)


# ── Dialogue content editor tab ───────────────────────────────────────────────
# Compact editor for the migrated LLM quest dialogue in
# data/content/llm_dialogue_content.json. Two dropdowns pick the bucket
# (mission type × agent voice); the fields below edit just that bucket so the
# panel never shows everything at once.
const _DC_TYPES  := ["KILL_SHIPS", "DELIVER_ORE", "PICKUP_SPECIAL"]
const _DC_AGENTS := ["zenith", "aurelia", "vanguard", "neutral"]
const _DC_AGENT_LABELS := {
	"zenith": "Zenith — Director Voss",
	"aurelia": "Aurelia — Liaison Ryn",
	"vanguard": "Vanguard — Captain Dask",
	"neutral": "Neutral — Broker Kaelen (Shiny OK)",
}

var _dc_type_dd: OptionButton
var _dc_agent_dd: OptionButton
var _dc_constraints: TextEdit
var _dc_dialogues: TextEdit
var _dc_r1: LineEdit
var _dc_r2: LineEdit
var _dc_r3: LineEdit
var _dc_validation: Label
var _dc_status: Label


func _build_dialogue_content_tab() -> void:
	var tab := add_tab("Dialogue Content")

	var hint := Label.new()
	hint.text = "Edit the LLM quest dialogue examples. Pick a mission type + agent, edit the bucket, then Apply (this session) or Save (writes the JSON file). One dialogue per line. Shiny is Kaelen-only — allowed only for the Neutral agent."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(hint)
	tab.add_child(HSeparator.new())

	# ── Section selectors ─────────────────────────────────────────────────────
	var picker := HBoxContainer.new()
	tab.add_child(picker)

	_dc_type_dd = OptionButton.new()
	for t in _DC_TYPES:
		_dc_type_dd.add_item(t)
	_dc_type_dd.item_selected.connect(func(_i: int): _dc_load_fields())
	picker.add_child(_dc_type_dd)

	_dc_agent_dd = OptionButton.new()
	for a in _DC_AGENTS:
		_dc_agent_dd.add_item(str(_DC_AGENT_LABELS.get(a, a)))
	_dc_agent_dd.item_selected.connect(func(_i: int): _dc_load_fields())
	picker.add_child(_dc_agent_dd)

	var reload_btn := Button.new()
	reload_btn.text = "Reload from file"
	reload_btn.pressed.connect(func() -> void:
		LLMDialogueContentRegistry.shared().reload()
		_dc_load_fields()
		_dc_set_status("Reloaded from disk.", Color(0.6, 0.9, 1.0))
	)
	picker.add_child(reload_btn)

	# ── Dummy constraints ─────────────────────────────────────────────────────
	tab.add_child(_dc_field_label("Dummy constraint line (fact-steering; keep Slithern / 3 ships / 25 m³ / Sable Mercer intact):"))
	_dc_constraints = TextEdit.new()
	_dc_constraints.custom_minimum_size = Vector2(0, 54)
	_dc_constraints.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	tab.add_child(_dc_constraints)

	# ── Example dialogues ─────────────────────────────────────────────────────
	tab.add_child(_dc_field_label("Example dialogues — ONE per line:"))
	_dc_dialogues = TextEdit.new()
	_dc_dialogues.custom_minimum_size = Vector2(0, 150)
	_dc_dialogues.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_dc_dialogues.text_changed.connect(_dc_validate)
	tab.add_child(_dc_dialogues)

	# ── Choice responses ──────────────────────────────────────────────────────
	tab.add_child(_dc_field_label("Choice responses (accept / advance / haggle):"))
	_dc_r1 = LineEdit.new()
	_dc_r2 = LineEdit.new()
	_dc_r3 = LineEdit.new()
	for le in [_dc_r1, _dc_r2, _dc_r3]:
		le.text_changed.connect(func(_t: String): _dc_validate())
		tab.add_child(le)

	# ── Validation + actions ──────────────────────────────────────────────────
	tab.add_child(HSeparator.new())
	_dc_validation = Label.new()
	_dc_validation.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(_dc_validation)

	var actions := HBoxContainer.new()
	tab.add_child(actions)
	var apply_btn := Button.new()
	apply_btn.text = "Apply (this session)"
	apply_btn.pressed.connect(func(): _dc_apply(false))
	actions.add_child(apply_btn)
	var save_btn := Button.new()
	save_btn.text = "Save to override file"
	save_btn.pressed.connect(func(): _dc_apply(true))
	actions.add_child(save_btn)

	_dc_status = Label.new()
	_dc_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(_dc_status)

	_build_override_controls(tab)
	_dc_load_fields()


func _dc_field_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	return lbl


func _dc_current_type() -> String:
	return _DC_TYPES[clampi(_dc_type_dd.selected, 0, _DC_TYPES.size() - 1)]


func _dc_current_agent() -> String:
	return _DC_AGENTS[clampi(_dc_agent_dd.selected, 0, _DC_AGENTS.size() - 1)]


func _dc_load_fields() -> void:
	var reg := LLMDialogueContentRegistry.shared()
	var objective_type := _dc_current_type()
	var agent := _dc_current_agent()
	_dc_constraints.text = reg.quest_dummy_constraints(objective_type)
	var bundle := reg.quest_examples(agent, objective_type)
	var dialogues: Array = bundle.get("dialogues", [])
	var joined: Array[String] = []
	for line in dialogues:
		joined.append(str(line))
	_dc_dialogues.text = "\n".join(joined)
	_dc_r1.text = str(bundle.get("response_1", ""))
	_dc_r2.text = str(bundle.get("response_2", ""))
	_dc_r3.text = str(bundle.get("response_3", ""))
	_dc_set_status("Loaded %s / %s." % [objective_type, agent], Color(0.6, 0.6, 0.6))
	_dc_validate()


func _dc_parsed_dialogues() -> Array[String]:
	var out: Array[String] = []
	for raw in _dc_dialogues.text.split("\n"):
		var line := str(raw).strip_edges()
		if not line.is_empty():
			out.append(line)
	return out


func _dc_validate() -> void:
	var agent := _dc_current_agent()
	var kaelen := agent == "neutral"
	var problems: Array[String] = []
	var dialogues := _dc_parsed_dialogues()
	if dialogues.is_empty():
		problems.append("No dialogues — need at least one (empty buckets fall back to the built-in copy).")
	if not kaelen:
		var offenders: Array[String] = []
		for line in dialogues:
			if line.contains("Shiny"):
				offenders.append(line)
		for resp in [_dc_r1.text, _dc_r2.text, _dc_r3.text]:
			if str(resp).contains("Shiny"):
				offenders.append(str(resp))
		if not offenders.is_empty():
			problems.append("'Shiny' is Kaelen-only — remove it from this agent (%d line(s))." % offenders.size())
	if problems.is_empty():
		_dc_validation.text = "✓ Looks good."
		_dc_validation.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	else:
		_dc_validation.text = "⚠ " + "  ".join(problems)
		_dc_validation.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))


func _dc_apply(save_to_disk: bool) -> void:
	var dialogues := _dc_parsed_dialogues()
	if dialogues.is_empty():
		_dc_set_status("Blocked: add at least one dialogue line before applying.", Color(1.0, 0.5, 0.4))
		return
	var agent := _dc_current_agent()
	if agent != "neutral":
		for line in dialogues:
			if line.contains("Shiny"):
				_dc_set_status("Blocked: 'Shiny' is Kaelen-only. Remove it from the %s bucket first." % agent, Color(1.0, 0.5, 0.4))
				return
	var reg := LLMDialogueContentRegistry.shared()
	reg.set_quest_content(
		agent,
		_dc_current_type(),
		dialogues,
		_dc_r1.text.strip_edges(),
		_dc_r2.text.strip_edges(),
		_dc_r3.text.strip_edges(),
		_dc_constraints.text.strip_edges() + " "
	)
	if not save_to_disk:
		_refresh_override_ui()
		_dc_set_status("Applied to the override (this session, not written to disk yet).", Color(0.6, 0.9, 1.0))
		return
	var result := reg.save()
	_refresh_override_ui()
	if result.is_valid():
		_dc_set_status("Saved to override file: data/content/llm_dialogue_content.override.json (base untouched).", Color(0.4, 1.0, 0.6))
	else:
		_dc_set_status("Save error: %s" % result.summary(), Color(1.0, 0.5, 0.4))


func _dc_set_status(text: String, color: Color) -> void:
	if _dc_status == null:
		return
	_dc_status.text = text
	_dc_status.add_theme_color_override("font_color", color)


# ── Shared override controls (used by both dialogue tabs) ─────────────────────
# The override is a delta file the panel writes; the base stays trusted. The
# toggle flips it on/off live for A/B comparison; Discard deletes it entirely.
var _override_checks: Array = []          # CheckButtons kept in sync
var _override_status_labels: Array = []   # status Labels kept in sync


func _build_override_controls(tab: VBoxContainer) -> void:
	tab.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	tab.add_child(row)

	var chk := CheckButton.new()
	chk.text = "Use override (my edits)"
	chk.button_pressed = LLMDialogueContentRegistry.shared().override_enabled
	chk.toggled.connect(func(on: bool) -> void:
		LLMDialogueContentRegistry.shared().set_override_enabled(on)
		_refresh_override_ui()
		_reload_all_content_fields()
	)
	_override_checks.append(chk)
	row.add_child(chk)

	var discard := Button.new()
	discard.text = "Discard override"
	discard.pressed.connect(func() -> void:
		LLMDialogueContentRegistry.shared().discard_override()
		_refresh_override_ui()
		_reload_all_content_fields()
	)
	row.add_child(discard)

	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_override_status_labels.append(status)
	tab.add_child(status)

	_refresh_override_ui()


func _refresh_override_ui() -> void:
	var reg := LLMDialogueContentRegistry.shared()
	for chk in _override_checks:
		if chk != null:
			chk.button_pressed = reg.override_enabled
	var msg := "No override — runtime is using the trusted base file."
	var col := Color(0.6, 0.6, 0.6)
	if reg.has_override():
		if reg.override_enabled:
			msg = "Override ACTIVE — runtime is using your edits (data/content/llm_dialogue_content.override.json)."
			col = Color(1.0, 0.85, 0.4)
		else:
			msg = "Override present but OFF — runtime is using the trusted base."
			col = Color(0.6, 0.8, 1.0)
	for lbl in _override_status_labels:
		if lbl != null:
			lbl.text = msg
			lbl.add_theme_color_override("font_color", col)


func _reload_all_content_fields() -> void:
	if _dc_type_dd != null:
		_dc_load_fields()
	if _dr_speaker_dd != null:
		_dr_load()


# ── Dialogue rules tab (global nickname rules + speaker cards) ─────────────────
# NOTE: these rules are documentation/reference right now — the live personas are
# still built in code (see TODO(llm-content) markers). Editing here is safe and
# saved to the override; future prompt wiring will read from it.
const _DR_SPEAKERS := ["kaelen", "faction_agent", "mechanic", "lounge_local", "enemy_pilot"]

var _dr_guidance: TextEdit
var _dr_kaelen_words: LineEdit
var _dr_banned: LineEdit
var _dr_rare: LineEdit
var _dr_max_rare: LineEdit
var _dr_speaker_dd: OptionButton
var _dr_voice: Label
var _dr_addr: TextEdit
var _dr_tone: TextEdit
var _dr_validation: Label
var _dr_status: Label


func _build_dialogue_rules_tab() -> void:
	var tab := add_tab("Dialogue Rules")

	var hint := Label.new()
	hint.text = "Reference rules for nickname/voice ownership. These document intent today (personas are still built in code); edits save to the override for future wiring. Shiny is Kaelen-only."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(hint)
	tab.add_child(HSeparator.new())

	# ── Global rules ──────────────────────────────────────────────────────────
	tab.add_child(_dc_field_label("GLOBAL — non-Kaelen address guidance:"))
	_dr_guidance = TextEdit.new()
	_dr_guidance.custom_minimum_size = Vector2(0, 48)
	_dr_guidance.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	tab.add_child(_dr_guidance)

	tab.add_child(_dc_field_label("Kaelen-only words (comma-separated):"))
	_dr_kaelen_words = LineEdit.new()
	tab.add_child(_dr_kaelen_words)

	tab.add_child(_dc_field_label("Banned non-Kaelen phrases (comma-separated):"))
	_dr_banned = LineEdit.new()
	tab.add_child(_dr_banned)

	tab.add_child(_dc_field_label("Allowed rare non-Kaelen addresses (comma-separated):"))
	_dr_rare = LineEdit.new()
	tab.add_child(_dr_rare)

	tab.add_child(_dc_field_label("Max rare address uses (integer):"))
	_dr_max_rare = LineEdit.new()
	tab.add_child(_dr_max_rare)

	# ── Speaker cards ─────────────────────────────────────────────────────────
	tab.add_child(HSeparator.new())
	tab.add_child(_dc_field_label("SPEAKER card:"))
	_dr_speaker_dd = OptionButton.new()
	for s in _DR_SPEAKERS:
		_dr_speaker_dd.add_item(s)
	_dr_speaker_dd.item_selected.connect(func(_i: int): _dr_load_speaker())
	tab.add_child(_dr_speaker_dd)

	_dr_voice = Label.new()
	_dr_voice.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	tab.add_child(_dr_voice)

	tab.add_child(_dc_field_label("Address rule:"))
	_dr_addr = TextEdit.new()
	_dr_addr.custom_minimum_size = Vector2(0, 48)
	_dr_addr.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_dr_addr.text_changed.connect(_dr_validate)
	tab.add_child(_dr_addr)

	tab.add_child(_dc_field_label("Tone card:"))
	_dr_tone = TextEdit.new()
	_dr_tone.custom_minimum_size = Vector2(0, 48)
	_dr_tone.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_dr_tone.text_changed.connect(_dr_validate)
	tab.add_child(_dr_tone)

	# ── Validation + actions ──────────────────────────────────────────────────
	tab.add_child(HSeparator.new())
	_dr_validation = Label.new()
	_dr_validation.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(_dr_validation)

	var actions := HBoxContainer.new()
	tab.add_child(actions)
	var apply_btn := Button.new()
	apply_btn.text = "Apply (this session)"
	apply_btn.pressed.connect(func(): _dr_apply(false))
	actions.add_child(apply_btn)
	var save_btn := Button.new()
	save_btn.text = "Save to override file"
	save_btn.pressed.connect(func(): _dr_apply(true))
	actions.add_child(save_btn)

	_dr_status = Label.new()
	_dr_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	tab.add_child(_dr_status)

	_build_override_controls(tab)
	_dr_load()


func _dr_current_speaker() -> String:
	return _DR_SPEAKERS[clampi(_dr_speaker_dd.selected, 0, _DR_SPEAKERS.size() - 1)]


func _dr_load() -> void:
	var rules := LLMDialogueContentRegistry.shared().global_non_kaelen_rules()
	_dr_guidance.text = str(rules.get("non_kaelen_address_guidance", ""))
	_dr_kaelen_words.text = _dr_join(rules.get("kaelen_only_words", []))
	_dr_banned.text = _dr_join(rules.get("banned_non_kaelen_phrases", []))
	_dr_rare.text = _dr_join(rules.get("allowed_rare_non_kaelen_addresses", []))
	_dr_max_rare.text = str(int(rules.get("max_rare_address_uses", 1)))
	_dr_load_speaker()


func _dr_load_speaker() -> void:
	var card := LLMDialogueContentRegistry.shared().speaker(_dr_current_speaker())
	var voice := str(card.get("voice_profile_id", ""))
	_dr_voice.text = "voice_profile_id: %s" % (voice if not voice.is_empty() else "(none)")
	_dr_addr.text = str(card.get("address_rule", ""))
	_dr_tone.text = str(card.get("tone_card", ""))
	_dr_validate()


func _dr_validate() -> void:
	var speaker := _dr_current_speaker()
	if speaker == "kaelen":
		_dr_validation.text = "✓ Kaelen may use Shiny."
		_dr_validation.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
		return
	var leaked := _dr_addr.text.contains("Shiny") or _dr_tone.text.contains("Shiny")
	if leaked:
		_dr_validation.text = "⚠ 'Shiny' is Kaelen-only — remove it from speaker '%s'." % speaker
		_dr_validation.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	else:
		_dr_validation.text = "✓ Looks good."
		_dr_validation.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))


func _dr_apply(save_to_disk: bool) -> void:
	var speaker := _dr_current_speaker()
	if speaker != "kaelen" and (_dr_addr.text.contains("Shiny") or _dr_tone.text.contains("Shiny")):
		_dr_set_status("Blocked: 'Shiny' is Kaelen-only. Remove it from speaker '%s' first." % speaker, Color(1.0, 0.5, 0.4))
		return
	var reg := LLMDialogueContentRegistry.shared()
	reg.set_global_rules({
		"non_kaelen_address_guidance": _dr_guidance.text.strip_edges(),
		"kaelen_only_words": _dr_split(_dr_kaelen_words.text),
		"banned_non_kaelen_phrases": _dr_split(_dr_banned.text),
		"allowed_rare_non_kaelen_addresses": _dr_split(_dr_rare.text),
		"max_rare_address_uses": int(_dr_max_rare.text.strip_edges()),
	})
	reg.set_speaker(speaker, _dr_addr.text.strip_edges(), _dr_tone.text.strip_edges())
	if not save_to_disk:
		_refresh_override_ui()
		_dr_set_status("Applied to the override (this session, not written to disk yet).", Color(0.6, 0.9, 1.0))
		return
	var result := reg.save()
	_refresh_override_ui()
	if result.is_valid():
		_dr_set_status("Saved to override file (base untouched).", Color(0.4, 1.0, 0.6))
	else:
		_dr_set_status("Save error: %s" % result.summary(), Color(1.0, 0.5, 0.4))


func _dr_set_status(text: String, color: Color) -> void:
	if _dr_status == null:
		return
	_dr_status.text = text
	_dr_status.add_theme_color_override("font_color", color)


func _dr_join(value: Variant) -> String:
	if not value is Array:
		return ""
	var parts: Array[String] = []
	for item in value:
		parts.append(str(item))
	return ", ".join(parts)


func _dr_split(text: String) -> Array:
	var out: Array = []
	for raw in text.split(","):
		var item := str(raw).strip_edges()
		if not item.is_empty():
			out.append(item)
	return out


const _TUN_FIELDS      := ["weapon_tier","hull_tier","powerplant_tier","shield_tier","weapon_dmg_mult","drone_dmg_mult","intelligence"]
const _TUN_LABELS      := ["W.Tier","H.Tier","PP.Tier","Sh.Tier","W.Res","D.Res","Intel"]
const _TUN_STEPS       := [1.0, 1.0, 1.0, 1.0, 0.1, 0.1, 0.05]
const _TUN_IS_INT      := [true, true, true, true, false, false, false]

var _tun_labels: Dictionary = {}   # { faction_key: { field: Label } }

func _build_faction_tuning_tab() -> void:
	var tab := add_tab("Faction Tuning")

	# Column headers.
	var header := HBoxContainer.new()
	tab.add_child(header)
	_tun_cell_label(header, "FACTION", 210)
	for lbl in _TUN_LABELS:
		_tun_cell_label(header, lbl, 110)
	tab.add_child(HSeparator.new())

	# Known profiles.
	var known_hdr := Label.new()
	known_hdr.text = "── Known Factions ──"
	known_hdr.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	tab.add_child(known_hdr)
	for key in FactionRegistry.KNOWN_PROFILES:
		var base: Dictionary = FactionRegistry.KNOWN_PROFILES[key]
		_build_tuning_row(tab, key, base.get("display_name", key), base)

	tab.add_child(HSeparator.new())

	# Unknown factions.
	var unk_hdr := Label.new()
	unk_hdr.text = "── Unknown Factions ──"
	unk_hdr.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	tab.add_child(unk_hdr)
	for entry in FactionRegistry.UNKNOWN_FACTIONS:
		_build_tuning_row(tab, entry["id"], entry.get("display_name", entry["id"]), entry)

	# Save / Reset footer.
	tab.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	tab.add_child(footer)

	var save_btn := Button.new()
	save_btn.text = "💾  Save overrides to disk"
	save_btn.pressed.connect(func(): FactionRegistry.save_overrides())
	footer.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "↺  Reset all overrides"
	reset_btn.pressed.connect(_on_reset_tuning)
	footer.add_child(reset_btn)

func _build_tuning_row(parent: VBoxContainer, key: String, display: String, base: Dictionary) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = display
	name_lbl.custom_minimum_size = Vector2(210, 0)
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	_tun_labels[key] = {}
	for i in _TUN_FIELDS.size():
		var field: String = _TUN_FIELDS[i]
		var base_val: float = float(base.get(field, 0))
		var eff_val: float  = float(FactionRegistry._overrides.get(key, {}).get(field, base_val))

		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(110, 0)
		row.add_child(cell)

		var dn := Button.new()
		dn.text = "▼"
		dn.custom_minimum_size = Vector2(24, 0)
		cell.add_child(dn)

		var val_lbl := Label.new()
		val_lbl.text = _tun_fmt(i, eff_val)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		val_lbl.custom_minimum_size = Vector2(52, 0)
		cell.add_child(val_lbl)
		_tun_labels[key][field] = val_lbl

		var up := Button.new()
		up.text = "▲"
		up.custom_minimum_size = Vector2(24, 0)
		cell.add_child(up)

		# Closures capture by value at bind time via bind().
		dn.pressed.connect(_adjust_tuning.bind(key, i, -_TUN_STEPS[i]))
		up.pressed.connect(_adjust_tuning.bind(key, i, +_TUN_STEPS[i]))

func _adjust_tuning(key: String, field_idx: int, delta: float) -> void:
	var field: String = _TUN_FIELDS[field_idx]
	var lbl: Label    = _tun_labels[key][field]
	var cur: float    = float(_parse_tun_label(lbl.text))
	var next: float   = cur + delta
	if _TUN_IS_INT[field_idx]:
		next = max(0.0, round(next))
	else:
		next = maxf(0.0, snapped(next, 0.01))
	FactionRegistry.set_override(key, field, int(next) if _TUN_IS_INT[field_idx] else next)
	lbl.text = _tun_fmt(field_idx, next)

func _on_reset_tuning() -> void:
	FactionRegistry.clear_overrides()
	# Re-read base values into labels.
	for key in _tun_labels:
		var base: Dictionary = FactionRegistry.KNOWN_PROFILES.get(key, {})
		if base.is_empty():
			for e in FactionRegistry.UNKNOWN_FACTIONS:
				if e["id"] == key:
					base = e
					break
		for i in _TUN_FIELDS.size():
			var field: String = _TUN_FIELDS[i]
			_tun_labels[key][field].text = _tun_fmt(i, float(base.get(field, 0)))

func _parse_tun_label(text: String) -> float:
	return float(text.strip_edges())

func _tun_fmt(field_idx: int, val: float) -> String:
	if _TUN_IS_INT[field_idx]:
		return "%d" % int(val)
	return "%.2f" % val

func _tun_cell_label(parent: HBoxContainer, text: String, min_w: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(min_w, 0)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	parent.add_child(lbl)

# ── Ship viewer tab ─────────────────────────────────────────────────────────
var _sv_viewer: Control
var _sv_entries: Array = []   # [{faction, role, idx}]
var _sv_dropdown: OptionButton

func _build_ship_viewer_tab() -> void:
	var tab := add_tab("Ship Viewer")

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(row)

	# Left: controls.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	row.add_child(left)

	var lbl := Label.new()
	lbl.text = "Ship"
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	left.add_child(lbl)

	_sv_dropdown = OptionButton.new()
	_sv_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_sv_dropdown)

	var hint := Label.new()
	hint.text = "Drag = orbit\nScroll = zoom"
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	left.add_child(hint)

	row.add_child(VSeparator.new())

	# Right: the reusable 3D viewer.
	_sv_viewer = load("res://scenes/ui/model_viewer.tscn").instantiate()
	_sv_viewer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sv_viewer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sv_viewer.custom_minimum_size = Vector2(640, 620)
	row.add_child(_sv_viewer)

	# Showcase / favourite ships first (player-ship candidates etc.).
	for i in range(ShipAssembler.special_ship_names().size()):
		_sv_dropdown.add_item("★ %s" % ShipAssembler.special_ship_names()[i])
		_sv_entries.append({"special": i})

	# Then every styled faction × every catalog design.
	for faction in ShipAssembler.styled_factions():
		for role in ShipAssembler.catalog_roles():
			for i in range(ShipAssembler.design_count(role)):
				_sv_dropdown.add_item("%s  %s  #%d" % [str(faction).capitalize(), role, i + 1])
				_sv_entries.append({"faction": faction, "role": role, "idx": i})

	_sv_dropdown.item_selected.connect(_on_sv_selected)
	if _sv_entries.size() > 0:
		_sv_dropdown.select(0)
		# Build first ship once the viewer is in-tree and ready.
		call_deferred("_on_sv_selected", 0)

func _on_sv_selected(index: int) -> void:
	if index < 0 or index >= _sv_entries.size():
		return
	var e: Dictionary = _sv_entries[index]
	if e.has("special"):
		var node := ShipAssembler.build_special(int(e["special"]))
		if node:
			_sv_viewer.set_model(node)
	else:
		_sv_viewer.show_ship(e["faction"], e["role"], e["idx"])

# ── Styling ───────────────────────────────────────────────────────────────────
func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color            = Color(0.08, 0.08, 0.10, 0.97)
	s.border_color        = Color(0.3, 1.0, 0.5, 0.8)
	s.set_border_width_all(2)
	s.set_content_margin_all(10)
	return s

func _style_action_btn(btn: Button) -> void:
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
