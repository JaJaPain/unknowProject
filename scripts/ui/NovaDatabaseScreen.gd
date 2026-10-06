extends CanvasLayer

## N.O.V.A.'s database (Abe, 2026-10-05): its own button on the systems menu.
## Everyone the Captain has dealt with, newest first: portrait, name and a
## very brief line of how (ContactsLedger). Click one for the detail; pin the
## ones you suspect (pins weigh on who the main story settles on). Esc or
## CLOSE goes back.

const HudStyle := preload("res://scripts/ui/HudStyle.gd")
const Ledger := preload("res://scripts/story/ContactsLedger.gd")
const PIN_COLOR := Color(1.0, 0.78, 0.35)
const HAND_COLOR := Color(1.0, 0.45, 0.35)
const ROW_PORTRAIT := 56
const BIG_PORTRAIT := 220
const PinBoardType := preload("res://scripts/ui/PinBoardPanel.gd")
## N.O.V.A.'s whole memory in one place (Abe, 2026-10-05): the people, the
## clues (pins; after the reveal, which were real), the destination (what's
## known of it), and the journal (the story so far).
const TABS := [["people", "PEOPLE"], ["clues", "CLUES"], ["destination", "DESTINATION"], ["journal", "JOURNAL"]]

signal closed

var _list: VBoxContainer
var _detail: VBoxContainer
var _empty: Label
var _count: Label
var _filter := "all"
var _filter_buttons := {}
var _entries: Array = []
var _selected := ""
var _here := ""
var _tab := "people"
var _tab_buttons := {}
var _people_body: Control
var _board: Control
var _journal_scroll: ScrollContainer
var _journal_rows: VBoxContainer


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.01, 0.03, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudStyle.box(Color(HudStyle.BG, 1.0), HudStyle.EDGE, 1, 8, 18))
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	outer.add_child(header)
	var title := Label.new()
	title.text = "N.O.V.A. DATABASE"
	HudStyle.style_label(title, 24, HudStyle.ACCENT)
	header.add_child(title)
	_count = Label.new()
	HudStyle.style_label(_count, 13, HudStyle.DIM)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_count)
	for tab in TABS:
		var tb := Button.new()
		tb.text = tab[1]
		tb.toggle_mode = true
		HudStyle.style_button(tb, 13)
		var tab_id: String = tab[0]
		tb.pressed.connect(func() -> void: show_tab(tab_id))
		header.add_child(tb)
		_tab_buttons[tab_id] = tb
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	header.add_child(gap)
	for f in [["all", "ALL"], ["here", "THIS SYSTEM"], ["pinned", "PINNED"]]:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		HudStyle.style_button(b, 12)
		var id: String = f[0]
		b.pressed.connect(func() -> void:
			_filter = id
			_render())
		header.add_child(b)
		_filter_buttons[id] = b
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(110, 36)
	HudStyle.style_button(close, 13)
	close.pressed.connect(_close)
	header.add_child(close)
	var sub := Label.new()
	sub.text = "Everyone we've dealt with. I keep it all."
	HudStyle.style_label(sub, 13, HudStyle.DIM)
	outer.add_child(sub)
	outer.add_child(HudStyle.rule())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	outer.add_child(body)
	_people_body = body
	_board = PinBoardType.new()
	_board.set("embedded", true)
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.visible = false
	outer.add_child(_board)
	_board.connect("pin_toggled", func(thread_id: String, pinned: bool) -> void:
		var scene := get_tree().current_scene
		if scene != null and scene.has_method("premise_pin_thread"):
			scene.call("premise_pin_thread", thread_id, pinned))
	_journal_scroll = ScrollContainer.new()
	_journal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_journal_scroll.visible = false
	outer.add_child(_journal_scroll)
	_journal_rows = VBoxContainer.new()
	_journal_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_rows.add_theme_constant_override("separation", 10)
	_journal_scroll.add_child(_journal_rows)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.4
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", HudStyle.box(Color(0.03, 0.05, 0.08, 0.9), HudStyle.EDGE.darkened(0.3), 1, 8, 14))
	body.add_child(detail_panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	detail_panel.add_child(_detail)
	_empty = Label.new()
	_empty.text = "No one yet. Everyone we deal with ends up in here."
	HudStyle.style_label(_empty, 15, HudStyle.DIM)
	_list.add_child(_empty)
	_load()
	_render()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()


func _load() -> void:
	var tree := get_tree()
	var scene := tree.current_scene
	var book: Dictionary = StoryManager.story_state.get("contacts", {})
	var people: Array = scene.call("premise_people") if scene != null and scene.has_method("premise_people") else []
	var fates: Dictionary = scene.call("premise_fates") if scene != null and scene.has_method("premise_fates") else {}
	var hand := str(scene.call("premise_hand_id")) if scene != null and scene.has_method("premise_hand_id") else ""
	_entries = Ledger.entries(book, people, fates, hand)
	var ui = GlobalState.get_ui_manager()
	if ui != null and ui.has_method("_get_current_system_display_name"):
		_here = str(ui.call("_get_current_system_display_name"))
	if _selected.is_empty() and not _entries.is_empty():
		_selected = str(_entries[0]["key"])


func shown_entries() -> Array:
	match _filter:
		"here":
			return _entries.filter(func(e): return (e.get("systems", []) as Array).has(_here))
		"pinned":
			return _entries.filter(func(e): return bool(e.get("pinned", false)))
	return _entries


## One of TABS.
func show_tab(tab: String) -> void:
	_tab = tab
	_render()


func current_tab() -> String:
	return _tab


func _render() -> void:
	for id in _tab_buttons:
		(_tab_buttons[id] as Button).button_pressed = id == _tab
	var people := _tab == "people"
	_people_body.visible = people
	for id in _filter_buttons:
		(_filter_buttons[id] as Button).visible = people
	_board.visible = _tab in ["clues", "destination"]
	_journal_scroll.visible = _tab == "journal"
	if _tab in ["clues", "destination"]:
		_render_board()
		return
	if _tab == "journal":
		_render_journal()
		return
	for id in _filter_buttons:
		(_filter_buttons[id] as Button).button_pressed = id == _filter
	for c in _list.get_children():
		if c != _empty:
			c.queue_free()
	var shown := shown_entries()
	_empty.visible = shown.is_empty()
	_count.text = "  %d %s" % [_entries.size(), "person" if _entries.size() == 1 else "people"]
	for e in shown:
		_list.add_child(_row(e))
	_render_detail()


func _render_board() -> void:
	var scene := get_tree().current_scene
	var threads: Array = scene.call("premise_main_story_threads") if scene != null and scene.has_method("premise_main_story_threads") else []
	var summary: Dictionary = scene.call("premise_main_story_summary") if scene != null and scene.has_method("premise_main_story_summary") else {}
	var ui = GlobalState.get_ui_manager()
	var dest: Dictionary = ui.call("lodestar_log") if ui != null and ui.has_method("lodestar_log") else {}
	_board.call("show_threads", threads, summary, dest)
	_board.call("show_tab", "lodestar" if _tab == "destination" else "loose")
	if _tab == "destination" and dest.is_empty():
		_board.get("_header").text = "Nothing yet. N.O.V.A. will tell you when she hears of somewhere worth reaching."


## The story so far, newest first (PremiseDirector.journal).
func _render_journal() -> void:
	for c in _journal_rows.get_children():
		c.queue_free()
	var scene := get_tree().current_scene
	var entries: Array = scene.call("premise_journal") if scene != null and scene.has_method("premise_journal") else []
	if entries.is_empty():
		var none := Label.new()
		none.text = "Nothing written yet. The stories you take part in go in here."
		HudStyle.style_label(none, 15, HudStyle.DIM)
		_journal_rows.add_child(none)
		return
	for e in entries:
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", HudStyle.box(Color(0.04, 0.06, 0.09, 0.9), HudStyle.EDGE.darkened(0.4), 1, 6, 12))
		_journal_rows.add_child(box)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		box.add_child(col)
		var head := Label.new()
		var day := 1 + int(e.get("minute", 0)) / 1440
		head.text = "Day %d  ·  %s%s" % [day, str(e.get("system", "")), "" if bool(e.get("ended", false)) else "  ·  ongoing"]
		HudStyle.style_label(head, 12, HudStyle.DIM)
		col.add_child(head)
		var title := Label.new()
		title.text = str(e.get("title", ""))
		HudStyle.style_label(title, 16, HudStyle.ACCENT if bool(e.get("ended", false)) else PIN_COLOR)
		col.add_child(title)
		var body := Label.new()
		body.text = str(e.get("text", ""))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudStyle.style_label(body, 13, HudStyle.TEXT)
		col.add_child(body)
		for d in e.get("deeds", []):
			var deed := Label.new()
			deed.text = "› " + str(d)
			deed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			HudStyle.style_label(deed, 12, HudStyle.DIM)
			col.add_child(deed)


func _row(e: Dictionary) -> Control:
	var selected := str(e["key"]) == _selected
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, ROW_PORTRAIT + 12)
	var edge := HAND_COLOR if bool(e.get("is_hand", false)) else (PIN_COLOR if bool(e.get("pinned", false)) else HudStyle.EDGE.darkened(0.35))
	btn.add_theme_stylebox_override("normal", HudStyle.box(Color(0.05, 0.07, 0.1, 0.9), edge if not selected else HudStyle.ACCENT, 2 if selected else 1, 6))
	btn.add_theme_stylebox_override("hover", HudStyle.box(Color(0.07, 0.1, 0.14, 0.95), HudStyle.ACCENT, 1, 6))
	btn.add_theme_stylebox_override("pressed", HudStyle.box(Color(0.07, 0.1, 0.14, 0.95), HudStyle.ACCENT, 2, 6))
	var key := str(e["key"])
	btn.pressed.connect(func() -> void:
		_selected = key
		_render())
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	var pic := TextureRect.new()
	pic.texture = portrait_for(e)
	pic.custom_minimum_size = Vector2(ROW_PORTRAIT, ROW_PORTRAIT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name := Label.new()
	name.text = ("◆ " if bool(e.get("pinned", false)) else "") + str(e["name"])
	HudStyle.style_label(name, 15, HAND_COLOR if bool(e.get("is_hand", false)) else HudStyle.TEXT)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name)
	var line := Label.new()
	line.text = str(e.get("line", ""))
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	HudStyle.style_label(line, 12, HudStyle.DIM)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(line)
	return btn


func _render_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	var e := _find(_selected)
	if e.is_empty():
		return
	var pic := TextureRect.new()
	pic.texture = portrait_for(e)
	pic.custom_minimum_size = Vector2(0, BIG_PORTRAIT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail.add_child(pic)
	var name := Label.new()
	name.text = str(e["name"])
	HudStyle.style_label(name, 22, HAND_COLOR if bool(e.get("is_hand", false)) else HudStyle.TEXT)
	_detail.add_child(name)
	var who := ", ".join([str(e.get("role", "")), str(e.get("faction", ""))].filter(func(s): return not str(s).is_empty()))
	if not who.is_empty():
		var role := Label.new()
		role.text = who
		HudStyle.style_label(role, 13, HudStyle.ACCENT)
		_detail.add_child(role)
	var line := Label.new()
	line.text = str(e.get("line", ""))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.style_label(line, 14, HudStyle.TEXT)
	_detail.add_child(line)
	var systems: Array = e.get("systems", [])
	if not systems.is_empty():
		var where := Label.new()
		where.text = "Seen in: " + ", ".join(systems)
		where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudStyle.style_label(where, 12, HudStyle.DIM)
		_detail.add_child(where)
	_detail.add_child(HudStyle.rule())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(spacer)
	var pin := Button.new()
	var pinned := bool(e.get("pinned", false))
	pin.text = "UNPIN" if pinned else "PIN AS SUSPICIOUS"
	pin.custom_minimum_size = Vector2(0, 38)
	HudStyle.style_button(pin, 13)
	pin.pressed.connect(_toggle_pin.bind(str(e["key"])))
	_detail.add_child(pin)


func _toggle_pin(key: String) -> void:
	var e := _find(key)
	if e.is_empty():
		return
	var pinned := not bool(e.get("pinned", false))
	var book: Dictionary = StoryManager.story_state.get("contacts", {})
	if not book.has(key):
		# Someone known only from stories: give them an entry to hold the pin.
		book = Ledger.record(book, {"name": str(e["name"]), "entity_id": str(e.get("entity_id", ""))}, "", "noted", "", int(e.get("last_minute", 0)))
		book[key]["events"] = []
	StoryManager.story_state["contacts"] = Ledger.set_pinned(book, key, pinned)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("premise_pin_person") and not str(e.get("entity_id", "")).is_empty():
		scene.call("premise_pin_person", str(e["entity_id"]), pinned)
	_load()
	_render()


func _find(key: String) -> Dictionary:
	for e in _entries:
		if str(e["key"]) == key:
			return e
	return {}


## A portrait for anyone: their own, a lounge contact's by name, Kaelen's, or a
## stable pick from the generated-contact faces.
static func portrait_for(e: Dictionary) -> Texture2D:
	var reg = GameContentRegistry.shared()
	var pid := str(e.get("portrait_id", ""))
	if not pid.is_empty():
		var tex = reg.portrait_texture(pid)
		if tex != null:
			return tex
	var name := str(e.get("name", ""))
	var minor = GlobalState.get_minor_npc_portrait(name)
	if minor != null:
		return minor
	if name.contains("Kaelen"):
		return reg.portrait_texture("portrait.quest_givers.kaelen")
	var pool: Array = GlobalState.GENERATED_CONTACT_PORTRAITS
	if pool.is_empty():
		return null
	return reg.portrait_texture(str(pool[absi(hash(str(e.get("key", name)))) % pool.size()]))
